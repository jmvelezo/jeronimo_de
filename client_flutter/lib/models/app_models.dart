class Household {
  final int id;
  final String name;
  final String inviteCode;

  Household({required this.id, required this.name, required this.inviteCode});

  factory Household.fromJson(Map<String, dynamic> json) => Household(
        id: json['id'],
        name: json['name'],
        inviteCode: json['invite_code'],
      );
}

class Member {
  final int id;
  final int householdId;
  final String name;
  final String color;
  final String role;
  final bool isActive;

  Member({
    required this.id,
    required this.householdId,
    required this.name,
    required this.color,
    required this.role,
    required this.isActive,
  });

  factory Member.fromJson(Map<String, dynamic> json) => Member(
        id: json['id'],
        householdId: json['household_id'],
        name: json['name'],
        color: json['color'],
        role: json['role'],
        isActive: json['is_active'],
      );
}

class SessionData {
  final String token;
  final Household household;
  final Member member;

  SessionData({required this.token, required this.household, required this.member});

  factory SessionData.fromJson(Map<String, dynamic> json) => SessionData(
        token: json['access_token'],
        household: Household.fromJson(json['household']),
        member: Member.fromJson(json['member']),
      );
}

enum AppWorkMode { personalLocal, sharedHousehold, hybrid }

class AppModeOption {
  final AppWorkMode mode;
  final String title;
  final String description;
  final bool enabled;

  const AppModeOption({required this.mode, required this.title, required this.description, required this.enabled});
}

class ServerSyncStatus {
  final bool ok;
  final String app;
  final String version;
  final String serverTime;
  final String syncProtocol;
  final String sharedScope;
  final String personalScope;
  final String message;

  ServerSyncStatus({
    required this.ok,
    required this.app,
    required this.version,
    required this.serverTime,
    required this.syncProtocol,
    required this.sharedScope,
    required this.personalScope,
    required this.message,
  });

  factory ServerSyncStatus.fromJson(Map<String, dynamic> json) => ServerSyncStatus(
        ok: json['ok'] == true,
        app: json['app'] ?? 'Servidor',
        version: json['version'] ?? '',
        serverTime: json['server_time'] ?? '',
        syncProtocol: json['sync_protocol'] ?? '',
        sharedScope: json['shared_scope'] ?? '',
        personalScope: json['personal_scope'] ?? '',
        message: json['message'] ?? '',
      );
}

class SyncViewState {
  final bool online;
  final DateTime? lastSuccessfulSync;
  final String serverUrl;
  final String message;

  const SyncViewState({required this.online, this.lastSuccessfulSync, required this.serverUrl, required this.message});
}

class AdvancedConfigState {
  final String serverUrl;
  final AppWorkMode activeMode;
  final bool advancedVisible;

  AdvancedConfigState({required this.serverUrl, required this.activeMode, this.advancedVisible = false});
}

class AppCapabilities {
  final String app;
  final String version;
  final List<String> modes;
  final String activeMode;
  final bool advancedConfiguration;
  final List<String> notes;

  AppCapabilities({
    required this.app,
    required this.version,
    required this.modes,
    required this.activeMode,
    required this.advancedConfiguration,
    required this.notes,
  });

  factory AppCapabilities.fromJson(Map<String, dynamic> json) => AppCapabilities(
        app: json['app'],
        version: json['version'],
        modes: (json['modes'] as List).map((item) => item.toString()).toList(),
        activeMode: json['active_mode'],
        advancedConfiguration: json['advanced_configuration'],
        notes: (json['notes'] as List).map((item) => item.toString()).toList(),
      );
}

class MemberSummary {
  final int memberId;
  final String name;
  final String color;
  final double income;
  final double incomeShare;
  final double shouldPay;
  final double actuallyPaid;
  final double balance;
  final bool participates;

  MemberSummary({
    required this.memberId,
    required this.name,
    required this.color,
    required this.income,
    required this.incomeShare,
    required this.shouldPay,
    required this.actuallyPaid,
    required this.balance,
    required this.participates,
  });

  factory MemberSummary.fromJson(Map<String, dynamic> json) => MemberSummary(
        memberId: json['member_id'],
        name: json['name'],
        color: json['color'],
        income: (json['income'] as num).toDouble(),
        incomeShare: (json['income_share'] as num).toDouble(),
        shouldPay: (json['should_pay'] as num).toDouble(),
        actuallyPaid: (json['actually_paid'] as num).toDouble(),
        balance: (json['balance'] as num).toDouble(),
        participates: json['participates'] ?? true,
      );
}

class MemberParticipationItem {
  final int memberId;
  final String month;
  final bool participates;
  final String? note;

  MemberParticipationItem({required this.memberId, required this.month, required this.participates, this.note});

  factory MemberParticipationItem.fromJson(Map<String, dynamic> json) => MemberParticipationItem(
        memberId: json['member_id'],
        month: json['month'],
        participates: json['participates'],
        note: json['note'],
      );
}

class SettlementSuggestion {
  final int debtorMemberId;
  final int creditorMemberId;
  final double amount;
  final String reason;

  SettlementSuggestion({
    required this.debtorMemberId,
    required this.creditorMemberId,
    required this.amount,
    required this.reason,
  });

  factory SettlementSuggestion.fromJson(Map<String, dynamic> json) => SettlementSuggestion(
        debtorMemberId: json['debtor_member_id'],
        creditorMemberId: json['creditor_member_id'],
        amount: (json['amount'] as num).toDouble(),
        reason: json['reason'],
      );
}

class MonthSummary {
  final String month;
  final double totalIncome;
  final double totalSharedExpenses;
  final List<MemberSummary> members;
  final List<SettlementSuggestion> settlements;
  final String? warning;

  MonthSummary({
    required this.month,
    required this.totalIncome,
    required this.totalSharedExpenses,
    required this.members,
    required this.settlements,
    this.warning,
  });

  factory MonthSummary.fromJson(Map<String, dynamic> json) => MonthSummary(
        month: json['month'],
        totalIncome: (json['total_income'] as num).toDouble(),
        totalSharedExpenses: (json['total_shared_expenses'] as num).toDouble(),
        members: (json['members'] as List).map((item) => MemberSummary.fromJson(item)).toList(),
        settlements: (json['settlements'] as List).map((item) => SettlementSuggestion.fromJson(item)).toList(),
        warning: json['warning'],
      );
}


class IncomeItem {
  final int id;
  final int memberId;
  final String month;
  final double amount;
  final String? note;

  IncomeItem({
    required this.id,
    required this.memberId,
    required this.month,
    required this.amount,
    this.note,
  });

  factory IncomeItem.fromJson(Map<String, dynamic> json) => IncomeItem(
        id: json['id'],
        memberId: json['member_id'],
        month: json['month'],
        amount: (json['amount'] as num).toDouble(),
        note: json['note'],
      );
}

class ExpenseItem {
  final int id;
  final int paidByMemberId;
  final double amount;
  final String category;
  final String description;
  final String date;
  final String month;
  final bool isShared;

  ExpenseItem({
    required this.id,
    required this.paidByMemberId,
    required this.amount,
    required this.category,
    required this.description,
    required this.date,
    required this.month,
    required this.isShared,
  });

  factory ExpenseItem.fromJson(Map<String, dynamic> json) => ExpenseItem(
        id: json['id'],
        paidByMemberId: json['paid_by_member_id'],
        amount: (json['amount'] as num).toDouble(),
        category: json['category'],
        description: json['description'] ?? '',
        date: json['date'],
        month: json['month'],
        isShared: json['is_shared'],
      );
}


class CardImportPreviewItem {
  final String? date;
  final String description;
  final double amount;
  final String currency;
  final String category;
  final double confidence;
  final String rawText;

  CardImportPreviewItem({
    required this.date,
    required this.description,
    required this.amount,
    required this.currency,
    required this.category,
    required this.confidence,
    required this.rawText,
  });

  factory CardImportPreviewItem.fromJson(Map<String, dynamic> json) => CardImportPreviewItem(
        date: json['date'],
        description: json['description'] ?? '',
        amount: (json['amount'] as num).toDouble(),
        currency: json['currency'] ?? 'ARS',
        category: json['category'] ?? 'General',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.5,
        rawText: json['raw_text'] ?? '',
      );
}

class CardImportPreviewResult {
  final List<CardImportPreviewItem> items;
  final List<String> warnings;

  CardImportPreviewResult({required this.items, required this.warnings});

  factory CardImportPreviewResult.fromJson(Map<String, dynamic> json) => CardImportPreviewResult(
        items: ((json['items'] ?? []) as List).map((item) => CardImportPreviewItem.fromJson(item)).toList(),
        warnings: ((json['warnings'] ?? []) as List).map((item) => item.toString()).toList(),
      );
}

class FixedExpenseTemplateItem {
  final int id;
  final String name;
  final double amount;
  final String category;
  final int? defaultPaidByMemberId;
  final String frequency;
  final bool active;
  final String notes;
  final String createdAt;
  final String updatedAt;

  FixedExpenseTemplateItem({
    required this.id,
    required this.name,
    required this.amount,
    required this.category,
    required this.defaultPaidByMemberId,
    required this.frequency,
    required this.active,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FixedExpenseTemplateItem.fromJson(Map<String, dynamic> json) => FixedExpenseTemplateItem(
        id: json['id'],
        name: json['name'] ?? '',
        amount: (json['amount'] as num).toDouble(),
        category: json['category'] ?? 'General',
        defaultPaidByMemberId: json['default_paid_by_member_id'],
        frequency: json['frequency'] ?? 'monthly',
        active: json['active'] == true,
        notes: json['notes'] ?? '',
        createdAt: json['created_at'] ?? '',
        updatedAt: json['updated_at'] ?? '',
      );
}


class DebtItem {
  final int id;
  final int debtorMemberId;
  final int creditorMemberId;
  final String source;
  final String? sourceMonth;
  final double originalAmount;
  final double paidAmount;
  final double pendingAmount;
  final double remainingAmount;
  final String reason;
  final String status;

  DebtItem({
    required this.id,
    required this.debtorMemberId,
    required this.creditorMemberId,
    required this.source,
    required this.sourceMonth,
    required this.originalAmount,
    required this.paidAmount,
    required this.pendingAmount,
    required this.remainingAmount,
    required this.reason,
    required this.status,
  });

  factory DebtItem.fromJson(Map<String, dynamic> json) => DebtItem(
        id: json['id'],
        debtorMemberId: json['debtor_member_id'],
        creditorMemberId: json['creditor_member_id'],
        source: json['source'],
        sourceMonth: json['source_month'],
        originalAmount: (json['original_amount'] as num).toDouble(),
        paidAmount: (json['paid_amount'] as num).toDouble(),
        pendingAmount: ((json['pending_amount'] ?? 0) as num).toDouble(),
        remainingAmount: (json['remaining_amount'] as num).toDouble(),
        reason: json['reason'] ?? '',
        status: json['status'],
      );
}

class DebtPaymentItem {
  final int id;
  final int debtId;
  final int paidByMemberId;
  final int? receivedByMemberId;
  final double amount;
  final double appliedAmount;
  final double creditAmount;
  final String status;
  final String date;
  final String note;
  final String rejectedReason;
  final int? confirmedByMemberId;
  final String? confirmedAt;

  DebtPaymentItem({
    required this.id,
    required this.debtId,
    required this.paidByMemberId,
    required this.receivedByMemberId,
    required this.amount,
    required this.appliedAmount,
    required this.creditAmount,
    required this.status,
    required this.date,
    required this.note,
    required this.rejectedReason,
    required this.confirmedByMemberId,
    required this.confirmedAt,
  });

  factory DebtPaymentItem.fromJson(Map<String, dynamic> json) => DebtPaymentItem(
        id: json['id'],
        debtId: json['debt_id'],
        paidByMemberId: json['paid_by_member_id'],
        receivedByMemberId: json['received_by_member_id'],
        amount: (json['amount'] as num).toDouble(),
        appliedAmount: ((json['applied_amount'] ?? 0) as num).toDouble(),
        creditAmount: ((json['credit_amount'] ?? 0) as num).toDouble(),
        status: json['status'] ?? 'pending',
        date: json['date'],
        note: json['note'] ?? '',
        rejectedReason: json['rejected_reason'] ?? '',
        confirmedByMemberId: json['confirmed_by_member_id'],
        confirmedAt: json['confirmed_at'],
      );
}

class CreditBalanceItem {
  final int id;
  final int ownerMemberId;
  final int counterpartyMemberId;
  final int? sourcePaymentId;
  final double originalAmount;
  final double remainingAmount;
  final String status;
  final String reason;
  final String createdAt;

  CreditBalanceItem({
    required this.id,
    required this.ownerMemberId,
    required this.counterpartyMemberId,
    required this.sourcePaymentId,
    required this.originalAmount,
    required this.remainingAmount,
    required this.status,
    required this.reason,
    required this.createdAt,
  });

  factory CreditBalanceItem.fromJson(Map<String, dynamic> json) => CreditBalanceItem(
        id: json['id'],
        ownerMemberId: json['owner_member_id'],
        counterpartyMemberId: json['counterparty_member_id'],
        sourcePaymentId: json['source_payment_id'],
        originalAmount: (json['original_amount'] as num).toDouble(),
        remainingAmount: (json['remaining_amount'] as num).toDouble(),
        status: json['status'] ?? 'available',
        reason: json['reason'] ?? '',
        createdAt: json['created_at'] ?? '',
      );
}

class MonthlyAdvancePaymentItem {
  final int id;
  final String month;
  final int paidByMemberId;
  final int receivedByMemberId;
  final double amount;
  final double appliedAmount;
  final double creditAmount;
  final String status;
  final String date;
  final String note;
  final String rejectedReason;
  final int? confirmedByMemberId;
  final String? confirmedAt;

  MonthlyAdvancePaymentItem({
    required this.id,
    required this.month,
    required this.paidByMemberId,
    required this.receivedByMemberId,
    required this.amount,
    required this.appliedAmount,
    required this.creditAmount,
    required this.status,
    required this.date,
    required this.note,
    required this.rejectedReason,
    required this.confirmedByMemberId,
    required this.confirmedAt,
  });

  factory MonthlyAdvancePaymentItem.fromJson(Map<String, dynamic> json) => MonthlyAdvancePaymentItem(
        id: json['id'],
        month: json['month'],
        paidByMemberId: json['paid_by_member_id'],
        receivedByMemberId: json['received_by_member_id'],
        amount: (json['amount'] as num).toDouble(),
        appliedAmount: ((json['applied_amount'] ?? 0) as num).toDouble(),
        creditAmount: ((json['credit_amount'] ?? 0) as num).toDouble(),
        status: json['status'] ?? 'pending',
        date: json['date'],
        note: json['note'] ?? '',
        rejectedReason: json['rejected_reason'] ?? '',
        confirmedByMemberId: json['confirmed_by_member_id'],
        confirmedAt: json['confirmed_at'],
      );
}

class HouseholdPeriodSettingsItem {
  final String periodMode;
  final int startDay;
  final String activeMonth;
  final String periodStart;
  final String periodEnd;
  final String label;
  final String? activeMonthOverride;
  final bool isManual;

  HouseholdPeriodSettingsItem({
    required this.periodMode,
    required this.startDay,
    required this.activeMonth,
    required this.periodStart,
    required this.periodEnd,
    required this.label,
    this.activeMonthOverride,
    this.isManual = false,
  });

  bool get isCustom => periodMode == 'custom';

  factory HouseholdPeriodSettingsItem.fromJson(Map<String, dynamic> json) => HouseholdPeriodSettingsItem(
        periodMode: json['period_mode'] ?? 'calendar',
        startDay: json['start_day'] ?? 1,
        activeMonth: json['active_month'] ?? '',
        periodStart: json['period_start'] ?? '',
        periodEnd: json['period_end'] ?? '',
        label: json['label'] ?? '',
        activeMonthOverride: json['active_month_override'],
        isManual: json['is_manual'] ?? false,
      );
}


class MonthlyCloseItem {
  final int id;
  final int householdId;
  final String month;
  final double totalIncome;
  final double totalSharedExpenses;
  final MonthSummary summary;
  final int closedByMemberId;
  final String createdAt;

  MonthlyCloseItem({
    required this.id,
    required this.householdId,
    required this.month,
    required this.totalIncome,
    required this.totalSharedExpenses,
    required this.summary,
    required this.closedByMemberId,
    required this.createdAt,
  });

  factory MonthlyCloseItem.fromJson(Map<String, dynamic> json) => MonthlyCloseItem(
        id: json['id'],
        householdId: json['household_id'],
        month: json['month'],
        totalIncome: (json['total_income'] as num).toDouble(),
        totalSharedExpenses: (json['total_shared_expenses'] as num).toDouble(),
        summary: MonthSummary.fromJson(json['summary']),
        closedByMemberId: json['closed_by_member_id'],
        createdAt: json['created_at'],
      );
}

class HouseholdTaskItem {
  final int id;
  final int householdId;
  final String title;
  final String description;
  final int? assignedMemberId;
  final String? dueDate;
  final String? alertDate;
  final String priority;
  final String status;
  final String repeatRule;
  final String sourceType;
  final double budgetAmount;
  final String productLinks;
  final String preferredSources;
  final String trackingFrequency;
  final String? lastAiCheckAt;
  final String lastAiSummary;
  final Map<String, dynamic> lastAiEvidence;
  final int createdByMemberId;
  final int? completedByMemberId;
  final String? completedAt;
  final String createdAt;
  final String updatedAt;
  final bool isOverdue;
  final bool isDueSoon;
  final String alertLevel;

  HouseholdTaskItem({
    required this.id,
    required this.householdId,
    required this.title,
    required this.description,
    required this.assignedMemberId,
    required this.dueDate,
    required this.alertDate,
    required this.priority,
    required this.status,
    required this.repeatRule,
    required this.sourceType,
    required this.budgetAmount,
    required this.productLinks,
    required this.preferredSources,
    required this.trackingFrequency,
    required this.lastAiCheckAt,
    required this.lastAiSummary,
    required this.lastAiEvidence,
    required this.createdByMemberId,
    required this.completedByMemberId,
    required this.completedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.isOverdue,
    required this.isDueSoon,
    required this.alertLevel,
  });

  factory HouseholdTaskItem.fromJson(Map<String, dynamic> json) => HouseholdTaskItem(
        id: json['id'],
        householdId: json['household_id'],
        title: json['title'] ?? '',
        description: json['description'] ?? '',
        assignedMemberId: json['assigned_member_id'],
        dueDate: json['due_date'],
        alertDate: json['alert_date'],
        priority: json['priority'] ?? 'normal',
        status: json['status'] ?? 'pending',
        repeatRule: json['repeat_rule'] ?? 'none',
        sourceType: json['source_type'] ?? 'manual',
        budgetAmount: ((json['budget_amount'] ?? 0) as num).toDouble(),
        productLinks: json['product_links'] ?? '',
        preferredSources: json['preferred_sources'] ?? '',
        trackingFrequency: json['tracking_frequency'] ?? 'manual',
        lastAiCheckAt: json['last_ai_check_at'],
        lastAiSummary: json['last_ai_summary'] ?? '',
        lastAiEvidence: Map<String, dynamic>.from(json['last_ai_evidence'] ?? {}),
        createdByMemberId: json['created_by_member_id'],
        completedByMemberId: json['completed_by_member_id'],
        completedAt: json['completed_at'],
        createdAt: json['created_at'],
        updatedAt: json['updated_at'],
        isOverdue: json['is_overdue'] == true,
        isDueSoon: json['is_due_soon'] == true,
        alertLevel: json['alert_level'] ?? 'normal',
      );
}

class HouseholdTaskSummary {
  final int pendingCount;
  final int overdueCount;
  final int dueSoonCount;
  final int highPriorityCount;
  final int assignedToMeCount;

  HouseholdTaskSummary({
    required this.pendingCount,
    required this.overdueCount,
    required this.dueSoonCount,
    required this.highPriorityCount,
    required this.assignedToMeCount,
  });

  factory HouseholdTaskSummary.fromJson(Map<String, dynamic> json) => HouseholdTaskSummary(
        pendingCount: json['pending_count'] ?? 0,
        overdueCount: json['overdue_count'] ?? 0,
        dueSoonCount: json['due_soon_count'] ?? 0,
        highPriorityCount: json['high_priority_count'] ?? 0,
        assignedToMeCount: json['assigned_to_me_count'] ?? 0,
      );
}

class AiReportItem {
  final int id;
  final int householdId;
  final String month;
  final String title;
  final String content;
  final Map<String, dynamic> evidence;
  final int createdByMemberId;
  final String createdAt;

  const AiReportItem({
    required this.id,
    required this.householdId,
    required this.month,
    required this.title,
    required this.content,
    required this.evidence,
    required this.createdByMemberId,
    required this.createdAt,
  });

  bool get generatedWithApi => evidence['generated_with_api'] == true;
  String get modelLabel => evidence['model']?.toString() ?? 'IA';

  factory AiReportItem.fromJson(Map<String, dynamic> json) => AiReportItem(
        id: json['id'],
        householdId: json['household_id'],
        month: json['month'],
        title: json['title'] ?? 'Informe IA',
        content: json['content'] ?? '',
        evidence: (json['evidence'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{},
        createdByMemberId: json['created_by_member_id'],
        createdAt: json['created_at'] ?? '',
      );
}

class AiWeeklySettings {
  final bool weeklyEnabled;
  final String analysisFrequency;
  final String frequencyLabel;
  final int preferredWeekday;
  final String preferredWeekdayLabel;
  final bool useExternalContext;
  final bool useNewsContext;
  final String currency;
  final String countryContext;
  final String? lastReportCreatedAt;
  final String? lastReportTitle;
  final String? nextAnalysisAt;
  final String? nextAnalysisHint;

  AiWeeklySettings({
    required this.weeklyEnabled,
    required this.analysisFrequency,
    required this.frequencyLabel,
    required this.preferredWeekday,
    required this.preferredWeekdayLabel,
    required this.useExternalContext,
    required this.useNewsContext,
    required this.currency,
    required this.countryContext,
    this.lastReportCreatedAt,
    this.lastReportTitle,
    this.nextAnalysisAt,
    this.nextAnalysisHint,
  });

  factory AiWeeklySettings.fromJson(Map<String, dynamic> json) => AiWeeklySettings(
        weeklyEnabled: json['weekly_enabled'] == true,
        analysisFrequency: json['analysis_frequency'] ?? 'weekly',
        frequencyLabel: json['frequency_label'] ?? 'Semanal',
        preferredWeekday: json['preferred_weekday'] ?? 0,
        preferredWeekdayLabel: json['preferred_weekday_label'] ?? 'Lunes',
        useExternalContext: json['use_external_context'] != false,
        useNewsContext: json['use_news_context'] != false,
        currency: json['currency'] ?? 'ARS',
        countryContext: json['country_context'] ?? 'Argentina',
        lastReportCreatedAt: json['last_report_created_at'],
        lastReportTitle: json['last_report_title'],
        nextAnalysisAt: json['next_analysis_at'],
        nextAnalysisHint: json['next_analysis_hint'],
      );
}

class AiVisibleTipItem {
  final String title;
  final String body;
  final String level;
  final String kind;
  final String? validUntil;

  AiVisibleTipItem({required this.title, required this.body, required this.level, required this.kind, this.validUntil});

  factory AiVisibleTipItem.fromJson(Map<String, dynamic> json) => AiVisibleTipItem(
        title: json['title'] ?? 'Consejo IA',
        body: json['body'] ?? '',
        level: json['level'] ?? 'info',
        kind: json['kind'] ?? 'general',
        validUntil: json['valid_until'],
      );
}

class AiWeeklyReportResult {
  final AiReportItem? report;
  final AiWeeklySettings settings;
  final List<AiVisibleTipItem> tips;
  final bool generatedNow;
  final String message;

  AiWeeklyReportResult({required this.report, required this.settings, required this.tips, required this.generatedNow, required this.message});

  factory AiWeeklyReportResult.fromJson(Map<String, dynamic> json) => AiWeeklyReportResult(
        report: json['report'] == null ? null : AiReportItem.fromJson((json['report'] as Map).cast<String, dynamic>()),
        settings: AiWeeklySettings.fromJson((json['settings'] as Map).cast<String, dynamic>()),
        tips: ((json['tips'] as List?) ?? []).map((item) => AiVisibleTipItem.fromJson((item as Map).cast<String, dynamic>())).toList(),
        generatedNow: json['generated_now'] == true,
        message: json['message'] ?? '',
      );
}
