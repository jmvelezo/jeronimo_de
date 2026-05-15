import json
from collections import defaultdict
from datetime import date, datetime, timedelta
from fastapi import APIRouter, Depends
from sqlmodel import Session, select
from ..config import get_settings
from ..database import get_session
from ..models import (
    AiReport,
    CreditBalance,
    CreditBalanceStatus,
    Debt,
    DebtStatus,
    Expense,
    FixedExpenseTemplate,
    HouseholdAiSettings,
    HouseholdTask,
    Member,
    MonthlyAdvancePayment,
    MonthlyClose,
    PaymentStatus,
    TaskStatus,
    utc_now,
)
from ..schemas import (
    AiReportCreate,
    AiReportRead,
    AiVisibleTip,
    AiWeeklyReportCreate,
    AiWeeklyReportRead,
    AiWeeklySettingsRead,
    AiWeeklySettingsUpdate,
)
from ..services.ai_engine import generate_household_report, generate_weekly_household_report
from ..services.economic_context import fetch_argentina_economic_context
from .auth import get_current_member
from .finance import build_month_summary, debt_to_read
from .tasks import task_to_read

router = APIRouter(prefix="/ai", tags=["ai"])

WEEKDAY_LABELS = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"]
FREQUENCY_LABELS = {
    "manual": "Manual",
    "weekly": "Semanal",
    "biweekly": "Quincenal",
    "monthly": "Mensual",
}
ALLOWED_FREQUENCIES = set(FREQUENCY_LABELS.keys())


def _normalize_frequency(value: str | None) -> str:
    raw = (value or "weekly").strip().lower()
    aliases = {
        "semanal": "weekly",
        "quincenal": "biweekly",
        "mensual": "monthly",
        "manual": "manual",
        "week": "weekly",
        "weekly": "weekly",
        "biweekly": "biweekly",
        "fortnightly": "biweekly",
        "monthly": "monthly",
    }
    return aliases.get(raw, "weekly") if raw not in ALLOWED_FREQUENCIES else raw


def _weekday_label(index: int | None) -> str:
    try:
        return WEEKDAY_LABELS[max(0, min(6, int(index or 0)))]
    except Exception:
        return WEEKDAY_LABELS[0]


def report_to_read(report: AiReport) -> AiReportRead:
    try:
        evidence = json.loads(report.evidence_json or "{}")
    except json.JSONDecodeError:
        evidence = {"raw": report.evidence_json}
    return AiReportRead(
        id=report.id or 0,
        household_id=report.household_id,
        month=report.month,
        title=report.title,
        content=report.content,
        evidence=evidence,
        created_by_member_id=report.created_by_member_id,
        created_at=report.created_at,
    )


def _extract_evidence(report: AiReport) -> dict:
    try:
        return json.loads(report.evidence_json or "{}")
    except json.JSONDecodeError:
        return {}


def _is_weekly_report(report: AiReport) -> bool:
    return _extract_evidence(report).get("analysis_type") == "weekly_contextual"


def _visible_tips_from_report(report: AiReport | None) -> list[AiVisibleTip]:
    if report is None:
        return []
    raw = _extract_evidence(report).get("visible_tips") or []
    tips: list[AiVisibleTip] = []
    for item in raw[:4]:
        if isinstance(item, dict):
            tips.append(
                AiVisibleTip(
                    title=str(item.get("title") or "Consejo IA"),
                    body=str(item.get("body") or "Revisá el informe completo."),
                    level=str(item.get("level") or "info"),
                    kind=str(item.get("kind") or "general"),
                    valid_until=item.get("valid_until"),
                )
            )
    return tips


def _get_or_create_weekly_settings(session: Session, household_id: int, member_id: int | None = None) -> HouseholdAiSettings:
    row = session.exec(select(HouseholdAiSettings).where(HouseholdAiSettings.household_id == household_id)).first()
    if row:
        if not getattr(row, "analysis_frequency", None):
            row.analysis_frequency = "weekly"
            session.add(row)
            session.commit()
            session.refresh(row)
        return row
    row = HouseholdAiSettings(
        household_id=household_id,
        weekly_enabled=False,
        analysis_frequency="weekly",
        preferred_weekday=0,
        use_external_context=True,
        use_news_context=True,
        currency="ARS",
        country_context="Argentina",
        updated_by_member_id=member_id,
    )
    session.add(row)
    session.commit()
    session.refresh(row)
    return row


def _latest_weekly_report(session: Session, household_id: int) -> AiReport | None:
    reports = session.exec(
        select(AiReport)
        .where(AiReport.household_id == household_id)
        .order_by(AiReport.created_at.desc(), AiReport.id.desc())
    ).all()
    for report in reports:
        if _is_weekly_report(report):
            return report
    return None


def _first_weekday_of_month(year: int, month: int, weekday: int) -> date:
    first = date(year, month, 1)
    offset = (weekday - first.weekday()) % 7
    return first + timedelta(days=offset)


def _add_month(year: int, month: int, delta: int = 1) -> tuple[int, int]:
    month += delta
    while month > 12:
        month -= 12
        year += 1
    while month < 1:
        month += 12
        year -= 1
    return year, month


def _period_info(frequency: str, preferred_weekday: int, today: date | None = None) -> dict:
    """Período vigente para evitar llamadas repetidas a IA según configuración."""
    today = today or date.today()
    frequency = _normalize_frequency(frequency)
    weekday = max(0, min(6, int(preferred_weekday or 0)))

    if frequency == "manual":
        start = today - timedelta(days=6)
        end = today
        previous_start = start - timedelta(days=7)
        previous_end = start - timedelta(days=1)
    elif frequency == "weekly":
        start = today - timedelta(days=(today.weekday() - weekday) % 7)
        end = start + timedelta(days=6)
        previous_start = start - timedelta(days=7)
        previous_end = start - timedelta(days=1)
    elif frequency == "biweekly":
        anchor = _first_weekday_of_month(2024, 1, weekday)
        if today < anchor:
            anchor = _first_weekday_of_month(2023, 12, weekday)
        periods = max(0, (today - anchor).days // 14)
        start = anchor + timedelta(days=periods * 14)
        end = start + timedelta(days=13)
        previous_start = start - timedelta(days=14)
        previous_end = start - timedelta(days=1)
    else:  # monthly
        start = _first_weekday_of_month(today.year, today.month, weekday)
        if today < start:
            y, m = _add_month(today.year, today.month, -1)
            start = _first_weekday_of_month(y, m, weekday)
        y2, m2 = _add_month(start.year, start.month, 1)
        next_start = _first_weekday_of_month(y2, m2, weekday)
        end = next_start - timedelta(days=1)
        y0, m0 = _add_month(start.year, start.month, -1)
        previous_start = _first_weekday_of_month(y0, m0, weekday)
        previous_end = start - timedelta(days=1)

    if frequency == "monthly":
        y2, m2 = _add_month(start.year, start.month, 1)
        next_start = _first_weekday_of_month(y2, m2, weekday)
    else:
        step = 7 if frequency in {"manual", "weekly"} else 14
        next_start = start + timedelta(days=step)

    return {
        "type": frequency,
        "frequency_label": FREQUENCY_LABELS.get(frequency, "Semanal"),
        "preferred_weekday": weekday,
        "preferred_weekday_label": _weekday_label(weekday),
        "period_key": f"{frequency}_{start.isoformat()}_{end.isoformat()}",
        "week_key": f"{start.isoformat()}_{end.isoformat()}",  # compatibilidad R11
        "start": start,
        "end": end,
        "previous_start": previous_start,
        "previous_end": previous_end,
        "next_start": next_start,
    }


def _report_matches_period(report: AiReport | None, period: dict) -> bool:
    if report is None:
        return False
    evidence = _extract_evidence(report)
    report_period = evidence.get("period") or {}
    return report_period.get("period_key") == period.get("period_key") or report_period.get("week_key") == period.get("week_key")


def _settings_to_read(session: Session, settings: HouseholdAiSettings) -> AiWeeklySettingsRead:
    latest = _latest_weekly_report(session, settings.household_id)
    frequency = _normalize_frequency(getattr(settings, "analysis_frequency", "weekly"))
    period = _period_info(frequency, settings.preferred_weekday)
    automatic_active = bool(settings.weekly_enabled) and frequency != "manual"
    if frequency == "manual":
        next_at = None
        next_hint = "Modo manual: la IA solo se ejecuta cuando tocás Generar análisis."
    elif not automatic_active:
        next_at = None
        next_hint = f"Automático desactivado. Frecuencia configurada: {period['frequency_label'].lower()}."
    elif _report_matches_period(latest, period):
        next_at = period["next_start"]
        next_hint = f"Informe vigente. Próximo análisis estimado: {period['next_start'].isoformat()} ({_weekday_label(period['next_start'].weekday())})."
    else:
        next_at = period["start"]
        next_hint = f"Hay análisis pendiente para el período {period['start'].isoformat()} a {period['end'].isoformat()}."
    return AiWeeklySettingsRead(
        weekly_enabled=bool(settings.weekly_enabled) and frequency != "manual",
        analysis_frequency=frequency,
        frequency_label=FREQUENCY_LABELS.get(frequency, "Semanal"),
        preferred_weekday=settings.preferred_weekday,
        preferred_weekday_label=_weekday_label(settings.preferred_weekday),
        use_external_context=settings.use_external_context,
        use_news_context=settings.use_news_context,
        currency=settings.currency,
        country_context=settings.country_context,
        last_report_created_at=latest.created_at if latest else None,
        last_report_title=latest.title if latest else None,
        next_analysis_at=next_at,
        next_analysis_hint=next_hint,
    )


def _sum_expenses_by_category(expenses: list[Expense]) -> list[dict]:
    by_category: dict[str, float] = defaultdict(float)
    for expense in expenses:
        by_category[expense.category or "General"] += float(expense.amount or 0)
    return [
        {"category": category, "amount": round(amount, 2)}
        for category, amount in sorted(by_category.items(), key=lambda item: item[1], reverse=True)
    ]


def _month_shift(month: str, delta: int) -> str:
    """Desplaza YYYY-MM sin depender de funciones internas de finance.py."""
    try:
        year, mon = [int(part) for part in month.split("-")]
        idx = year * 12 + (mon - 1) + delta
        return f"{idx // 12:04d}-{idx % 12 + 1:02d}"
    except Exception:
        today = date.today()
        return f"{today.year:04d}-{today.month:02d}"


def _category_variations(current: list[dict], previous: list[dict]) -> list[dict]:
    previous_map = {str(item.get("category") or "General"): float(item.get("amount") or 0) for item in previous}
    variations: list[dict] = []
    for item in current:
        category = str(item.get("category") or "General")
        current_amount = float(item.get("amount") or 0)
        previous_amount = float(previous_map.get(category) or 0)
        delta = current_amount - previous_amount
        variation_pct = (delta / previous_amount * 100) if previous_amount else None
        variations.append(
            {
                "category": category,
                "current_amount": round(current_amount, 2),
                "previous_amount": round(previous_amount, 2),
                "delta_amount": round(delta, 2),
                "variation_pct": round(variation_pct, 2) if variation_pct is not None else None,
                "status": "new" if previous_amount == 0 and current_amount > 0 else ("up" if delta > 0 else ("down" if delta < 0 else "stable")),
            }
        )
    for category, previous_amount in previous_map.items():
        if not any(item.get("category") == category for item in variations):
            variations.append(
                {
                    "category": category,
                    "current_amount": 0,
                    "previous_amount": round(previous_amount, 2),
                    "delta_amount": round(-previous_amount, 2),
                    "variation_pct": -100,
                    "status": "down",
                }
            )
    return sorted(variations, key=lambda item: abs(float(item.get("delta_amount") or 0)), reverse=True)


def _expense_anomalies(current_expenses: list[Expense], previous_expenses: list[Expense]) -> list[dict]:
    previous_by_category: dict[str, list[float]] = defaultdict(list)
    for expense in previous_expenses:
        previous_by_category[expense.category or "General"].append(float(expense.amount or 0))

    anomalies: list[dict] = []
    for expense in current_expenses:
        category = expense.category or "General"
        amount = float(expense.amount or 0)
        previous_values = previous_by_category.get(category, [])
        previous_avg = (sum(previous_values) / len(previous_values)) if previous_values else 0
        is_large_new = not previous_values and amount > 0
        is_spike = bool(previous_avg and amount >= previous_avg * 1.75 and amount - previous_avg >= 1000)
        if is_large_new or is_spike:
            anomalies.append(
                {
                    "expense_id": expense.id,
                    "date": expense.date.isoformat() if expense.date else None,
                    "category": category,
                    "description": expense.description,
                    "amount": round(amount, 2),
                    "previous_category_average": round(previous_avg, 2),
                    "reason": "gasto_nuevo_en_categoria" if is_large_new else "monto_muy_superior_al_promedio_previo",
                }
            )
    return sorted(anomalies, key=lambda item: float(item.get("amount") or 0), reverse=True)[:8]


def _settlement_metrics(summary: dict) -> dict:
    settlements = summary.get("settlements") or []
    total_to_settle = 0.0
    biggest = None
    for item in settlements:
        amount = float(item.get("amount") or 0)
        total_to_settle += amount
        if biggest is None or amount > float(biggest.get("amount") or 0):
            biggest = item
    return {
        "count": len(settlements),
        "total_to_settle": round(total_to_settle, 2),
        "biggest_settlement": biggest,
    }


def _read_fixed_templates(session: Session, household_id: int) -> list[dict]:
    templates = session.exec(
        select(FixedExpenseTemplate)
        .where(FixedExpenseTemplate.household_id == household_id)
        .order_by(FixedExpenseTemplate.active.desc(), FixedExpenseTemplate.name.asc())
    ).all()
    return [
        {
            "id": item.id,
            "name": item.name,
            "amount": round(float(item.amount or 0), 2),
            "category": item.category,
            "default_paid_by_member_id": item.default_paid_by_member_id,
            "frequency": item.frequency,
            "active": bool(item.active),
            "notes": item.notes,
        }
        for item in templates
    ]


def _read_credit_balances(session: Session, household_id: int) -> list[dict]:
    credits = session.exec(
        select(CreditBalance)
        .where(CreditBalance.household_id == household_id, CreditBalance.status == CreditBalanceStatus.available, CreditBalance.remaining_amount > 0)
        .order_by(CreditBalance.created_at.desc(), CreditBalance.id.desc())
    ).all()
    return [
        {
            "id": item.id,
            "owner_member_id": item.owner_member_id,
            "counterparty_member_id": item.counterparty_member_id,
            "original_amount": round(float(item.original_amount or 0), 2),
            "remaining_amount": round(float(item.remaining_amount or 0), 2),
            "reason": item.reason,
            "created_at": item.created_at.isoformat() if item.created_at else None,
        }
        for item in credits
    ]


def _read_advance_payments(session: Session, household_id: int, month: str) -> list[dict]:
    rows = session.exec(
        select(MonthlyAdvancePayment)
        .where(MonthlyAdvancePayment.household_id == household_id, MonthlyAdvancePayment.month == month)
        .order_by(MonthlyAdvancePayment.created_at.desc(), MonthlyAdvancePayment.id.desc())
    ).all()
    return [
        {
            "id": item.id,
            "month": item.month,
            "paid_by_member_id": item.paid_by_member_id,
            "received_by_member_id": item.received_by_member_id,
            "amount": round(float(item.amount or 0), 2),
            "applied_amount": round(float(item.applied_amount or 0), 2),
            "credit_amount": round(float(item.credit_amount or 0), 2),
            "status": item.status,
            "date": item.date.isoformat() if item.date else None,
            "note": item.note,
        }
        for item in rows
    ]


def _read_recent_closes(session: Session, household_id: int, limit: int = 3) -> list[dict]:
    closes = session.exec(
        select(MonthlyClose)
        .where(MonthlyClose.household_id == household_id)
        .order_by(MonthlyClose.created_at.desc(), MonthlyClose.id.desc())
    ).all()
    return [
        {
            "id": item.id,
            "month": item.month,
            "total_income": round(float(item.total_income or 0), 2),
            "total_shared_expenses": round(float(item.total_shared_expenses or 0), 2),
            "created_at": item.created_at.isoformat() if item.created_at else None,
        }
        for item in closes[:limit]
    ]



def _jsonable(value):
    """Convierte modelos Pydantic/SQLModel o dicts anidados a datos JSON seguros para IA."""
    if hasattr(value, "model_dump"):
        return value.model_dump(mode="json")
    if isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, list):
        return [_jsonable(item) for item in value]
    if isinstance(value, tuple):
        return [_jsonable(item) for item in value]
    if isinstance(value, dict):
        return {key: _jsonable(item) for key, item in value.items()}
    return value


def build_household_ai_payload(session: Session, household_id: int, month: str, focus: str) -> dict:
    summary = _jsonable(build_month_summary(month, household_id, session))
    previous_month = _month_shift(month, -1)
    previous_summary: dict = {}
    try:
        previous_summary = _jsonable(build_month_summary(previous_month, household_id, session))
    except Exception:
        previous_summary = {}

    expenses = session.exec(select(Expense).where(Expense.household_id == household_id, Expense.month == month)).all()
    previous_expenses = session.exec(select(Expense).where(Expense.household_id == household_id, Expense.month == previous_month)).all()
    debts = session.exec(
        select(Debt).where(
            Debt.household_id == household_id,
            Debt.status.in_([DebtStatus.active, DebtStatus.partial]),
        )
    ).all()
    tasks = session.exec(select(HouseholdTask).where(HouseholdTask.household_id == household_id, HouseholdTask.status == TaskStatus.pending)).all()
    task_reads = [task_to_read(task) for task in tasks]
    members = session.exec(select(Member).where(Member.household_id == household_id)).all()

    expenses_by_category = _sum_expenses_by_category(expenses)
    previous_expenses_by_category = _sum_expenses_by_category(previous_expenses)
    total_expenses = float(summary.get("total_shared_expenses") or 0)
    previous_total_expenses = float(previous_summary.get("total_shared_expenses") or 0)
    total_income = float(summary.get("total_income") or 0)
    previous_total_income = float(previous_summary.get("total_income") or 0)
    total_expense_delta = total_expenses - previous_total_expenses
    income_delta = total_income - previous_total_income

    credit_balances = _read_credit_balances(session, household_id)
    advance_payments = _read_advance_payments(session, household_id, month)
    fixed_templates = _read_fixed_templates(session, household_id)
    recent_closes = _read_recent_closes(session, household_id)

    return {
        "month": month,
        "previous_month": previous_month,
        "focus": focus,
        "currency": "ARS",
        "country_context": "Argentina",
        "summary": summary,
        "previous_summary": previous_summary,
        "month_comparison": {
            "current_total_income": round(total_income, 2),
            "previous_total_income": round(previous_total_income, 2),
            "income_delta": round(income_delta, 2),
            "current_total_shared_expenses": round(total_expenses, 2),
            "previous_total_shared_expenses": round(previous_total_expenses, 2),
            "expense_delta": round(total_expense_delta, 2),
            "expense_variation_pct": round((total_expense_delta / previous_total_expenses * 100), 2) if previous_total_expenses else None,
            "settlements": _settlement_metrics(summary),
        },
        "expenses_by_category": expenses_by_category,
        "previous_expenses_by_category": previous_expenses_by_category,
        "category_variations": _category_variations(expenses_by_category, previous_expenses_by_category),
        "expense_anomalies": _expense_anomalies(expenses, previous_expenses),
        "active_debts": [_jsonable(debt_to_read(session, debt)) for debt in debts],
        "credit_balances": credit_balances,
        "monthly_advance_payments": advance_payments,
        "fixed_expense_templates": fixed_templates,
        "fixed_expense_summary": {
            "active_count": len([item for item in fixed_templates if item.get("active")]),
            "active_total_expected": round(sum(float(item.get("amount") or 0) for item in fixed_templates if item.get("active")), 2),
            "inactive_count": len([item for item in fixed_templates if not item.get("active")]),
        },
        "recent_monthly_closes": recent_closes,
        "task_summary": {
            "pending_count": len(task_reads),
            "overdue_count": len([task for task in task_reads if task.is_overdue]),
            "due_soon_count": len([task for task in task_reads if task.is_due_soon]),
            "high_priority_count": len([task for task in task_reads if task.alert_level in {"high", "overdue"}]),
            "projects_or_purchases": len([task for task in tasks if getattr(task, "source_type", "manual") in {"purchase", "project", "savings"}]),
        },
        "pending_tasks_sample": [
            {
                "id": task.id,
                "title": task.title,
                "priority": task.priority,
                "source_type": task.source_type,
                "budget_amount": round(float(task.budget_amount or 0), 2),
                "due_date": task.due_date.isoformat() if task.due_date else None,
            }
            for task in tasks[:8]
        ],
        "members": [
            {"id": member.id, "name": member.name, "role": member.role, "is_active": member.is_active}
            for member in members
        ],
        "analysis_guidance": [
            "Separar datos observados de inferencias.",
            "Indicar si falta histórico suficiente para comparar.",
            "No mezclar saldo provisorio con saldos a favor ya confirmados.",
            "No recomendar inversiones ni endeudamiento; solo organización doméstica prudente.",
        ],
    }



def build_weekly_household_payload(session: Session, household_id: int, month: str, period: dict) -> dict:
    start = period["start"]
    end = period["end"]
    previous_start = period["previous_start"]
    previous_end = period["previous_end"]
    current_expenses = session.exec(
        select(Expense).where(Expense.household_id == household_id, Expense.date >= start, Expense.date <= end)
    ).all()
    previous_expenses = session.exec(
        select(Expense).where(Expense.household_id == household_id, Expense.date >= previous_start, Expense.date <= previous_end)
    ).all()
    payload = build_household_ai_payload(session, household_id, month, f"analisis {period['frequency_label'].lower()} contextual")
    payload.update(
        {
            "period": {
                "type": period["type"],
                "frequency_label": period["frequency_label"],
                "preferred_weekday": period["preferred_weekday"],
                "preferred_weekday_label": period["preferred_weekday_label"],
                "period_key": period["period_key"],
                "week_key": period["week_key"],
                "start": start.isoformat(),
                "end": end.isoformat(),
                "previous_start": previous_start.isoformat(),
                "previous_end": previous_end.isoformat(),
                "next_start": period["next_start"].isoformat(),
            },
            "weekly_expenses_total": round(sum(float(item.amount or 0) for item in current_expenses), 2),
            "previous_weekly_expenses_total": round(sum(float(item.amount or 0) for item in previous_expenses), 2),
            "weekly_expenses_by_category": _sum_expenses_by_category(current_expenses),
            "previous_expenses_by_category": _sum_expenses_by_category(previous_expenses),
        }
    )
    if current_expenses:
        payload["expenses_by_category"] = payload["weekly_expenses_by_category"]
    return payload


def _create_weekly_report(
    session: Session,
    current_member: Member,
    month: str,
    use_api: bool,
    use_external_context: bool,
    use_news_context: bool,
    period: dict,
) -> AiReport:
    settings = get_settings()
    data = build_weekly_household_payload(session, current_member.household_id, month, period)
    external_context = fetch_argentina_economic_context(include_news=use_news_context) if use_external_context else {
        "country": "Argentina",
        "base_currency": "ARS",
        "indicators": [],
        "news": [],
        "traces": [],
        "notes": ["Contexto externo desactivado para este informe."],
    }
    api_key = settings.openai_api_key if use_api else None
    title, content, evidence = generate_weekly_household_report(data, external_context, api_key=api_key, model=settings.openai_model)
    evidence["analysis_frequency"] = period["type"]
    evidence["frequency_label"] = period["frequency_label"]
    report = AiReport(
        household_id=current_member.household_id,
        month=month,
        title=title,
        content=content,
        evidence_json=json.dumps(evidence, ensure_ascii=False, default=str),
        created_by_member_id=current_member.id or 0,
    )
    session.add(report)
    session.commit()
    session.refresh(report)
    return report


@router.get("/household-reports", response_model=list[AiReportRead])
def list_household_reports(month: str | None = None, current_member: Member = Depends(get_current_member), session: Session = Depends(get_session)):
    query = select(AiReport).where(AiReport.household_id == current_member.household_id)
    if month:
        query = query.where(AiReport.month == month)
    rows = session.exec(query.order_by(AiReport.created_at.desc(), AiReport.id.desc())).all()
    return [report_to_read(row) for row in rows]


@router.post("/household-reports", response_model=AiReportRead)
def create_household_report(payload: AiReportCreate, current_member: Member = Depends(get_current_member), session: Session = Depends(get_session)):
    settings = get_settings()
    data = build_household_ai_payload(session, current_member.household_id, payload.month, payload.focus)
    api_key = settings.openai_api_key if payload.use_api else None
    title, content, evidence = generate_household_report(data, api_key=api_key, model=settings.openai_model)
    report = AiReport(
        household_id=current_member.household_id,
        month=payload.month,
        title=title,
        content=content,
        evidence_json=json.dumps(evidence, ensure_ascii=False, default=str),
        created_by_member_id=current_member.id or 0,
    )
    session.add(report)
    session.commit()
    session.refresh(report)
    return report_to_read(report)


@router.get("/weekly-settings", response_model=AiWeeklySettingsRead)
def get_weekly_settings(current_member: Member = Depends(get_current_member), session: Session = Depends(get_session)):
    row = _get_or_create_weekly_settings(session, current_member.household_id, current_member.id)
    return _settings_to_read(session, row)


@router.put("/weekly-settings", response_model=AiWeeklySettingsRead)
def update_weekly_settings(payload: AiWeeklySettingsUpdate, current_member: Member = Depends(get_current_member), session: Session = Depends(get_session)):
    row = _get_or_create_weekly_settings(session, current_member.household_id, current_member.id)
    if payload.analysis_frequency is not None:
        row.analysis_frequency = _normalize_frequency(payload.analysis_frequency)
        if row.analysis_frequency == "manual":
            row.weekly_enabled = False
    if payload.weekly_enabled is not None:
        row.weekly_enabled = bool(payload.weekly_enabled)
        if row.weekly_enabled and _normalize_frequency(getattr(row, "analysis_frequency", "weekly")) == "manual":
            row.analysis_frequency = "weekly"
    if payload.preferred_weekday is not None:
        row.preferred_weekday = payload.preferred_weekday
    if payload.use_external_context is not None:
        row.use_external_context = payload.use_external_context
    if payload.use_news_context is not None:
        row.use_news_context = payload.use_news_context
    if payload.currency is not None:
        row.currency = payload.currency.upper()
    if payload.country_context is not None:
        row.country_context = payload.country_context
    row.updated_by_member_id = current_member.id
    row.updated_at = utc_now()
    session.add(row)
    session.commit()
    session.refresh(row)
    return _settings_to_read(session, row)


@router.get("/weekly-latest", response_model=AiWeeklyReportRead)
def latest_weekly_report(current_member: Member = Depends(get_current_member), session: Session = Depends(get_session)):
    settings = _get_or_create_weekly_settings(session, current_member.household_id, current_member.id)
    report = _latest_weekly_report(session, current_member.household_id)
    frequency = _normalize_frequency(getattr(settings, "analysis_frequency", "weekly"))
    label = FREQUENCY_LABELS.get(frequency, "Semanal").lower()
    return AiWeeklyReportRead(
        report=report_to_read(report) if report else None,
        settings=_settings_to_read(session, settings),
        tips=_visible_tips_from_report(report),
        generated_now=False,
        message=f"Último informe {label} disponible." if report else f"Todavía no hay informe {label} del hogar.",
    )


@router.post("/weekly-reports", response_model=AiWeeklyReportRead)
def create_weekly_report(payload: AiWeeklyReportCreate, current_member: Member = Depends(get_current_member), session: Session = Depends(get_session)):
    settings = _get_or_create_weekly_settings(session, current_member.household_id, current_member.id)
    frequency = _normalize_frequency(getattr(settings, "analysis_frequency", "weekly"))
    period = _period_info(frequency, settings.preferred_weekday)
    latest = _latest_weekly_report(session, current_member.household_id)
    if latest and _report_matches_period(latest, period) and not payload.force:
        return AiWeeklyReportRead(
            report=report_to_read(latest),
            settings=_settings_to_read(session, settings),
            tips=_visible_tips_from_report(latest),
            generated_now=False,
            message="Ya existe un análisis vigente según la frecuencia configurada. Usamos ese informe para no gastar llamadas innecesarias.",
        )
    report = _create_weekly_report(
        session=session,
        current_member=current_member,
        month=payload.month,
        use_api=payload.use_api,
        use_external_context=settings.use_external_context if payload.use_external_context is None else payload.use_external_context,
        use_news_context=settings.use_news_context if payload.use_news_context is None else payload.use_news_context,
        period=period,
    )
    return AiWeeklyReportRead(
        report=report_to_read(report),
        settings=_settings_to_read(session, settings),
        tips=_visible_tips_from_report(report),
        generated_now=True,
        message="Análisis IA generado. Los consejos visibles se usarán en Inicio hasta el próximo período configurado.",
    )


@router.post("/weekly-refresh-if-needed", response_model=AiWeeklyReportRead)
def weekly_refresh_if_needed(payload: AiWeeklyReportCreate, current_member: Member = Depends(get_current_member), session: Session = Depends(get_session)):
    settings = _get_or_create_weekly_settings(session, current_member.household_id, current_member.id)
    frequency = _normalize_frequency(getattr(settings, "analysis_frequency", "weekly"))
    period = _period_info(frequency, settings.preferred_weekday)
    latest = _latest_weekly_report(session, current_member.household_id)
    automatic_active = bool(settings.weekly_enabled) and frequency != "manual"
    if not automatic_active:
        return AiWeeklyReportRead(
            report=report_to_read(latest) if latest else None,
            settings=_settings_to_read(session, settings),
            tips=_visible_tips_from_report(latest),
            generated_now=False,
            message="Análisis automático desactivado o en modo manual. Mostramos el último consejo guardado.",
        )
    if latest and _report_matches_period(latest, period) and not payload.force:
        return AiWeeklyReportRead(
            report=report_to_read(latest),
            settings=_settings_to_read(session, settings),
            tips=_visible_tips_from_report(latest),
            generated_now=False,
            message="Consejos actualizados para el período vigente.",
        )
    report = _create_weekly_report(
        session=session,
        current_member=current_member,
        month=payload.month,
        use_api=payload.use_api,
        use_external_context=settings.use_external_context if payload.use_external_context is None else payload.use_external_context,
        use_news_context=settings.use_news_context if payload.use_news_context is None else payload.use_news_context,
        period=period,
    )
    return AiWeeklyReportRead(
        report=report_to_read(report),
        settings=_settings_to_read(session, settings),
        tips=_visible_tips_from_report(report),
        generated_now=True,
        message="Se generó el análisis automático del hogar según la frecuencia configurada.",
    )
