from datetime import datetime, timezone
from fastapi import APIRouter, Depends
from fastapi.encoders import jsonable_encoder
from sqlmodel import Session, select

from ..database import get_session
from ..models import (
    AiReport,
    CreditBalance,
    Debt,
    DebtPayment,
    Expense,
    Household,
    HouseholdPeriodSettings,
    HouseholdTask,
    Member,
    MonthlyAdvancePayment,
    MonthlyClose,
    MonthlyIncome,
    MonthlyParticipation,
)
from .auth import get_current_member

router = APIRouter(prefix="/backup", tags=["backup"])


@router.get("/status")
def backup_status(current_member: Member = Depends(get_current_member)) -> dict:
    return {
        "ok": True,
        "scope": "hogar_compartido",
        "household_id": current_member.household_id,
        "message": "Respaldo disponible para datos comunes del hogar. Los datos personales siguen siendo locales del dispositivo.",
    }


def _rows(session: Session, model, household_id: int):
    return session.exec(select(model).where(model.household_id == household_id)).all()


@router.get("/household")
def export_household_backup(
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
) -> dict:
    household_id = current_member.household_id
    household = session.get(Household, household_id)
    members = _rows(session, Member, household_id)

    # No se exporta pin_hash para evitar copiar credenciales internas en texto.
    safe_members = [
        {
            "id": member.id,
            "household_id": member.household_id,
            "name": member.name,
            "color": member.color,
            "role": member.role,
            "is_active": member.is_active,
            "created_at": member.created_at,
        }
        for member in members
    ]

    tables = {
        "household": household,
        "members": safe_members,
        "monthly_incomes": _rows(session, MonthlyIncome, household_id),
        "monthly_participation": _rows(session, MonthlyParticipation, household_id),
        "expenses": _rows(session, Expense, household_id),
        "debts": _rows(session, Debt, household_id),
        "debt_payments": _rows(session, DebtPayment, household_id),
        "credit_balances": _rows(session, CreditBalance, household_id),
        "monthly_advance_payments": _rows(session, MonthlyAdvancePayment, household_id),
        "period_settings": _rows(session, HouseholdPeriodSettings, household_id),
        "monthly_closes": _rows(session, MonthlyClose, household_id),
        "household_tasks": _rows(session, HouseholdTask, household_id),
        "ai_reports": _rows(session, AiReport, household_id),
    }
    counts = {key: (1 if key == "household" and value is not None else len(value) if isinstance(value, list) else 0) for key, value in tables.items()}
    payload = {
        "ok": True,
        "schema_version": "jeronimo_de_r16_backup_v4",
        "generated_at": datetime.now(timezone.utc),
        "generated_by_member_id": current_member.id,
        "household_id": household_id,
        "personal_data_note": "Este respaldo solo contiene datos comunes del hogar. Las cuentas, gastos y análisis personales locales no salen del dispositivo.",
        "counts": counts,
        "tables": tables,
    }
    return jsonable_encoder(payload)
