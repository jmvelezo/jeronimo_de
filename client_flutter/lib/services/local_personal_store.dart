import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../models/local_personal_models.dart';

class LocalPersonalStore {
  static const _profileKey = 'personal_local_profile_v1';
  static const _accountsKey = 'personal_local_accounts_v1';
  static const _categoriesKey = 'personal_local_categories_v1';
  static const _budgetsKey = 'personal_local_budgets_v1';
  static const _incomesKey = 'personal_local_incomes_v1';
  static const _expensesKey = 'personal_local_expenses_v1';
  static const _debtsKey = 'personal_local_debts_v1';
  static const _tasksKey = 'personal_local_tasks_v1';
  static const _aiReportsKey = 'personal_local_ai_reports_v1';
  static const _apiKeyKey = 'personal_local_ai_api_key_v1';

  Future<PersonalLocalSnapshot> loadSnapshot({String? month}) async {
    final prefs = await SharedPreferences.getInstance();
    final activeMonth = month ?? _monthOf(DateTime.now());
    final profileRaw = prefs.getString(_profileKey);
    final profile = profileRaw == null
        ? const PersonalProfile(name: '')
        : PersonalProfile.fromJson(jsonDecode(profileRaw) as Map<String, dynamic>);
    final loadedCategories = decodeList(prefs.getString(_categoriesKey), PersonalCategory.fromJson);
    final categories = loadedCategories.isEmpty ? defaultPersonalCategories() : loadedCategories;
    return PersonalLocalSnapshot(
      profile: profile,
      accounts: decodeList(prefs.getString(_accountsKey), PersonalAccount.fromJson),
      categories: categories,
      budgets: decodeList(prefs.getString(_budgetsKey), PersonalBudget.fromJson),
      incomes: decodeList(prefs.getString(_incomesKey), PersonalIncome.fromJson),
      expenses: decodeList(prefs.getString(_expensesKey), PersonalExpense.fromJson),
      debts: decodeList(prefs.getString(_debtsKey), PersonalDebt.fromJson),
      tasks: decodeList(prefs.getString(_tasksKey), PersonalTask.fromJson),
      aiReports: decodeList(prefs.getString(_aiReportsKey), PersonalAiReport.fromJson),
      month: activeMonth,
    );
  }

  Future<void> saveProfile(PersonalProfile profile, {String? apiKey}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileKey, jsonEncode(profile.toJson()));
    if (apiKey != null) {
      await prefs.setString(_apiKeyKey, apiKey);
    }
  }

  Future<String?> loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_apiKeyKey);
  }

  Future<PersonalAccount> createAccount({required String name, required String type, required double initialBalance}) async {
    final snapshot = await loadSnapshot();
    final account = PersonalAccount(
      id: _id(),
      name: name.trim().isEmpty ? 'Cuenta personal' : name.trim(),
      type: type.trim().isEmpty ? 'general' : type.trim(),
      initialBalance: initialBalance,
      isActive: true,
      createdAt: DateTime.now().toIso8601String(),
    );
    await _saveAccounts([...snapshot.accounts, account]);
    return account;
  }

  Future<void> updateAccount(PersonalAccount account) async {
    final snapshot = await loadSnapshot();
    await _saveAccounts(snapshot.accounts.map((item) => item.id == account.id ? account : item).toList());
  }

  Future<void> deactivateAccount(String id) async {
    final snapshot = await loadSnapshot();
    await _saveAccounts(snapshot.accounts.map((item) => item.id == id ? item.copyWith(isActive: false) : item).toList());
  }

  Future<void> _saveAccounts(List<PersonalAccount> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accountsKey, jsonEncode(items.map((item) => item.toJson()).toList()));
  }

  Future<PersonalCategory> createCategory({required String name, String type = 'expense'}) async {
    final snapshot = await loadSnapshot();
    final category = PersonalCategory(
      id: _slug(name).isEmpty ? _id() : _slug(name),
      name: name.trim().isEmpty ? 'Nueva categoría' : name.trim(),
      type: type,
      isActive: true,
      isSystem: false,
    );
    final exists = snapshot.categories.any((item) => item.id == category.id || item.name.toLowerCase() == category.name.toLowerCase());
    if (exists) return category;
    await _saveCategories([...snapshot.categories, category]);
    return category;
  }

  Future<void> toggleCategory(String id, bool active) async {
    final snapshot = await loadSnapshot();
    await _saveCategories(snapshot.categories.map((item) => item.id == id ? item.copyWith(isActive: active) : item).toList());
  }

  Future<void> _saveCategories(List<PersonalCategory> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_categoriesKey, jsonEncode(items.map((item) => item.toJson()).toList()));
  }

  Future<PersonalBudget> upsertBudget({required String categoryId, required String month, required double amount, String note = ''}) async {
    final snapshot = await loadSnapshot(month: month);
    PersonalBudget? existing;
    for (final item in snapshot.budgets) {
      if (item.month == month && item.categoryId == categoryId) existing = item;
    }
    final next = existing == null
        ? PersonalBudget(id: _id(), categoryId: categoryId, month: month, amount: amount, note: note)
        : existing.copyWith(amount: amount, note: note);
    final items = existing == null
        ? [...snapshot.budgets, next]
        : snapshot.budgets.map((item) => item.id == existing!.id ? next : item).toList();
    await _saveBudgets(items);
    return next;
  }

  Future<void> deleteBudget(String id) async {
    final snapshot = await loadSnapshot();
    await _saveBudgets(snapshot.budgets.where((item) => item.id != id).toList());
  }

  Future<void> _saveBudgets(List<PersonalBudget> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_budgetsKey, jsonEncode(items.map((item) => item.toJson()).toList()));
  }

  Future<PersonalIncome> createIncome({required String accountId, required double amount, required String source, String note = '', DateTime? date}) async {
    final snapshot = await loadSnapshot();
    final usedDate = date ?? DateTime.now();
    final item = PersonalIncome(
      id: _id(),
      accountId: accountId,
      amount: amount,
      source: source.trim().isEmpty ? 'Ingreso personal' : source.trim(),
      note: note.trim(),
      date: _dateOnly(usedDate),
      month: _monthOf(usedDate),
    );
    await _saveIncomes([...snapshot.incomes, item]);
    return item;
  }

  Future<void> deleteIncome(String id) async {
    final snapshot = await loadSnapshot();
    await _saveIncomes(snapshot.incomes.where((item) => item.id != id).toList());
  }

  Future<void> _saveIncomes(List<PersonalIncome> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_incomesKey, jsonEncode(items.map((item) => item.toJson()).toList()));
  }

  Future<PersonalExpense> createExpense({
    required String accountId,
    required double amount,
    required PersonalCategory category,
    String description = '',
    DateTime? date,
    String source = '',
    String sourceMonth = '',
    String sourceType = '',
  }) async {
    final snapshot = await loadSnapshot();
    final usedDate = date ?? DateTime.now();
    final item = PersonalExpense(
      id: _id(),
      accountId: accountId,
      amount: amount,
      categoryId: category.id,
      category: category.name,
      description: description.trim(),
      date: _dateOnly(usedDate),
      month: _monthOf(usedDate),
      source: source.trim(),
      sourceMonth: sourceMonth.trim(),
      sourceType: sourceType.trim(),
    );
    await _saveExpenses([...snapshot.expenses, item]);
    return item;
  }

  Future<void> deleteExpense(String id) async {
    final snapshot = await loadSnapshot();
    await _saveExpenses(snapshot.expenses.where((item) => item.id != id).toList());
  }

  Future<void> _saveExpenses(List<PersonalExpense> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_expensesKey, jsonEncode(items.map((item) => item.toJson()).toList()));
  }

  Future<PersonalDebt> createDebt({required String title, required String counterparty, required String direction, required double amount, String note = '', String? dueDate}) async {
    final snapshot = await loadSnapshot();
    final item = PersonalDebt(
      id: _id(),
      title: title.trim().isEmpty ? 'Deuda personal' : title.trim(),
      counterparty: counterparty.trim(),
      direction: direction,
      originalAmount: amount,
      paidAmount: 0,
      status: 'active',
      createdAt: DateTime.now().toIso8601String(),
      dueDate: dueDate?.trim().isEmpty == true ? null : dueDate,
      note: note.trim(),
    );
    await _saveDebts([...snapshot.debts, item]);
    return item;
  }

  Future<void> registerDebtPayment({required String debtId, required double amount}) async {
    final snapshot = await loadSnapshot();
    final updated = snapshot.debts.map((item) {
      if (item.id != debtId) return item;
      final newPaid = (item.paidAmount + amount).clamp(0, item.originalAmount).toDouble();
      return item.copyWith(
        paidAmount: newPaid,
        status: newPaid >= item.originalAmount ? 'paid' : item.status,
      );
    }).toList();
    await _saveDebts(updated);
  }

  Future<void> cancelDebt(String debtId) async {
    final snapshot = await loadSnapshot();
    await _saveDebts(snapshot.debts.map((item) => item.id == debtId ? item.copyWith(status: 'cancelled') : item).toList());
  }

  Future<void> _saveDebts(List<PersonalDebt> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_debtsKey, jsonEncode(items.map((item) => item.toJson()).toList()));
  }


  Future<PersonalAiReport> generatePersonalAiReport({String focus = 'general'}) async {
    final snapshot = await loadSnapshot();
    final categoryStatuses = snapshot.budgetStatuses.take(5).map((item) => {
          'category': item.category.name,
          'spent': item.spent,
          'budget': item.limit,
          'exceeded': item.exceeded,
        }).toList();
    final evidence = <String, dynamic>{
      'scope': 'personal_local',
      'month': snapshot.month,
      'focus': focus,
      'generated_with_api': false,
      'monthly_income': snapshot.monthlyIncome,
      'monthly_expense': snapshot.monthlyExpense,
      'monthly_balance': snapshot.monthlyBalance,
      'estimated_available': snapshot.estimatedAvailable,
      'pending_i_owe': snapshot.pendingIowe,
      'pending_owes_me': snapshot.pendingOwesMe,
      'overdue_tasks': snapshot.overdueTasksCount,
      'due_soon_tasks': snapshot.dueSoonTasksCount,
      'categories': categoryStatuses,
    };
    final biggest = categoryStatuses.isEmpty ? null : categoryStatuses.first;
    final lines = <String>[
      'Análisis personal de ${snapshot.month}',
      '',
      'Ingresos registrados: ${snapshot.monthlyIncome.toStringAsFixed(0)}.',
      'Gastos registrados: ${snapshot.monthlyExpense.toStringAsFixed(0)}.',
      'Balance del mes: ${snapshot.monthlyBalance.toStringAsFixed(0)}.',
    ];
    if (biggest != null) {
      lines.add("La categoría con mayor movimiento es ${biggest['category']}, con ${((biggest['spent'] as num?) ?? 0).toDouble().toStringAsFixed(0)}.");
    }
    if (snapshot.pendingIowe > 0) {
      lines.add('Tenés deudas personales pendientes por ${snapshot.pendingIowe.toStringAsFixed(0)}. Conviene priorizar abonos antes de asumir nuevos gastos flexibles.');
    }
    if (snapshot.overdueTasksCount > 0 || snapshot.dueSoonTasksCount > 0) {
      lines.add('Hay ${snapshot.overdueTasksCount} tarea(s) vencida(s) y ${snapshot.dueSoonTasksCount} próxima(s). Revisalas para evitar intereses, recargos o compras apuradas.');
    }
    lines.add('');
    lines.add('Consejos:');
    lines.add('1. Separá gastos fijos de gastos variables antes de decidir ahorro.');
    lines.add('2. Revisá categorías con presupuesto superado o sin presupuesto.');
    lines.add('3. Si el balance del mes es positivo, reservá primero una parte para ahorro o deuda antes de gastar el excedente.');
    if (snapshot.monthlyBalance < 0) {
      lines.add('4. Alerta: el mes está en negativo. Conviene reducir compras no esenciales y revisar deudas de corto plazo.');
    } else if (snapshot.profile.monthlySavingGoal > 0 && snapshot.monthlyBalance < snapshot.profile.monthlySavingGoal) {
      lines.add('4. Estás por debajo de tu meta de ahorro. El faltante aproximado es ${snapshot.savingsGoalGap.toStringAsFixed(0)}.');
    }
    final apiKey = await loadApiKey();
    final apiContent = snapshot.hasPrivateAiReady && apiKey != null && apiKey.trim().isNotEmpty
        ? await _callPersonalAiApi(apiKey.trim(), evidence)
        : null;
    evidence['generated_with_api'] = apiContent != null;
    evidence['model_label'] = apiContent != null ? 'gpt-4o-mini' : 'consejo-local';
    final report = PersonalAiReport(
      id: _id(),
      month: snapshot.month,
      title: 'Informe personal · ${snapshot.month}',
      content: apiContent ?? lines.join('\n'),
      createdAt: DateTime.now().toIso8601String(),
      generatedWithApi: apiContent != null,
      modelLabel: apiContent != null ? 'gpt-4o-mini' : 'consejo-local',
      evidence: evidence,
    );
    final updated = [report, ...snapshot.aiReports];
    await _saveAiReports(updated);
    return report;
  }

  Future<String?> _callPersonalAiApi(String apiKey, Map<String, dynamic> evidence) async {
    final payload = {
      'model': 'gpt-4o-mini',
      'messages': [
        {
          'role': 'system',
          'content': 'Sos un asistente de finanzas personales. Analizá solo datos locales privados. No inventes movimientos. Da consejos claros, prudentes y accionables en español rioplatense.',
        },
        {'role': 'user', 'content': jsonEncode(evidence)},
      ],
      'temperature': 0.25,
    };
    try {
      final response = await http
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: {'Authorization': 'Bearer $apiKey', 'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 35));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) return null;
      final first = choices.first;
      if (first is! Map) return null;
      final message = first['message'];
      if (message is! Map) return null;
      return message['content']?.toString().trim();
    } catch (_) {
      return null;
    }
  }


  Future<void> _saveAiReports(List<PersonalAiReport> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_aiReportsKey, jsonEncode(items.map((item) => item.toJson()).toList()));
  }


  Future<PersonalTask> createTask({
    required String title,
    String description = '',
    String? dueDate,
    String? alertDate,
    String priority = 'normal',
    String repeatRule = 'none',
  }) async {
    final snapshot = await loadSnapshot();
    final task = PersonalTask(
      id: _id(),
      title: title.trim().isEmpty ? 'Tarea personal' : title.trim(),
      description: description.trim(),
      dueDate: dueDate?.trim().isEmpty == true ? null : dueDate,
      alertDate: alertDate?.trim().isEmpty == true ? null : alertDate,
      priority: priority,
      repeatRule: repeatRule,
      status: 'pending',
      createdAt: DateTime.now().toIso8601String(),
    );
    await _saveTasks([...snapshot.tasks, task]);
    return task;
  }

  Future<void> completeTask(String taskId) async {
    final snapshot = await loadSnapshot();
    final updated = <PersonalTask>[];
    for (final item in snapshot.tasks) {
      if (item.id != taskId) {
        updated.add(item);
        continue;
      }
      updated.add(item.copyWith(status: 'done', completedAt: DateTime.now().toIso8601String()));
      if (item.repeatRule == 'monthly' && item.dueDate != null) {
        updated.add(PersonalTask(
          id: _id(),
          title: item.title,
          description: item.description,
          dueDate: _addMonth(item.dueDate!),
          alertDate: item.alertDate == null ? null : _addMonth(item.alertDate!),
          priority: item.priority,
          status: 'pending',
          repeatRule: item.repeatRule,
          createdAt: DateTime.now().toIso8601String(),
        ));
      }
    }
    await _saveTasks(updated);
  }

  Future<void> cancelTask(String taskId) async {
    final snapshot = await loadSnapshot();
    await _saveTasks(snapshot.tasks.map((item) => item.id == taskId ? item.copyWith(status: 'cancelled') : item).toList());
  }

  Future<void> _saveTasks(List<PersonalTask> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tasksKey, jsonEncode(items.map((item) => item.toJson()).toList()));
  }

  String _addMonth(String isoDate) {
    final parsed = DateTime.tryParse(isoDate);
    if (parsed == null) return isoDate;
    final year = parsed.month == 12 ? parsed.year + 1 : parsed.year;
    final month = parsed.month == 12 ? 1 : parsed.month + 1;
    var day = parsed.day;
    while (day > 27) {
      try {
        final value = DateTime(year, month, day);
        return _dateOnly(value);
      } catch (_) {
        day -= 1;
      }
    }
    return _dateOnly(DateTime(year, month, day));
  }

  String _id() => DateTime.now().microsecondsSinceEpoch.toString();
  String _monthOf(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';
  String _dateOnly(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _slug(String raw) {
    return raw
        .trim()
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }
}
