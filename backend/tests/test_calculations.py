from datetime import date
from app.models import Expense, Member, MonthlyIncome
from app.services.calculations import calculate_month_summary


def test_proportional_summary_two_members():
    members = [
        Member(id=1, household_id=1, name="Jose", pin_hash="x"),
        Member(id=2, household_id=1, name="Amiga", pin_hash="x"),
    ]
    incomes = [
        MonthlyIncome(household_id=1, member_id=1, month="2026-05", amount=1200000),
        MonthlyIncome(household_id=1, member_id=2, month="2026-05", amount=800000),
    ]
    expenses = [
        Expense(household_id=1, paid_by_member_id=1, month="2026-05", date=date(2026, 5, 1), amount=400000),
        Expense(household_id=1, paid_by_member_id=2, month="2026-05", date=date(2026, 5, 2), amount=100000),
    ]
    summary = calculate_month_summary("2026-05", members, incomes, expenses)
    assert summary["total_shared_expenses"] == 500000
    assert summary["members"][0]["should_pay"] == 300000
    assert summary["members"][1]["should_pay"] == 200000
    assert summary["settlements"][0]["debtor_member_id"] == 2
    assert summary["settlements"][0]["creditor_member_id"] == 1
    assert summary["settlements"][0]["amount"] == 100000
