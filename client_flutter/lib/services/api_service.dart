import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_models.dart';
import 'friendly_messages.dart';

class LastHomeSession {
  final String serverUrl;
  final int householdId;
  final String householdName;
  final String inviteCode;
  final String memberName;

  const LastHomeSession({
    required this.serverUrl,
    required this.householdId,
    required this.householdName,
    required this.inviteCode,
    required this.memberName,
  });
}

class ApiService {
  String baseUrl;
  String? token;

  ApiService({required this.baseUrl, this.token});

  Future<void> saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', baseUrl);
    if (token != null) await prefs.setString('token', token!);
  }

  Future<void> saveLastHomeSession(SessionData session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_server_url', baseUrl);
    await prefs.setInt('last_household_id', session.household.id);
    await prefs.setString('last_household_name', session.household.name);
    await prefs.setString('last_household_code', session.household.inviteCode);
    await prefs.setString('last_member_name', session.member.name);
  }

  static Future<LastHomeSession?> loadLastHomeSession() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('last_household_code');
    final name = prefs.getString('last_household_name');
    final member = prefs.getString('last_member_name');
    if (code == null || code.trim().isEmpty || name == null || member == null) return null;
    return LastHomeSession(
      serverUrl: prefs.getString('last_server_url') ?? prefs.getString('server_url') ?? 'http://127.0.0.1:8000',
      householdId: prefs.getInt('last_household_id') ?? 0,
      householdName: name,
      inviteCode: code,
      memberName: member,
    );
  }

  static Future<void> clearLastHomeSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_household_id');
    await prefs.remove('last_household_name');
    await prefs.remove('last_household_code');
    await prefs.remove('last_member_name');
    await prefs.remove('last_server_url');
  }

  static Future<ApiService> load() async {
    final prefs = await SharedPreferences.getInstance();
    return ApiService(
      baseUrl: prefs.getString('server_url') ?? 'http://127.0.0.1:8000',
      token: prefs.getString('token'),
    );
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Uri _uri(String path, [Map<String, String>? query]) {
    final clean = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.parse('$clean$path').replace(queryParameters: query);
  }

  Future<SessionData> login({required String householdCode, required String memberName, required String pin}) async {
    try {
      final response = await http.post(
        _uri('/auth/login'),
        headers: _headers,
        body: jsonEncode({
          'household_code': householdCode,
          'member_name': memberName,
          'pin': pin,
        }),
      );
      if (response.statusCode != 200) throw Exception(_extractError(response));
      final session = SessionData.fromJson(jsonDecode(response.body));
      token = session.token;
      await saveConfig();
      await saveLastHomeSession(session);
      return session;
    } catch (e) {
      throw Exception(_friendlyException(e));
    }
  }

  Future<SessionData> registerHousehold({
    required String householdName,
    required String joseName,
    required String josePin,
    required String otherName,
    required String otherPin,
  }) async {
    try {
      final response = await http.post(
        _uri('/auth/register-household'),
        headers: _headers,
        body: jsonEncode({
          'name': householdName,
          'members': [
            {'name': joseName, 'pin': josePin, 'color': '#7C3AED', 'role': 'admin'},
            if (otherName.trim().isNotEmpty && otherPin.trim().isNotEmpty)
              {'name': otherName, 'pin': otherPin, 'color': '#06B6D4', 'role': 'member'},
          ]
        }),
      );
      if (response.statusCode != 200) throw Exception(_extractError(response));
      final session = SessionData.fromJson(jsonDecode(response.body));
      token = session.token;
      await saveConfig();
      await saveLastHomeSession(session);
      return session;
    } catch (e) {
      throw Exception(_friendlyException(e));
    }
  }

  Future<AppCapabilities> getCapabilities() async {
    final response = await http.get(_uri('/app/capabilities'), headers: _headers).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw Exception(_extractError(response));
    return AppCapabilities.fromJson(jsonDecode(response.body));
  }

  Future<ServerSyncStatus> getServerSyncStatus() async {
    try {
      final response = await http.get(_uri('/app/sync-status'), headers: _headers).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) throw Exception(_extractError(response));
      return ServerSyncStatus.fromJson(jsonDecode(response.body));
    } catch (e) {
      throw Exception(_friendlyException(e));
    }
  }


  Future<Member> getMe() async {
    final response = await http.get(_uri('/auth/me'), headers: _headers);
    if (response.statusCode != 200) throw Exception(_extractError(response));
    return Member.fromJson(jsonDecode(response.body));
  }

  Future<List<Member>> getMembers({bool includeInactive = false}) async {
    final response = await http.get(
      _uri('/household/members', {'include_inactive': includeInactive.toString()}),
      headers: _headers,
    );
    if (response.statusCode != 200) throw Exception(_extractError(response));
    return (jsonDecode(response.body) as List).map((item) => Member.fromJson(item)).toList();
  }

  Future<Member> createMember({required String name, required String pin, String color = '#7C3AED', String role = 'member'}) async {
    final response = await http.post(
      _uri('/household/members'),
      headers: _headers,
      body: jsonEncode({'name': name, 'pin': pin, 'color': color, 'role': role}),
    );
    if (response.statusCode != 200) throw Exception(_extractError(response));
    return Member.fromJson(jsonDecode(response.body));
  }

  Future<Member> updateMember({required int memberId, String? name, String? color, String? role}) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (color != null) body['color'] = color;
    if (role != null) body['role'] = role;
    final response = await http.patch(_uri('/household/members/$memberId'), headers: _headers, body: jsonEncode(body));
    if (response.statusCode != 200) throw Exception(_extractError(response));
    return Member.fromJson(jsonDecode(response.body));
  }

  Future<Member> setMemberActive({required int memberId, required bool isActive, String reason = ''}) async {
    final response = await http.patch(
      _uri('/household/members/$memberId/active'),
      headers: _headers,
      body: jsonEncode({'is_active': isActive, 'reason': reason}),
    );
    if (response.statusCode != 200) throw Exception(_extractError(response));
    return Member.fromJson(jsonDecode(response.body));
  }

  Future<void> saveIncome({required int memberId, required String month, required double amount}) async {
    final response = await http.post(
      _uri('/finance/income'),
      headers: _headers,
      body: jsonEncode({'member_id': memberId, 'month': month, 'amount': amount}),
    );
    if (response.statusCode != 200) throw Exception(_extractError(response));
  }

  Future<List<IncomeItem>> getIncome(String month) async {
    final response = await http.get(_uri('/finance/income', {'month': month}), headers: _headers);
    if (response.statusCode != 200) throw Exception(_extractError(response));
    return (jsonDecode(response.body) as List).map((item) => IncomeItem.fromJson(item)).toList();
  }

  Future<List<FixedExpenseTemplateItem>> getFixedExpenses({bool activeOnly = true}) async {
    final response = await http.get(_uri('/finance/fixed-expenses', {'active_only': activeOnly.toString()}), headers: _headers);
    if (response.statusCode != 200) throw Exception(_extractError(response));
    return (jsonDecode(response.body) as List).map((item) => FixedExpenseTemplateItem.fromJson(item)).toList();
  }

  Future<FixedExpenseTemplateItem> createFixedExpense({
    required String name,
    required double amount,
    required String category,
    int? defaultPaidByMemberId,
    String notes = '',
    bool active = true,
  }) async {
    final response = await http.post(
      _uri('/finance/fixed-expenses'),
      headers: _headers,
      body: jsonEncode({
        'name': name,
        'amount': amount,
        'category': category,
        'default_paid_by_member_id': defaultPaidByMemberId,
        'frequency': 'monthly',
        'active': active,
        'notes': notes,
      }),
    );
    if (response.statusCode != 200) throw Exception(_extractError(response));
    return FixedExpenseTemplateItem.fromJson(jsonDecode(response.body));
  }

  Future<FixedExpenseTemplateItem> updateFixedExpense({
    required int templateId,
    String? name,
    double? amount,
    String? category,
    int? defaultPaidByMemberId,
    bool clearDefaultPaidByMember = false,
    String? notes,
    bool? active,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (amount != null) body['amount'] = amount;
    if (category != null) body['category'] = category;
    if (clearDefaultPaidByMember) {
      body['default_paid_by_member_id'] = null;
    } else if (defaultPaidByMemberId != null) {
      body['default_paid_by_member_id'] = defaultPaidByMemberId;
    }
    if (notes != null) body['notes'] = notes;
    if (active != null) body['active'] = active;
    final response = await http.patch(_uri('/finance/fixed-expenses/$templateId'), headers: _headers, body: jsonEncode(body));
    if (response.statusCode != 200) throw Exception(_extractError(response));
    return FixedExpenseTemplateItem.fromJson(jsonDecode(response.body));
  }

  Future<ExpenseItem> generateFixedExpense({required int templateId, required String month}) async {
    final response = await http.post(_uri('/finance/fixed-expenses/$templateId/generate', {'month': month}), headers: _headers);
    if (response.statusCode != 200) throw Exception(_extractError(response));
    return ExpenseItem.fromJson(jsonDecode(response.body));
  }

  Future<List<ExpenseItem>> generateFixedExpensesForMonth(String month) async {
    final response = await http.post(_uri('/finance/fixed-expenses/generate-for-month', {'month': month}), headers: _headers);
    if (response.statusCode != 200) throw Exception(_extractError(response));
    return (jsonDecode(response.body) as List).map((item) => ExpenseItem.fromJson(item)).toList();
  }



  Future<CardImportPreviewResult> previewCardImportPdf({required Uint8List bytes, required String filename, String? month}) async {
    final request = http.MultipartRequest('POST', _uri('/finance/card-imports/preview', {if (month != null) 'month': month}));
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await request.send().timeout(const Duration(seconds: 60));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) throw Exception(_extractError(response));
    return CardImportPreviewResult.fromJson(jsonDecode(response.body));
  }

  Future<void> createExpense({
    required int paidByMemberId,
    required double amount,
    required String category,
    required String description,
    required DateTime date,
  }) async {
    final isoDate = _dateOnly(date);
    final response = await http.post(
      _uri('/finance/expenses'),
      headers: _headers,
      body: jsonEncode({
        'paid_by_member_id': paidByMemberId,
        'amount': amount,
        'category': category,
        'description': description,
        'date': isoDate,
        'is_shared': true,
      }),
    );
    if (response.statusCode != 200) throw Exception(_extractError(response));
  }

  Future<List<ExpenseItem>> getExpenses(String month) async {
    final response = await http.get(_uri('/finance/expenses', {'month': month}), headers: _headers);
    if (response.statusCode != 200) throw Exception(_extractError(response));
    return (jsonDecode(response.body) as List).map((item) => ExpenseItem.fromJson(item)).toList();
  }

  Future<void> deleteExpense(int expenseId) async {
    final response = await http.delete(_uri('/finance/expenses/$expenseId'), headers: _headers);
    if (response.statusCode != 200) throw Exception(_extractError(response));
  }

  Future<MonthSummary> getSummary(String month) async {
    final response = await http.get(_uri('/finance/summary', {'month': month}), headers: _headers);
    if (response.statusCode != 200) throw Exception(_extractError(response));
    return MonthSummary.fromJson(jsonDecode(response.body));
  }

  Future<List<MemberParticipationItem>> getParticipation(String month, {bool includeInactive = false}) async {
    final response = await http.get(
      _uri('/finance/participation', {'month': month, 'include_inactive': includeInactive.toString()}),
      headers: _headers,
    );
    if (response.statusCode != 200) throw Exception(_extractError(response));
    return (jsonDecode(response.body) as List).map((item) => MemberParticipationItem.fromJson(item)).toList();
  }

  Future<void> setParticipation({required int memberId, required String month, required bool participates, String? note}) async {
    final response = await http.put(
      _uri('/finance/participation/$memberId'),
      headers: _headers,
      body: jsonEncode({'month': month, 'participates': participates, 'note': note}),
    );
    if (response.statusCode != 200) throw Exception(_extractError(response));
  }

  Future<void> createAutomaticDebts(String month) async {
    final response = await http.post(
      _uri('/finance/debts/from-summary'),
      headers: _headers,
      body: jsonEncode({'month': month}),
    );
    if (response.statusCode != 200) throw Exception(_extractError(response));
  }

  Future<List<DebtItem>> getDebts({bool includeCancelled = false}) async {
    final response = await http.get(
      _uri('/finance/debts', {'include_cancelled': includeCancelled.toString()}),
      headers: _headers,
    );
    if (response.statusCode != 200) throw Exception(_extractError(response));
    return (jsonDecode(response.body) as List).map((item) => DebtItem.fromJson(item)).toList();
  }

  Future<void> createManualDebt({
    required int debtorMemberId,
    required int creditorMemberId,
    required double amount,
    required String reason,
  }) async {
    final response = await http.post(
      _uri('/finance/debts'),
      headers: _headers,
      body: jsonEncode({
        'debtor_member_id': debtorMemberId,
        'creditor_member_id': creditorMemberId,
        'original_amount': amount,
        'reason': reason,
      }),
    );
    if (response.statusCode != 200) throw Exception(_extractError(response));
  }

  Future<void> addDebtPayment({
    required int debtId,
    required double amount,
    required String note,
    required DateTime date,
  }) async {
    final response = await http.post(
      _uri('/finance/debts/$debtId/payments'),
      headers: _headers,
      body: jsonEncode({'amount': amount, 'date': _dateOnly(date), 'note': note}),
    );
    if (response.statusCode != 200) throw Exception(_extractError(response));
  }

  Future<List<DebtPaymentItem>> getDebtPayments(int debtId) async {
    final response = await http.get(_uri('/finance/debts/$debtId/payments'), headers: _headers);
    if (response.statusCode != 200) throw Exception(_extractError(response));
    return (jsonDecode(response.body) as List).map((item) => DebtPaymentItem.fromJson(item)).toList();
  }

  Future<void> confirmDebtPayment({required int debtId, required int paymentId}) async {
    final response = await http.post(_uri('/finance/debts/$debtId/payments/$paymentId/confirm'), headers: _headers);
    if (response.statusCode != 200) throw Exception(_extractError(response));
  }

  Future<void> rejectDebtPayment({required int debtId, required int paymentId, String reason = ''}) async {
    final response = await http.post(
      _uri('/finance/debts/$debtId/payments/$paymentId/reject'),
      headers: _headers,
      body: jsonEncode({'reason': reason}),
    );
    if (response.statusCode != 200) throw Exception(_extractError(response));
  }

  Future<List<CreditBalanceItem>> getCreditBalances({bool activeOnly = true}) async {
    final response = await http.get(_uri('/finance/credit-balances', {'active_only': activeOnly.toString()}), headers: _headers);
    if (response.statusCode != 200) throw Exception(_extractError(response));
    return (jsonDecode(response.body) as List).map((item) => CreditBalanceItem.fromJson(item)).toList();
  }

  Future<void> applyCreditBalance({required int creditId, required int debtId, required double amount, String note = ''}) async {
    final response = await http.post(
      _uri('/finance/credit-balances/$creditId/apply'),
      headers: _headers,
      body: jsonEncode({'debt_id': debtId, 'amount': amount, 'note': note}),
    );
    if (response.statusCode != 200) throw Exception(_extractError(response));
  }

  Future<void> cancelDebt(int debtId, {String reason = ''}) async {
    final response = await http.patch(
      _uri('/finance/debts/$debtId/cancel'),
      headers: _headers,
      body: jsonEncode({'reason': reason}),
    );
    if (response.statusCode != 200) throw Exception(_extractError(response));
  }

  Future<MonthlyCloseItem> closeMonth(String month, {bool advanceToNext = false}) async {
    final response = await http.post(
      _uri('/finance/monthly-closes'),
      headers: _headers,
      body: jsonEncode({'month': month, 'advance_to_next': advanceToNext}),
    );
    if (response.statusCode != 200) throw Exception(_extractError(response));
    return MonthlyCloseItem.fromJson(jsonDecode(response.body));
  }

  Future<List<MonthlyCloseItem>> getMonthlyCloses() async {
    final response = await http.get(_uri('/finance/monthly-closes'), headers: _headers);
    if (response.statusCode != 200) throw Exception(_extractError(response));
    return (jsonDecode(response.body) as List).map((item) => MonthlyCloseItem.fromJson(item)).toList();
  }

  Future<void> reopenMonth(String month, {String reason = ''}) async {
    final response = await http.post(
      _uri('/finance/monthly-closes/$month/reopen'),
      headers: _headers,
      body: jsonEncode({'reason': reason}),
    );
    if (response.statusCode != 200) throw Exception(_extractError(response));
  }

  Future<HouseholdPeriodSettingsItem> getPeriodSettings() async {
    final response = await http.get(_uri('/finance/period-settings'), headers: _headers);
    if (response.statusCode != 200) throw Exception(_extractError(response));
    return HouseholdPeriodSettingsItem.fromJson(jsonDecode(response.body));
  }

  Future<HouseholdPeriodSettingsItem> updatePeriodSettings({required String periodMode, required int startDay}) async {
    final response = await http.put(
      _uri('/finance/period-settings'),
      headers: _headers,
      body: jsonEncode({'period_mode': periodMode, 'start_day': startDay}),
    );
    if (response.statusCode != 200) throw Exception(_extractError(response));
    return HouseholdPeriodSettingsItem.fromJson(jsonDecode(response.body));
  }

  Future<HouseholdPeriodSettingsItem> getActivePeriod() async {
    final response = await http.get(_uri('/finance/active-period'), headers: _headers);
    if (response.statusCode != 200) throw Exception(_extractError(response));
    return HouseholdPeriodSettingsItem.fromJson(jsonDecode(response.body));
  }

  Future<List<MonthlyAdvancePaymentItem>> getMonthlyAdvancePayments(String month) async {
    final response = await http.get(_uri('/finance/monthly-advance-payments', {'month': month}), headers: _headers);
    if (response.statusCode != 200) throw Exception(_extractError(response));
    return (jsonDecode(response.body) as List).map((item) => MonthlyAdvancePaymentItem.fromJson(item)).toList();
  }

  Future<void> createMonthlyAdvancePayment({required String month, required int receivedByMemberId, required double amount, required DateTime date, String note = ''}) async {
    final response = await http.post(
      _uri('/finance/monthly-advance-payments'),
      headers: _headers,
      body: jsonEncode({'month': month, 'received_by_member_id': receivedByMemberId, 'amount': amount, 'date': _dateOnly(date), 'note': note}),
    );
    if (response.statusCode != 200) throw Exception(_extractError(response));
  }

  Future<void> confirmMonthlyAdvancePayment(int paymentId) async {
    final response = await http.post(_uri('/finance/monthly-advance-payments/$paymentId/confirm'), headers: _headers);
    if (response.statusCode != 200) throw Exception(_extractError(response));
  }

  Future<void> rejectMonthlyAdvancePayment({required int paymentId, String reason = ''}) async {
    final response = await http.post(
      _uri('/finance/monthly-advance-payments/$paymentId/reject'),
      headers: _headers,
      body: jsonEncode({'reason': reason}),
    );
    if (response.statusCode != 200) throw Exception(_extractError(response));
  }


  Future<HouseholdTaskSummary> getTaskSummary() async {
    final response = await http.get(_uri('/tasks/summary'), headers: _headers);
    if (response.statusCode != 200) throw Exception(_extractError(response));
    return HouseholdTaskSummary.fromJson(jsonDecode(response.body));
  }

  Future<List<HouseholdTaskItem>> getTasks({bool includeDone = false, bool assignedToMe = false}) async {
    final response = await http.get(
      _uri('/tasks', {'include_done': includeDone.toString(), 'assigned_to_me': assignedToMe.toString()}),
      headers: _headers,
    );
    if (response.statusCode != 200) throw Exception(_extractError(response));
    return (jsonDecode(response.body) as List).map((item) => HouseholdTaskItem.fromJson(item)).toList();
  }

  Future<HouseholdTaskItem> createTask({
    required String title,
    String description = '',
    int? assignedMemberId,
    String? dueDate,
    String? alertDate,
    String priority = 'normal',
    String repeatRule = 'none',
    String sourceType = 'manual',
    double budgetAmount = 0,
    String productLinks = '',
    String preferredSources = '',
    String trackingFrequency = 'manual',
  }) async {
    final response = await http.post(
      _uri('/tasks'),
      headers: _headers,
      body: jsonEncode({
        'title': title,
        'description': description,
        'assigned_member_id': assignedMemberId,
        'due_date': dueDate,
        'alert_date': alertDate,
        'priority': priority,
        'repeat_rule': repeatRule,
        'source_type': sourceType,
        'budget_amount': budgetAmount,
        'product_links': productLinks,
        'preferred_sources': preferredSources,
        'tracking_frequency': trackingFrequency,
      }),
    );
    if (response.statusCode != 200) throw Exception(_extractError(response));
    return HouseholdTaskItem.fromJson(jsonDecode(response.body));
  }

  Future<HouseholdTaskItem> refreshTaskAi(int taskId) async {
    final response = await http.post(_uri('/tasks/$taskId/ai-refresh'), headers: _headers);
    if (response.statusCode != 200) throw Exception(_extractError(response));
    return HouseholdTaskItem.fromJson(jsonDecode(response.body));
  }

  Future<void> completeTask(int taskId) async {
    final response = await http.post(_uri('/tasks/$taskId/complete'), headers: _headers);
    if (response.statusCode != 200) throw Exception(_extractError(response));
  }

  Future<void> cancelTask(int taskId) async {
    final response = await http.post(_uri('/tasks/$taskId/cancel'), headers: _headers);
    if (response.statusCode != 200) throw Exception(_extractError(response));
  }


  Future<List<AiReportItem>> getHouseholdAiReports(String month) async {
    final response = await http.get(_uri('/ai/household-reports', {'month': month}), headers: _headers);
    if (response.statusCode != 200) throw Exception(_extractError(response));
    return (jsonDecode(response.body) as List).map((item) => AiReportItem.fromJson(item)).toList();
  }

  Future<AiReportItem> createHouseholdAiReport({required String month, String focus = 'general', bool useApi = true}) async {
    final response = await http.post(
      _uri('/ai/household-reports'),
      headers: _headers,
      body: jsonEncode({'month': month, 'focus': focus, 'use_api': useApi}),
    );
    if (response.statusCode != 200) throw Exception(_extractError(response));
    return AiReportItem.fromJson(jsonDecode(response.body));
  }


  Future<AiWeeklySettings> getWeeklyAiSettings() async {
    final response = await http.get(_uri('/ai/weekly-settings'), headers: _headers);
    if (response.statusCode != 200) throw Exception(_extractError(response));
    return AiWeeklySettings.fromJson(jsonDecode(response.body));
  }

  Future<AiWeeklySettings> updateWeeklyAiSettings({
    bool? weeklyEnabled,
    String? analysisFrequency,
    int? preferredWeekday,
    bool? useExternalContext,
    bool? useNewsContext,
  }) async {
    final body = <String, dynamic>{};
    if (weeklyEnabled != null) body['weekly_enabled'] = weeklyEnabled;
    if (analysisFrequency != null) body['analysis_frequency'] = analysisFrequency;
    if (preferredWeekday != null) body['preferred_weekday'] = preferredWeekday;
    if (useExternalContext != null) body['use_external_context'] = useExternalContext;
    if (useNewsContext != null) body['use_news_context'] = useNewsContext;
    final response = await http.put(_uri('/ai/weekly-settings'), headers: _headers, body: jsonEncode(body));
    if (response.statusCode != 200) throw Exception(_extractError(response));
    return AiWeeklySettings.fromJson(jsonDecode(response.body));
  }

  Future<AiWeeklyReportResult> getLatestWeeklyAiReport() async {
    final response = await http.get(_uri('/ai/weekly-latest'), headers: _headers);
    if (response.statusCode != 200) throw Exception(_extractError(response));
    return AiWeeklyReportResult.fromJson(jsonDecode(response.body));
  }

  Future<AiWeeklyReportResult> createWeeklyAiReport({required String month, bool force = false, bool useApi = true}) async {
    final response = await http.post(
      _uri('/ai/weekly-reports'),
      headers: _headers,
      body: jsonEncode({'month': month, 'force': force, 'use_api': useApi}),
    ).timeout(const Duration(seconds: 80));
    if (response.statusCode != 200) throw Exception(_extractError(response));
    return AiWeeklyReportResult.fromJson(jsonDecode(response.body));
  }

  Future<AiWeeklyReportResult> refreshWeeklyAiIfNeeded({required String month, bool useApi = true}) async {
    final response = await http.post(
      _uri('/ai/weekly-refresh-if-needed'),
      headers: _headers,
      body: jsonEncode({'month': month, 'force': false, 'use_api': useApi}),
    ).timeout(const Duration(seconds: 80));
    if (response.statusCode != 200) throw Exception(_extractError(response));
    return AiWeeklyReportResult.fromJson(jsonDecode(response.body));
  }

  Future<Map<String, dynamic>> exportHouseholdBackup() async {
    try {
      final response = await http.get(_uri('/backup/household'), headers: _headers).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw Exception(_extractError(response));
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw Exception(_friendlyException(e));
    }
  }

  String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _extractError(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      return decoded['detail']?.toString() ?? 'Error ${response.statusCode}';
    } catch (_) {
      return 'Error ${response.statusCode}';
    }
  }

  String _friendlyException(Object error) => friendlyMessage(error);
}
