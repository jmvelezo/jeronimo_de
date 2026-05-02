import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_models.dart';

class SharedMonthCache {
  final String serverUrl;
  final int householdId;
  final String month;
  final DateTime savedAt;
  final List<Member> members;
  final List<MemberParticipationItem> participation;
  final MonthSummary summary;
  final HouseholdTaskSummary? taskSummary;

  SharedMonthCache({
    required this.serverUrl,
    required this.householdId,
    required this.month,
    required this.savedAt,
    required this.members,
    required this.participation,
    required this.summary,
    this.taskSummary,
  });
}

class SharedSyncStore {
  static const _lastSyncKey = 'shared_last_successful_sync';
  static const _lastServerKey = 'shared_last_server_url';
  static const _lastOnlineKey = 'shared_last_online';

  String _cacheKey(int householdId, String month) => 'shared_cache_${householdId}_$month';

  Future<void> saveServerUrl(String serverUrl) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastServerKey, serverUrl);
  }

  Future<DateTime?> lastSuccessfulSync() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastSyncKey);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  Future<SyncViewState> loadSyncViewState({required String currentServerUrl}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastSyncKey);
    final last = raw == null ? null : DateTime.tryParse(raw);
    final online = prefs.getBool(_lastOnlineKey) ?? false;
    final serverUrl = prefs.getString(_lastServerKey) ?? currentServerUrl;
    return SyncViewState(
      online: online,
      lastSuccessfulSync: last,
      serverUrl: serverUrl,
      message: online ? 'Sincronizado con el hogar compartido.' : 'Sin conexión confirmada con el hogar compartido.',
    );
  }

  Future<void> markOnline(String serverUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().toIso8601String();
    await prefs.setBool(_lastOnlineKey, true);
    await prefs.setString(_lastSyncKey, now);
    await prefs.setString(_lastServerKey, serverUrl);
  }

  Future<void> markOffline() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_lastOnlineKey, false);
  }

  Future<void> saveSharedSnapshot({
    required String serverUrl,
    required int householdId,
    required String month,
    required List<Member> members,
    required List<MemberParticipationItem> participation,
    required MonthSummary summary,
    HouseholdTaskSummary? taskSummary,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final payload = {
      'server_url': serverUrl,
      'household_id': householdId,
      'month': month,
      'saved_at': now.toIso8601String(),
      'members': members.map(_memberToJson).toList(),
      'participation': participation.map(_participationToJson).toList(),
      'summary': _summaryToJson(summary),
      'task_summary': taskSummary == null ? null : _taskSummaryToJson(taskSummary),
    };
    await prefs.setString(_cacheKey(householdId, month), jsonEncode(payload));
    await prefs.setString(_lastSyncKey, now.toIso8601String());
    await prefs.setString(_lastServerKey, serverUrl);
    await prefs.setBool(_lastOnlineKey, true);
  }

  Future<SharedMonthCache?> loadSharedSnapshot({required int householdId, required String month}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey(householdId, month));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final members = (decoded['members'] as List).map((item) => Member.fromJson(Map<String, dynamic>.from(item))).toList();
      final participation = (decoded['participation'] as List)
          .map((item) => MemberParticipationItem.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      final summary = MonthSummary.fromJson(Map<String, dynamic>.from(decoded['summary']));
      final taskRaw = decoded['task_summary'];
      return SharedMonthCache(
        serverUrl: decoded['server_url'] ?? '',
        householdId: decoded['household_id'] ?? householdId,
        month: decoded['month'] ?? month,
        savedAt: DateTime.tryParse(decoded['saved_at'] ?? '') ?? DateTime.now(),
        members: members,
        participation: participation,
        summary: summary,
        taskSummary: taskRaw == null ? null : HouseholdTaskSummary.fromJson(Map<String, dynamic>.from(taskRaw)),
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _memberToJson(Member item) => {
        'id': item.id,
        'household_id': item.householdId,
        'name': item.name,
        'color': item.color,
        'role': item.role,
        'is_active': item.isActive,
      };

  Map<String, dynamic> _participationToJson(MemberParticipationItem item) => {
        'member_id': item.memberId,
        'month': item.month,
        'participates': item.participates,
        'note': item.note,
      };

  Map<String, dynamic> _summaryToJson(MonthSummary item) => {
        'month': item.month,
        'total_income': item.totalIncome,
        'total_shared_expenses': item.totalSharedExpenses,
        'members': item.members.map(_memberSummaryToJson).toList(),
        'settlements': item.settlements.map(_settlementToJson).toList(),
        'warning': item.warning,
      };

  Map<String, dynamic> _memberSummaryToJson(MemberSummary item) => {
        'member_id': item.memberId,
        'name': item.name,
        'color': item.color,
        'income': item.income,
        'income_share': item.incomeShare,
        'should_pay': item.shouldPay,
        'actually_paid': item.actuallyPaid,
        'balance': item.balance,
        'participates': item.participates,
      };

  Map<String, dynamic> _settlementToJson(SettlementSuggestion item) => {
        'debtor_member_id': item.debtorMemberId,
        'creditor_member_id': item.creditorMemberId,
        'amount': item.amount,
        'reason': item.reason,
      };

  Map<String, dynamic> _taskSummaryToJson(HouseholdTaskSummary item) => {
        'pending_count': item.pendingCount,
        'overdue_count': item.overdueCount,
        'due_soon_count': item.dueSoonCount,
        'high_priority_count': item.highPriorityCount,
        'assigned_to_me_count': item.assignedToMeCount,
      };
}
