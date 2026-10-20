from fastapi import APIRouter, Depends
from sqlmodel import Session

from ..database import get_session
from ..models import Member
from ..schemas import DashboardBootstrapRead
from . import ai, finance, household, tasks
from .auth import get_current_member


router = APIRouter(prefix="/dashboard", tags=["dashboard"])


@router.get("/bootstrap", response_model=DashboardBootstrapRead)
def get_dashboard_bootstrap(
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    """Devuelve en una sola llamada la información necesaria para Inicio.

    La operación mantiene las mismas reglas de cada módulo, pero elimina las
    múltiples conexiones HTTP consecutivas que hacía el cliente.
    """
    active_period = finance.read_active_period(current_member=current_member, session=session)
    month = active_period.active_month

    # Sincronizar primero los anticipos garantiza que resumen y saldos se lean
    # desde el mismo estado confirmado.
    advance_payments = finance.list_monthly_advance_payments(
        month=month,
        current_member=current_member,
        session=session,
    )

    return DashboardBootstrapRead(
        month=month,
        active_period=active_period,
        members=household.list_members(
            include_inactive=False,
            current_member=current_member,
            session=session,
        ),
        participation=finance.list_month_participation(
            month=month,
            include_inactive=False,
            current_member=current_member,
            session=session,
        ),
        summary=finance.get_month_summary(
            month=month,
            current_member=current_member,
            session=session,
        ),
        advance_payments=advance_payments,
        credit_balances=finance.list_credit_balances(
            active_only=True,
            current_member=current_member,
            session=session,
        ),
        fixed_expenses=finance.list_fixed_expenses(
            active_only=True,
            current_member=current_member,
            session=session,
        ),
        task_summary=tasks.task_summary(current_member=current_member, session=session),
        weekly_ai=ai.latest_weekly_report(current_member=current_member, session=session),
    )
