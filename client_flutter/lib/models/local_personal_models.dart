import 'dart:convert';

class PersonalProfile {
  final String name;
  final String currencySymbol;
  final double monthlySavingGoal;
  final bool localAiEnabled;
  final String aiProviderLabel;
  final bool hasApiKey;

  const PersonalProfile({
    required this.name,
    this.currencySymbol = r'$ ',
    this.monthlySavingGoal = 0,
    this.localAiEnabled = false,
    this.aiProviderLabel = 'API IA personal',
    this.hasApiKey = false,
  });

  bool get isConfigured => name.trim().isNotEmpty;

  PersonalProfile copyWith({
    String? name,
    String? currencySymbol,
    double? monthlySavingGoal,
    bool? localAiEnabled,
    String? aiProviderLabel,
    bool? hasApiKey,
  }) {
    return PersonalProfile(
      name: name ?? this.name,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      monthlySavingGoal: monthlySavingGoal ?? this.monthlySavingGoal,
      localAiEnabled: localAiEnabled ?? this.localAiEnabled,
      aiProviderLabel: aiProviderLabel ?? this.aiProviderLabel,
      hasApiKey: hasApiKey ?? this.hasApiKey,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'currency_symbol': currencySymbol,
        'monthly_saving_goal': monthlySavingGoal,
        'local_ai_enabled': localAiEnabled,
        'ai_provider_label': aiProviderLabel,
        'has_api_key': hasApiKey,
      };

  factory PersonalProfile.fromJson(Map<String, dynamic> json) => PersonalProfile(
        name: json['name']?.toString() ?? '',
        currencySymbol: json['currency_symbol']?.toString() ?? r'$ ',
        monthlySavingGoal: (json['monthly_saving_goal'] as num?)?.toDouble() ?? 0,
        localAiEnabled: json['local_ai_enabled'] == true,
        aiProviderLabel: json['ai_provider_label']?.toString() ?? 'API IA personal',
        hasApiKey: json['has_api_key'] == true,
      );
}

class PersonalAccount {
  final String id;
  final String name;
  final String type;
  final double initialBalance;
  final bool isActive;
  final String createdAt;

  const PersonalAccount({
    required this.id,
    required this.name,
    required this.type,
    required this.initialBalance,
    required this.isActive,
    required this.createdAt,
  });

  PersonalAccount copyWith({String? name, String? type, double? initialBalance, bool? isActive}) {
    return PersonalAccount(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      initialBalance: initialBalance ?? this.initialBalance,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'initial_balance': initialBalance,
        'is_active': isActive,
        'created_at': createdAt,
      };

  factory PersonalAccount.fromJson(Map<String, dynamic> json) => PersonalAccount(
        id: json['id'].toString(),
        name: json['name']?.toString() ?? 'Cuenta',
        type: json['type']?.toString() ?? 'general',
        initialBalance: (json['initial_balance'] as num?)?.toDouble() ?? 0,
        isActive: json['is_active'] != false,
        createdAt: json['created_at']?.toString() ?? DateTime.now().toIso8601String(),
      );
}

class PersonalCategory {
  final String id;
  final String name;
  final String type;
  final bool isActive;
  final bool isSystem;

  const PersonalCategory({
    required this.id,
    required this.name,
    required this.type,
    this.isActive = true,
    this.isSystem = false,
  });

  PersonalCategory copyWith({String? name, String? type, bool? isActive}) {
    return PersonalCategory(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      isActive: isActive ?? this.isActive,
      isSystem: isSystem,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'is_active': isActive,
        'is_system': isSystem,
      };

  factory PersonalCategory.fromJson(Map<String, dynamic> json) => PersonalCategory(
        id: json['id'].toString(),
        name: json['name']?.toString() ?? 'Otros',
        type: json['type']?.toString() ?? 'expense',
        isActive: json['is_active'] != false,
        isSystem: json['is_system'] == true,
      );
}

class PersonalBudget {
  final String id;
  final String categoryId;
  final String month;
  final double amount;
  final String note;

  const PersonalBudget({
    required this.id,
    required this.categoryId,
    required this.month,
    required this.amount,
    this.note = '',
  });

  PersonalBudget copyWith({double? amount, String? note}) {
    return PersonalBudget(
      id: id,
      categoryId: categoryId,
      month: month,
      amount: amount ?? this.amount,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'category_id': categoryId,
        'month': month,
        'amount': amount,
        'note': note,
      };

  factory PersonalBudget.fromJson(Map<String, dynamic> json) => PersonalBudget(
        id: json['id'].toString(),
        categoryId: json['category_id']?.toString() ?? '',
        month: json['month']?.toString() ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        note: json['note']?.toString() ?? '',
      );
}

class PersonalIncome {
  final String id;
  final String accountId;
  final double amount;
  final String source;
  final String note;
  final String date;
  final String month;

  const PersonalIncome({
    required this.id,
    required this.accountId,
    required this.amount,
    required this.source,
    required this.note,
    required this.date,
    required this.month,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'account_id': accountId,
        'amount': amount,
        'source': source,
        'note': note,
        'date': date,
        'month': month,
      };

  factory PersonalIncome.fromJson(Map<String, dynamic> json) => PersonalIncome(
        id: json['id'].toString(),
        accountId: json['account_id']?.toString() ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        source: json['source']?.toString() ?? 'Ingreso',
        note: json['note']?.toString() ?? '',
        date: json['date']?.toString() ?? '',
        month: json['month']?.toString() ?? '',
      );
}

class PersonalExpense {
  final String id;
  final String accountId;
  final double amount;
  final String categoryId;
  final String category;
  final String description;
  final String date;
  final String month;
  final String source;
  final String sourceMonth;
  final String sourceType;

  const PersonalExpense({
    required this.id,
    required this.accountId,
    required this.amount,
    required this.categoryId,
    required this.category,
    required this.description,
    required this.date,
    required this.month,
    this.source = '',
    this.sourceMonth = '',
    this.sourceType = '',
  });

  bool get isFromHousehold => source == 'household';

  Map<String, dynamic> toJson() => {
        'id': id,
        'account_id': accountId,
        'amount': amount,
        'category_id': categoryId,
        'category': category,
        'description': description,
        'date': date,
        'month': month,
        'source': source,
        'source_month': sourceMonth,
        'source_type': sourceType,
      };

  factory PersonalExpense.fromJson(Map<String, dynamic> json) {
    final legacyCategory = json['category']?.toString() ?? 'Otros';
    return PersonalExpense(
      id: json['id'].toString(),
      accountId: json['account_id']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      categoryId: json['category_id']?.toString() ?? legacyCategory.toLowerCase(),
      category: legacyCategory,
      description: json['description']?.toString() ?? '',
      date: json['date']?.toString() ?? '',
      month: json['month']?.toString() ?? '',
      source: json['source']?.toString() ?? '',
      sourceMonth: json['source_month']?.toString() ?? '',
      sourceType: json['source_type']?.toString() ?? '',
    );
  }
}

class PersonalDebt {
  final String id;
  final String title;
  final String counterparty;
  final String direction;
  final double originalAmount;
  final double paidAmount;
  final String status;
  final String createdAt;
  final String? dueDate;
  final String note;

  const PersonalDebt({
    required this.id,
    required this.title,
    required this.counterparty,
    required this.direction,
    required this.originalAmount,
    required this.paidAmount,
    required this.status,
    required this.createdAt,
    this.dueDate,
    required this.note,
  });

  double get remainingAmount => (originalAmount - paidAmount).clamp(0, double.infinity).toDouble();

  PersonalDebt copyWith({double? paidAmount, String? status, String? dueDate, String? note}) {
    return PersonalDebt(
      id: id,
      title: title,
      counterparty: counterparty,
      direction: direction,
      originalAmount: originalAmount,
      paidAmount: paidAmount ?? this.paidAmount,
      status: status ?? this.status,
      createdAt: createdAt,
      dueDate: dueDate ?? this.dueDate,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'counterparty': counterparty,
        'direction': direction,
        'original_amount': originalAmount,
        'paid_amount': paidAmount,
        'status': status,
        'created_at': createdAt,
        'due_date': dueDate,
        'note': note,
      };

  factory PersonalDebt.fromJson(Map<String, dynamic> json) => PersonalDebt(
        id: json['id'].toString(),
        title: json['title']?.toString() ?? 'Deuda',
        counterparty: json['counterparty']?.toString() ?? '',
        direction: json['direction']?.toString() ?? 'i_owe',
        originalAmount: (json['original_amount'] as num?)?.toDouble() ?? 0,
        paidAmount: (json['paid_amount'] as num?)?.toDouble() ?? 0,
        status: json['status']?.toString() ?? 'active',
        createdAt: json['created_at']?.toString() ?? DateTime.now().toIso8601String(),
        dueDate: json['due_date']?.toString(),
        note: json['note']?.toString() ?? '',
      );
}


class PersonalTask {
  final String id;
  final String title;
  final String description;
  final String? dueDate;
  final String? alertDate;
  final String priority;
  final String status;
  final String repeatRule;
  final String createdAt;
  final String? completedAt;

  const PersonalTask({
    required this.id,
    required this.title,
    required this.description,
    this.dueDate,
    this.alertDate,
    this.priority = 'normal',
    this.status = 'pending',
    this.repeatRule = 'none',
    required this.createdAt,
    this.completedAt,
  });

  bool get isPending => status == 'pending';
  bool get isOverdue {
    if (!isPending || dueDate == null || dueDate!.isEmpty) return false;
    final due = DateTime.tryParse(dueDate!);
    if (due == null) return false;
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    return due.isBefore(day);
  }

  bool get isDueSoon {
    if (!isPending || dueDate == null || dueDate!.isEmpty) return false;
    final due = DateTime.tryParse(dueDate!);
    if (due == null) return false;
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    final diff = due.difference(day).inDays;
    return diff >= 0 && diff <= 3;
  }

  PersonalTask copyWith({String? status, String? completedAt}) {
    return PersonalTask(
      id: id,
      title: title,
      description: description,
      dueDate: dueDate,
      alertDate: alertDate,
      priority: priority,
      status: status ?? this.status,
      repeatRule: repeatRule,
      createdAt: createdAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'due_date': dueDate,
        'alert_date': alertDate,
        'priority': priority,
        'status': status,
        'repeat_rule': repeatRule,
        'created_at': createdAt,
        'completed_at': completedAt,
      };

  factory PersonalTask.fromJson(Map<String, dynamic> json) => PersonalTask(
        id: json['id'].toString(),
        title: json['title']?.toString() ?? 'Tarea',
        description: json['description']?.toString() ?? '',
        dueDate: json['due_date']?.toString(),
        alertDate: json['alert_date']?.toString(),
        priority: json['priority']?.toString() ?? 'normal',
        status: json['status']?.toString() ?? 'pending',
        repeatRule: json['repeat_rule']?.toString() ?? 'none',
        createdAt: json['created_at']?.toString() ?? DateTime.now().toIso8601String(),
        completedAt: json['completed_at']?.toString(),
      );
}


class PersonalAiReport {
  final String id;
  final String month;
  final String title;
  final String content;
  final String createdAt;
  final bool generatedWithApi;
  final String modelLabel;
  final Map<String, dynamic> evidence;

  const PersonalAiReport({
    required this.id,
    required this.month,
    required this.title,
    required this.content,
    required this.createdAt,
    this.generatedWithApi = false,
    this.modelLabel = 'consejo-local',
    this.evidence = const {},
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'month': month,
        'title': title,
        'content': content,
        'created_at': createdAt,
        'generated_with_api': generatedWithApi,
        'model_label': modelLabel,
        'evidence': evidence,
      };

  factory PersonalAiReport.fromJson(Map<String, dynamic> json) => PersonalAiReport(
        id: json['id'].toString(),
        month: json['month']?.toString() ?? '',
        title: json['title']?.toString() ?? 'Informe personal',
        content: json['content']?.toString() ?? '',
        createdAt: json['created_at']?.toString() ?? DateTime.now().toIso8601String(),
        generatedWithApi: json['generated_with_api'] == true,
        modelLabel: json['model_label']?.toString() ?? 'consejo-local',
        evidence: (json['evidence'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
}

class BudgetStatus {
  final PersonalCategory category;
  final PersonalBudget? budget;
  final double spent;

  const BudgetStatus({required this.category, required this.budget, required this.spent});

  double get limit => budget?.amount ?? 0;
  double get remaining => limit - spent;
  double get progress => limit <= 0 ? 0 : (spent / limit).clamp(0, 1).toDouble();
  bool get hasBudget => limit > 0;
  bool get exceeded => hasBudget && spent > limit;
}

class PersonalLocalSnapshot {
  final PersonalProfile profile;
  final List<PersonalAccount> accounts;
  final List<PersonalCategory> categories;
  final List<PersonalBudget> budgets;
  final List<PersonalIncome> incomes;
  final List<PersonalExpense> expenses;
  final List<PersonalDebt> debts;
  final List<PersonalTask> tasks;
  final List<PersonalAiReport> aiReports;
  final String month;

  const PersonalLocalSnapshot({
    required this.profile,
    required this.accounts,
    required this.categories,
    required this.budgets,
    required this.incomes,
    required this.expenses,
    required this.debts,
    required this.tasks,
    required this.aiReports,
    required this.month,
  });

  List<PersonalAccount> get activeAccounts => accounts.where((item) => item.isActive).toList();
  List<PersonalCategory> get activeExpenseCategories => categories.where((item) => item.isActive && item.type == 'expense').toList();
  List<PersonalDebt> get activeDebts => debts.where((item) => item.status == 'active').toList();
  List<PersonalTask> get pendingTasks => tasks.where((item) => item.status == 'pending').toList();
  int get overdueTasksCount => pendingTasks.where((item) => item.isOverdue).length;
  int get dueSoonTasksCount => pendingTasks.where((item) => item.isDueSoon).length;
  List<PersonalAiReport> get reportsForMonth => aiReports.where((item) => item.month == month).toList();
  PersonalAiReport? get latestAiReport => reportsForMonth.isEmpty ? null : reportsForMonth.first;

  double get monthlyIncome => incomes.where((item) => item.month == month).fold(0.0, (sum, item) => sum + item.amount);
  double get monthlyExpense => expenses.where((item) => item.month == month).fold(0.0, (sum, item) => sum + item.amount);
  double get monthlyBalance => monthlyIncome - monthlyExpense;
  double get pendingIowe => activeDebts.where((item) => item.direction == 'i_owe').fold(0.0, (sum, item) => sum + item.remainingAmount);
  double get pendingOwesMe => activeDebts.where((item) => item.direction == 'owes_me').fold(0.0, (sum, item) => sum + item.remainingAmount);
  double get estimatedAvailable => accounts.fold(0.0, (sum, item) => sum + balanceForAccount(item.id)) - pendingIowe;
  double get savingsGoalGap => (profile.monthlySavingGoal - monthlyBalance).clamp(0, double.infinity).toDouble();
  bool get hasPrivateAiReady => profile.localAiEnabled && profile.hasApiKey;

  double balanceForAccount(String accountId) {
    final account = accounts.firstWhere(
      (item) => item.id == accountId,
      orElse: () => PersonalAccount(id: accountId, name: 'Cuenta', type: 'general', initialBalance: 0, isActive: true, createdAt: ''),
    );
    final income = incomes.where((item) => item.accountId == accountId).fold(0.0, (sum, item) => sum + item.amount);
    final expense = expenses.where((item) => item.accountId == accountId).fold(0.0, (sum, item) => sum + item.amount);
    return account.initialBalance + income - expense;
  }

  String categoryName(String categoryId, {String fallback = 'Otros'}) {
    for (final category in categories) {
      if (category.id == categoryId || category.name.toLowerCase() == categoryId.toLowerCase()) return category.name;
    }
    return fallback;
  }

  double spentByCategory(String categoryId) {
    return expenses.where((item) => item.month == month && (item.categoryId == categoryId || item.category.toLowerCase() == categoryId.toLowerCase())).fold(0.0, (sum, item) => sum + item.amount);
  }

  PersonalBudget? budgetFor(String categoryId) {
    for (final item in budgets) {
      if (item.month == month && item.categoryId == categoryId) return item;
    }
    return null;
  }

  List<BudgetStatus> get budgetStatuses {
    final list = activeExpenseCategories.map((category) {
      return BudgetStatus(category: category, budget: budgetFor(category.id), spent: spentByCategory(category.id));
    }).toList();
    list.sort((a, b) => b.spent.compareTo(a.spent));
    return list;
  }

  double get totalBudget => budgetStatuses.fold(0.0, (sum, item) => sum + item.limit);
  double get budgetRemaining => totalBudget - monthlyExpense;
}

List<T> decodeList<T>(String? raw, T Function(Map<String, dynamic>) fromJson) {
  if (raw == null || raw.trim().isEmpty) return [];
  final decoded = jsonDecode(raw) as List;
  return decoded.map((item) => fromJson(item as Map<String, dynamic>)).toList();
}

String encodeList(List<Object> items, Map<String, dynamic> Function(Object item) toJson) {
  return jsonEncode(items.map(toJson).toList());
}

List<PersonalCategory> defaultPersonalCategories() => const [
      PersonalCategory(id: 'comida', name: 'Comida', type: 'expense', isSystem: true),
      PersonalCategory(id: 'transporte', name: 'Transporte', type: 'expense', isSystem: true),
      PersonalCategory(id: 'salud', name: 'Salud', type: 'expense', isSystem: true),
      PersonalCategory(id: 'educacion', name: 'Educación', type: 'expense', isSystem: true),
      PersonalCategory(id: 'salidas', name: 'Salidas', type: 'expense', isSystem: true),
      PersonalCategory(id: 'suscripciones', name: 'Suscripciones', type: 'expense', isSystem: true),
      PersonalCategory(id: 'hogar_personal', name: 'Hogar personal', type: 'expense', isSystem: true),
      PersonalCategory(id: 'otros', name: 'Otros', type: 'expense', isSystem: true),
    ];
