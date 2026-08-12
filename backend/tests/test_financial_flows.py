from datetime import date

import pytest
from fastapi import HTTPException
from sqlalchemy.pool import StaticPool
from sqlmodel import SQLModel, Session, create_engine, select

from app.models import (
    CreditBalance,
    Debt,
    DebtStatus,
    Expense,
    Household,
    HouseholdPeriodSettings,
    Member,
    MemberRole,
    MonthlyAdvancePayment,
    MonthlyIncome,
    PaymentStatus,
)
from app.routers.finance import (
    _sync_all_advance_credits,
    _sync_monthly_advance_allocations,
    apply_credit_balance,
    close_month,
    create_automatic_debts_from_summary,
    create_manual_debt,
    confirm_monthly_advance_payment,
    reset_active_period_basic,
)
from app.schemas import AutomaticDebtCreate, CreditBalanceApply, DebtCreate, MonthCloseCreate


TEST_MONTH = "2026-08"


def new_session() -> Session:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(engine)
    return Session(engine)


def seed_household(session: Session):
    household = Household(name="Casa", invite_code="test-house")
    session.add(household)
    session.flush()
    payer = Member(
        household_id=household.id or 0,
        name="Yo",
        pin_hash="x",
        role=MemberRole.owner,
    )
    receiver = Member(
        household_id=household.id or 0,
        name="Amiga",
        pin_hash="x",
    )
    session.add(payer)
    session.add(receiver)
    session.flush()
    session.add(MonthlyIncome(household_id=household.id or 0, member_id=payer.id or 0, month=TEST_MONTH, amount=50))
    session.add(MonthlyIncome(household_id=household.id or 0, member_id=receiver.id or 0, month=TEST_MONTH, amount=50))
    session.add(
        Expense(
            household_id=household.id or 0,
            paid_by_member_id=receiver.id or 0,
            month=TEST_MONTH,
            date=date(2026, 8, 1),
            amount=100,
        )
    )
    session.add(
        HouseholdPeriodSettings(
            household_id=household.id or 0,
            active_month_override=TEST_MONTH,
            updated_by_member_id=payer.id,
        )
    )
    session.commit()
    return household, payer, receiver


def add_advance(session: Session, household: Household, payer: Member, receiver: Member, *, status=PaymentStatus.pending):
    payment = MonthlyAdvancePayment(
        household_id=household.id or 0,
        month=TEST_MONTH,
        paid_by_member_id=payer.id or 0,
        received_by_member_id=receiver.id or 0,
        amount=80,
        applied_amount=50 if status == PaymentStatus.confirmed else 0,
        credit_amount=30 if status == PaymentStatus.confirmed else 0,
        status=status,
        date=date(2026, 8, 2),
    )
    session.add(payment)
    session.commit()
    session.refresh(payment)
    return payment


def test_confirmed_advance_creates_formal_credit():
    with new_session() as session:
        household, payer, receiver = seed_household(session)
        payment = add_advance(session, household, payer, receiver)

        result = confirm_monthly_advance_payment(payment.id or 0, receiver, session)
        credit = session.exec(select(CreditBalance)).one()

        assert result.applied_amount == 50
        assert result.credit_amount == 30
        assert credit.original_amount == 30
        assert credit.remaining_amount == 30
        assert credit.owner_member_id == payer.id
        assert credit.counterparty_member_id == receiver.id
        assert credit.source_advance_payment_id == payment.id


def test_reconcile_repairs_missing_historical_credit():
    with new_session() as session:
        household, payer, receiver = seed_household(session)
        payment = add_advance(session, household, payer, receiver, status=PaymentStatus.confirmed)

        assert _sync_all_advance_credits(household.id or 0, session) is True
        session.commit()
        credit = session.exec(select(CreditBalance)).one()

        assert credit.source_advance_payment_id == payment.id
        assert credit.remaining_amount == 30


def test_used_credit_freezes_advance_allocation():
    with new_session() as session:
        household, payer, receiver = seed_household(session)
        payment = add_advance(session, household, payer, receiver)
        confirm_monthly_advance_payment(payment.id or 0, receiver, session)
        credit = session.exec(select(CreditBalance)).one()
        debt = Debt(
            household_id=household.id or 0,
            debtor_member_id=payer.id or 0,
            creditor_member_id=receiver.id or 0,
            original_amount=20,
            reason="Otra deuda",
        )
        session.add(debt)
        session.commit()
        session.refresh(debt)
        apply_credit_balance(credit.id or 0, CreditBalanceApply(debt_id=debt.id or 0, amount=20), payer, session)
        session.add(
            Expense(
                household_id=household.id or 0,
                paid_by_member_id=receiver.id or 0,
                month=TEST_MONTH,
                date=date(2026, 8, 3),
                amount=40,
            )
        )
        session.commit()

        _sync_monthly_advance_allocations(TEST_MONTH, household.id or 0, session)
        session.refresh(payment)
        session.refresh(credit)

        assert payment.applied_amount == 50
        assert payment.credit_amount == 30
        assert credit.remaining_amount == 10


def test_close_creates_final_automatic_debt():
    with new_session() as session:
        household, payer, receiver = seed_household(session)

        close_month(MonthCloseCreate(month=TEST_MONTH), payer, session)
        debts = session.exec(select(Debt).where(Debt.status != DebtStatus.cancelled)).all()

        assert len(debts) == 1
        assert debts[0].debtor_member_id == payer.id
        assert debts[0].creditor_member_id == receiver.id
        assert debts[0].original_amount == 50


def test_reset_refuses_to_delete_confirmed_transfer():
    with new_session() as session:
        household, payer, receiver = seed_household(session)
        add_advance(session, household, payer, receiver, status=PaymentStatus.confirmed)

        with pytest.raises(HTTPException) as exc:
            reset_active_period_basic(payer, session)

        assert exc.value.status_code == 409
        assert session.exec(select(MonthlyAdvancePayment)).one().status == PaymentStatus.confirmed


def test_automatic_debt_regeneration_does_not_duplicate_active_debt():
    with new_session() as session:
        household, payer, _ = seed_household(session)

        create_automatic_debts_from_summary(AutomaticDebtCreate(month=TEST_MONTH), payer, session)
        create_automatic_debts_from_summary(AutomaticDebtCreate(month=TEST_MONTH), payer, session)
        active = session.exec(
            select(Debt).where(
                Debt.household_id == household.id,
                Debt.status != DebtStatus.cancelled,
            )
        ).all()

        assert len(active) == 1
        assert active[0].original_amount == 50


def test_uninvolved_member_cannot_create_debt_for_other_people():
    with new_session() as session:
        household, payer, receiver = seed_household(session)
        outsider = Member(
            household_id=household.id or 0,
            name="Otra persona",
            pin_hash="x",
        )
        session.add(outsider)
        session.commit()
        session.refresh(outsider)

        with pytest.raises(HTTPException) as exc:
            create_manual_debt(
                DebtCreate(
                    debtor_member_id=payer.id or 0,
                    creditor_member_id=receiver.id or 0,
                    original_amount=25,
                    reason="No autorizada",
                ),
                outsider,
                session,
            )

        assert exc.value.status_code == 403
        assert session.exec(select(Debt)).all() == []
