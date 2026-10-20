from sqlmodel import SQLModel, Session, create_engine
from sqlalchemy.pool import StaticPool

from app.models import Household, HouseholdPeriodSettings, Member, MemberRole
from app.routers.dashboard import get_dashboard_bootstrap


def test_dashboard_bootstrap_returns_one_coherent_snapshot():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(engine)

    with Session(engine) as session:
        household = Household(name="Casa", invite_code="dashboard-test")
        session.add(household)
        session.flush()
        owner = Member(
            household_id=household.id or 0,
            name="Solana",
            pin_hash="x",
            role=MemberRole.owner,
        )
        session.add(owner)
        session.flush()
        session.add(
            HouseholdPeriodSettings(
                household_id=household.id or 0,
                active_month_override="2026-10",
                updated_by_member_id=owner.id,
            )
        )
        session.commit()
        session.refresh(owner)

        result = get_dashboard_bootstrap(current_member=owner, session=session)

        assert result.month == "2026-10"
        assert result.active_period.active_month == result.month
        assert [member.name for member in result.members] == ["Solana"]
        assert result.participation[0].member_id == owner.id
        assert result.summary.month == result.month
        assert result.advance_payments == []
        assert result.credit_balances == []
        assert result.fixed_expenses == []
        assert result.task_summary.pending_count == 0
        assert result.weekly_ai.generated_now is False
        assert result.weekly_ai.report is None
