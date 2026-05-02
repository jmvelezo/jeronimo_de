from dataclasses import dataclass
from math import isclose
from ..models import Expense, Member, MonthlyIncome, MonthlyParticipation


@dataclass
class SummaryMember:
    member_id: int
    name: str
    color: str
    income: float
    income_share: float
    should_pay: float
    actually_paid: float
    balance: float
    participates: bool


def round_money(value: float) -> float:
    return round(float(value) + 0.0000001, 2)


def _participation_by_member(members: list[Member], participations: list[MonthlyParticipation] | None) -> dict[int, bool]:
    explicit = {row.member_id: row.participates for row in (participations or [])}
    return {m.id or 0: bool(explicit.get(m.id or 0, m.is_active)) for m in members}


def calculate_month_summary(
    month: str,
    members: list[Member],
    incomes: list[MonthlyIncome],
    expenses: list[Expense],
    participations: list[MonthlyParticipation] | None = None,
    advance_payments: list | None = None,
) -> dict:
    # Se conserva historial de integrantes inactivos, pero el reparto mensual solo considera
    # integrantes activos. La participación mensual permite excluir temporalmente a alguien
    # sin borrarlo ni romper cierres anteriores.
    active_members = [m for m in members if m.is_active]
    participation = _participation_by_member(active_members, participations)

    income_by_member = {m.id: 0.0 for m in active_members}
    paid_by_member = {m.id: 0.0 for m in active_members}

    for inc in incomes:
        if inc.member_id in income_by_member:
            income_by_member[inc.member_id] += inc.amount

    shared_expenses = [e for e in expenses if e.is_shared]
    total_shared = sum(e.amount for e in shared_expenses)

    for expense in shared_expenses:
        if expense.paid_by_member_id in paid_by_member:
            paid_by_member[expense.paid_by_member_id] += expense.amount

    # Los pagos anticipados confirmados contra el saldo del período reducen el saldo vivo:
    # quien paga suma como si hubiera cubierto más; quien recibe resta porque ya cobró parte de su crédito.
    for payment in (advance_payments or []):
        paid_by = getattr(payment, "paid_by_member_id", None)
        received_by = getattr(payment, "received_by_member_id", None)
        applied = round_money(getattr(payment, "applied_amount", 0) or 0)
        if applied <= 0:
            continue
        if paid_by in paid_by_member:
            paid_by_member[paid_by] += applied
        if received_by in paid_by_member:
            paid_by_member[received_by] -= applied

    participating_members = [m for m in active_members if participation.get(m.id or 0, True)]
    total_income = sum(income_by_member.get(m.id, 0.0) for m in participating_members)

    warning = None
    summaries: list[SummaryMember] = []

    if not participating_members:
        warning = "No hay integrantes participando en el reparto de este mes. Activá al menos uno para calcular."
    elif total_income <= 0:
        warning = "Todavía faltan ingresos del mes para los integrantes que participan. Sin ingresos no se puede calcular un reparto proporcional confiable."

    if total_income <= 0:
        for member in active_members:
            member_id = member.id or 0
            paid = paid_by_member.get(member_id, 0.0)
            summaries.append(
                SummaryMember(
                    member_id=member_id,
                    name=member.name,
                    color=member.color,
                    income=round_money(income_by_member.get(member.id, 0)),
                    income_share=0,
                    should_pay=0,
                    actually_paid=round_money(paid),
                    balance=round_money(paid),
                    participates=participation.get(member_id, True),
                )
            )
        return {
            "month": month,
            "total_income": 0,
            "total_shared_expenses": round_money(total_shared),
            "members": [s.__dict__ for s in summaries],
            "settlements": [],
            "warning": warning,
        }

    for member in active_members:
        member_id = member.id or 0
        participates = participation.get(member_id, True)
        income = income_by_member.get(member_id, 0.0)
        share = income / total_income if participates and total_income else 0
        should_pay = total_shared * share if participates else 0
        actually_paid = paid_by_member.get(member_id, 0.0)
        balance = actually_paid - should_pay
        summaries.append(
            SummaryMember(
                member_id=member_id,
                name=member.name,
                color=member.color,
                income=round_money(income),
                income_share=round(share, 6),
                should_pay=round_money(should_pay),
                actually_paid=round_money(actually_paid),
                balance=round_money(balance),
                participates=participates,
            )
        )

    debtors = sorted(
        [{"member_id": s.member_id, "amount": round_money(-s.balance)} for s in summaries if s.balance < -0.01],
        key=lambda x: x["amount"],
        reverse=True,
    )
    creditors = sorted(
        [{"member_id": s.member_id, "amount": round_money(s.balance)} for s in summaries if s.balance > 0.01],
        key=lambda x: x["amount"],
        reverse=True,
    )

    settlements = []
    i = j = 0
    while i < len(debtors) and j < len(creditors):
        amount = min(debtors[i]["amount"], creditors[j]["amount"])
        amount = round_money(amount)
        if amount > 0 and not isclose(amount, 0.0):
            settlements.append(
                {
                    "debtor_member_id": debtors[i]["member_id"],
                    "creditor_member_id": creditors[j]["member_id"],
                    "amount": amount,
                    "reason": f"Ajuste proporcional de gastos comunes del mes {month}",
                }
            )
        debtors[i]["amount"] = round_money(debtors[i]["amount"] - amount)
        creditors[j]["amount"] = round_money(creditors[j]["amount"] - amount)
        if debtors[i]["amount"] <= 0.01:
            i += 1
        if creditors[j]["amount"] <= 0.01:
            j += 1

    return {
        "month": month,
        "total_income": round_money(total_income),
        "total_shared_expenses": round_money(total_shared),
        "members": [s.__dict__ for s in summaries],
        "settlements": settlements,
        "warning": warning,
    }
