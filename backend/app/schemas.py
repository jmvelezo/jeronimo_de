from datetime import date, datetime
from pydantic import BaseModel, Field
from .models import CreditBalanceStatus, DebtSource, DebtStatus, MemberRole, PaymentStatus, TaskPriority, TaskRepeatRule, TaskStatus


class InitialMemberCreate(BaseModel):
    name: str = Field(min_length=2, max_length=80)
    pin: str = Field(min_length=4, max_length=72)
    color: str = "#7C3AED"
    role: MemberRole = MemberRole.member


class HouseholdCreate(BaseModel):
    name: str = Field(min_length=2, max_length=120)
    invite_code: str | None = Field(default=None, min_length=4, max_length=40)
    members: list[InitialMemberCreate]


class HouseholdRead(BaseModel):
    id: int
    name: str
    invite_code: str


class MemberRead(BaseModel):
    id: int
    household_id: int
    name: str
    color: str
    role: MemberRole
    is_active: bool


class MemberCreate(BaseModel):
    name: str = Field(min_length=2, max_length=80)
    pin: str = Field(min_length=4, max_length=72)
    color: str = "#7C3AED"
    role: MemberRole = MemberRole.member


class MemberUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=80)
    color: str | None = Field(default=None, max_length=32)
    role: MemberRole | None = None


class MemberActiveUpdate(BaseModel):
    is_active: bool
    reason: str = ""


class MemberParticipationUpdate(BaseModel):
    month: str = Field(pattern=r"^\d{4}-\d{2}$")
    participates: bool
    note: str | None = None


class MemberParticipationRead(BaseModel):
    member_id: int
    month: str
    participates: bool
    note: str | None = None


class AuthLogin(BaseModel):
    household_code: str
    member_name: str
    pin: str


class TokenRead(BaseModel):
    access_token: str
    token_type: str = "bearer"
    household: HouseholdRead
    member: MemberRead


class IncomeUpsert(BaseModel):
    member_id: int
    month: str = Field(pattern=r"^\d{4}-\d{2}$")
    amount: float = Field(ge=0)
    note: str | None = None


class IncomeRead(BaseModel):
    id: int
    member_id: int
    month: str
    amount: float
    note: str | None = None


class ExpenseCreate(BaseModel):
    paid_by_member_id: int
    amount: float = Field(gt=0)
    category: str = "General"
    description: str = ""
    date: date
    is_shared: bool = True


class ExpenseRead(BaseModel):
    id: int
    paid_by_member_id: int
    amount: float
    category: str
    description: str
    date: date
    month: str
    is_shared: bool


class CardImportPreviewItem(BaseModel):
    date: date | None = None
    description: str = ""
    amount: float = Field(ge=0)
    currency: str = "ARS"
    category: str = "General"
    confidence: float = Field(default=0.5, ge=0, le=1)
    raw_text: str = ""


class CardImportPreviewResponse(BaseModel):
    items: list[CardImportPreviewItem] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)


class FixedExpenseTemplateCreate(BaseModel):
    name: str = Field(min_length=2, max_length=120)
    amount: float = Field(gt=0)
    category: str = Field(default="General", max_length=80)
    default_paid_by_member_id: int | None = None
    frequency: str = Field(default="monthly", max_length=20)
    active: bool = True
    notes: str = ""


class FixedExpenseTemplateUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=120)
    amount: float | None = Field(default=None, gt=0)
    category: str | None = Field(default=None, max_length=80)
    default_paid_by_member_id: int | None = None
    frequency: str | None = Field(default=None, max_length=20)
    active: bool | None = None
    notes: str | None = None


class FixedExpenseTemplateRead(BaseModel):
    id: int
    name: str
    amount: float
    category: str
    default_paid_by_member_id: int | None = None
    frequency: str
    active: bool
    notes: str
    created_at: datetime
    updated_at: datetime


class MemberSummary(BaseModel):
    member_id: int
    name: str
    color: str
    income: float
    income_share: float
    should_pay: float
    actually_paid: float
    balance: float
    participates: bool = True


class SettlementSuggestion(BaseModel):
    debtor_member_id: int
    creditor_member_id: int
    amount: float
    reason: str


class MonthSummary(BaseModel):
    month: str
    total_income: float
    total_shared_expenses: float
    members: list[MemberSummary]
    settlements: list[SettlementSuggestion]
    warning: str | None = None


class DebtCreate(BaseModel):
    debtor_member_id: int
    creditor_member_id: int
    original_amount: float = Field(gt=0)
    reason: str = ""


class DebtRead(BaseModel):
    id: int
    debtor_member_id: int
    creditor_member_id: int
    source: DebtSource
    source_month: str | None
    original_amount: float
    paid_amount: float
    pending_amount: float = 0
    remaining_amount: float
    reason: str
    status: DebtStatus


class DebtPaymentCreate(BaseModel):
    amount: float = Field(gt=0)
    date: date
    note: str = ""


class DebtPaymentDecision(BaseModel):
    reason: str = ""


class DebtPaymentRead(BaseModel):
    id: int
    debt_id: int
    paid_by_member_id: int
    received_by_member_id: int | None = None
    amount: float
    applied_amount: float = 0
    credit_amount: float = 0
    status: PaymentStatus = PaymentStatus.pending
    date: date
    note: str
    rejected_reason: str = ""
    confirmed_by_member_id: int | None = None
    confirmed_at: datetime | None = None


class CreditBalanceRead(BaseModel):
    id: int
    owner_member_id: int
    counterparty_member_id: int
    source_payment_id: int | None = None
    original_amount: float
    remaining_amount: float
    status: CreditBalanceStatus
    reason: str
    created_at: datetime


class CreditBalanceApply(BaseModel):
    debt_id: int
    amount: float = Field(gt=0)
    note: str = ""


class MonthlyAdvancePaymentCreate(BaseModel):
    month: str = Field(pattern=r"^\d{4}-\d{2}$")
    received_by_member_id: int
    amount: float = Field(gt=0)
    date: date
    note: str = ""


class MonthlyAdvancePaymentRead(BaseModel):
    id: int
    month: str
    paid_by_member_id: int
    received_by_member_id: int
    amount: float
    applied_amount: float = 0
    credit_amount: float = 0
    status: PaymentStatus = PaymentStatus.pending
    date: date
    note: str = ""
    rejected_reason: str = ""
    confirmed_by_member_id: int | None = None
    confirmed_at: datetime | None = None


class HouseholdPeriodSettingsRead(BaseModel):
    period_mode: str = "calendar"
    start_day: int = 1
    active_month: str
    period_start: date
    period_end: date
    label: str
    active_month_override: str | None = None
    is_manual: bool = False


class HouseholdPeriodSettingsUpdate(BaseModel):
    period_mode: str | None = Field(default=None, max_length=20)
    start_day: int | None = Field(default=None, ge=1, le=28)


class AutomaticDebtCreate(BaseModel):
    month: str = Field(pattern=r"^\d{4}-\d{2}$")


class DebtCancel(BaseModel):
    reason: str = ""


class MonthCloseCreate(BaseModel):
    month: str = Field(pattern=r"^\d{4}-\d{2}$")
    advance_to_next: bool = False


class MonthReopen(BaseModel):
    reason: str = ""


class MonthlyCloseRead(BaseModel):
    id: int
    household_id: int
    month: str
    total_income: float
    total_shared_expenses: float
    summary: MonthSummary
    closed_by_member_id: int
    created_at: datetime


class AppCapabilities(BaseModel):
    app: str
    version: str
    modes: list[str]
    active_mode: str
    advanced_configuration: bool
    notes: list[str]


class AppSyncStatus(BaseModel):
    ok: bool
    app: str
    version: str
    server_time: datetime
    sync_protocol: str
    shared_scope: str
    personal_scope: str
    message: str



class HouseholdTaskCreate(BaseModel):
    title: str = Field(min_length=2, max_length=160)
    description: str = ""
    assigned_member_id: int | None = None
    due_date: date | None = None
    alert_date: date | None = None
    priority: TaskPriority = TaskPriority.normal
    repeat_rule: TaskRepeatRule = TaskRepeatRule.none
    source_type: str = Field(default="manual", max_length=40)
    budget_amount: float = Field(default=0, ge=0)
    product_links: str = ""
    preferred_sources: str = ""
    tracking_frequency: str = Field(default="manual", max_length=20)


class HouseholdTaskUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=2, max_length=160)
    description: str | None = None
    assigned_member_id: int | None = None
    due_date: date | None = None
    alert_date: date | None = None
    priority: TaskPriority | None = None
    status: TaskStatus | None = None
    repeat_rule: TaskRepeatRule | None = None
    source_type: str | None = Field(default=None, max_length=40)
    budget_amount: float | None = Field(default=None, ge=0)
    product_links: str | None = None
    preferred_sources: str | None = None
    tracking_frequency: str | None = Field(default=None, max_length=20)


class HouseholdTaskRead(BaseModel):
    id: int
    household_id: int
    title: str
    description: str
    assigned_member_id: int | None = None
    due_date: date | None = None
    alert_date: date | None = None
    priority: TaskPriority
    status: TaskStatus
    repeat_rule: TaskRepeatRule
    source_type: str
    budget_amount: float = 0
    product_links: str = ""
    preferred_sources: str = ""
    tracking_frequency: str = "manual"
    last_ai_check_at: datetime | None = None
    last_ai_summary: str = ""
    last_ai_evidence: dict = Field(default_factory=dict)
    created_by_member_id: int
    completed_by_member_id: int | None = None
    completed_at: datetime | None = None
    created_at: datetime
    updated_at: datetime
    is_overdue: bool = False
    is_due_soon: bool = False
    alert_level: str = "normal"


class HouseholdTaskSummary(BaseModel):
    pending_count: int
    overdue_count: int
    due_soon_count: int
    high_priority_count: int
    assigned_to_me_count: int


class AiReportCreate(BaseModel):
    month: str = Field(pattern=r"^\d{4}-\d{2}$")
    focus: str = Field(default="general", max_length=120)
    use_api: bool = True


class AiReportRead(BaseModel):
    id: int
    household_id: int
    month: str
    title: str
    content: str
    evidence: dict
    created_by_member_id: int
    created_at: datetime


class AiReportPreview(BaseModel):
    title: str
    content: str
    evidence: dict


class AiWeeklySettingsRead(BaseModel):
    weekly_enabled: bool
    analysis_frequency: str = "weekly"
    frequency_label: str = "Semanal"
    preferred_weekday: int
    preferred_weekday_label: str = "Lunes"
    use_external_context: bool
    use_news_context: bool
    currency: str = "ARS"
    country_context: str = "Argentina"
    last_report_created_at: datetime | None = None
    last_report_title: str | None = None
    next_analysis_at: date | None = None
    next_analysis_hint: str | None = None


class AiWeeklySettingsUpdate(BaseModel):
    weekly_enabled: bool | None = None
    analysis_frequency: str | None = Field(default=None, max_length=20)
    preferred_weekday: int | None = Field(default=None, ge=0, le=6)
    use_external_context: bool | None = None
    use_news_context: bool | None = None
    currency: str | None = Field(default=None, max_length=8)
    country_context: str | None = Field(default=None, max_length=80)


class AiWeeklyReportCreate(BaseModel):
    month: str = Field(pattern=r"^\d{4}-\d{2}$")
    force: bool = False
    use_api: bool = True
    use_external_context: bool | None = None
    use_news_context: bool | None = None


class AiVisibleTip(BaseModel):
    title: str
    body: str
    level: str = "info"
    kind: str = "general"
    valid_until: date | None = None


class AiWeeklyReportRead(BaseModel):
    report: AiReportRead | None = None
    settings: AiWeeklySettingsRead
    tips: list[AiVisibleTip] = []
    generated_now: bool = False
    message: str
