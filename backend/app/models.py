from datetime import date as Date, datetime, timezone
from enum import Enum
from typing import Optional
from sqlmodel import Field, Relationship, SQLModel


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


class MemberRole(str, Enum):
    owner = "owner"
    admin = "admin"  # administrador operativo
    member = "member"


class DebtSource(str, Enum):
    manual = "manual"
    automatic = "automatic"


class DebtStatus(str, Enum):
    active = "active"
    partial = "partial"
    paid = "paid"
    cancelled = "cancelled"


class PaymentStatus(str, Enum):
    pending = "pending"
    confirmed = "confirmed"
    rejected = "rejected"
    voided = "voided"


class CreditBalanceStatus(str, Enum):
    available = "available"
    applied = "applied"
    cancelled = "cancelled"


class TaskPriority(str, Enum):
    low = "low"
    normal = "normal"
    high = "high"
    urgent = "urgent"


class TaskStatus(str, Enum):
    pending = "pending"
    done = "done"
    cancelled = "cancelled"


class TaskRepeatRule(str, Enum):
    none = "none"
    monthly = "monthly"


class Household(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    name: str = Field(index=True)
    invite_code: str = Field(index=True, unique=True)
    created_at: datetime = Field(default_factory=utc_now)
    members: list["Member"] = Relationship(back_populates="household")


class HouseholdPeriodSettings(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    household_id: int = Field(foreign_key="household.id", index=True, unique=True)
    period_mode: str = Field(default="calendar", max_length=20, description="calendar|custom")
    start_day: int = Field(default=1, ge=1, le=28)
    updated_by_member_id: int | None = Field(default=None, foreign_key="member.id")
    created_at: datetime = Field(default_factory=utc_now)
    updated_at: datetime = Field(default_factory=utc_now)


class Member(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    household_id: int = Field(foreign_key="household.id", index=True)
    name: str = Field(index=True)
    color: str = "#7C3AED"
    role: MemberRole = MemberRole.member
    pin_hash: str
    is_active: bool = True
    created_at: datetime = Field(default_factory=utc_now)
    household: Household = Relationship(back_populates="members")


class MonthlyIncome(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    household_id: int = Field(foreign_key="household.id", index=True)
    member_id: int = Field(foreign_key="member.id", index=True)
    month: str = Field(index=True, description="Formato YYYY-MM")
    amount: float = Field(ge=0)
    note: str | None = None
    created_at: datetime = Field(default_factory=utc_now)
    updated_at: datetime = Field(default_factory=utc_now)



class MonthlyParticipation(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    household_id: int = Field(foreign_key="household.id", index=True)
    member_id: int = Field(foreign_key="member.id", index=True)
    month: str = Field(index=True, description="Formato YYYY-MM")
    participates: bool = True
    note: str | None = None
    created_at: datetime = Field(default_factory=utc_now)
    updated_at: datetime = Field(default_factory=utc_now)


class Expense(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    household_id: int = Field(foreign_key="household.id", index=True)
    paid_by_member_id: int = Field(foreign_key="member.id", index=True)
    date: Date = Field(default_factory=Date.today, index=True)
    month: str = Field(index=True, description="Formato YYYY-MM")
    category: str = Field(default="General", index=True)
    amount: float = Field(gt=0)
    description: str = ""
    is_shared: bool = True
    created_at: datetime = Field(default_factory=utc_now)
    updated_at: datetime = Field(default_factory=utc_now)


class Debt(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    household_id: int = Field(foreign_key="household.id", index=True)
    debtor_member_id: int = Field(foreign_key="member.id", index=True)
    creditor_member_id: int = Field(foreign_key="member.id", index=True)
    source: DebtSource = DebtSource.manual
    source_month: str | None = Field(default=None, index=True)
    original_amount: float = Field(gt=0)
    reason: str = ""
    status: DebtStatus = DebtStatus.active
    created_at: datetime = Field(default_factory=utc_now)
    updated_at: datetime = Field(default_factory=utc_now)


class DebtPayment(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    debt_id: int = Field(foreign_key="debt.id", index=True)
    household_id: int = Field(foreign_key="household.id", index=True)
    paid_by_member_id: int = Field(foreign_key="member.id", index=True)
    received_by_member_id: int | None = Field(default=None, foreign_key="member.id", index=True)
    amount: float = Field(gt=0)
    applied_amount: float = Field(default=0, ge=0)
    credit_amount: float = Field(default=0, ge=0)
    status: PaymentStatus = Field(default=PaymentStatus.pending, index=True)
    date: Date = Field(default_factory=Date.today)
    note: str = ""
    rejected_reason: str = ""
    confirmed_by_member_id: int | None = Field(default=None, foreign_key="member.id")
    confirmed_at: datetime | None = None
    created_at: datetime = Field(default_factory=utc_now)
    updated_at: datetime = Field(default_factory=utc_now)


class CreditBalance(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    household_id: int = Field(foreign_key="household.id", index=True)
    owner_member_id: int = Field(foreign_key="member.id", index=True)
    counterparty_member_id: int = Field(foreign_key="member.id", index=True)
    source_payment_id: int | None = Field(default=None, foreign_key="debtpayment.id", index=True)
    original_amount: float = Field(gt=0)
    remaining_amount: float = Field(ge=0)
    status: CreditBalanceStatus = Field(default=CreditBalanceStatus.available, index=True)
    reason: str = ""
    created_at: datetime = Field(default_factory=utc_now)
    updated_at: datetime = Field(default_factory=utc_now)


class MonthlyAdvancePayment(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    household_id: int = Field(foreign_key="household.id", index=True)
    month: str = Field(index=True, description="Período YYYY-MM")
    paid_by_member_id: int = Field(foreign_key="member.id", index=True)
    received_by_member_id: int = Field(foreign_key="member.id", index=True)
    amount: float = Field(gt=0)
    applied_amount: float = Field(default=0, ge=0)
    credit_amount: float = Field(default=0, ge=0)
    status: PaymentStatus = Field(default=PaymentStatus.pending, index=True)
    date: Date = Field(default_factory=Date.today)
    note: str = ""
    rejected_reason: str = ""
    confirmed_by_member_id: int | None = Field(default=None, foreign_key="member.id")
    confirmed_at: datetime | None = None
    created_at: datetime = Field(default_factory=utc_now)
    updated_at: datetime = Field(default_factory=utc_now)


class MonthlyClose(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    household_id: int = Field(foreign_key="household.id", index=True)
    month: str = Field(index=True)
    total_income: float
    total_shared_expenses: float
    summary_json: str
    closed_by_member_id: int = Field(foreign_key="member.id")
    created_at: datetime = Field(default_factory=utc_now)


class AiReport(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    household_id: int = Field(foreign_key="household.id", index=True)
    month: str = Field(index=True)
    title: str
    content: str
    evidence_json: str = "{}"
    created_by_member_id: int = Field(foreign_key="member.id")
    created_at: datetime = Field(default_factory=utc_now)


class HouseholdTask(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    household_id: int = Field(foreign_key="household.id", index=True)
    title: str = Field(index=True)
    description: str = ""
    assigned_member_id: int | None = Field(default=None, foreign_key="member.id", index=True)
    due_date: Date | None = Field(default=None, index=True)
    alert_date: Date | None = Field(default=None, index=True)
    priority: TaskPriority = Field(default=TaskPriority.normal, index=True)
    status: TaskStatus = Field(default=TaskStatus.pending, index=True)
    repeat_rule: TaskRepeatRule = TaskRepeatRule.none
    source_type: str = Field(default="manual", index=True, description="manual|payment|purchase|savings")
    budget_amount: float = Field(default=0, ge=0)
    product_links: str = Field(default="", description="Links o fuentes separados por saltos de línea")
    preferred_sources: str = Field(default="", description="Tiendas/fuentes sugeridas separadas por saltos de línea")
    tracking_frequency: str = Field(default="manual", max_length=20, description="manual|weekly|biweekly|monthly")
    last_ai_check_at: datetime | None = None
    last_ai_summary: str = ""
    last_ai_evidence_json: str = "{}"
    created_by_member_id: int = Field(foreign_key="member.id", index=True)
    completed_by_member_id: int | None = Field(default=None, foreign_key="member.id")
    completed_at: datetime | None = None
    created_at: datetime = Field(default_factory=utc_now)
    updated_at: datetime = Field(default_factory=utc_now)


class HouseholdAiSettings(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    household_id: int = Field(foreign_key="household.id", index=True, unique=True)
    weekly_enabled: bool = False
    analysis_frequency: str = Field(default="weekly", max_length=20, description="manual|weekly|biweekly|monthly")
    preferred_weekday: int = Field(default=0, description="0=lunes, 6=domingo")
    use_external_context: bool = True
    use_news_context: bool = True
    currency: str = Field(default="ARS", max_length=8)
    country_context: str = Field(default="Argentina", max_length=80)
    updated_by_member_id: int | None = Field(default=None, foreign_key="member.id")
    created_at: datetime = Field(default_factory=utc_now)
    updated_at: datetime = Field(default_factory=utc_now)


class TaskItem(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    household_id: int = Field(foreign_key="household.id", index=True)
    title: str
    due_date: Date | None = None
    is_done: bool = False
    created_by_member_id: int = Field(foreign_key="member.id")
    created_at: datetime = Field(default_factory=utc_now)
