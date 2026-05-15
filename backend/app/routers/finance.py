import json
import re
from io import BytesIO
from datetime import date as Date, datetime, timedelta, timezone
from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile
from sqlmodel import Session, select
from ..database import get_session
from ..models import (
    CreditBalance,
    CreditBalanceStatus,
    Debt,
    DebtPayment,
    DebtSource,
    DebtStatus,
    Expense,
    FixedExpenseTemplate,
    HouseholdPeriodSettings,
    Member,
    MemberRole,
    MonthlyAdvancePayment,
    MonthlyClose,
    MonthlyIncome,
    MonthlyParticipation,
    PaymentStatus,
)
from ..schemas import (
    AutomaticDebtCreate,
    CardImportPreviewItem,
    CardImportPreviewResponse,
    DebtCancel,
    DebtCreate,
    CreditBalanceApply,
    CreditBalanceRead,
    DebtPaymentCreate,
    DebtPaymentDecision,
    DebtPaymentRead,
    DebtRead,
    ExpenseCreate,
    ExpenseRead,
    FixedExpenseTemplateCreate,
    FixedExpenseTemplateRead,
    FixedExpenseTemplateUpdate,
    IncomeRead,
    IncomeUpsert,
    MemberParticipationRead,
    MemberParticipationUpdate,
    MonthCloseCreate,
    MonthReopen,
    MonthSummary,
    MonthlyAdvancePaymentCreate,
    MonthlyAdvancePaymentRead,
    HouseholdPeriodSettingsRead,
    HouseholdPeriodSettingsUpdate,
    MonthlyCloseRead,
)
from ..services.calculations import calculate_month_summary, round_money
from .auth import get_current_member

router = APIRouter(prefix="/finance", tags=["finance"])


_CARD_IMPORT_MAX_BYTES = 8 * 1024 * 1024


def _parse_card_amount(raw: str) -> float | None:
    value = raw.strip()
    if not value:
        return None
    value = value.replace('$', '').replace('ARS', '').replace(' ', '').replace(' ', '')
    value = value.replace('+', '')
    negative = value.startswith('-') or value.endswith('-') or value.startswith('(')
    value = value.strip('-()')
    if not value:
        return None
    if ',' in value:
        value = value.replace('.', '').replace(',', '.')
    else:
        parts = value.split('.')
        if len(parts) > 2:
            value = ''.join(parts)
    try:
        amount = abs(float(value))
    except ValueError:
        return None
    if amount <= 0:
        return None
    return amount if not negative else amount


def _parse_card_date(raw: str, fallback_month: str | None = None) -> Date | None:
    parts = re.split(r'[/-]', raw.strip())
    if len(parts) < 2:
        return None
    try:
        day = int(parts[0])
        month = int(parts[1])
        if len(parts) >= 3:
            year = int(parts[2])
            if year < 100:
                year += 2000
        elif fallback_month:
            year = int(fallback_month.split('-')[0])
        else:
            year = datetime.now(timezone.utc).year
        return Date(year, month, day)
    except Exception:
        return None


def _guess_card_category(description: str) -> str:
    text = description.lower()
    rules = [
        ('Supermercado', ['super', 'mercado', 'carrefour', 'coto', 'dia ', 'jumbo', 'vea']),
        ('Comida', ['restaurant', 'resto', 'bar ', 'cafe', 'delivery', 'pedidosya', 'rappi', 'mostaza', 'mcdonald']),
        ('Transporte', ['sube', 'uber', 'cabify', 'taxi', 'ypf', 'shell', 'axion', 'combustible']),
        ('Servicios', ['luz', 'gas', 'aysa', 'edenor', 'edesur', 'telecom', 'movistar', 'claro', 'personal', 'internet']),
        ('Salud', ['farmacia', 'doctor', 'medic', 'clinica', 'hospital']),
        ('Hogar', ['ferreteria', 'easy', 'sodimac', 'pintureria', 'bazar']),
    ]
    for category, keywords in rules:
        if any(keyword in text for keyword in keywords):
            return category
    return 'General'


def _extract_pdf_text(file_bytes: bytes) -> tuple[str, list[str]]:
    warnings: list[str] = []
    try:
        from pypdf import PdfReader
    except Exception as exc:  # pragma: no cover - depende del entorno
        raise HTTPException(status_code=500, detail='El servidor no tiene disponible el lector de PDF.') from exc
    try:
        reader = PdfReader(BytesIO(file_bytes))
        texts: list[str] = []
        for page in reader.pages[:12]:
            texts.append(page.extract_text() or '')
        text = '\n'.join(texts).strip()
    except Exception as exc:
        raise HTTPException(status_code=400, detail='No se pudo leer el PDF. Probá con un resumen digital, no escaneado.') from exc
    if not text:
        warnings.append('No se detectó texto en el PDF. Si es un escaneo o imagen, esta etapa no usa OCR.')
    return text, warnings


def _detect_card_movements(text: str, fallback_month: str | None = None) -> tuple[list[CardImportPreviewItem], list[str]]:
    warnings: list[str] = []
    items: list[CardImportPreviewItem] = []
    date_re = re.compile(r'\b(\d{1,2}[/-]\d{1,2}(?:[/-]\d{2,4})?)\b')
    amount_re = re.compile(r'(?<!\d)(?:\$\s*)?-?\d{1,3}(?:[.\s]\d{3})*(?:,\d{2})|-?\d+(?:,\d{2})(?!\d)')
    ignored = ('total', 'saldo', 'pago', 'vencimiento', 'cierre', 'limite', 'límite', 'resumen', 'cuota del resumen')
    seen: set[tuple[str, str, int]] = set()

    for raw_line in text.splitlines():
        line = re.sub(r'\s+', ' ', raw_line).strip()
        if len(line) < 8:
            continue
        lower = line.lower()
        if any(word in lower for word in ignored) and not re.search(r'compra|consumo|establecimiento', lower):
            continue
        date_match = date_re.search(line)
        if not date_match:
            continue
        amount_matches = list(amount_re.finditer(line))
        if not amount_matches:
            continue
        # Usar el último importe de la línea, que suele ser el monto final de la operación.
        amount_match = amount_matches[-1]
        amount = _parse_card_amount(amount_match.group(0))
        if amount is None:
            continue
        parsed_date = _parse_card_date(date_match.group(1), fallback_month)
        description = (line[:date_match.start()] + ' ' + line[date_match.end():amount_match.start()]).strip(' -·|')
        if not description:
            description = line[date_match.end():amount_match.start()].strip(' -·|') or 'Movimiento detectado'
        # Limpiar números sueltos típicos de comprobantes/cuotas.
        description = re.sub(r'\b\d{3,}\b', '', description).strip(' -·|') or 'Movimiento detectado'
        key = (parsed_date.isoformat() if parsed_date else '', description.lower(), int(round(amount * 100)))
        if key in seen:
            continue
        seen.add(key)
        confidence = 0.72 if parsed_date else 0.55
        if '$' in amount_match.group(0) or 'ars' in lower:
            confidence += 0.08
        items.append(
            CardImportPreviewItem(
                date=parsed_date,
                description=description[:160],
                amount=round_money(amount),
                currency='ARS',
                category=_guess_card_category(description),
                confidence=min(confidence, 0.92),
                raw_text=line[:260],
            )
        )
        if len(items) >= 120:
            warnings.append('Se muestran los primeros 120 movimientos detectados para mantener la vista previa liviana.')
            break

    if not items and text.strip():
        warnings.append('No se detectaron movimientos con el formato esperado. El resumen puede tener columnas no compatibles todavía.')
    return items, warnings


def _month_add(year: int, month: int, delta: int) -> tuple[int, int]:
    idx = year * 12 + (month - 1) + delta
    return idx // 12, idx % 12 + 1


def _month_str_add(month: str, delta: int) -> str:
    year, mon = [int(x) for x in month.split("-")]
    y, m = _month_add(year, mon, delta)
    return f"{y:04d}-{m:02d}"


def _period_end(start: Date) -> Date:
    y, m = _month_add(start.year, start.month, 1)
    return Date(y, m, start.day) - timedelta(days=1)


def _active_period(settings: HouseholdPeriodSettings, today: Date | None = None) -> tuple[str, Date, Date, bool]:
    if settings.active_month_override:
        start, end = period_bounds_from_month(settings.active_month_override, settings)
        return settings.active_month_override, start, end, True
    active_month, start, end = period_for_date(today or datetime.now(timezone.utc).date(), settings)
    return active_month, start, end, False


def get_period_settings(session: Session, household_id: int) -> HouseholdPeriodSettings:
    settings = session.exec(select(HouseholdPeriodSettings).where(HouseholdPeriodSettings.household_id == household_id)).first()
    if settings:
        return settings
    settings = HouseholdPeriodSettings(household_id=household_id, period_mode="calendar", start_day=1)
    session.add(settings)
    session.commit()
    session.refresh(settings)
    return settings


def period_for_date(value: Date, settings: HouseholdPeriodSettings) -> tuple[str, Date, Date]:
    if settings.period_mode != "custom" or settings.start_day <= 1:
        start = Date(value.year, value.month, 1)
        y, m = _month_add(value.year, value.month, 1)
        end = Date(y, m, 1) - timedelta(days=1)
        return f"{value.year:04d}-{value.month:02d}", start, end
    start_day = max(1, min(int(settings.start_day or 1), 28))
    if value.day >= start_day:
        start_y, start_m = value.year, value.month
    else:
        start_y, start_m = _month_add(value.year, value.month, -1)
    start = Date(start_y, start_m, start_day)
    end = _period_end(start)
    return f"{start_y:04d}-{start_m:02d}", start, end


def period_bounds_from_month(month: str, settings: HouseholdPeriodSettings) -> tuple[Date, Date]:
    year, mon = [int(x) for x in month.split("-")]
    if settings.period_mode == "custom" and settings.start_day > 1:
        start = Date(year, mon, max(1, min(int(settings.start_day), 28)))
        return start, _period_end(start)
    start = Date(year, mon, 1)
    y, m = _month_add(year, mon, 1)
    return start, Date(y, m, 1) - timedelta(days=1)


def ensure_owner(current_member: Member) -> None:
    if current_member.role != MemberRole.owner:
        raise HTTPException(status_code=403, detail="Solo el propietario del hogar puede cambiar usuarios o permisos")


def ensure_operator(current_member: Member) -> None:
    if current_member.role not in {MemberRole.owner, MemberRole.admin}:
        raise HTTPException(status_code=403, detail="Necesitás permiso de administrador operativo para esta acción")



def month_from_date(value) -> str:
    return f"{value.year:04d}-{value.month:02d}"



def _fixed_template_read(template: FixedExpenseTemplate) -> FixedExpenseTemplateRead:
    return FixedExpenseTemplateRead(**template.model_dump())


def _generated_fixed_expense_description(template: FixedExpenseTemplate) -> str:
    notes = (template.notes or '').strip()
    return f"Gasto fijo: {template.name.strip()}" + (f" · {notes}" if notes else "")


def _existing_generated_fixed_expense(session: Session, household_id: int, month: str, template: FixedExpenseTemplate) -> Expense | None:
    description = _generated_fixed_expense_description(template)
    return session.exec(
        select(Expense).where(
            Expense.household_id == household_id,
            Expense.month == month,
            Expense.category == (template.category.strip() or "General"),
            Expense.amount == template.amount,
            Expense.description == description,
        )
    ).first()


def _create_expense_from_fixed_template(
    session: Session,
    household_id: int,
    template: FixedExpenseTemplate,
    month: str,
    current_member: Member,
) -> Expense:
    if template.household_id != household_id:
        raise HTTPException(status_code=404, detail="Gasto fijo no encontrado")
    ensure_month_open(session, household_id, month)
    paid_by_member_id = template.default_paid_by_member_id or current_member.id
    ensure_member_in_household(session, household_id, paid_by_member_id)
    if _existing_generated_fixed_expense(session, household_id, month, template):
        raise HTTPException(status_code=409, detail="Este gasto fijo ya fue generado para este período.")
    settings = get_period_settings(session, household_id)
    period_start, _ = period_bounds_from_month(month, settings)
    expense = Expense(
        household_id=household_id,
        paid_by_member_id=paid_by_member_id,
        date=period_start,
        month=month,
        category=template.category.strip() or "General",
        amount=template.amount,
        description=_generated_fixed_expense_description(template),
        is_shared=True,
    )
    session.add(expense)
    session.commit()
    session.refresh(expense)
    return expense


def ensure_member_in_household(session: Session, household_id: int, member_id: int) -> Member:
    member = session.get(Member, member_id)
    if not member or member.household_id != household_id or not member.is_active:
        raise HTTPException(status_code=404, detail="Integrante no encontrado en este hogar")
    return member


def get_debt_for_household(session: Session, household_id: int, debt_id: int) -> Debt:
    debt = session.get(Debt, debt_id)
    if not debt or debt.household_id != household_id:
        raise HTTPException(status_code=404, detail="Deuda no encontrada")
    return debt


def get_month_close(session: Session, household_id: int, month: str) -> MonthlyClose | None:
    return session.exec(
        select(MonthlyClose).where(MonthlyClose.household_id == household_id, MonthlyClose.month == month)
    ).first()


def ensure_month_open(session: Session, household_id: int, month: str) -> None:
    if get_month_close(session, household_id, month):
        raise HTTPException(
            status_code=409,
            detail="Este mes ya está cerrado. Para cambiar ingresos, gastos o deudas automáticas primero hay que reabrirlo.",
        )


def debt_payments(session: Session, debt_id: int) -> list[DebtPayment]:
    return session.exec(select(DebtPayment).where(DebtPayment.debt_id == debt_id).order_by(DebtPayment.date.desc(), DebtPayment.id.desc())).all()


def confirmed_debt_payments(session: Session, debt_id: int) -> list[DebtPayment]:
    return session.exec(
        select(DebtPayment).where(DebtPayment.debt_id == debt_id, DebtPayment.status == PaymentStatus.confirmed)
    ).all()


def debt_paid_amount(session: Session, debt_id: int) -> float:
    payments = confirmed_debt_payments(session, debt_id)
    return round_money(sum(payment.applied_amount for payment in payments))


def debt_pending_amount(session: Session, debt_id: int) -> float:
    payments = session.exec(
        select(DebtPayment).where(DebtPayment.debt_id == debt_id, DebtPayment.status == PaymentStatus.pending)
    ).all()
    return round_money(sum(payment.amount for payment in payments))


def sync_debt_status(session: Session, debt: Debt) -> None:
    if debt.status == DebtStatus.cancelled:
        return
    paid = debt_paid_amount(session, debt.id or 0)
    remaining = round_money(max(debt.original_amount - paid, 0))
    if remaining <= 0.01:
        debt.status = DebtStatus.paid
    elif paid > 0.01:
        debt.status = DebtStatus.partial
    else:
        debt.status = DebtStatus.active
    debt.updated_at = datetime.now(timezone.utc)
    session.add(debt)


def debt_to_read(session: Session, debt: Debt) -> DebtRead:
    paid = debt_paid_amount(session, debt.id or 0)
    pending = debt_pending_amount(session, debt.id or 0)
    remaining = round_money(max(debt.original_amount - paid, 0))
    status = debt.status
    if debt.status != DebtStatus.cancelled:
        if remaining <= 0.01:
            status = DebtStatus.paid
        elif paid > 0.01:
            status = DebtStatus.partial
        else:
            status = DebtStatus.active
    return DebtRead(
        id=debt.id or 0,
        debtor_member_id=debt.debtor_member_id,
        creditor_member_id=debt.creditor_member_id,
        source=debt.source,
        source_month=debt.source_month,
        original_amount=round_money(debt.original_amount),
        paid_amount=paid,
        pending_amount=pending,
        remaining_amount=remaining,
        reason=debt.reason,
        status=status,
    )


def payment_to_read(payment: DebtPayment) -> DebtPaymentRead:
    return DebtPaymentRead(
        id=payment.id or 0,
        debt_id=payment.debt_id,
        paid_by_member_id=payment.paid_by_member_id,
        received_by_member_id=payment.received_by_member_id,
        amount=round_money(payment.amount),
        applied_amount=round_money(payment.applied_amount),
        credit_amount=round_money(payment.credit_amount),
        status=payment.status,
        date=payment.date,
        note=payment.note,
        rejected_reason=payment.rejected_reason,
        confirmed_by_member_id=payment.confirmed_by_member_id,
        confirmed_at=payment.confirmed_at,
    )


def credit_to_read(credit: CreditBalance) -> CreditBalanceRead:
    return CreditBalanceRead(
        id=credit.id or 0,
        owner_member_id=credit.owner_member_id,
        counterparty_member_id=credit.counterparty_member_id,
        source_payment_id=credit.source_payment_id,
        original_amount=round_money(credit.original_amount),
        remaining_amount=round_money(credit.remaining_amount),
        status=credit.status,
        reason=credit.reason,
        created_at=credit.created_at,
    )


def monthly_close_to_read(close: MonthlyClose) -> MonthlyCloseRead:
    summary = MonthSummary.model_validate(json.loads(close.summary_json))
    return MonthlyCloseRead(
        id=close.id or 0,
        household_id=close.household_id,
        month=close.month,
        total_income=round_money(close.total_income),
        total_shared_expenses=round_money(close.total_shared_expenses),
        summary=summary,
        closed_by_member_id=close.closed_by_member_id,
        created_at=close.created_at,
    )


def build_month_summary(month: str, household_id: int, session: Session) -> MonthSummary:
    members = session.exec(select(Member).where(Member.household_id == household_id)).all()
    incomes = session.exec(
        select(MonthlyIncome).where(MonthlyIncome.household_id == household_id, MonthlyIncome.month == month)
    ).all()
    expenses = session.exec(select(Expense).where(Expense.household_id == household_id, Expense.month == month)).all()
    participations = session.exec(
        select(MonthlyParticipation).where(MonthlyParticipation.household_id == household_id, MonthlyParticipation.month == month)
    ).all()
    advance_payments = session.exec(
        select(MonthlyAdvancePayment).where(
            MonthlyAdvancePayment.household_id == household_id,
            MonthlyAdvancePayment.month == month,
            MonthlyAdvancePayment.status == PaymentStatus.confirmed,
        )
    ).all()
    summary = calculate_month_summary(month, members, incomes, expenses, participations, advance_payments)
    if isinstance(summary, MonthSummary):
        return summary
    return MonthSummary.model_validate(summary)


def participation_to_read(member: Member, row: MonthlyParticipation | None, month: str) -> MemberParticipationRead:
    return MemberParticipationRead(
        member_id=member.id or 0,
        month=month,
        participates=row.participates if row else member.is_active,
        note=row.note if row else None,
    )


def get_participation_row(session: Session, household_id: int, member_id: int, month: str) -> MonthlyParticipation | None:
    return session.exec(
        select(MonthlyParticipation).where(
            MonthlyParticipation.household_id == household_id,
            MonthlyParticipation.member_id == member_id,
            MonthlyParticipation.month == month,
        )
    ).first()


@router.get("/participation", response_model=list[MemberParticipationRead])
def list_month_participation(
    month: str,
    include_inactive: bool = False,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    query = select(Member).where(Member.household_id == current_member.household_id)
    if not include_inactive:
        query = query.where(Member.is_active == True)
    members = session.exec(query.order_by(Member.is_active.desc(), Member.name.asc())).all()
    rows = session.exec(
        select(MonthlyParticipation).where(
            MonthlyParticipation.household_id == current_member.household_id,
            MonthlyParticipation.month == month,
        )
    ).all()
    by_member = {row.member_id: row for row in rows}
    return [participation_to_read(member, by_member.get(member.id or 0), month) for member in members]


@router.put("/participation/{member_id}", response_model=MemberParticipationRead)
def set_month_participation(
    member_id: int,
    payload: MemberParticipationUpdate,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    ensure_month_open(session, current_member.household_id, payload.month)
    member = session.get(Member, member_id)
    if not member or member.household_id != current_member.household_id:
        raise HTTPException(status_code=404, detail="Integrante no encontrado en este hogar")
    if payload.participates and not member.is_active:
        raise HTTPException(status_code=400, detail="No se puede incluir en el reparto a un integrante inactivo")

    if not payload.participates:
        active_members = session.exec(select(Member).where(Member.household_id == current_member.household_id, Member.is_active == True)).all()
        current_rows = session.exec(
            select(MonthlyParticipation).where(
                MonthlyParticipation.household_id == current_member.household_id,
                MonthlyParticipation.month == payload.month,
            )
        ).all()
        state = {m.id or 0: m.is_active for m in active_members}
        for row in current_rows:
            if row.member_id in state:
                state[row.member_id] = row.participates
        state[member_id] = False
        if not any(state.values()):
            raise HTTPException(status_code=409, detail="El mes debe conservar al menos un integrante participante")

    row = get_participation_row(session, current_member.household_id, member_id, payload.month)
    if row:
        row.participates = payload.participates
        row.note = payload.note
        row.updated_at = datetime.now(timezone.utc)
    else:
        row = MonthlyParticipation(
            household_id=current_member.household_id,
            member_id=member_id,
            month=payload.month,
            participates=payload.participates,
            note=payload.note,
        )
    session.add(row)
    session.commit()
    session.refresh(row)
    return participation_to_read(member, row, payload.month)


@router.post("/income", response_model=IncomeRead)
def upsert_income(
    payload: IncomeUpsert,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    ensure_month_open(session, current_member.household_id, payload.month)
    ensure_member_in_household(session, current_member.household_id, payload.member_id)
    existing = session.exec(
        select(MonthlyIncome).where(
            MonthlyIncome.household_id == current_member.household_id,
            MonthlyIncome.member_id == payload.member_id,
            MonthlyIncome.month == payload.month,
        )
    ).first()

    if existing:
        existing.amount = payload.amount
        existing.note = payload.note
        existing.updated_at = datetime.now(timezone.utc)
        session.add(existing)
        session.commit()
        session.refresh(existing)
        income = existing
    else:
        income = MonthlyIncome(
            household_id=current_member.household_id,
            member_id=payload.member_id,
            month=payload.month,
            amount=payload.amount,
            note=payload.note,
        )
        session.add(income)
        session.commit()
        session.refresh(income)

    return IncomeRead(id=income.id or 0, member_id=income.member_id, month=income.month, amount=income.amount, note=income.note)


@router.get("/income", response_model=list[IncomeRead])
def list_income(month: str, current_member: Member = Depends(get_current_member), session: Session = Depends(get_session)):
    rows = session.exec(
        select(MonthlyIncome).where(MonthlyIncome.household_id == current_member.household_id, MonthlyIncome.month == month)
    ).all()
    return [IncomeRead(id=row.id or 0, member_id=row.member_id, month=row.month, amount=row.amount, note=row.note) for row in rows]


@router.get("/fixed-expenses", response_model=list[FixedExpenseTemplateRead])
def list_fixed_expenses(
    active_only: bool = True,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    query = select(FixedExpenseTemplate).where(FixedExpenseTemplate.household_id == current_member.household_id)
    if active_only:
        query = query.where(FixedExpenseTemplate.active == True)  # noqa: E712
    rows = session.exec(query.order_by(FixedExpenseTemplate.active.desc(), FixedExpenseTemplate.name.asc())).all()
    return [_fixed_template_read(row) for row in rows]


@router.post("/fixed-expenses", response_model=FixedExpenseTemplateRead)
def create_fixed_expense(
    payload: FixedExpenseTemplateCreate,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    paid_by = payload.default_paid_by_member_id
    if paid_by is not None:
        ensure_member_in_household(session, current_member.household_id, paid_by)
    template = FixedExpenseTemplate(
        household_id=current_member.household_id,
        name=payload.name.strip(),
        amount=payload.amount,
        category=payload.category.strip() or "General",
        default_paid_by_member_id=paid_by,
        frequency=payload.frequency.strip() or "monthly",
        active=payload.active,
        notes=(payload.notes or '').strip(),
    )
    session.add(template)
    session.commit()
    session.refresh(template)
    return _fixed_template_read(template)


@router.patch("/fixed-expenses/{template_id}", response_model=FixedExpenseTemplateRead)
def update_fixed_expense(
    template_id: int,
    payload: FixedExpenseTemplateUpdate,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    template = session.get(FixedExpenseTemplate, template_id)
    if not template or template.household_id != current_member.household_id:
        raise HTTPException(status_code=404, detail="Gasto fijo no encontrado")
    if payload.default_paid_by_member_id is not None:
        ensure_member_in_household(session, current_member.household_id, payload.default_paid_by_member_id)
    if payload.name is not None:
        template.name = payload.name.strip()
    if payload.amount is not None:
        template.amount = payload.amount
    if payload.category is not None:
        template.category = payload.category.strip() or "General"
    if 'default_paid_by_member_id' in payload.model_fields_set:
        template.default_paid_by_member_id = payload.default_paid_by_member_id
    if payload.frequency is not None:
        template.frequency = payload.frequency.strip() or "monthly"
    if payload.active is not None:
        template.active = payload.active
    if payload.notes is not None:
        template.notes = payload.notes.strip()
    template.updated_at = datetime.now(timezone.utc)
    session.add(template)
    session.commit()
    session.refresh(template)
    return _fixed_template_read(template)


@router.post("/fixed-expenses/{template_id}/generate", response_model=ExpenseRead)
def generate_fixed_expense(
    template_id: int,
    month: str = Query(pattern=r"^\d{4}-\d{2}$"),
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    template = session.get(FixedExpenseTemplate, template_id)
    if not template or template.household_id != current_member.household_id:
        raise HTTPException(status_code=404, detail="Gasto fijo no encontrado")
    if not template.active:
        raise HTTPException(status_code=409, detail="Este gasto fijo está inactivo.")
    expense = _create_expense_from_fixed_template(session, current_member.household_id, template, month, current_member)
    return ExpenseRead(**expense.model_dump())


@router.post("/fixed-expenses/generate-for-month", response_model=list[ExpenseRead])
def generate_fixed_expenses_for_month(
    month: str = Query(pattern=r"^\d{4}-\d{2}$"),
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    templates = session.exec(
        select(FixedExpenseTemplate).where(
            FixedExpenseTemplate.household_id == current_member.household_id,
            FixedExpenseTemplate.active == True,  # noqa: E712
        )
    ).all()
    generated: list[Expense] = []
    for template in templates:
        if _existing_generated_fixed_expense(session, current_member.household_id, month, template):
            continue
        generated.append(_create_expense_from_fixed_template(session, current_member.household_id, template, month, current_member))
    return [ExpenseRead(**expense.model_dump()) for expense in generated]




@router.post("/card-imports/preview", response_model=CardImportPreviewResponse)
async def preview_card_import(
    file: UploadFile = File(...),
    month: str | None = Query(default=None, pattern=r"^\d{4}-\d{2}$"),
    current_member: Member = Depends(get_current_member),
):
    filename = (file.filename or '').lower()
    if not filename.endswith('.pdf'):
        raise HTTPException(status_code=400, detail='Subí un archivo PDF de resumen de tarjeta.')
    file_bytes = await file.read()
    if not file_bytes:
        raise HTTPException(status_code=400, detail='El PDF está vacío.')
    if len(file_bytes) > _CARD_IMPORT_MAX_BYTES:
        raise HTTPException(status_code=413, detail='El PDF supera el tamaño máximo permitido para esta vista previa.')
    text, warnings = _extract_pdf_text(file_bytes)
    items, detection_warnings = _detect_card_movements(text, month)
    warnings.extend(detection_warnings)
    if items:
        warnings.append('Vista previa solamente: ningún movimiento fue cargado como gasto común.')
    return CardImportPreviewResponse(items=items, warnings=warnings)


@router.post("/expenses", response_model=ExpenseRead)
def create_expense(
    payload: ExpenseCreate,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    settings = get_period_settings(session, current_member.household_id)
    if settings.active_month_override:
        expense_month = settings.active_month_override
    else:
        expense_month, _, _ = period_for_date(payload.date, settings)
    ensure_month_open(session, current_member.household_id, expense_month)
    ensure_member_in_household(session, current_member.household_id, payload.paid_by_member_id)
    expense = Expense(
        household_id=current_member.household_id,
        paid_by_member_id=payload.paid_by_member_id,
        date=payload.date,
        month=expense_month,
        category=payload.category.strip() or "General",
        amount=payload.amount,
        description=payload.description.strip(),
        is_shared=payload.is_shared,
    )
    session.add(expense)
    session.commit()
    session.refresh(expense)
    return ExpenseRead(**expense.model_dump())


@router.get("/expenses", response_model=list[ExpenseRead])
def list_expenses(month: str, current_member: Member = Depends(get_current_member), session: Session = Depends(get_session)):
    rows = session.exec(
        select(Expense)
        .where(Expense.household_id == current_member.household_id, Expense.month == month)
        .order_by(Expense.date.desc(), Expense.id.desc())
    ).all()
    return [ExpenseRead(**row.model_dump()) for row in rows]


@router.delete("/expenses/{expense_id}")
def delete_expense(
    expense_id: int,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    expense = session.get(Expense, expense_id)
    if not expense or expense.household_id != current_member.household_id:
        raise HTTPException(status_code=404, detail="Gasto no encontrado")
    ensure_month_open(session, current_member.household_id, expense.month)
    session.delete(expense)
    session.commit()
    return {"ok": True}


@router.get("/summary", response_model=MonthSummary)
def get_month_summary(month: str, current_member: Member = Depends(get_current_member), session: Session = Depends(get_session)):
    return build_month_summary(month, current_member.household_id, session)


@router.post("/debts", response_model=DebtRead)
def create_manual_debt(
    payload: DebtCreate,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    ensure_member_in_household(session, current_member.household_id, payload.debtor_member_id)
    ensure_member_in_household(session, current_member.household_id, payload.creditor_member_id)
    if payload.debtor_member_id == payload.creditor_member_id:
        raise HTTPException(status_code=400, detail="Deudor y acreedor no pueden ser la misma persona")
    debt = Debt(
        household_id=current_member.household_id,
        debtor_member_id=payload.debtor_member_id,
        creditor_member_id=payload.creditor_member_id,
        source=DebtSource.manual,
        original_amount=payload.original_amount,
        reason=payload.reason.strip(),
    )
    session.add(debt)
    session.commit()
    session.refresh(debt)
    return debt_to_read(session, debt)


@router.post("/debts/from-summary", response_model=list[DebtRead])
def create_automatic_debts_from_summary(
    payload: AutomaticDebtCreate,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    ensure_month_open(session, current_member.household_id, payload.month)
    previous = session.exec(
        select(Debt).where(
            Debt.household_id == current_member.household_id,
            Debt.source == DebtSource.automatic,
            Debt.source_month == payload.month,
            Debt.status == DebtStatus.active,
        )
    ).all()

    for debt in previous:
        if debt_paid_amount(session, debt.id or 0) > 0:
            raise HTTPException(
                status_code=409,
                detail="Ya existe una deuda automática de este mes con abonos cargados. No se cancela ni se pisa para proteger la trazabilidad.",
            )

    summary = build_month_summary(payload.month, current_member.household_id, session)

    for debt in previous:
        debt.status = DebtStatus.cancelled
        debt.updated_at = datetime.now(timezone.utc)
        session.add(debt)
    session.commit()

    created: list[Debt] = []
    for settlement in summary.settlements:
        debt = Debt(
            household_id=current_member.household_id,
            debtor_member_id=settlement.debtor_member_id,
            creditor_member_id=settlement.creditor_member_id,
            source=DebtSource.automatic,
            source_month=payload.month,
            original_amount=settlement.amount,
            reason=settlement.reason,
        )
        session.add(debt)
        session.commit()
        session.refresh(debt)
        created.append(debt)
    return [debt_to_read(session, debt) for debt in created]


@router.get("/debts", response_model=list[DebtRead])
def list_debts(
    include_cancelled: bool = False,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    query = select(Debt).where(Debt.household_id == current_member.household_id)
    if not include_cancelled:
        query = query.where(Debt.status != DebtStatus.cancelled)
    rows = session.exec(query.order_by(Debt.created_at.desc())).all()
    return [debt_to_read(session, row) for row in rows]


@router.get("/debts/{debt_id}/payments", response_model=list[DebtPaymentRead])
def list_debt_payments(
    debt_id: int,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    debt = get_debt_for_household(session, current_member.household_id, debt_id)
    return [payment_to_read(payment) for payment in debt_payments(session, debt.id or 0)]


@router.post("/debts/{debt_id}/payments", response_model=DebtPaymentRead)
def add_debt_payment(
    debt_id: int,
    payload: DebtPaymentCreate,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    debt = get_debt_for_household(session, current_member.household_id, debt_id)
    if debt.status == DebtStatus.cancelled:
        raise HTTPException(status_code=400, detail="No se pueden cargar abonos sobre una deuda cancelada")
    current_read = debt_to_read(session, debt)
    if current_read.remaining_amount <= 0.01:
        raise HTTPException(status_code=400, detail="Esta deuda ya figura como saldada. Si hay un nuevo pago, conviene crear un nuevo acuerdo o usar saldo a favor existente.")
    if current_member.id != debt.debtor_member_id:
        raise HTTPException(status_code=403, detail="Solo quien figura como deudor puede registrar un abono pendiente de confirmación")

    payment = DebtPayment(
        debt_id=debt.id or 0,
        household_id=current_member.household_id,
        paid_by_member_id=current_member.id or 0,
        received_by_member_id=debt.creditor_member_id,
        amount=payload.amount,
        applied_amount=0,
        credit_amount=0,
        status=PaymentStatus.pending,
        date=payload.date,
        note=payload.note.strip(),
    )
    session.add(payment)
    session.commit()
    session.refresh(payment)
    return payment_to_read(payment)


def get_payment_for_debt(session: Session, household_id: int, debt_id: int, payment_id: int) -> DebtPayment:
    payment = session.get(DebtPayment, payment_id)
    if not payment or payment.household_id != household_id or payment.debt_id != debt_id:
        raise HTTPException(status_code=404, detail="Abono no encontrado")
    return payment


@router.post("/debts/{debt_id}/payments/{payment_id}/confirm", response_model=DebtPaymentRead)
def confirm_debt_payment(
    debt_id: int,
    payment_id: int,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    debt = get_debt_for_household(session, current_member.household_id, debt_id)
    payment = get_payment_for_debt(session, current_member.household_id, debt_id, payment_id)
    if current_member.id != debt.creditor_member_id:
        raise HTTPException(status_code=403, detail="Solo quien recibe el pago puede confirmarlo")
    if payment.status != PaymentStatus.pending:
        raise HTTPException(status_code=409, detail="Este abono ya fue resuelto")

    remaining_before = debt_to_read(session, debt).remaining_amount
    applied = round_money(min(payment.amount, remaining_before))
    credit = round_money(max(payment.amount - applied, 0))

    payment.status = PaymentStatus.confirmed
    payment.applied_amount = applied
    payment.credit_amount = credit
    payment.confirmed_by_member_id = current_member.id
    payment.confirmed_at = datetime.now(timezone.utc)
    payment.updated_at = datetime.now(timezone.utc)
    session.add(payment)

    if credit > 0.01:
        credit_row = CreditBalance(
            household_id=current_member.household_id,
            owner_member_id=payment.paid_by_member_id,
            counterparty_member_id=debt.creditor_member_id,
            source_payment_id=payment.id,
            original_amount=credit,
            remaining_amount=credit,
            status=CreditBalanceStatus.available,
            reason=f"Excedente confirmado del abono #{payment.id} sobre deuda #{debt.id}",
        )
        session.add(credit_row)

    sync_debt_status(session, debt)
    session.commit()
    session.refresh(payment)
    return payment_to_read(payment)


@router.post("/debts/{debt_id}/payments/{payment_id}/reject", response_model=DebtPaymentRead)
def reject_debt_payment(
    debt_id: int,
    payment_id: int,
    payload: DebtPaymentDecision,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    debt = get_debt_for_household(session, current_member.household_id, debt_id)
    payment = get_payment_for_debt(session, current_member.household_id, debt_id, payment_id)
    if current_member.id != debt.creditor_member_id:
        raise HTTPException(status_code=403, detail="Solo quien recibiría el pago puede rechazarlo")
    if payment.status != PaymentStatus.pending:
        raise HTTPException(status_code=409, detail="Este abono ya fue resuelto")
    payment.status = PaymentStatus.rejected
    payment.rejected_reason = payload.reason.strip()
    payment.updated_at = datetime.now(timezone.utc)
    session.add(payment)
    session.commit()
    session.refresh(payment)
    return payment_to_read(payment)


@router.post("/debts/{debt_id}/payments/{payment_id}/void", response_model=DebtPaymentRead)
def void_debt_payment(
    debt_id: int,
    payment_id: int,
    payload: DebtPaymentDecision,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    debt = get_debt_for_household(session, current_member.household_id, debt_id)
    payment = get_payment_for_debt(session, current_member.household_id, debt_id, payment_id)
    if payment.status != PaymentStatus.pending:
        raise HTTPException(status_code=409, detail="Solo se puede anular un abono pendiente")
    if current_member.id not in {payment.paid_by_member_id, debt.creditor_member_id}:
        raise HTTPException(status_code=403, detail="Solo quien registró o recibiría el pago puede anularlo")
    note = payload.reason.strip()
    payment.status = PaymentStatus.voided
    payment.rejected_reason = note
    payment.updated_at = datetime.now(timezone.utc)
    session.add(payment)
    session.commit()
    session.refresh(payment)
    return payment_to_read(payment)


@router.get("/credit-balances", response_model=list[CreditBalanceRead])
def list_credit_balances(
    active_only: bool = True,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    query = select(CreditBalance).where(CreditBalance.household_id == current_member.household_id)
    if active_only:
        query = query.where(CreditBalance.status == CreditBalanceStatus.available, CreditBalance.remaining_amount > 0.01)
    rows = session.exec(query.order_by(CreditBalance.created_at.desc(), CreditBalance.id.desc())).all()
    return [credit_to_read(row) for row in rows]


@router.post("/credit-balances/{credit_id}/apply", response_model=CreditBalanceRead)
def apply_credit_balance(
    credit_id: int,
    payload: CreditBalanceApply,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    credit = session.get(CreditBalance, credit_id)
    if not credit or credit.household_id != current_member.household_id:
        raise HTTPException(status_code=404, detail="Saldo a favor no encontrado")
    if credit.status != CreditBalanceStatus.available or credit.remaining_amount <= 0.01:
        raise HTTPException(status_code=400, detail="Este saldo a favor ya no está disponible")
    if current_member.id != credit.owner_member_id:
        raise HTTPException(status_code=403, detail="Solo el titular del saldo a favor puede aplicarlo")

    debt = get_debt_for_household(session, current_member.household_id, payload.debt_id)
    if debt.status == DebtStatus.cancelled:
        raise HTTPException(status_code=400, detail="No se puede aplicar saldo a una deuda cancelada")
    if debt.debtor_member_id != credit.owner_member_id or debt.creditor_member_id != credit.counterparty_member_id:
        raise HTTPException(status_code=400, detail="El saldo a favor solo puede aplicarse a deudas con la misma contraparte")

    remaining_debt = debt_to_read(session, debt).remaining_amount
    if remaining_debt <= 0.01:
        raise HTTPException(status_code=400, detail="La deuda seleccionada ya está saldada")
    amount = round_money(min(payload.amount, credit.remaining_amount, remaining_debt))
    if amount <= 0.01:
        raise HTTPException(status_code=400, detail="No hay monto disponible para aplicar")

    payment = DebtPayment(
        debt_id=debt.id or 0,
        household_id=current_member.household_id,
        paid_by_member_id=credit.owner_member_id,
        received_by_member_id=credit.counterparty_member_id,
        amount=amount,
        applied_amount=amount,
        credit_amount=0,
        status=PaymentStatus.confirmed,
        date=datetime.now(timezone.utc).date(),
        note=payload.note.strip() or f"Aplicado desde saldo a favor #{credit.id}",
        confirmed_by_member_id=credit.counterparty_member_id,
        confirmed_at=datetime.now(timezone.utc),
    )
    session.add(payment)
    credit.remaining_amount = round_money(max(credit.remaining_amount - amount, 0))
    if credit.remaining_amount <= 0.01:
        credit.status = CreditBalanceStatus.applied
    credit.updated_at = datetime.now(timezone.utc)
    session.add(credit)
    sync_debt_status(session, debt)
    session.commit()
    session.refresh(credit)
    return credit_to_read(credit)


@router.patch("/debts/{debt_id}/cancel", response_model=DebtRead)
def cancel_debt(
    debt_id: int,
    payload: DebtCancel,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    debt = get_debt_for_household(session, current_member.household_id, debt_id)
    if debt_paid_amount(session, debt.id or 0) > 0 or debt_pending_amount(session, debt.id or 0) > 0:
        raise HTTPException(status_code=409, detail="No se cancela una deuda con abonos registrados o pendientes. La trazabilidad queda protegida.")
    debt.status = DebtStatus.cancelled
    note = payload.reason.strip()
    if note:
        debt.reason = f"{debt.reason}\nCancelada: {note}" if debt.reason else f"Cancelada: {note}"
    debt.updated_at = datetime.now(timezone.utc)
    session.add(debt)
    session.commit()
    session.refresh(debt)
    return debt_to_read(session, debt)




def advance_payment_to_read(payment: MonthlyAdvancePayment) -> MonthlyAdvancePaymentRead:
    return MonthlyAdvancePaymentRead(
        id=payment.id or 0,
        month=payment.month,
        paid_by_member_id=payment.paid_by_member_id,
        received_by_member_id=payment.received_by_member_id,
        amount=round_money(payment.amount),
        applied_amount=round_money(payment.applied_amount),
        credit_amount=round_money(payment.credit_amount),
        status=payment.status,
        date=payment.date,
        note=payment.note,
        rejected_reason=payment.rejected_reason,
        confirmed_by_member_id=payment.confirmed_by_member_id,
        confirmed_at=payment.confirmed_at,
    )


def period_settings_to_read(session: Session, household_id: int) -> HouseholdPeriodSettingsRead:
    settings = get_period_settings(session, household_id)
    active_month, start, end, is_manual = _active_period(settings)
    mode_label = "mes calendario" if settings.period_mode != "custom" else f"corte día {settings.start_day}"
    manual_label = " · período operativo manual" if is_manual else ""
    return HouseholdPeriodSettingsRead(
        period_mode=settings.period_mode,
        start_day=settings.start_day,
        active_month=active_month,
        period_start=start,
        period_end=end,
        label=f"{active_month} · {mode_label}{manual_label} · {start.isoformat()} al {end.isoformat()}",
        active_month_override=settings.active_month_override,
        is_manual=is_manual,
    )


@router.get("/period-settings", response_model=HouseholdPeriodSettingsRead)
def read_period_settings(current_member: Member = Depends(get_current_member), session: Session = Depends(get_session)):
    return period_settings_to_read(session, current_member.household_id)


@router.put("/period-settings", response_model=HouseholdPeriodSettingsRead)
def update_period_settings(
    payload: HouseholdPeriodSettingsUpdate,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    ensure_operator(current_member)
    settings = get_period_settings(session, current_member.household_id)
    if payload.period_mode is not None:
        if payload.period_mode not in {"calendar", "custom"}:
            raise HTTPException(status_code=400, detail="El período debe ser calendario o corte personalizado")
        settings.period_mode = payload.period_mode
    if payload.start_day is not None:
        settings.start_day = max(1, min(int(payload.start_day), 28))
    if settings.period_mode == "calendar":
        settings.start_day = 1
    settings.updated_by_member_id = current_member.id
    settings.updated_at = datetime.now(timezone.utc)
    session.add(settings)
    session.commit()
    session.refresh(settings)
    return period_settings_to_read(session, current_member.household_id)


@router.get("/active-period", response_model=HouseholdPeriodSettingsRead)
def read_active_period(current_member: Member = Depends(get_current_member), session: Session = Depends(get_session)):
    return period_settings_to_read(session, current_member.household_id)


@router.get("/monthly-advance-payments", response_model=list[MonthlyAdvancePaymentRead])
def list_monthly_advance_payments(
    month: str,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    rows = session.exec(
        select(MonthlyAdvancePayment).where(
            MonthlyAdvancePayment.household_id == current_member.household_id,
            MonthlyAdvancePayment.month == month,
        ).order_by(MonthlyAdvancePayment.created_at.desc(), MonthlyAdvancePayment.id.desc())
    ).all()
    return [advance_payment_to_read(row) for row in rows]


@router.post("/monthly-advance-payments", response_model=MonthlyAdvancePaymentRead)
def create_monthly_advance_payment(
    payload: MonthlyAdvancePaymentCreate,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    ensure_month_open(session, current_member.household_id, payload.month)
    receiver = ensure_member_in_household(session, current_member.household_id, payload.received_by_member_id)
    if receiver.id == current_member.id:
        raise HTTPException(status_code=400, detail="El receptor no puede ser la misma persona que registra el pago")
    payment = MonthlyAdvancePayment(
        household_id=current_member.household_id,
        month=payload.month,
        paid_by_member_id=current_member.id or 0,
        received_by_member_id=payload.received_by_member_id,
        amount=payload.amount,
        date=payload.date,
        note=payload.note.strip(),
        status=PaymentStatus.pending,
    )
    session.add(payment)
    session.commit()
    session.refresh(payment)
    return advance_payment_to_read(payment)


def _get_advance_payment(session: Session, household_id: int, payment_id: int) -> MonthlyAdvancePayment:
    payment = session.get(MonthlyAdvancePayment, payment_id)
    if not payment or payment.household_id != household_id:
        raise HTTPException(status_code=404, detail="Pago anticipado no encontrado")
    return payment


@router.post("/monthly-advance-payments/{payment_id}/confirm", response_model=MonthlyAdvancePaymentRead)
def confirm_monthly_advance_payment(
    payment_id: int,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    payment = _get_advance_payment(session, current_member.household_id, payment_id)
    if current_member.id != payment.received_by_member_id:
        raise HTTPException(status_code=403, detail="Solo quien recibe el pago puede confirmarlo")
    if payment.status != PaymentStatus.pending:
        raise HTTPException(status_code=409, detail="Este pago anticipado ya fue resuelto")
    summary = build_month_summary(payment.month, current_member.household_id, session)
    matching = next((s for s in summary.settlements if s.debtor_member_id == payment.paid_by_member_id and s.creditor_member_id == payment.received_by_member_id), None)
    remaining_before = matching.amount if matching else 0
    applied = round_money(min(payment.amount, remaining_before))
    credit = round_money(max(payment.amount - applied, 0))
    payment.status = PaymentStatus.confirmed
    payment.applied_amount = applied
    payment.credit_amount = credit
    payment.confirmed_by_member_id = current_member.id
    payment.confirmed_at = datetime.now(timezone.utc)
    payment.updated_at = datetime.now(timezone.utc)
    session.add(payment)
    if credit > 0.01:
        credit_row = CreditBalance(
            household_id=current_member.household_id,
            owner_member_id=payment.paid_by_member_id,
            counterparty_member_id=payment.received_by_member_id,
            source_payment_id=None,
            original_amount=credit,
            remaining_amount=credit,
            status=CreditBalanceStatus.available,
            reason=f"Excedente confirmado del pago anticipado #{payment.id} del período {payment.month}",
        )
        session.add(credit_row)
    session.commit()
    session.refresh(payment)
    return advance_payment_to_read(payment)


@router.post("/monthly-advance-payments/{payment_id}/reject", response_model=MonthlyAdvancePaymentRead)
def reject_monthly_advance_payment(
    payment_id: int,
    payload: DebtPaymentDecision,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    payment = _get_advance_payment(session, current_member.household_id, payment_id)
    if current_member.id != payment.received_by_member_id:
        raise HTTPException(status_code=403, detail="Solo quien recibiría el pago puede rechazarlo")
    if payment.status != PaymentStatus.pending:
        raise HTTPException(status_code=409, detail="Este pago anticipado ya fue resuelto")
    payment.status = PaymentStatus.rejected
    payment.rejected_reason = payload.reason.strip()
    payment.updated_at = datetime.now(timezone.utc)
    session.add(payment)
    session.commit()
    session.refresh(payment)
    return advance_payment_to_read(payment)


@router.post("/monthly-closes", response_model=MonthlyCloseRead)
def close_month(
    payload: MonthCloseCreate,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    ensure_operator(current_member)
    existing = get_month_close(session, current_member.household_id, payload.month)
    if existing:
        raise HTTPException(status_code=409, detail="Este mes ya estaba cerrado. Reabrilo si necesitás corregir algo.")

    summary = build_month_summary(payload.month, current_member.household_id, session)
    if summary.total_income <= 0:
        raise HTTPException(status_code=400, detail="No se puede cerrar un mes sin ingresos cargados.")

    close = MonthlyClose(
        household_id=current_member.household_id,
        month=payload.month,
        total_income=summary.total_income,
        total_shared_expenses=summary.total_shared_expenses,
        summary_json=json.dumps(summary.model_dump(), ensure_ascii=False),
        closed_by_member_id=current_member.id or 0,
    )
    session.add(close)

    if payload.advance_to_next:
        settings = get_period_settings(session, current_member.household_id)
        settings.active_month_override = _month_str_add(payload.month, 1)
        settings.updated_by_member_id = current_member.id
        settings.updated_at = datetime.now(timezone.utc)
        session.add(settings)

    session.commit()
    session.refresh(close)
    return monthly_close_to_read(close)


@router.get("/monthly-closes", response_model=list[MonthlyCloseRead])
def list_monthly_closes(
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    rows = session.exec(
        select(MonthlyClose)
        .where(MonthlyClose.household_id == current_member.household_id)
        .order_by(MonthlyClose.month.desc(), MonthlyClose.id.desc())
    ).all()
    return [monthly_close_to_read(row) for row in rows]


@router.get("/monthly-closes/{month}", response_model=MonthlyCloseRead)
def read_monthly_close(
    month: str,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    close = get_month_close(session, current_member.household_id, month)
    if not close:
        raise HTTPException(status_code=404, detail="Cierre mensual no encontrado")
    return monthly_close_to_read(close)


@router.post("/monthly-closes/{month}/reopen")
def reopen_month(
    month: str,
    payload: MonthReopen,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    ensure_operator(current_member)
    close = get_month_close(session, current_member.household_id, month)
    if not close:
        raise HTTPException(status_code=404, detail="El mes no estaba cerrado")
    session.delete(close)
    session.commit()
    return {"ok": True, "month": month, "reason": payload.reason}
