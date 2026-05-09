import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/app_models.dart';
import '../services/api_service.dart';
import '../services/friendly_messages.dart';
import '../services/shared_sync_store.dart';
import '../widgets/app_card.dart';
import '../widgets/app_shell.dart';
import 'debts_screen.dart';
import 'expenses_screen.dart';
import 'history_screen.dart';
import 'advanced_config_screen.dart';
import 'personal_local_screen.dart';
import 'tasks_screen.dart';
import 'ai_screen.dart';

class DashboardScreen extends StatefulWidget {
  final ApiService api;
  final SessionData session;

  const DashboardScreen({super.key, required this.api, required this.session});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final money = NumberFormat.currency(locale: 'es_AR', symbol: r'$ ', decimalDigits: 0);
  late String month;
  bool loading = true;
  String? error;
  int navIndex = 0;
  List<Member> members = [];
  List<MemberParticipationItem> participation = [];
  MonthSummary? summary;
  HouseholdTaskSummary? taskSummary;
  HouseholdPeriodSettingsItem? periodSettings;
  List<MonthlyAdvancePaymentItem> advancePayments = [];
  List<CreditBalanceItem> creditBalances = [];
  AiWeeklyReportResult? weeklyAi;
  bool weeklyAiLoading = false;
  String? weeklyAiMessage;
  final SharedSyncStore syncStore = SharedSyncStore();
  DateTime? lastSuccessfulSync;
  bool offlineMode = false;
  String? syncMessage;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    month = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await widget.api.getServerSyncStatus();
      HouseholdPeriodSettingsItem? loadedPeriod;
      try {
        loadedPeriod = await widget.api.getActivePeriod();
        if (loadedPeriod.activeMonth.isNotEmpty) month = loadedPeriod.activeMonth;
      } catch (_) {
        loadedPeriod = null;
      }
      final loadedMembers = await widget.api.getMembers();
      final loadedParticipation = await widget.api.getParticipation(month);
      final loadedSummary = await widget.api.getSummary(month);
      List<MonthlyAdvancePaymentItem> loadedAdvancePayments = [];
      try {
        loadedAdvancePayments = await widget.api.getMonthlyAdvancePayments(month);
      } catch (_) {
        loadedAdvancePayments = [];
      }
      List<CreditBalanceItem> loadedCreditBalances = [];
      try {
        loadedCreditBalances = await widget.api.getCreditBalances(activeOnly: true);
      } catch (_) {
        loadedCreditBalances = [];
      }
      HouseholdTaskSummary? loadedTaskSummary;
      try {
        loadedTaskSummary = await widget.api.getTaskSummary();
      } catch (_) {
        loadedTaskSummary = null;
      }
      AiWeeklyReportResult? loadedWeeklyAi;
      try {
        loadedWeeklyAi = await widget.api.refreshWeeklyAiIfNeeded(month: month);
      } catch (_) {
        try {
          loadedWeeklyAi = await widget.api.getLatestWeeklyAiReport();
        } catch (_) {
          loadedWeeklyAi = null;
        }
      }
      await syncStore.saveSharedSnapshot(
        serverUrl: widget.api.baseUrl,
        householdId: widget.session.household.id,
        month: month,
        members: loadedMembers,
        participation: loadedParticipation,
        summary: loadedSummary,
        taskSummary: loadedTaskSummary,
      );
      final last = await syncStore.lastSuccessfulSync();
      setState(() {
        members = loadedMembers;
        participation = loadedParticipation;
        summary = loadedSummary;
        taskSummary = loadedTaskSummary;
        weeklyAi = loadedWeeklyAi;
        weeklyAiMessage = loadedWeeklyAi?.message;
        periodSettings = loadedPeriod;
        advancePayments = loadedAdvancePayments;
        creditBalances = loadedCreditBalances;
        lastSuccessfulSync = last;
        offlineMode = false;
        syncMessage = "Sincronizado con el hogar compartido.";
      });
    } catch (e) {
      await syncStore.markOffline();
      final cached = await syncStore.loadSharedSnapshot(householdId: widget.session.household.id, month: month);
      if (cached != null) {
        setState(() {
          members = cached.members;
          participation = cached.participation;
          summary = cached.summary;
          taskSummary = cached.taskSummary;
          advancePayments = [];
          creditBalances = [];
          lastSuccessfulSync = cached.savedAt;
          offlineMode = true;
          syncMessage = "Sin conexión. Mostrando la última información sincronizada.";
          error = "No pudimos sincronizar ahora. Te mostramos la última foto guardada de este hogar.";
        });
      } else {
        setState(() => error = friendlyMessage(e));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _saveAutomaticDebts() async {
    try {
      await widget.api.createAutomaticDebts(month);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deuda automática del mes registrada.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyMessage(e))));
    }
  }

  Future<void> _generateWeeklyAi({bool force = true}) async {
    setState(() {
      weeklyAiLoading = true;
      weeklyAiMessage = null;
    });
    try {
      final result = await widget.api.createWeeklyAiReport(month: month, force: force);
      setState(() {
        weeklyAi = result;
        weeklyAiMessage = result.message;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.generatedNow ? 'Análisis IA actualizado.' : result.message)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyMessage(e))));
    } finally {
      if (mounted) setState(() => weeklyAiLoading = false);
    }
  }


  double get _myAvailableCreditBalance {
    return creditBalances
        .where((item) => item.ownerMemberId == widget.session.member.id && item.status == 'available' && item.remainingAmount > 0.01)
        .fold<double>(0.0, (total, item) => total + item.remainingAmount);
  }

  Widget _creditBalanceChip(double amount, {bool compact = false}) {
    if (amount <= 0.01) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(compact ? 0.12 : 0.16),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.16), borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.savings_outlined, color: Colors.white, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Crédito disponible: ${money.format(amount)}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  'Se conserva para próximas deudas o podés aplicarlo desde Deudas y abonos.',
                  style: TextStyle(color: Colors.white.withOpacity(0.78), fontWeight: FontWeight.w700, fontSize: 11, height: 1.25),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _isParticipating(int memberId) {
    final matches = participation.where((item) => item.memberId == memberId).toList();
    if (matches.isEmpty) return true;
    return matches.first.participates;
  }

  List<Member> get _participatingMembers {
    final filtered = members.where((member) => _isParticipating(member.id)).toList();
    return filtered.isEmpty ? members : filtered;
  }

  Future<void> _setParticipation(Member member, bool participates) async {
    try {
      await widget.api.setParticipation(memberId: member.id, month: month, participates: participates);
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(participates ? '${member.name} participa en $month.' : '${member.name} quedó fuera del reparto de $month.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return Scaffold(
      extendBody: true,
      body: AppGradientBackground(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 90),
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            children: [
              _topHeader(),
              const SizedBox(height: 14),
              if (error != null) ...[
                FriendlyError(message: error!),
                const SizedBox(height: 14),
              ],
              if (loading && s == null) const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())),
              if (s != null) _buildTab(s),
            ],
          ),
        ),
      ),
      bottomNavigationBar: JeronimoBottomNav(
        currentIndex: navIndex,
        onDestinationSelected: (value) => setState(() => navIndex = value),
      ),
    );
  }


  Future<void> _openInternal(Widget screen) async {
    final result = await Navigator.of(context).push<int>(MaterialPageRoute(builder: (_) => screen));
    if (!mounted) return;
    if (result is int) {
      setState(() => navIndex = result);
      await _refresh();
    }
  }

  Widget _topHeader() {
    return AppHeroHeader(
      eyebrow: 'ARS · Hogar conectado · $month',
      title: widget.session.household.name,
      subtitle: offlineMode
          ? 'Hola, ${widget.session.member.name}. Vemos la última sincronización guardada.'
          : 'Hola, ${widget.session.member.name}. Resumen claro de casa, tareas e IA.',
      icon: Icons.roofing_rounded,
      assetIconPath: kBrandNavCasa,
      trailing: IconButton(
        onPressed: _refresh,
        icon: const Icon(Icons.refresh, color: Colors.white),
        tooltip: 'Actualizar',
      ),
    );
  }

  Widget _buildTab(MonthSummary s) {
    switch (navIndex) {
      case 1:
        return _homeManagementTab(s);
      case 2:
        return _personalTab();
      case 3:
        return _tasksTab(s);
      case 4:
        return _moreTab(s);
      default:
        return _overviewTab(s);
    }
  }


  Widget _overviewTab(MonthSummary s) {
    final matchingMembers = s.members.where((item) => item.memberId == widget.session.member.id).toList();
    final mySummary = matchingMembers.isEmpty ? null : matchingMembers.first;
    final balance = mySummary?.balance ?? 0;
    final balanceLabel = balance >= 0 ? 'Te deberían compensar' : 'Deberías compensar';
    final balanceColor = balance >= 0 ? kSuccess : kWarning;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _homePulseCard(s, mySummary, balanceLabel, balanceColor),
        const SizedBox(height: 14),
        const SectionTitle(title: 'Atajos del mes', subtitle: 'Lectura rápida para decidir qué hacer.', icon: Icons.auto_graph_outlined),
        _monthShortcuts(s, balance, balanceLabel, balanceColor),
        const SizedBox(height: 14),
        if (s.warning != null) ...[
          AppCard(
            color: const Color(0xFFFFFBEB),
            border: Border.all(color: const Color(0xFFFBBF24)),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706)),
                const SizedBox(width: 10),
                Expanded(child: Text(s.warning!, style: const TextStyle(color: Color(0xFF92400E), fontWeight: FontWeight.w800))),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        _weeklyAiAdviceCard(),
        const SizedBox(height: 14),
        _quickActionsCard(),
        const SizedBox(height: 14),
        _syncStatusCard(),
        const SizedBox(height: 14),
        _taskAlertCard(),
        const SizedBox(height: 14),
        const SectionTitle(title: 'Participación del mes', subtitle: 'Cada persona aporta según ingresos cargados.', icon: Icons.pie_chart_outline),
        for (final member in s.members) ...[
          _MemberSummaryCard(member: member, money: money),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _monthShortcuts(MonthSummary s, double balance, String balanceLabel, Color balanceColor) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 760;
        final spacing = 10.0;
        final itemWidth = isWide ? (constraints.maxWidth - spacing * 3) / 4 : (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            _ShortcutMetricCard(
              width: itemWidth,
              label: 'Ingresos hogar',
              value: money.format(s.totalIncome),
              hint: 'Cargar',
              icon: Icons.payments_outlined,
              color: kPrimary,
              onTap: members.isEmpty ? null : _showIncomeSheet,
            ),
            _ShortcutMetricCard(
              width: itemWidth,
              label: 'Gastos comunes',
              value: money.format(s.totalSharedExpenses),
              hint: 'Agregar gasto',
              icon: Icons.shopping_bag_outlined,
              assetIconPath: kBrandGastos,
              color: kPrimaryMid,
              onTap: members.isEmpty ? null : _showExpenseSheet,
            ),
            _ShortcutMetricCard(
              width: itemWidth,
              label: 'Saldo provisorio',
              value: money.format(balance.abs()),
              hint: balance >= 0 ? 'Si cerrás hoy: te deben' : 'Si cerrás hoy: debés',
              icon: Icons.account_balance_wallet_outlined,
              assetIconPath: kBrandPulsoHogar,
              color: balanceColor,
              onTap: members.isEmpty ? null : () => _showMonthlyBalanceDetail(s),
            ),
            _ShortcutMetricCard(
              width: itemWidth,
              label: 'Integrantes',
              value: members.length.toString(),
              hint: 'Gestionar',
              icon: Icons.groups_2_outlined,
              color: kPrimaryDark,
              onTap: () => setState(() => navIndex = 1),
            ),
          ],
        );
      },
    );
  }

  Future<void> _copyHouseholdCode() async {
    await Clipboard.setData(ClipboardData(text: widget.session.household.inviteCode));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Código de hogar copiado.')));
    }
  }

  Widget _homePulseCard(MonthSummary s, MemberSummary? mySummary, String balanceLabel, Color balanceColor) {
    final myPaid = mySummary == null ? 0.0 : mySummary.actuallyPaid;
    final myExpected = mySummary == null ? 0.0 : mySummary.shouldPay;
    return AppCard(
      padding: const EdgeInsets.all(20),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF6D28D9), Color(0xFF4C1D95)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BrandAssetIcon(
                assetPath: kBrandPulsoHogar,
                fallbackIcon: Icons.home_rounded,
                size: 42,
                frameSize: 52,
                borderRadius: 20,
                padding: 4,
                withShadow: false,
                backgroundColor: Colors.white.withOpacity(0.94),
                borderColor: Colors.white.withOpacity(0.22),
                fallbackColor: kPrimary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pulso del hogar', style: TextStyle(color: Colors.white.withOpacity(0.74), fontWeight: FontWeight.w900, letterSpacing: 0.3)),
                    const SizedBox(height: 2),
                    Text('Saldo provisorio del período', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.4)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            money.format((mySummary?.balance ?? 0).abs()),
            style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w900, letterSpacing: -1.2),
          ),
          const SizedBox(height: 8),
          Text(
            'Si cerrás hoy: ${balanceLabel.toLowerCase()} ${money.format((mySummary?.balance ?? 0).abs())}. Te correspondía ${money.format(myExpected)} y pagaste ${money.format(myPaid)}.',
            style: TextStyle(color: Colors.white.withOpacity(0.86), height: 1.3, fontWeight: FontWeight.w600),
          ),
          if (_myAvailableCreditBalance > 0.01) ...[
            const SizedBox(height: 12),
            _creditBalanceChip(_myAvailableCreditBalance),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(18)),
            child: Row(
              children: [
                Icon(Icons.currency_exchange_rounded, color: Colors.white.withOpacity(0.88), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    periodSettings?.label ?? 'ARS como moneda base · período calendario por defecto.',
                    style: TextStyle(color: Colors.white.withOpacity(0.82), fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _homeManagementTab(MonthSummary s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(title: 'Casa', subtitle: 'Cargar lo común y revisar quién pagó qué.', icon: Icons.home_work_outlined),
        _quickActionsCard(),
        const SizedBox(height: 14),
        _participationCard(),
        const SizedBox(height: 14),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Integrantes activos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              for (final member in members)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(backgroundColor: _colorFromHex(member.color), child: Text(member.name.isEmpty ? '?' : member.name[0].toUpperCase(), style: const TextStyle(color: Colors.white))),
                  title: Text(member.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(_roleLabel(member.role)),
                  trailing: Icon(member.isActive ? Icons.check_circle : Icons.pause_circle_outline, color: member.isActive ? kSuccess : kWarning),
                ),
            ],
          ),
        ),
      ],
    );
  }


  Widget _weeklyAiAdviceCard() {
    final result = weeklyAi;
    final tips = result?.tips ?? [];
    final firstTip = tips.isNotEmpty ? tips.first : null;
    final settings = result?.settings;
    Color levelColor(String level) {
      switch (level) {
        case 'danger':
          return kDanger;
        case 'warning':
          return kWarning;
        case 'success':
          return kSuccess;
        default:
          return kPrimary;
      }
    }
    final color = firstTip == null ? kPrimary : levelColor(firstTip.level);
    return AppCard(
      gradient: LinearGradient(colors: [color.withOpacity(0.92), const Color(0xFF312E81)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BrandAssetIcon(
                assetPath: kBrandIaHogar,
                fallbackIcon: Icons.auto_awesome,
                size: 34,
                frameSize: 46,
                borderRadius: 16,
                padding: 4,
                withShadow: false,
                backgroundColor: Colors.white.withOpacity(0.94),
                borderColor: Colors.white.withOpacity(0.18),
                fallbackColor: color,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(firstTip?.title ?? 'Consejo IA del hogar', style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    Text(
                      firstTip?.body ?? 'Todavía no hay consejo IA. Generá un análisis para que la app muestre recomendaciones visibles según la frecuencia configurada.',
                      style: TextStyle(color: Colors.white.withOpacity(0.9), height: 1.32, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (tips.length > 1)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: tips.skip(1).take(3).map((tip) => Chip(label: Text(tip.title), backgroundColor: Colors.white.withOpacity(0.88))).toList(),
            ),
          if (weeklyAiMessage != null) ...[
            const SizedBox(height: 8),
            Text(weeklyAiMessage!, style: TextStyle(color: Colors.white.withOpacity(0.74), fontSize: 12, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: weeklyAiLoading ? null : () => _generateWeeklyAi(force: true),
                  icon: weeklyAiLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.insights_outlined),
                  label: Text(weeklyAiLoading ? 'Analizando...' : 'Actualizar análisis'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Ver IA completa',
                onPressed: () => _openInternal(AiScreen(api: widget.api, month: month, currentMember: widget.session.member)),
                icon: const Icon(Icons.open_in_new),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            settings?.weeklyEnabled == true
                ? 'Análisis automático activo · ${settings!.frequencyLabel} · ARS como moneda base.'
                : 'Automático desactivado o manual · podés configurarlo en Ajustes avanzados.',
            style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _syncStatusCard() {
    final last = lastSuccessfulSync == null
        ? 'Sin sincronización previa'
        : 'Última sincronización: ${lastSuccessfulSync!.toLocal().toString().substring(0, 16)}';
    final color = offlineMode ? kWarning : kSuccess;
    return AppCard(
      color: color.withOpacity(0.08),
      border: Border.all(color: color.withOpacity(0.18)),
      child: Row(
        children: [
          Icon(offlineMode ? Icons.cloud_off_outlined : Icons.cloud_done_outlined, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(offlineMode ? 'Hogar sin conexión' : 'Hogar sincronizado', style: TextStyle(color: color, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(syncMessage ?? last, style: const TextStyle(color: Colors.black54)),
                Text(last, style: const TextStyle(color: Colors.black45, fontSize: 12)),
              ],
            ),
          ),
          TextButton.icon(onPressed: _refresh, icon: const Icon(Icons.sync), label: const Text('Sincronizar')),
        ],
      ),
    );
  }

  Widget _tasksTab(MonthSummary s) {
    final item = taskSummary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(title: 'Tareas comunes', subtitle: 'Pagos, pendientes y alertas visibles para el hogar.', icon: Icons.task_alt_outlined),
        if (item != null) _taskAlertCard(),
        const SizedBox(height: 12),
        BigActionButton(
          onPressed: () => _openInternal(TasksScreen(api: widget.api, members: members, onChanged: _refresh)),
          icon: Icons.notifications_active_outlined,
          title: 'Abrir tareas y alertas',
          subtitle: 'Responsables, vencimientos, prioridad y repetición mensual',
        ),
      ],
    );
  }

  Widget _taskAlertCard() {
    final item = taskSummary;
    if (item == null) {
      return AppCard(
        child: Row(
          children: const [
            Icon(Icons.task_alt_outlined, color: kPrimary),
            SizedBox(width: 10),
            Expanded(child: Text('Tareas comunes preparadas. Entrá a la pestaña Tareas para cargar pendientes.', style: TextStyle(fontWeight: FontWeight.w800))),
          ],
        ),
      );
    }
    final danger = item.overdueCount > 0;
    final color = danger ? kDanger : (item.dueSoonCount > 0 || item.highPriorityCount > 0 ? kWarning : kPrimary);
    final message = item.pendingCount == 0
        ? 'Sin tareas comunes pendientes.'
        : '${item.pendingCount} pendiente(s), ${item.overdueCount} vencida(s), ${item.dueSoonCount} próxima(s), ${item.assignedToMeCount} para mí.';
    return AppCard(
      color: color.withOpacity(0.08),
      border: Border.all(color: color.withOpacity(0.18)),
      child: Row(
        children: [
          Icon(danger ? Icons.warning_amber_rounded : Icons.task_alt_outlined, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: TextStyle(color: color, fontWeight: FontWeight.w900))),
        ],
      ),
    );
  }

  Widget _debtsTab(MonthSummary s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(title: 'Deudas y ajustes', subtitle: 'Saldos comunes, abonos y reparto pendiente.', icon: Icons.receipt_long_outlined),
        if (s.settlements.isEmpty)
          const EmptyState(
            icon: Icons.verified_outlined,
            title: 'Sin ajuste recomendado',
            message: 'Cuando alguien pague de más o de menos, acá va a aparecer el saldo sugerido.',
          )
        else
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Ajuste recomendado', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                for (final settlement in s.settlements)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.arrow_forward_rounded, color: kPrimary),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_settlementText(settlement), style: const TextStyle(fontWeight: FontWeight.w800))),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                BigActionButton(
                  onPressed: _saveAutomaticDebts,
                  icon: Icons.check_circle_outline,
                  title: 'Registrar como deuda del mes',
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        BigActionButton(
          onPressed: members.isEmpty
              ? null
              : () => _openInternal(DebtsScreen(api: widget.api, members: members, month: month, currentMemberId: widget.session.member.id, onChanged: _refresh)),
          icon: Icons.account_balance_wallet_outlined,
          title: 'Ver deudas y abonos',
          subtitle: 'Manual, automática y pagos parciales',
        ),
      ],
    );
  }

  Widget _historyTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(title: 'Historial', subtitle: 'Cerrar el mes y consultar fotos anteriores.', icon: Icons.history_outlined),
        BigActionButton(
          onPressed: members.isEmpty
              ? null
              : () => _openInternal(HistoryScreen(api: widget.api, members: members, currentMonth: month, onChanged: _refresh)),
          icon: Icons.event_available_outlined,
          title: 'Historial y cierre mensual',
          subtitle: 'Cierre, reapertura y consulta',
        ),
      ],
    );
  }


  Widget _personalTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(
          title: 'Personal',
          subtitle: 'Tu billetera privada queda en este dispositivo.',
          icon: Icons.account_balance_wallet_outlined,
        ),
        AppCard(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BrandAssetIcon(
                assetPath: kBrandNavPersonal,
                fallbackIcon: Icons.lock_person_rounded,
                size: 44,
                frameSize: 56,
                borderRadius: 22,
                padding: 4,
                withShadow: false,
                backgroundColor: Colors.white.withOpacity(0.94),
                borderColor: Colors.white.withOpacity(0.22),
                fallbackColor: kPrimary,
              ),
              const SizedBox(height: 14),
              const Text('Mis cuentas', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(
                'Gastos, ingresos, presupuestos, deudas personales e IA privada. No se comparte con el hogar.',
                style: TextStyle(color: Colors.white.withOpacity(0.88), height: 1.3, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _openInternal(const PersonalLocalScreen(allowSharedNavigation: true)),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Abrir espacio personal'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: kPrimary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              SectionTitle(title: 'Privado por diseño', subtitle: 'Este módulo funciona localmente. El hogar solo ve lo compartido.', icon: Icons.privacy_tip_outlined),
              Text('Ideal para registrar cuentas personales sin mezclar todo con los gastos comunes.', style: TextStyle(color: kMuted, height: 1.35, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _householdCodeCard() {
    return AppCard(
      gradient: const LinearGradient(colors: [Color(0xFFF4EDFF), Color(0xFFFFFFFF)]),
      border: Border.all(color: kPrimarySoft.withOpacity(0.8)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: kPrimarySoft, borderRadius: BorderRadius.circular(18)),
            child: const Icon(Icons.key_rounded, color: kPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Código de hogar', style: TextStyle(fontWeight: FontWeight.w900, color: kInk)),
                const SizedBox(height: 3),
                SelectableText(widget.session.household.inviteCode, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: 1.0, color: kPrimary)),
                const SizedBox(height: 2),
                const Text('Sirve para invitar o volver a entrar a este hogar.', style: TextStyle(color: kMuted, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Copiar código',
            onPressed: _copyHouseholdCode,
            icon: const Icon(Icons.copy_rounded),
          ),
        ],
      ),
    );
  }

  Widget _moreTab(MonthSummary s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(
          title: 'Más opciones',
          subtitle: 'Herramientas importantes, sin saturar la barra principal.',
          icon: Icons.dashboard_customize_outlined,
        ),
        _householdCodeCard(),
        const SizedBox(height: 14),
        AppCard(
          child: Column(
            children: [
              SoftActionTile(
                icon: Icons.receipt_long_outlined,
                assetIconPath: kBrandGastos,
                title: 'Deudas y abonos',
                subtitle: 'Saldos comunes, pagos parciales y ajustes del mes.',
                onTap: members.isEmpty ? null : () => _openInternal(DebtsScreen(api: widget.api, members: members, month: month, currentMemberId: widget.session.member.id, onChanged: _refresh)),
              ),
              const SizedBox(height: 10),
              SoftActionTile(
                icon: Icons.event_available_outlined,
                assetIconPath: kBrandHistorialCierre,
                title: 'Historial y cierre mensual',
                subtitle: 'Fotos del mes, cierre, reapertura y trazabilidad.',
                onTap: members.isEmpty ? null : () => _openInternal(HistoryScreen(api: widget.api, members: members, currentMonth: month, onChanged: _refresh)),
              ),
              const SizedBox(height: 10),
              SoftActionTile(
                icon: Icons.auto_awesome_outlined,
                assetIconPath: kBrandIaHogar,
                title: 'IA completa',
                subtitle: 'Informe semanal, consejos, trazabilidad y contexto económico.',
                onTap: () => _openInternal(AiScreen(api: widget.api, month: month, currentMember: widget.session.member)),
              ),
              const SizedBox(height: 10),
              SoftActionTile(
                icon: Icons.admin_panel_settings_outlined,
                assetIconPath: kBrandConfigAvanzada,
                title: 'Configuración avanzada',
                subtitle: 'Servidor, integrantes, IA, respaldo y sincronización.',
                onTap: () => _openInternal(AdvancedConfigScreen(api: widget.api, session: widget.session, onChanged: _refresh)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _syncStatusCard(),
      ],
    );
  }


  Widget _aiTab() {
    return AiScreen(api: widget.api, month: month, currentMember: widget.session.member, embedded: true);
  }

  Widget _settingsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(title: 'Ajustes', subtitle: 'Lo básico visible; lo técnico queda aparte.', icon: Icons.tune_outlined),
        _syncStatusCard(),
        const SizedBox(height: 10),
        BigActionButton(
          onPressed: () => _openInternal(const PersonalLocalScreen(allowSharedNavigation: true)),
          icon: Icons.lock_person_outlined,
          title: 'Mis cuentas personales',
          subtitle: 'Espacio privado en este dispositivo',
        ),
        const SizedBox(height: 10),
        BigActionButton(
          outlined: true,
          onPressed: () => _openInternal(AdvancedConfigScreen(api: widget.api, session: widget.session, onChanged: _refresh)),
          icon: Icons.admin_panel_settings_outlined,
          title: 'Configuración avanzada',
          subtitle: 'Servidor, integrantes y opciones técnicas',
        ),
      ],
    );
  }

  Widget _participationCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Participación mensual', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          const Text(
            'Sirve para excluir a alguien solo este mes sin borrarlo del hogar ni romper el historial.',
            style: TextStyle(color: Colors.black54, height: 1.3),
          ),
          const SizedBox(height: 10),
          for (final member in members)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isParticipating(member.id),
              onChanged: (value) => _setParticipation(member, value),
              title: Text(member.name, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(_isParticipating(member.id) ? 'Participa en el reparto de $month' : 'No participa este mes'),
              secondary: CircleAvatar(
                backgroundColor: _colorFromHex(member.color),
                child: Text(member.name.isEmpty ? '?' : member.name[0].toUpperCase(), style: const TextStyle(color: Colors.white)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _quickActionsCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: 'Acciones rápidas', subtitle: 'Cargá lo importante sin perderte.', icon: Icons.bolt_rounded),
          SoftActionTile(
            onTap: members.isEmpty ? null : _showIncomeSheet,
            icon: Icons.payments_outlined,
            assetIconPath: kBrandPulsoHogar,
            title: 'Cargar ingresos',
            subtitle: 'Base del reparto proporcional del mes.',
          ),
          const SizedBox(height: 10),
          SoftActionTile(
            onTap: members.isEmpty ? null : _showExpenseSheet,
            icon: Icons.add_card_outlined,
            assetIconPath: kBrandGastos,
            title: 'Cargar gasto común',
            subtitle: 'Quién pagó, monto, categoría y detalle.',
            color: kPrimaryMid,
          ),
          const SizedBox(height: 10),
          SoftActionTile(
            onTap: members.isEmpty
                ? null
                : () => _openInternal(ExpensesScreen(api: widget.api, members: members, month: month, onChanged: _refresh)),
            icon: Icons.list_alt_outlined,
            assetIconPath: kBrandGastos,
            title: 'Ver gastos del mes',
            subtitle: 'Revisar, corregir o eliminar movimientos.',
            color: kPrimaryDark,
          ),
        ],
      ),
    );
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'owner':
        return 'Propietario';
      case 'admin':
        return 'Administrador operativo';
      default:
        return 'Integrante';
    }
  }

  String _memberName(int id) => members.firstWhere((m) => m.id == id, orElse: () => Member(id: id, householdId: 0, name: 'Integrante $id', color: '#000000', role: 'member', isActive: true)).name;

  String _settlementText(SettlementSuggestion settlement) {
    final debtor = _memberName(settlement.debtorMemberId);
    final creditor = _memberName(settlement.creditorMemberId);
    return '$debtor le debe ${money.format(settlement.amount)} a $creditor';
  }

  Future<void> _showMonthlyBalanceDetail(MonthSummary s) async {
    final mine = s.members.where((item) => item.memberId == widget.session.member.id).toList();
    final mySummary = mine.isEmpty ? null : mine.first;
    final balance = mySummary?.balance ?? 0;
    final matchingSettlement = s.settlements.where((item) => item.debtorMemberId == widget.session.member.id).toList();
    final receivedPending = advancePayments.where((p) => p.receivedByMemberId == widget.session.member.id && p.status == 'pending').toList();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SheetFrame(
        title: 'Saldo provisorio del período',
        subtitle: 'Todavía no es una deuda formal. Se vuelve deuda al cerrar el período o generar deuda automática.',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppCard(
              padding: const EdgeInsets.all(14),
              color: kPrimarySoft.withOpacity(0.55),
              border: Border.all(color: kPrimary.withOpacity(0.16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detailLine('Te correspondía cubrir', money.format(mySummary?.shouldPay ?? 0)),
                  _detailLine('Pagaste en gastos comunes', money.format(mySummary?.actuallyPaid ?? 0)),
                  _detailLine(balance >= 0 ? 'Si cerrás hoy te deberían' : 'Si cerrás hoy deberías', money.format(balance.abs())),
                  if (periodSettings != null) _detailLine('Período', periodSettings!.label),
                ],
              ),
            ),
            if (_myAvailableCreditBalance > 0.01) ...[
              const SizedBox(height: 12),
              AppCard(
                padding: const EdgeInsets.all(14),
                color: kPrimary.withOpacity(0.08),
                border: Border.all(color: kPrimary.withOpacity(0.14)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: kPrimarySoft, borderRadius: BorderRadius.circular(14)),
                      child: const Icon(Icons.savings_outlined, color: kPrimary, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Saldo a favor confirmado', style: TextStyle(color: kInk, fontWeight: FontWeight.w900, fontSize: 15)),
                          const SizedBox(height: 4),
                          Text(
                            'Tenés ${money.format(_myAvailableCreditBalance)} disponibles como crédito. No forma parte del saldo provisorio del período hasta que lo apliques a una deuda.',
                            style: const TextStyle(color: kMuted, fontWeight: FontWeight.w700, height: 1.25),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Text('Pagos anticipados del período', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 6),
            Text(
              'Sirven para compensar antes del cierre. Quedan pendientes hasta que quien recibe confirme.',
              style: const TextStyle(color: kMuted, fontWeight: FontWeight.w600, height: 1.25),
            ),
            const SizedBox(height: 10),
            if (advancePayments.isEmpty)
              const Text('Todavía no hay pagos anticipados registrados.', style: TextStyle(color: kMuted))
            else
              for (final payment in advancePayments.take(6))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_paymentStatusIcon(payment.status), color: _paymentStatusColor(payment.status)),
                  title: Text('${_memberName(payment.paidByMemberId)} → ${_memberName(payment.receivedByMemberId)} · ${money.format(payment.amount)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(_paymentStatusLabel(payment)),
                  trailing: payment.status == 'pending' && payment.receivedByMemberId == widget.session.member.id
                      ? Wrap(
                          spacing: 4,
                          children: [
                            IconButton(tooltip: 'Confirmar', onPressed: () => _confirmAdvancePayment(payment.id), icon: const Icon(Icons.check_circle_outline, color: kSuccess)),
                            IconButton(tooltip: 'Rechazar', onPressed: () => _rejectAdvancePayment(payment.id), icon: const Icon(Icons.cancel_outlined, color: kDanger)),
                          ],
                        )
                      : null,
                ),
            const SizedBox(height: 12),
            if (balance < -0.01 && matchingSettlement.isNotEmpty)
              BigActionButton(
                icon: Icons.send_to_mobile_outlined,
                title: 'Registrar pago anticipado',
                subtitle: 'Quedará pendiente hasta confirmación de ${_memberName(matchingSettlement.first.creditorMemberId)}',
                onPressed: () => _showAdvancePaymentSheet(s),
              ),
            const SizedBox(height: 10),
            BigActionButton(
              outlined: true,
              icon: Icons.receipt_long_outlined,
              title: 'Ver deudas formales',
              subtitle: 'Manual, automática, abonos y saldos a favor',
              onPressed: members.isEmpty
                  ? null
                  : () => _openInternal(DebtsScreen(api: widget.api, members: members, month: month, currentMemberId: widget.session.member.id, onChanged: _refresh)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: kMuted, fontWeight: FontWeight.w700))),
          const SizedBox(width: 10),
          Flexible(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(color: kInk, fontWeight: FontWeight.w900))),
        ],
      ),
    );
  }

  IconData _paymentStatusIcon(String status) {
    switch (status) {
      case 'confirmed':
        return Icons.verified_outlined;
      case 'rejected':
        return Icons.cancel_outlined;
      case 'voided':
        return Icons.block_outlined;
      default:
        return Icons.hourglass_top_outlined;
    }
  }

  Color _paymentStatusColor(String status) {
    switch (status) {
      case 'confirmed':
        return kSuccess;
      case 'rejected':
      case 'voided':
        return kDanger;
      default:
        return kWarning;
    }
  }

  String _paymentStatusLabel(MonthlyAdvancePaymentItem payment) {
    switch (payment.status) {
      case 'confirmed':
        final extra = payment.creditAmount > 0 ? ' · excedente ${money.format(payment.creditAmount)} a favor' : '';
        return 'Confirmado · aplicado ${money.format(payment.appliedAmount)}$extra';
      case 'rejected':
        return 'Rechazado${payment.rejectedReason.isEmpty ? '' : ': ${payment.rejectedReason}'}';
      case 'voided':
        return 'Anulado';
      default:
        return 'Pendiente de confirmación';
    }
  }

  Future<void> _showAdvancePaymentSheet(MonthSummary s) async {
    final settlements = s.settlements.where((item) => item.debtorMemberId == widget.session.member.id).toList();
    if (settlements.isEmpty) return;
    SettlementSuggestion selected = settlements.first;
    final amountController = TextEditingController(text: selected.amount.toStringAsFixed(0));
    final noteController = TextEditingController(text: 'Transferencia contra saldo del período $month');
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (context, setModalState) => _SheetFrame(
          title: 'Pago anticipado',
          subtitle: 'No descuenta hasta que la otra persona confirme que recibió el pago.',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<SettlementSuggestion>(
                value: selected,
                items: settlements
                    .map((item) => DropdownMenuItem(value: item, child: Text('A ${_memberName(item.creditorMemberId)} · sugerido ${money.format(item.amount)}')))
                    .toList(),
                onChanged: (value) => setModalState(() {
                  selected = value ?? selected;
                  amountController.text = selected.amount.toStringAsFixed(0);
                }),
                decoration: const InputDecoration(labelText: 'A quién pagaste'),
              ),
              const SizedBox(height: 10),
              TextField(controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Monto transferido')), 
              const SizedBox(height: 10),
              TextField(controller: noteController, decoration: const InputDecoration(labelText: 'Nota opcional')),
              const SizedBox(height: 16),
              BigActionButton(
                icon: Icons.pending_actions_outlined,
                title: 'Registrar pendiente de confirmación',
                onPressed: () async {
                  try {
                    final raw = amountController.text.trim().replaceAll('.', '').replaceAll(',', '.');
                    await widget.api.createMonthlyAdvancePayment(
                      month: month,
                      receivedByMemberId: selected.creditorMemberId,
                      amount: double.parse(raw),
                      date: DateTime.now(),
                      note: noteController.text.trim(),
                    );
                    if (mounted) Navigator.pop(context);
                    if (mounted) Navigator.pop(context);
                    await _refresh();
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pago registrado. Falta confirmación del receptor.')));
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyMessage(e))));
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmAdvancePayment(int paymentId) async {
    try {
      await widget.api.confirmMonthlyAdvancePayment(paymentId);
      if (mounted) Navigator.pop(context);
      await _refresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pago anticipado confirmado.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyMessage(e))));
    }
  }

  Future<void> _rejectAdvancePayment(int paymentId) async {
    try {
      await widget.api.rejectMonthlyAdvancePayment(paymentId: paymentId, reason: 'Rechazado desde app');
      if (mounted) Navigator.pop(context);
      await _refresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pago anticipado rechazado.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyMessage(e))));
    }
  }

  Future<void> _showIncomeSheet() async {
    final incomeMembers = _participatingMembers;
    final controllers = {for (final m in incomeMembers) m.id: TextEditingController()};
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SheetFrame(
        title: 'Ingresos del mes',
        subtitle: 'Cargá lo que cobró cada integrante para calcular el reparto.',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final member in incomeMembers) ...[
              TextField(
                controller: controllers[member.id],
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'Ingreso de ${member.name}'),
              ),
              const SizedBox(height: 10),
            ],
            BigActionButton(
              onPressed: () async {
                for (final member in incomeMembers) {
                  final raw = controllers[member.id]!.text.trim().replaceAll('.', '').replaceAll(',', '.');
                  if (raw.isNotEmpty) {
                    await widget.api.saveIncome(memberId: member.id, month: month, amount: double.parse(raw));
                  }
                }
                if (mounted) Navigator.pop(context);
                await _refresh();
              },
              icon: Icons.save_outlined,
              title: 'Guardar ingresos',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showExpenseSheet() async {
    Member selected = members.first;
    final amountController = TextEditingController();
    final categoryController = TextEditingController(text: 'Comida');
    final descriptionController = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (context, setModalState) => _SheetFrame(
          title: 'Nuevo gasto común',
          subtitle: 'Cargá quién pagó y el monto. El reparto se calcula solo.',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<Member>(
                value: selected,
                items: members.map((m) => DropdownMenuItem(value: m, child: Text('Pagó ${m.name}'))).toList(),
                onChanged: (value) => setModalState(() => selected = value ?? selected),
                decoration: const InputDecoration(labelText: 'Quién pagó'),
              ),
              const SizedBox(height: 10),
              TextField(controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Monto')),
              const SizedBox(height: 10),
              TextField(controller: categoryController, decoration: const InputDecoration(labelText: 'Categoría')),
              const SizedBox(height: 10),
              TextField(controller: descriptionController, decoration: const InputDecoration(labelText: 'Descripción opcional')),
              const SizedBox(height: 16),
              BigActionButton(
                onPressed: () async {
                  final raw = amountController.text.trim().replaceAll('.', '').replaceAll(',', '.');
                  await widget.api.createExpense(
                    paidByMemberId: selected.id,
                    amount: double.parse(raw),
                    category: categoryController.text.trim(),
                    description: descriptionController.text.trim(),
                    date: DateTime.now(),
                  );
                  if (mounted) Navigator.pop(context);
                  await _refresh();
                },
                icon: Icons.save_outlined,
                title: 'Guardar gasto',
              )
            ],
          ),
        ),
      ),
    );
  }

  Color _colorFromHex(String hex) {
    final clean = hex.replaceAll('#', '');
    final parsed = int.tryParse(clean.length == 6 ? 'FF$clean' : clean, radix: 16);
    return Color(parsed ?? 0xFF6D28D9);
  }
}


class _ShortcutMetricCard extends StatelessWidget {
  final double width;
  final String label;
  final String value;
  final String hint;
  final IconData icon;
  final String? assetIconPath;
  final Color color;
  final VoidCallback? onTap;

  const _ShortcutMetricCard({
    required this.width,
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
    this.assetIconPath,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: color.withOpacity(0.16)),
              boxShadow: [
                BoxShadow(color: color.withOpacity(0.06), blurRadius: 18, offset: const Offset(0, 10)),
              ],
            ),
            child: Row(
              children: [
                assetIconPath == null
                    ? Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(16)),
                        child: Icon(icon, color: color, size: 23),
                      )
                    : BrandAssetIcon(
                        assetPath: assetIconPath!,
                        fallbackIcon: icon,
                        size: 34,
                        frameSize: 42,
                        borderRadius: 16,
                        padding: 3,
                        withShadow: false,
                        backgroundColor: Colors.white.withOpacity(0.88),
                        borderColor: color.withOpacity(0.14),
                        fallbackColor: color,
                      ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kMuted, fontSize: 12, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.4)),
                      const SizedBox(height: 2),
                      Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kMuted, fontSize: 11, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: color.withOpacity(0.65)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetFrame extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _SheetFrame({required this.title, required this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF8F5FF),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: EdgeInsets.only(left: 18, right: 18, top: 18, bottom: MediaQuery.of(context).viewInsets.bottom + 18),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 48, height: 5, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(99))),
            ),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: Colors.black54, height: 1.3)),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _MemberSummaryCard extends StatelessWidget {
  final MemberSummary member;
  final NumberFormat money;

  const _MemberSummaryCard({required this.member, required this.money});

  @override
  Widget build(BuildContext context) {
    final percent = (member.incomeShare * 100).toStringAsFixed(1);
    final balanceText = member.balance >= 0 ? 'Debe recibir ${money.format(member.balance)}' : 'Debe pagar ${money.format(member.balance.abs())}';
    final balanceColor = member.balance >= 0 ? kSuccess : kWarning;
    return AppCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: _colorFromHex(member.color),
            child: Text(member.name.isEmpty ? '?' : member.name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(member.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                Text(member.participates ? '$percent% del ingreso · pagó ${money.format(member.actuallyPaid)}' : 'No participa este mes · pagó ${money.format(member.actuallyPaid)}', style: const TextStyle(color: Colors.black54)),
                const SizedBox(height: 6),
                Text(balanceText, style: TextStyle(fontWeight: FontWeight.w900, color: balanceColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _colorFromHex(String hex) {
    final clean = hex.replaceAll('#', '');
    final parsed = int.tryParse(clean.length == 6 ? 'FF$clean' : clean, radix: 16);
    return Color(parsed ?? 0xFF6D28D9);
  }
}
