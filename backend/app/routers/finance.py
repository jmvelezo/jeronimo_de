import json
import re
import unicodedata
from io import BytesIO
from types import SimpleNamespace
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
    ActivePeriodResetRead,
    AutomaticDebtCreate,
    CardImportPreviewItem,
    CardImportPreviewResponse,
    DebtCancel,
    DebtCreate,
    DebtIncrease,
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
    IncomeSelfUpsert,
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
    MonthPeriodStatusRead,
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
        page_count = len(reader.pages)
        for page in reader.pages[:12]:
            texts.append(page.extract_text() or '')
        text = '\n'.join(texts).strip()
        if page_count > 12:
            warnings.append('El PDF tiene más de 12 páginas. Se leyó la primera parte para mantener la vista previa liviana.')
        if page_count:
            pages_read = min(page_count, 12)
            page_suffix = '' if pages_read == 1 else 's'
            warnings.append(f'Se leyó texto de {pages_read} página{page_suffix} del PDF.')
    except Exception as exc:
        raise HTTPException(status_code=400, detail='No se pudo leer el PDF. Probá con un resumen digital, no escaneado.') from exc
    if not text:
        warnings.append('No se detectó texto en el PDF. Si es un escaneo o imagen, esta etapa no usa OCR.')
    return text, warnings


def _clean_card_line(raw: str) -> str:
    return re.sub(r'\s+', ' ', raw.replace('\xa0', ' ')).strip()


def _strip_card_accents(value: str) -> str:
    normalized = unicodedata.normalize('NFKD', value)
    return ''.join(char for char in normalized if not unicodedata.combining(char))


def _normalize_card_description(description: str) -> str:
    text = _strip_card_accents(description).lower()
    text = re.sub(r'\b\d{1,2}[/-]\d{1,2}(?:[/-]\d{2,4})?\b', ' ', text)
    text = re.sub(r'\b(?:ars|pesos|usd|u\$s|visa|mastercard|master|tarjeta|debito|credito)\b', ' ', text)
    text = re.sub(r'\b(?:compra|consumo|establecimiento|comprobante|autorizacion|cuotas?|plan|nro|numero)\b', ' ', text)
    text = re.sub(r'\b\d{3,}\b', ' ', text)
    text = re.sub(r'[^a-z0-9]+', ' ', text)
    tokens = [token for token in text.split() if len(token) > 1]
    return ' '.join(tokens)[:96]


def _descriptions_look_duplicated(left: str, right: str) -> bool:
    if not left or not right:
        return False
    if left == right or left in right or right in left:
        return True
    left_tokens = set(left.split())
    right_tokens = set(right.split())
    if not left_tokens or not right_tokens:
        return False
    overlap = len(left_tokens & right_tokens)
    return overlap >= 2 and overlap / min(len(left_tokens), len(right_tokens)) >= 0.75


def _line_looks_like_transaction_start(line: str) -> bool:
    if _looks_like_summary_line(line):
        return False
    has_date = re.search(r'^\s*\d{1,2}[/-]\d{1,2}(?:[/-]\d{2,4})?\b', line) is not None
    has_amount = re.search(r'(?:\$\s*)?-?\d{1,3}(?:[.\s]\d{3})*(?:,\d{2})|-?\d+(?:,\d{2})', line) is not None
    return has_date and has_amount


def _line_windows(lines: list[str]) -> list[tuple[str, int, int]]:
    windows: list[tuple[str, int, int]] = []
    for index, line in enumerate(lines):
        windows.append((line, index, 1))
        if index + 1 < len(lines) and not _line_looks_like_transaction_start(lines[index + 1]):
            windows.append((f'{line} {lines[index + 1]}', index, 2))
            if index + 2 < len(lines) and not _line_looks_like_transaction_start(lines[index + 2]):
                windows.append((f'{line} {lines[index + 1]} {lines[index + 2]}', index, 3))
    return windows


def _looks_like_summary_line(line: str) -> bool:
    lower = line.lower()
    summary_words = (
        'total', 'saldo', 'pago minimo', 'pago mínimo', 'vencimiento', 'cierre',
        'limite', 'límite', 'resumen', 'anterior', 'financiacion', 'financiación',
        'interes', 'interés', 'iva', 'sellado', 'tna', 'tea', 'cft', 'disponible',
    )
    movement_words = (
        'compra', 'consumo', 'establecimiento', 'cuota', 'debito', 'débito',
        'mercado', 'super', 'farmacia', 'ypf', 'shell', 'uber', 'cabify', 'rappi',
        'pedidosya', 'transfer', 'spotify', 'netflix', 'personal pay', 'movistar',
    )
    if not any(word in lower for word in summary_words):
        return False
    if any(word in lower for word in movement_words):
        return False
    return True


def _extract_installments(line: str) -> str | None:
    patterns = [
        r'cuotas?\s*(\d{1,2})\s*/\s*(\d{1,2})',
        r'cuotas?\s*(\d{1,2})\s+de\s+(\d{1,2})',
        r'\b(\d{1,2})\s*/\s*(\d{1,2})\b',
    ]
    lower = line.lower()
    for pattern in patterns:
        match = re.search(pattern, lower)
        if match:
            if '/' in match.group(0) and 'cuot' not in lower:
                start = max(0, match.start() - 12)
                end = min(len(lower), match.end() + 12)
                if 'cuot' not in lower[start:end]:
                    continue
            return f'{match.group(1)}/{match.group(2)}'
    return None


def _description_from_card_line(line: str, date_match: re.Match[str] | None, amount_match: re.Match[str]) -> str:
    without_amount = (line[:amount_match.start()] + ' ' + line[amount_match.end():]).strip()
    if date_match:
        # Recalcular sobre la cadena sin importe: alcanza para limpiar la fecha aunque el índice cambie levemente.
        without_amount = re.sub(r'\b\d{1,2}[/-]\d{1,2}(?:[/-]\d{2,4})?\b', ' ', without_amount, count=1)
    description = without_amount
    description = re.sub(r'\b(?:ars|pesos|usd|u\$s)\b', ' ', description, flags=re.I)
    description = re.sub(r'\b(?:cuotas?|plan)\s*\d{1,2}\s*(?:/|de)\s*\d{1,2}\b', ' ', description, flags=re.I)
    description = re.sub(r'\b\d{3,}\b', ' ', description)
    description = re.sub(r'\s+', ' ', description).strip(' -·|:;')
    return description[:160] or 'Movimiento detectado'


def _find_card_date_match(line: str, date_re: re.Pattern[str]) -> re.Match[str] | None:
    matches = list(date_re.finditer(line))
    if not matches:
        return None
    lower = line.lower()
    for match in matches:
        start = max(0, match.start() - 14)
        end = min(len(lower), match.end() + 14)
        if 'cuot' in lower[start:end]:
            continue
        parsed = _parse_card_date(match.group(1))
        if parsed is not None:
            return match
    return None


def _candidate_without_date(line: str, fallback_month: str | None) -> bool:
    if not fallback_month:
        return False
    lower = line.lower()
    movement_words = (
        'compra', 'consumo', 'cuota', 'debito', 'débito', 'mercado', 'super',
        'farmacia', 'restaurant', 'resto', 'bar ', 'cafe', 'cafÉ', 'uber', 'cabify',
        'rappi', 'pedidosya', 'netflix', 'spotify', 'movistar', 'personal', 'telecom',
        'edenor', 'edesur', 'aysa', 'ypf', 'shell', 'axion', 'carrefour', 'coto', 'jumbo',
    )
    return any(word in lower for word in movement_words)


def _detect_card_movements(text: str, fallback_month: str | None = None) -> tuple[list[CardImportPreviewItem], list[str]]:
    warnings: list[str] = []
    items: list[CardImportPreviewItem] = []
    date_re = re.compile(r'\b(\d{1,2}[/-]\d{1,2}(?:[/-]\d{2,4})?)\b')
    amount_re = re.compile(r'(?<!\d)(?:\$\s*)?-?\d{1,3}(?:[.\s]\d{3})*(?:,\d{2})|-?\d+(?:,\d{2})(?!\d)')
    lines = [_clean_card_line(line) for line in text.splitlines()]
    lines = [line for line in lines if len(line) >= 4]
    seen: dict[tuple[str, int, str], list[str]] = {}
    scanned = 0
    skipped_summary = 0
    skipped_invalid_amount = 0
    skipped_duplicates = 0
    skipped_mixed_windows = 0
    without_date = 0

    for line, index, window_size in _line_windows(lines):
        if len(line) < 8:
            continue
        scanned += 1
        if _looks_like_summary_line(line):
            skipped_summary += 1
            continue
        date_match = _find_card_date_match(line, date_re)
        amount_matches = list(amount_re.finditer(line))
        if not amount_matches:
            continue
        if window_size > 1:
            valid_dates = [match for match in date_re.finditer(line) if _parse_card_date(match.group(1), fallback_month) is not None]
            if len(valid_dates) >= 2 and len(amount_matches) >= 2:
                # Una ventana que une dos líneas completas suele mezclar dos consumos distintos.
                # En ese caso se conserva cada línea por separado y se descarta esta combinación.
                skipped_mixed_windows += 1
                continue
        if not date_match and not _candidate_without_date(line, fallback_month):
            without_date += 1
            continue
        amount_match = amount_matches[-1]
        amount = _parse_card_amount(amount_match.group(0))
        if amount is None:
            skipped_invalid_amount += 1
            continue
        parsed_date = _parse_card_date(date_match.group(1), fallback_month) if date_match else None
        description = _description_from_card_line(line, date_match, amount_match)
        if _looks_like_summary_line(description):
            skipped_summary += 1
            continue
        installments = _extract_installments(line)
        normalized_description = _normalize_card_description(description)
        date_key = parsed_date.isoformat() if parsed_date else f"{fallback_month or ''}-sin-fecha-{index}"
        amount_cents = int(round(amount * 100))
        duplicate_key = (date_key, amount_cents, installments or '')
        related_descriptions = seen.setdefault(duplicate_key, [])
        if any(_descriptions_look_duplicated(existing, normalized_description) for existing in related_descriptions):
            skipped_duplicates += 1
            continue
        related_descriptions.append(normalized_description)
        observation: str | None = None
        confidence = 0.74 if parsed_date else 0.52
        if date_match is None:
            observation = 'Fecha no detectada: se usará el primer día del mes en la app si lo importás sin corregir.'
        if len(amount_matches) > 1:
            confidence -= 0.06
            observation = observation or 'La línea tenía más de un importe; se tomó el último como monto del movimiento.'
        if installments:
            confidence += 0.04
        if '$' in amount_match.group(0) or 'ars' in line.lower():
            confidence += 0.06
        items.append(
            CardImportPreviewItem(
                date=parsed_date,
                description=description,
                amount=round_money(amount),
                currency='ARS',
                category=_guess_card_category(description),
                confidence=max(0.35, min(confidence, 0.94)),
                installments=installments,
                observation=observation,
                raw_text=line[:300],
            )
        )
        if len(items) >= 180:
            warnings.append('Se muestran los primeros 180 movimientos detectados para mantener la vista previa liviana.')
            break

    if not items and text.strip():
        warnings.append('No se detectaron movimientos con el formato esperado. El resumen puede tener columnas no compatibles todavía.')
    else:
        item_suffix = '' if len(items) == 1 else 's'
        warnings.append(f'Se detectaron {len(items)} movimiento{item_suffix} candidato{item_suffix} para revisar antes de importar.')
        if skipped_summary:
            summary_suffix = '' if skipped_summary == 1 else 's'
            warnings.append(f'Se omitieron {skipped_summary} línea{summary_suffix} que parecían totales, saldos, vencimientos o datos del resumen.')
        if skipped_mixed_windows:
            mixed_suffix = '' if skipped_mixed_windows == 1 else 'es'
            warnings.append(f'Se descartaron {skipped_mixed_windows} combinación{mixed_suffix} de líneas que parecían mezclar consumos distintos.')
        if skipped_duplicates:
            duplicate_suffix = '' if skipped_duplicates == 1 else 's'
            warnings.append(f'Se ocultaron {skipped_duplicates} posible{duplicate_suffix} duplicado{duplicate_suffix} por fecha, monto, cuota y descripción similar.')
        if without_date:
            warnings.append('Algunas líneas con importe no se mostraron porque no tenían fecha ni señales claras de consumo.')
        if skipped_invalid_amount:
            warnings.append('Algunas líneas fueron omitidas porque el monto no pudo interpretarse con seguridad.')
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


def _months_with_open_data(session: Session, household_id: int) -> list[str]:
    """Meses con datos operativos y sin cierre formal.

    Se usa solo para inicializar una vez el período operativo manual cuando un hogar
    venía de versiones anteriores sin active_month_override persistido.
    """
    months: set[str] = set()
    for model in (MonthlyIncome, Expense, MonthlyParticipation, MonthlyAdvancePayment):
        values = session.exec(select(model.month).where(model.household_id == household_id)).all()
        months.update(month for month in values if month)

    closed_months = set(
        session.exec(select(MonthlyClose.month).where(MonthlyClose.household_id == household_id)).all()
    )
    return sorted(month for month in months if month not in closed_months)


def _initial_active_month(session: Session, household_id: int, settings: HouseholdPeriodSettings, today: Date | None = None) -> str:
    open_months = _months_with_open_data(session, household_id)
    if open_months:
        return open_months[-1]

    latest_closed_month = session.exec(
        select(MonthlyClose.month)
        .where(MonthlyClose.household_id == household_id)
        .order_by(MonthlyClose.month.desc())
    ).first()
    if latest_closed_month:
        return _month_str_add(latest_closed_month, 1)

    calendar_month, _, _ = period_for_date(today or datetime.now(timezone.utc).date(), settings)
    return calendar_month


def _ensure_active_month_override(session: Session, settings: HouseholdPeriodSettings) -> HouseholdPeriodSettings:
    if settings.active_month_override:
        return settings
    settings.active_month_override = _initial_active_month(session, settings.household_id, settings)
    settings.updated_at = datetime.now(timezone.utc)
    session.add(settings)
    session.commit()
    session.refresh(settings)
    return settings


def get_period_settings(session: Session, household_id: int) -> HouseholdPeriodSettings:
    settings = session.exec(select(HouseholdPeriodSettings).where(HouseholdPeriodSettings.household_id == household_id)).first()
    if not settings:
        settings = HouseholdPeriodSettings(household_id=household_id, period_mode="calendar", start_day=1)
        session.add(settings)
        session.commit()
        session.refresh(settings)
    return _ensure_active_month_override(session, settings)


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
        source_advance_payment_id=credit.source_advance_payment_id,
        original_amount=round_money(credit.original_amount),
        remaining_amount=round_money(credit.remaining_amount),
        status=credit.status,
        reason=credit.reason,
        created_at=credit.created_at,
    )


def monthly_close_to_read(close: MonthlyClose) -> MonthlyCloseRead:
    try:
        summary = MonthSummary.model_validate(json.loads(close.summary_json or "{}"))
    except Exception:
        summary = MonthSummary(
            month=close.month,
            total_income=round_money(close.total_income),
            total_shared_expenses=round_money(close.total_shared_expenses),
            members=[],
            settlements=[],
            warning="El cierre existe, pero el detalle completo no pudo reconstruirse por formato anterior.",
        )
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


def _monthly_summary_inputs(month: str, household_id: int, session: Session):
    members = session.exec(select(Member).where(Member.household_id == household_id)).all()
    incomes = session.exec(
        select(MonthlyIncome).where(MonthlyIncome.household_id == household_id, MonthlyIncome.month == month)
    ).all()
    expenses = session.exec(select(Expense).where(Expense.household_id == household_id, Expense.month == month)).all()
    participations = session.exec(
        select(MonthlyParticipation).where(MonthlyParticipation.household_id == household_id, MonthlyParticipation.month == month)
    ).all()
    advance_payments = session.exec(
        select(MonthlyAdvancePayment)
        .where(
            MonthlyAdvancePayment.household_id == household_id,
            MonthlyAdvancePayment.month == month,
            MonthlyAdvancePayment.status == PaymentStatus.confirmed,
        )
        .order_by(MonthlyAdvancePayment.date.asc(), MonthlyAdvancePayment.created_at.asc(), MonthlyAdvancePayment.id.asc())
    ).all()
    return members, incomes, expenses, participations, advance_payments


def _advance_credit_reason(payment: MonthlyAdvancePayment) -> str:
    return f"Excedente confirmado del pago anticipado #{payment.id} del período {payment.month}"


def _credit_rows_for_advance(session: Session, payment: MonthlyAdvancePayment) -> list[CreditBalance]:
    candidates = session.exec(
        select(CreditBalance).where(
            CreditBalance.household_id == payment.household_id,
            CreditBalance.owner_member_id == payment.paid_by_member_id,
            CreditBalance.counterparty_member_id == payment.received_by_member_id,
        )
    ).all()
    reason = _advance_credit_reason(payment)
    marker = f"#{payment.id}"
    return sorted(
        [
            row
            for row in candidates
            if row.source_advance_payment_id == payment.id
            or row.reason == reason
            or (marker in (row.reason or "") and "pago anticipado" in (row.reason or "").lower())
        ],
        key=lambda row: row.id or 0,
    )


def _locked_advance_allocations(
    session: Session,
    advance_payments: list[MonthlyAdvancePayment],
) -> dict[int, tuple[float, float]]:
    """Congela un anticipo cuando su credito ya fue usado total o parcialmente."""
    locked: dict[int, tuple[float, float]] = {}
    for payment in advance_payments:
        rows = _credit_rows_for_advance(session, payment)
        was_consumed = any(
            row.status != CreditBalanceStatus.available
            or round_money(row.remaining_amount) != round_money(row.original_amount)
            for row in rows
        )
        if was_consumed:
            locked[payment.id or 0] = (
                round_money(payment.applied_amount),
                round_money(payment.credit_amount),
            )
    return locked



def _advance_payment_allocations(
    month: str,
    members: list[Member],
    incomes: list[MonthlyIncome],
    expenses: list[Expense],
    participations: list[MonthlyParticipation],
    advance_payments: list[MonthlyAdvancePayment],
    locked_allocations: dict[int, tuple[float, float]] | None = None,
) -> dict[int, tuple[float, float]]:
    """Calcula aplicación vigente de pagos anticipados contra el resumen actual.

    La confirmación del pago es un hecho real, pero su aplicación no debe quedar
    congelada con el estado del mes al momento de confirmar. Por eso se calcula
    primero el saldo base sin pagos anticipados y luego se aplican, en orden,
    contra el saldo vivo de cada par de integrantes.
    """
    base_summary_raw = calculate_month_summary(month, members, incomes, expenses, participations, [])
    base_summary = MonthSummary.model_validate(base_summary_raw)

    # FASE 23: la aplicación del pago anticipado se calcula contra la deuda
    # viva del pagador y el crédito vivo del receptor, no contra "lo que ya
    # pagó en gastos comunes" ni contra un valor congelado de confirmación.
    # Esto evita casos como: deuda vigente 581.066, pago confirmado 1.186.000,
    # pero aplicado erróneo 97.453.
    live_balance_by_member = {item.member_id: round_money(item.balance) for item in base_summary.members}

    allocations: dict[int, tuple[float, float]] = {}
    for payment in advance_payments:
        payment_id = payment.id or 0
        payer_balance = round_money(live_balance_by_member.get(payment.paid_by_member_id, 0))
        receiver_balance = round_money(live_balance_by_member.get(payment.received_by_member_id, 0))
        payer_debt = round_money(max(-payer_balance, 0))
        if payment_id in (locked_allocations or {}):
            applied, credit = (locked_allocations or {})[payment_id]
            allocations[payment_id] = (round_money(applied), round_money(credit))
            if applied > 0.01:
                live_balance_by_member[payment.paid_by_member_id] = round_money(payer_balance + applied)
                live_balance_by_member[payment.received_by_member_id] = round_money(receiver_balance - applied)
            continue

        receiver_credit = round_money(max(receiver_balance, 0))
        applicable_now = round_money(min(payment.amount, payer_debt, receiver_credit))
        applied = applicable_now
        credit = round_money(max(payment.amount - applied, 0))
        allocations[payment_id] = (applied, credit)
        if applied > 0.01:
            live_balance_by_member[payment.paid_by_member_id] = round_money(payer_balance + applied)
            live_balance_by_member[payment.received_by_member_id] = round_money(receiver_balance - applied)
    return allocations


def _advance_payment_views(
    advance_payments: list[MonthlyAdvancePayment],
    allocations: dict[int, tuple[float, float]],
):
    views = []
    for payment in advance_payments:
        applied, _ = allocations.get(payment.id or 0, (0.0, round_money(payment.amount)))
        views.append(
            SimpleNamespace(
                paid_by_member_id=payment.paid_by_member_id,
                received_by_member_id=payment.received_by_member_id,
                applied_amount=applied,
            )
        )
    return views


def _sync_monthly_advance_allocations(month: str, household_id: int, session: Session) -> bool:
    members, incomes, expenses, participations, advance_payments = _monthly_summary_inputs(month, household_id, session)
    locked_allocations = _locked_advance_allocations(session, advance_payments)
    allocations = _advance_payment_allocations(month, members, incomes, expenses, participations, advance_payments, locked_allocations)
    changed = False

    for payment in advance_payments:
        if (payment.id or 0) in locked_allocations:
            continue

        applied, credit = allocations.get(payment.id or 0, (0.0, round_money(payment.amount)))
        if round_money(payment.applied_amount) != applied or round_money(payment.credit_amount) != credit:
            payment.applied_amount = applied
            payment.credit_amount = credit
            payment.updated_at = datetime.now(timezone.utc)
            session.add(payment)
            changed = True

        linked_credits = _credit_rows_for_advance(session, payment)
        for row in linked_credits:
            if row.source_advance_payment_id is None:
                row.source_advance_payment_id = payment.id
                row.updated_at = datetime.now(timezone.utc)
                session.add(row)
                changed = True

        if credit > 0.01 and not linked_credits:
            session.add(
                CreditBalance(
                    household_id=household_id,
                    owner_member_id=payment.paid_by_member_id,
                    counterparty_member_id=payment.received_by_member_id,
                    source_advance_payment_id=payment.id,
                    original_amount=credit,
                    remaining_amount=credit,
                    status=CreditBalanceStatus.available,
                    reason=_advance_credit_reason(payment),
                )
            )
            session.flush()
            changed = True

        # Compatibilidad con datos previos: algunas confirmaciones tempranas crearon
        # saldos a favor formales aunque todavía no existía saldo mensual para compensar.
        # Si ese crédito automático sigue intacto, se ajusta o cancela según el cálculo vigente.
        reason = _advance_credit_reason(payment)
        credit_candidates = session.exec(
            select(CreditBalance).where(
                CreditBalance.household_id == household_id,
                CreditBalance.owner_member_id == payment.paid_by_member_id,
                CreditBalance.counterparty_member_id == payment.received_by_member_id,
            )
        ).all()
        payment_marker = f"#{payment.id}"
        credit_rows = [
            row
            for row in credit_candidates
            if row.reason == reason
            or (
                payment_marker in (row.reason or "")
                and "pago anticipado" in (row.reason or "").lower()
            )
        ]
        for row in credit_rows:
            if row.status != CreditBalanceStatus.available:
                continue
            if round_money(row.remaining_amount) != round_money(row.original_amount):
                continue
            if credit <= 0.01:
                row.remaining_amount = 0
                row.status = CreditBalanceStatus.cancelled
                row.updated_at = datetime.now(timezone.utc)
                session.add(row)
                changed = True
            elif round_money(row.original_amount) != credit:
                row.original_amount = credit
                row.remaining_amount = credit
                row.updated_at = datetime.now(timezone.utc)
                session.add(row)
                changed = True

    return changed

def _sync_all_advance_credits(household_id: int, session: Session, month: str | None = None) -> bool:
    query = select(MonthlyAdvancePayment).where(
        MonthlyAdvancePayment.household_id == household_id,
        MonthlyAdvancePayment.status == PaymentStatus.confirmed,
    )
    if month is not None:
        query = query.where(MonthlyAdvancePayment.month == month)
    payments = session.exec(query).all()
    changed = False
    for payment_month in sorted({payment.month for payment in payments}):
        changed = _sync_monthly_advance_allocations(payment_month, household_id, session) or changed
    return changed




def build_month_summary(month: str, household_id: int, session: Session) -> MonthSummary:
    members, incomes, expenses, participations, advance_payments = _monthly_summary_inputs(month, household_id, session)
    locked_allocations = _locked_advance_allocations(session, advance_payments)
    allocations = _advance_payment_allocations(month, members, incomes, expenses, participations, advance_payments, locked_allocations)
    advance_payment_views = _advance_payment_views(advance_payments, allocations)
    summary = calculate_month_summary(month, members, incomes, expenses, participations, advance_payment_views)
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


def _upsert_income_record(
    session: Session,
    household_id: int,
    member_id: int,
    month: str,
    amount: float,
    note: str | None,
) -> IncomeRead:
    ensure_month_open(session, household_id, month)
    ensure_member_in_household(session, household_id, member_id)
    existing = session.exec(
        select(MonthlyIncome).where(
            MonthlyIncome.household_id == household_id,
            MonthlyIncome.member_id == member_id,
            MonthlyIncome.month == month,
        )
    ).first()

    clean_note = note.strip() if isinstance(note, str) else note
    if existing:
        existing.amount = amount
        existing.note = clean_note
        existing.updated_at = datetime.now(timezone.utc)
        session.add(existing)
        session.commit()
        session.refresh(existing)
        income = existing
    else:
        income = MonthlyIncome(
            household_id=household_id,
            member_id=member_id,
            month=month,
            amount=amount,
            note=clean_note,
        )
        session.add(income)
        session.commit()
        session.refresh(income)

    return IncomeRead(id=income.id or 0, member_id=income.member_id, month=income.month, amount=income.amount, note=income.note)


@router.post("/income", response_model=IncomeRead)
def upsert_income(
    payload: IncomeUpsert,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    return _upsert_income_record(
        session=session,
        household_id=current_member.household_id,
        member_id=payload.member_id,
        month=payload.month,
        amount=payload.amount,
        note=payload.note,
    )


@router.post("/income/me", response_model=IncomeRead)
def upsert_my_income(
    payload: IncomeSelfUpsert,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    return _upsert_income_record(
        session=session,
        household_id=current_member.household_id,
        member_id=current_member.id or 0,
        month=payload.month,
        amount=payload.amount,
        note=payload.note or "Ingreso del mes cargado desde Personal.",
    )


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
        warnings.append('Vista previa solamente: ningún movimiento fue cargado todavía. Elegí destino en la app antes de importar.')
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
    if current_member.role not in {MemberRole.owner, MemberRole.admin} and current_member.id not in {
        payload.debtor_member_id, payload.creditor_member_id
    }:
        raise HTTPException(status_code=403, detail="Solo integrantes involucrados o un administrador pueden crear esta deuda")
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


@router.patch("/debts/{debt_id}/increase", response_model=DebtRead)
def increase_manual_debt(
    debt_id: int,
    payload: DebtIncrease,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    debt = get_debt_for_household(session, current_member.household_id, debt_id)
    if debt.source != DebtSource.manual:
        raise HTTPException(status_code=400, detail="Solo se pueden agregar consumos a deudas manuales. Para deudas automáticas conviene crear una deuda nueva agrupada.")
    if debt.status == DebtStatus.cancelled:
        raise HTTPException(status_code=400, detail="No se pueden agregar consumos a una deuda cancelada.")
    current_read = debt_to_read(session, debt)
    if current_read.status == DebtStatus.paid or current_read.remaining_amount <= 0.01:
        raise HTTPException(status_code=400, detail="No se agregan consumos a una deuda saldada. Creá una deuda nueva para proteger la trazabilidad.")
    if current_member.id not in {debt.debtor_member_id, debt.creditor_member_id}:
        raise HTTPException(status_code=403, detail="Solo integrantes involucrados en la deuda pueden ampliarla.")

    amount = round_money(payload.amount)
    if amount <= 0.01:
        raise HTTPException(status_code=400, detail="El monto a agregar debe ser mayor a cero.")

    debt.original_amount = round_money(debt.original_amount + amount)
    note = payload.reason.strip()
    if note:
        separator = "\n\n---\n" if debt.reason.strip() else ""
        debt.reason = f"{debt.reason.rstrip()}{separator}{note}"
    debt.updated_at = datetime.now(timezone.utc)
    session.add(debt)
    sync_debt_status(session, debt)
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
    ensure_operator(current_member)
    previous = session.exec(
        select(Debt).where(
            Debt.household_id == current_member.household_id,
            Debt.source == DebtSource.automatic,
            Debt.source_month == payload.month,
            Debt.status != DebtStatus.cancelled,
        )
    ).all()

    for debt in previous:
        if debt_paid_amount(session, debt.id or 0) > 0 or debt_pending_amount(session, debt.id or 0) > 0:
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



@router.post("/credit-balances/reconcile")
def reconcile_advance_credits(
    month: str | None = Query(default=None, pattern=r"^\d{4}-\d{2}$"),
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    """Repara, de forma explicita, excedentes confirmados sin saldo formal."""
    ensure_operator(current_member)
    changed = _sync_all_advance_credits(current_member.household_id, session, month)
    if changed:
        session.commit()
    credits = session.exec(
        select(CreditBalance).where(
            CreditBalance.household_id == current_member.household_id,
            CreditBalance.source_advance_payment_id != None,
        )
    ).all()
    return {
        "ok": True,
        "changed": changed,
        "month": month,
        "linked_advance_credit_count": len(credits),
    }


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
    if current_member.role not in {MemberRole.owner, MemberRole.admin} and current_member.id not in {debt.debtor_member_id, debt.creditor_member_id}:
        raise HTTPException(status_code=403, detail="Solo integrantes involucrados o un administrador pueden cancelar esta deuda")

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


@router.post("/active-period/reset-basic", response_model=ActivePeriodResetRead)
def reset_active_period_basic(
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    """Vacía ingresos, gastos y pagos anticipados del período activo no cerrado.

    No toca cierres, deudas formales, abonos de deudas, saldos a favor ni plantillas.
    Se usa para limpiar un período operativo contaminado por datos previos/pruebas.
    """
    ensure_operator(current_member)
    settings = get_period_settings(session, current_member.household_id)
    active_month, _, _, _ = _active_period(settings)
    if get_month_close(session, current_member.household_id, active_month):
        raise HTTPException(status_code=409, detail="No se puede reiniciar un período que ya está cerrado. Reabrilo si necesitás corregirlo.")

    incomes = session.exec(
        select(MonthlyIncome).where(
            MonthlyIncome.household_id == current_member.household_id,
            MonthlyIncome.month == active_month,
        )
    ).all()
    expenses = session.exec(
        select(Expense).where(
            Expense.household_id == current_member.household_id,
            Expense.month == active_month,
        )
    ).all()
    advance_payments = session.exec(
        select(MonthlyAdvancePayment).where(
            MonthlyAdvancePayment.household_id == current_member.household_id,
            MonthlyAdvancePayment.month == active_month,
        )
    ).all()
    confirmed_advance_payments = [
        payment for payment in advance_payments if payment.status == PaymentStatus.confirmed
    ]
    if confirmed_advance_payments:
        raise HTTPException(
            status_code=409,
            detail="No se puede reiniciar el periodo porque contiene transferencias confirmadas. Esos movimientos reales deben conservarse y corregirse mediante una reversion auditable.",
        )


    deleted_incomes = len(incomes)
    deleted_expenses = len(expenses)
    deleted_advance_payments = len(advance_payments)
    for row in incomes:
        session.delete(row)
    for row in expenses:
        session.delete(row)
    for row in advance_payments:
        session.delete(row)
    session.commit()

    return ActivePeriodResetRead(
        month=active_month,
        deleted_incomes=deleted_incomes,
        deleted_expenses=deleted_expenses,
        deleted_advance_payments=deleted_advance_payments,
        message=f"Se reinició {active_month}: ingresos, gastos y pagos anticipados quedaron en cero.",
    )


@router.get("/monthly-advance-payments", response_model=list[MonthlyAdvancePaymentRead])
def list_monthly_advance_payments(
    month: str,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    if _sync_monthly_advance_allocations(month, current_member.household_id, session):
        session.commit()
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

    # La confirmación registra el hecho real. La aplicación contra el saldo del mes
    # se recalcula inmediatamente y cada vez que se consulta el listado, para que un
    # pago confirmado temprano no quede congelado como aplicado en cero.
    payment.status = PaymentStatus.confirmed
    payment.applied_amount = 0
    payment.credit_amount = 0
    payment.confirmed_by_member_id = current_member.id
    payment.confirmed_at = datetime.now(timezone.utc)
    payment.updated_at = datetime.now(timezone.utc)
    session.add(payment)
    session.flush()
    _sync_monthly_advance_allocations(payment.month, current_member.household_id, session)
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
    settings = get_period_settings(session, current_member.household_id)
    active_month, _, _, _ = _active_period(settings)
    if payload.month != active_month:
        raise HTTPException(status_code=400, detail="Solo se puede cerrar el mes operativo activo.")

    existing = get_month_close(session, current_member.household_id, payload.month)
    if existing:
        raise HTTPException(status_code=409, detail="Este mes ya estaba cerrado. Reabrilo si necesitás corregir algo.")
    _sync_monthly_advance_allocations(payload.month, current_member.household_id, session)
    session.flush()


    summary = build_month_summary(payload.month, current_member.household_id, session)
    if summary.total_income <= 0:
        raise HTTPException(status_code=400, detail="No se puede cerrar un mes sin ingresos cargados.")
    expected_debts = {
        (item.debtor_member_id, item.creditor_member_id): round_money(item.amount)
        for item in summary.settlements
    }
    existing_automatic = session.exec(
        select(Debt).where(
            Debt.household_id == current_member.household_id,
            Debt.source == DebtSource.automatic,
            Debt.source_month == payload.month,
            Debt.status != DebtStatus.cancelled,
        )
    ).all()
    existing_debts: dict[tuple[int, int], float] = {}
    has_movements = False
    for debt in existing_automatic:
        key = (debt.debtor_member_id, debt.creditor_member_id)
        existing_debts[key] = round_money(existing_debts.get(key, 0) + debt.original_amount)
        has_movements = has_movements or debt_paid_amount(session, debt.id or 0) > 0 or debt_pending_amount(session, debt.id or 0) > 0

    if existing_debts != expected_debts:
        if has_movements:
            raise HTTPException(
                status_code=409,
                detail="Las deudas automaticas del periodo tienen abonos y ya no coinciden con el cierre. Revisalas antes de cerrar para no duplicar movimientos.",
            )
        for debt in existing_automatic:
            debt.status = DebtStatus.cancelled
            debt.updated_at = datetime.now(timezone.utc)
            session.add(debt)
        for settlement in summary.settlements:
            session.add(
                Debt(
                    household_id=current_member.household_id,
                    debtor_member_id=settlement.debtor_member_id,
                    creditor_member_id=settlement.creditor_member_id,
                    source=DebtSource.automatic,
                    source_month=payload.month,
                    original_amount=settlement.amount,
                    reason=settlement.reason,
                )
            )


    close = MonthlyClose(
        household_id=current_member.household_id,
        month=payload.month,
        total_income=summary.total_income,
        total_shared_expenses=summary.total_shared_expenses,
        summary_json=json.dumps(summary.model_dump(), ensure_ascii=False),
        closed_by_member_id=current_member.id or 0,
    )
    session.add(close)

    # Regla FASE 14: el mes operativo no cambia por calendario ni queda cerrado activo.
    # Cerrar el mes activo siempre guarda snapshot y abre el período siguiente vacío.
    settings.active_month_override = _month_str_add(payload.month, 1)
    settings.updated_by_member_id = current_member.id
    settings.updated_at = datetime.now(timezone.utc)
    session.add(settings)

    session.commit()
    session.refresh(close)
    return monthly_close_to_read(close)


@router.get("/month-periods", response_model=list[MonthPeriodStatusRead])
def list_month_period_statuses(
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    settings = get_period_settings(session, current_member.household_id)
    active_month, _, _, _ = _active_period(settings)
    periods: dict[str, dict] = {
        active_month: {
            "month": active_month,
            "status": "active",
            "total_income": 0.0,
            "total_shared_expenses": 0.0,
            "income_count": 0,
            "expense_count": 0,
            "advance_payment_count": 0,
            "is_active": True,
            "is_closed": False,
        }
    }

    def ensure_period(month: str) -> dict:
        if month not in periods:
            periods[month] = {
                "month": month,
                "status": "open_with_data",
                "total_income": 0.0,
                "total_shared_expenses": 0.0,
                "income_count": 0,
                "expense_count": 0,
                "advance_payment_count": 0,
                "is_active": month == active_month,
                "is_closed": False,
            }
        return periods[month]

    for income in session.exec(select(MonthlyIncome).where(MonthlyIncome.household_id == current_member.household_id)).all():
        period = ensure_period(income.month)
        period["total_income"] += income.amount
        period["income_count"] += 1

    for expense in session.exec(select(Expense).where(Expense.household_id == current_member.household_id)).all():
        period = ensure_period(expense.month)
        if expense.is_shared:
            period["total_shared_expenses"] += expense.amount
        period["expense_count"] += 1

    for payment in session.exec(select(MonthlyAdvancePayment).where(MonthlyAdvancePayment.household_id == current_member.household_id)).all():
        period = ensure_period(payment.month)
        period["advance_payment_count"] += 1

    closes = session.exec(
        select(MonthlyClose)
        .where(MonthlyClose.household_id == current_member.household_id)
        .order_by(MonthlyClose.month.desc(), MonthlyClose.id.desc())
    ).all()
    for close in closes:
        period = ensure_period(close.month)
        period["status"] = "closed"
        period["total_income"] = close.total_income
        period["total_shared_expenses"] = close.total_shared_expenses
        period["is_closed"] = True
        period["is_active"] = close.month == active_month

    for period in periods.values():
        if period["is_closed"]:
            period["status"] = "closed"
        elif period["is_active"]:
            period["status"] = "active"
        else:
            period["status"] = "open_with_data"
        period["total_income"] = round_money(period["total_income"])
        period["total_shared_expenses"] = round_money(period["total_shared_expenses"])

    return [MonthPeriodStatusRead(**period) for period in sorted(periods.values(), key=lambda item: item["month"], reverse=True)]


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
