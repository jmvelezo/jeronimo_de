import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/app_models.dart';
import '../models/local_personal_models.dart';
import '../services/api_service.dart';
import '../services/local_personal_store.dart';
import '../services/friendly_messages.dart';
import '../widgets/app_card.dart';
import '../widgets/app_shell.dart';

class PersonalLocalScreen extends StatefulWidget {
  final bool allowSharedNavigation;

  const PersonalLocalScreen({super.key, this.allowSharedNavigation = false});

  @override
  State<PersonalLocalScreen> createState() => _PersonalLocalScreenState();
}

class _PersonalQuickAction {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _PersonalQuickAction(this.icon, this.label, this.onTap);
}

class _HouseholdImpact {
  final String month;
  final String memberName;
  final double householdIncome;
  final double householdSharedCost;
  final double householdPaidByMe;
  final double provisionalBalance;
  final double formalDebtIowe;
  final double formalDebtOwedToMe;
  final double creditAvailable;
  final double localPersonalExpense;
  final double estimatedAvailable;

  const _HouseholdImpact({
    required this.month,
    required this.memberName,
    required this.householdIncome,
    required this.householdSharedCost,
    required this.householdPaidByMe,
    required this.provisionalBalance,
    required this.formalDebtIowe,
    required this.formalDebtOwedToMe,
    required this.creditAvailable,
    required this.localPersonalExpense,
    required this.estimatedAvailable,
  });
}

class _PersonalLocalScreenState extends State<PersonalLocalScreen> {
  static const double _desktopContentMaxWidth = 1280;
  final store = LocalPersonalStore();
  final money = NumberFormat.currency(locale: 'es_AR', symbol: r'$ ', decimalDigits: 0);
  bool loading = true;
  bool householdImpactLoading = false;
  bool householdImpactAvailable = false;
  bool showHouseholdImpact = true;
  String? error;
  String? householdImpactError;
  PersonalLocalSnapshot? snapshot;
  _HouseholdImpact? householdImpact;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final loaded = await store.loadSnapshot();
      if (mounted) setState(() => snapshot = loaded);
      await _loadHouseholdImpact(loaded);
    } catch (e) {
      if (mounted) setState(() => error = friendlyMessage(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _loadHouseholdImpact(PersonalLocalSnapshot data) async {
    try {
      final api = await ApiService.load();
      if (api.token == null || api.token!.trim().isEmpty) {
        if (mounted) {
          setState(() {
            householdImpactAvailable = false;
            householdImpactLoading = false;
            householdImpactError = null;
            householdImpact = null;
          });
        }
        return;
      }
      if (mounted) {
        setState(() {
          householdImpactAvailable = true;
          householdImpactLoading = true;
          householdImpactError = null;
        });
      }

      final currentMember = await api.getMe();
      final activePeriod = await api.getActivePeriod();
      final activeMonth = activePeriod.activeMonth.isNotEmpty ? activePeriod.activeMonth : data.month;
      final results = await Future.wait<dynamic>([
        api.getSummary(activeMonth),
        api.getExpenses(activeMonth),
        api.getDebts(includeCancelled: false),
        api.getCreditBalances(activeOnly: true),
      ]);
      final summary = results[0] as MonthSummary;
      final sharedExpenses = results[1] as List<ExpenseItem>;
      final debts = results[2] as List<DebtItem>;
      final credits = results[3] as List<CreditBalanceItem>;
      MemberSummary? memberSummary;
      for (final item in summary.members) {
        if (item.memberId == currentMember.id) {
          memberSummary = item;
          break;
        }
      }
      final activeDebts = debts.where((item) => item.status != 'cancelled' && item.status != 'paid').toList();
      final formalDebtIowe = activeDebts
          .where((item) => item.debtorMemberId == currentMember.id)
          .fold(0.0, (sum, item) => sum + item.remainingAmount);
      final formalDebtOwedToMe = activeDebts
          .where((item) => item.creditorMemberId == currentMember.id)
          .fold(0.0, (sum, item) => sum + item.remainingAmount);
      final creditAvailable = credits
          .where((item) => item.ownerMemberId == currentMember.id && item.remainingAmount > 0)
          .fold(0.0, (sum, item) => sum + item.remainingAmount);
      final householdPaidByMe = sharedExpenses
          .where((item) => item.paidByMemberId == currentMember.id)
          .fold(0.0, (sum, item) => sum + item.amount);
      final householdIncome = memberSummary?.income ?? 0;
      final householdSharedCost = memberSummary?.shouldPay ?? 0;
      final estimatedAvailable = householdIncome - data.monthlyExpense - householdSharedCost;

      if (mounted) {
        setState(() {
          householdImpact = _HouseholdImpact(
            month: activeMonth,
            memberName: currentMember.name,
            householdIncome: householdIncome,
            householdSharedCost: householdSharedCost,
            householdPaidByMe: householdPaidByMe,
            provisionalBalance: memberSummary?.balance ?? 0,
            formalDebtIowe: formalDebtIowe,
            formalDebtOwedToMe: formalDebtOwedToMe,
            creditAvailable: creditAvailable,
            localPersonalExpense: data.monthlyExpense,
            estimatedAvailable: estimatedAvailable,
          );
          householdImpactLoading = false;
          householdImpactError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          householdImpactAvailable = true;
          householdImpactLoading = false;
          householdImpactError = 'No pude leer ahora el impacto del hogar compartido. Tu modo personal sigue funcionando.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = snapshot;
    return Scaffold(
      extendBody: true,
      body: AppGradientBackground(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 90),
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _desktopContentMaxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppHeroHeader(
                        eyebrow: 'Modo personal local',
                        title: data?.profile.isConfigured == true ? data!.profile.name : 'Mis cuentas',
                        subtitle: 'Tu espacio privado: cuentas, ingresos, gastos, presupuestos y deudas.',
                        icon: Icons.lock_person_rounded,
                        assetIconPath: kBrandNavPersonal,
                        trailing: IconButton(onPressed: _load, icon: const Icon(Icons.refresh, color: Colors.white)),
                      ),
                      const SizedBox(height: 14),
                      if (loading && data == null) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
                      if (error != null) ...[FriendlyError(message: error!), const SizedBox(height: 12)],
                      if (data != null) ...[
                        if (!data.profile.isConfigured) _setupProfileCard() else _profileHeader(data),
                        const SizedBox(height: 12),
                        _summaryCard(data),
                        const SizedBox(height: 12),
                        _householdImpactCard(data),
                        if (householdImpactAvailable || householdImpactLoading || householdImpactError != null) const SizedBox(height: 12),
                        _personalAiCard(data),
                        const SizedBox(height: 12),
                        _quickActionsCard(data),
                        const SizedBox(height: 12),
                        _accountsCard(data),
                        const SizedBox(height: 12),
                        _budgetsCard(data),
                        const SizedBox(height: 12),
                        _categoriesCard(data),
                        const SizedBox(height: 12),
                        _movementsCard(data),
                        const SizedBox(height: 12),
                        _tasksCard(data),
                        const SizedBox(height: 12),
                        _debtsCard(data),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: JeronimoBottomNav(
        currentIndex: kBottomNavPersonalIndex,
        allowSharedNavigation: widget.allowSharedNavigation,
        onDestinationSelected: _handleBottomNav,
      ),
    );
  }

  void _handleBottomNav(int index) {
    if (index == kBottomNavPersonalIndex) return;
    if (Navigator.of(context).canPop()) Navigator.of(context).pop(index);
  }

  Widget _profileHeader(PersonalLocalSnapshot data) {
    return AppCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: 27,
            backgroundColor: kPrimary.withOpacity(0.12),
            child: const Icon(Icons.person_outline, color: kPrimary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data.profile.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                Text('Mes privado · ${data.month}', style: const TextStyle(color: Colors.black54)),
                if (data.profile.hasApiKey)
                  Text('IA personal preparada: ${data.profile.aiProviderLabel}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          IconButton(onPressed: _showProfileSheet, icon: const Icon(Icons.tune_outlined)),
        ],
      ),
    );
  }

  Widget _setupProfileCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Configurar modo personal', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          const Text('Este espacio queda guardado en este dispositivo. Sirve para llevar tus finanzas privadas sin servidor.'),
          const SizedBox(height: 14),
          ElevatedButton.icon(onPressed: _showProfileSheet, icon: const Icon(Icons.person_add_alt), label: const Text('Crear perfil personal')),
        ],
      ),
    );
  }

  Widget _summaryCard(PersonalLocalSnapshot data) {
    final budgetColor = data.totalBudget <= 0 || data.budgetRemaining >= 0 ? Colors.green : Colors.red;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: 'Resumen privado', subtitle: 'Vista rápida de tu mes personal.', icon: Icons.insights_rounded),
          GridView(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 290,
              mainAxisExtent: 128,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              MetricTile(label: 'Ingresos', value: money.format(data.monthlyIncome), icon: Icons.arrow_downward, color: Colors.green),
              MetricTile(label: 'Gastos', value: money.format(data.monthlyExpense), icon: Icons.arrow_upward, color: Colors.deepOrange),
              MetricTile(label: 'Balance', value: money.format(data.monthlyBalance), icon: Icons.savings_outlined, color: data.monthlyBalance >= 0 ? Colors.green : Colors.red),
              MetricTile(label: 'Disponible', value: money.format(data.estimatedAvailable), icon: Icons.account_balance_wallet_outlined, color: kPrimary),
            ],
          ),
          const SizedBox(height: 14),
          _line('Presupuesto mensual', data.totalBudget <= 0 ? 'Sin definir' : money.format(data.totalBudget), Icons.pie_chart_outline, kPrimary),
          if (data.totalBudget > 0) _line('Margen de presupuesto', money.format(data.budgetRemaining), Icons.speed_outlined, budgetColor),
          if (data.profile.monthlySavingGoal > 0) _line('Meta de ahorro', money.format(data.profile.monthlySavingGoal), Icons.flag_outlined, Colors.indigo),
          if (data.savingsGoalGap > 0) _line('Falta para meta', money.format(data.savingsGoalGap), Icons.trending_up_outlined, Colors.deepOrange),
          if (data.pendingIowe > 0) _line('Debo personalmente', money.format(data.pendingIowe), Icons.warning_amber, Colors.red),
          if (data.pendingOwesMe > 0) _line('Me deben', money.format(data.pendingOwesMe), Icons.volunteer_activism_outlined, Colors.green),
        ],
      ),
    );
  }


  Widget _householdImpactCard(PersonalLocalSnapshot data) {
    if (!householdImpactAvailable && !householdImpactLoading && householdImpactError == null) {
      return const SizedBox.shrink();
    }
    final impact = householdImpact;
    return AppCard(
      border: Border.all(color: Colors.indigo.withOpacity(0.14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SectionTitle(
                  title: 'Impacto del hogar compartido',
                  subtitle: impact == null ? 'Lectura opcional del modo hogar, sin crear gastos personales.' : 'Lectura de ${impact.memberName} · ${impact.month}',
                  icon: Icons.home_work_outlined,
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() => showHouseholdImpact = !showHouseholdImpact),
                icon: Icon(showHouseholdImpact ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                label: Text(showHouseholdImpact ? 'Ocultar' : 'Mostrar'),
              ),
            ],
          ),
          if (!showHouseholdImpact)
            const Text('Bloque oculto. El modo personal local no fue modificado.', style: TextStyle(color: Colors.black54))
          else if (householdImpactLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: LinearProgressIndicator(),
            )
          else if (householdImpactError != null)
            Text(householdImpactError!, style: const TextStyle(color: Colors.black54))
          else if (impact != null) ...[
            const Text(
              'Solo lectura: no crea gastos personales ni duplica movimientos.',
              style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            _line('Ingreso declarado en Casa', money.format(impact.householdIncome), Icons.payments_outlined, Colors.green),
            _line('Costo proporcional hogar', money.format(impact.householdSharedCost), Icons.pie_chart_outline, kPrimary),
            _line('Pagado por mí en Casa', money.format(impact.householdPaidByMe), Icons.receipt_long_outlined, Colors.indigo),
            _line('Saldo provisorio con Casa', _householdBalanceText(impact.provisionalBalance), Icons.compare_arrows_rounded, _balanceColor(impact.provisionalBalance)),
            _line('Deudas formales que debo', money.format(impact.formalDebtIowe), Icons.warning_amber_rounded, impact.formalDebtIowe > 0 ? Colors.red : Colors.black45),
            _line('Deudas formales a mi favor', money.format(impact.formalDebtOwedToMe), Icons.volunteer_activism_outlined, impact.formalDebtOwedToMe > 0 ? Colors.green : Colors.black45),
            _line('Crédito disponible', money.format(impact.creditAvailable), Icons.savings_outlined, impact.creditAvailable > 0 ? Colors.green : Colors.black45),
            const Divider(height: 22),
            _line('Gastos personales locales', money.format(impact.localPersonalExpense), Icons.lock_person_outlined, Colors.deepOrange),
            _line('Disponible estimado', money.format(impact.estimatedAvailable), Icons.account_balance_wallet_outlined, impact.estimatedAvailable >= 0 ? Colors.green : Colors.red),
            const SizedBox(height: 8),
            const Text(
              'El disponible estimado usa: ingreso de Casa - gastos personales locales - costo proporcional del hogar. No reemplaza el balance completo de la casa.',
              style: TextStyle(color: Colors.black54, height: 1.25),
            ),
            const SizedBox(height: 12),
            if (data.activeAccounts.isEmpty)
              const Text(
                'Para registrar este impacto en Personal, primero agregá una cuenta personal.',
                style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w600),
              )
            else if (impact.householdSharedCost <= 0 && impact.householdPaidByMe <= 0)
              const Text(
                'No hay montos del hogar para convertir en gasto personal en este período.',
                style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w600),
              )
            else
              ElevatedButton.icon(
                onPressed: () => _showHouseholdImpactSyncSheet(data, impact),
                icon: const Icon(Icons.add_link_outlined),
                label: const Text('Agregar impacto del hogar a Personal'),
              ),
          ],
        ],
      ),
    );
  }

  String _householdBalanceText(double value) {
    if (value > 0) return 'Te deben ${money.format(value)}';
    if (value < 0) return 'Debés ${money.format(value.abs())}';
    return 'Equilibrado';
  }

  Color _balanceColor(double value) {
    if (value > 0) return Colors.green;
    if (value < 0) return Colors.red;
    return Colors.black54;
  }

  Widget _personalAiCard(PersonalLocalSnapshot data) {
    final latest = data.latestAiReport;
    return AppCard(
      border: Border.all(color: kPrimary.withOpacity(0.14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: SectionTitle(
                  title: 'IA personal privada',
                  subtitle: 'Consejos sobre tus cuentas locales. No se suben al hogar compartido.',
                  icon: Icons.auto_awesome_outlined,
                ),
              ),
              TextButton.icon(onPressed: () => _generatePersonalAi(data), icon: const Icon(Icons.insights), label: const Text('Analizar')),
            ],
          ),
          if (latest == null)
            const Text('Todavía no hay informes personales. Podés generar uno con tus ingresos, gastos, presupuestos, deudas y tareas privadas.', style: TextStyle(color: Colors.black54))
          else ...[
            Text(latest.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(latest.content, style: const TextStyle(height: 1.34)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(latest.generatedWithApi ? 'API IA' : latest.modelLabel)),
                const Chip(label: Text('Privado')),
                const Chip(label: Text('Datos locales')),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _generatePersonalAi(PersonalLocalSnapshot data) async {
    try {
      await store.generatePersonalAiReport(focus: 'ahorro, gastos, deudas, tareas y presupuesto');
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe personal generado.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyMessage(e))));
      }
    }
  }

  Widget _quickActionsCard(PersonalLocalSnapshot data) {
    final hasAccounts = data.activeAccounts.isNotEmpty;
    final actions = <_PersonalQuickAction>[
      _PersonalQuickAction(Icons.account_balance_wallet_outlined, 'Cuenta', _showAccountSheet),
      _PersonalQuickAction(Icons.payments_outlined, 'Ingreso', hasAccounts ? _showIncomeSheet : null),
      _PersonalQuickAction(Icons.shopping_bag_outlined, 'Gasto', hasAccounts ? _showExpenseSheet : null),
      _PersonalQuickAction(Icons.pie_chart_outline, 'Presupuesto', data.activeExpenseCategories.isNotEmpty ? _showBudgetSheet : null),
      _PersonalQuickAction(Icons.category_outlined, 'Categoría', _showCategorySheet),
      _PersonalQuickAction(Icons.receipt_long_outlined, 'Deuda', _showDebtSheet),
      _PersonalQuickAction(Icons.task_alt_outlined, 'Tarea', _showTaskSheet),
      _PersonalQuickAction(Icons.auto_awesome_outlined, 'IA', () => _generatePersonalAi(data)),
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: 'Acciones rápidas', subtitle: 'Lo cotidiano, sin menús raros.', icon: Icons.add_circle_outline),
          GridView.builder(
            itemCount: actions.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 230,
              mainAxisExtent: 92,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemBuilder: (context, index) {
              final action = actions[index];
              return _smallAction(action.icon, action.label, action.onTap);
            },
          ),
          if (!hasAccounts) ...[
            const SizedBox(height: 12),
            const Text('Primero agregá una cuenta personal: efectivo, banco, billetera o tarjeta.', style: TextStyle(color: Colors.black54)),
          ],
        ],
      ),
    );
  }

  Widget _smallAction(IconData icon, String label, VoidCallback? onTap) {
    final enabled = onTap != null;
    final iconColor = enabled ? kPrimary : Colors.black38;
    final textColor = enabled ? kInk : Colors.black38;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: enabled ? kPrimary.withOpacity(0.08) : Colors.grey.withOpacity(0.09),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: enabled ? kPrimary.withOpacity(0.14) : Colors.grey.withOpacity(0.18)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 145;
            final iconBox = Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: enabled ? Colors.white.withOpacity(0.78) : Colors.white.withOpacity(0.55),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            );
            final labelText = Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: compact ? TextAlign.center : TextAlign.start,
              style: TextStyle(fontWeight: FontWeight.w900, color: textColor),
            );

            if (compact) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  iconBox,
                  const SizedBox(height: 7),
                  labelText,
                ],
              );
            }

            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                iconBox,
                const SizedBox(width: 10),
                Flexible(child: labelText),
              ],
            );
          },
        ),
      ),
    );
  }


  Widget _tasksCard(PersonalLocalSnapshot data) {
    final tasks = data.pendingTasks;
    final color = data.overdueTasksCount > 0 ? Colors.red : (data.dueSoonTasksCount > 0 ? Colors.orange : kPrimary);
    return AppCard(
      border: Border.all(color: color.withOpacity(0.14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: SectionTitle(title: 'Tareas personales', subtitle: 'Pagos, vencimientos y pendientes privados.', icon: Icons.task_alt_outlined)),
              TextButton.icon(onPressed: _showTaskSheet, icon: const Icon(Icons.add), label: const Text('Nueva')),
            ],
          ),
          if (tasks.isEmpty)
            const Text('No tenés tareas personales pendientes.', style: TextStyle(color: Colors.black54))
          else ...[
            Text('${tasks.length} pendiente(s) · ${data.overdueTasksCount} vencida(s) · ${data.dueSoonTasksCount} próxima(s)', style: TextStyle(color: color, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            for (final task in tasks.take(8))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(task.isOverdue ? Icons.warning_amber_rounded : Icons.task_alt_outlined, color: task.isOverdue ? Colors.red : kPrimary),
                title: Text(task.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                subtitle: Text([
                  if (task.dueDate != null) 'Vence ${task.dueDate}',
                  _priorityText(task.priority),
                  if (task.repeatRule == 'monthly') 'mensual',
                ].join(' · ')),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(onPressed: () => _completeTask(task), icon: const Icon(Icons.check_circle_outline), tooltip: 'Completar'),
                    IconButton(onPressed: () => _cancelTask(task), icon: const Icon(Icons.close_outlined), tooltip: 'Cancelar'),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _accountsCard(PersonalLocalSnapshot data) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: 'Cuentas personales', subtitle: 'Saldo estimado según movimientos registrados.', icon: Icons.account_balance_wallet_outlined),
          if (data.accounts.isEmpty) const EmptyState(icon: Icons.account_balance_wallet_outlined, title: 'Sin cuentas', message: 'Agregá efectivo, banco, billetera o tarjeta para empezar.'),
          for (final account in data.accounts)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(account.isActive ? Icons.account_balance_wallet_outlined : Icons.visibility_off_outlined, color: account.isActive ? kPrimary : Colors.black38),
              title: Text(account.name, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('${account.type}${account.isActive ? '' : ' · inactiva'}'),
              trailing: Text(money.format(data.balanceForAccount(account.id)), style: const TextStyle(fontWeight: FontWeight.w900)),
              onLongPress: account.isActive ? () => _deactivateAccount(account) : null,
            ),
        ],
      ),
    );
  }

  Widget _budgetsCard(PersonalLocalSnapshot data) {
    final statuses = data.budgetStatuses.where((item) => item.hasBudget || item.spent > 0).toList();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: SectionTitle(title: 'Presupuestos', subtitle: 'Control por categoría del mes actual.', icon: Icons.pie_chart_outline)),
              TextButton.icon(onPressed: _showBudgetSheet, icon: const Icon(Icons.add), label: const Text('Definir')),
            ],
          ),
          if (statuses.isEmpty) const Text('Todavía no hay presupuestos ni gastos por categoría este mes.', style: TextStyle(color: Colors.black54)),
          for (final item in statuses) _budgetRow(item),
        ],
      ),
    );
  }

  Widget _budgetRow(BudgetStatus item) {
    final color = item.exceeded ? Colors.red : kPrimary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(item.category.name, style: const TextStyle(fontWeight: FontWeight.w900))),
              Text(item.hasBudget ? '${money.format(item.spent)} / ${money.format(item.limit)}' : money.format(item.spent), style: TextStyle(fontWeight: FontWeight.w800, color: color)),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: item.hasBudget ? item.progress : 0, minHeight: 8, borderRadius: BorderRadius.circular(20), color: color, backgroundColor: Colors.black.withOpacity(0.06)),
          const SizedBox(height: 3),
          if (item.hasBudget)
            Text(item.exceeded ? 'Te pasaste por ${money.format(item.spent - item.limit)}' : 'Disponible: ${money.format(item.remaining)}', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _categoriesCard(PersonalLocalSnapshot data) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: SectionTitle(title: 'Categorías', subtitle: 'Usalas para ordenar gastos y presupuestos.', icon: Icons.category_outlined)),
              TextButton.icon(onPressed: _showCategorySheet, icon: const Icon(Icons.add), label: const Text('Nueva')),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: data.categories.map((category) {
              return FilterChip(
                selected: category.isActive,
                label: Text(category.name),
                onSelected: category.isSystem ? null : (value) async {
                  await store.toggleCategory(category.id, value);
                  await _load();
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _movementsCard(PersonalLocalSnapshot data) {
    final expenses = data.expenses.where((item) => item.month == data.month).toList().reversed.take(8).toList();
    final incomes = data.incomes.where((item) => item.month == data.month).toList().reversed.take(5).toList();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: 'Movimientos del mes', subtitle: 'Ingresos y gastos privados recientes.', icon: Icons.swap_vert_rounded),
          if (expenses.isEmpty && incomes.isEmpty) const Text('Todavía no hay movimientos personales este mes.', style: TextStyle(color: Colors.black54)),
          for (final income in incomes)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.arrow_downward, color: Colors.green),
              title: Text(income.source, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(income.note.isEmpty ? income.date : '${income.note} · ${income.date}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(money.format(income.amount), style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w900)),
                  IconButton(icon: const Icon(Icons.delete_outline, size: 20), onPressed: () => _deleteIncome(income)),
                ],
              ),
            ),
          for (final expense in expenses)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.arrow_upward, color: Colors.deepOrange),
              title: Text(expense.category, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(expense.description.isEmpty ? expense.date : '${expense.description} · ${expense.date}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(money.format(expense.amount), style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.w900)),
                  IconButton(icon: const Icon(Icons.delete_outline, size: 20), onPressed: () => _deleteExpense(expense)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _debtsCard(PersonalLocalSnapshot data) {
    final debts = data.activeDebts;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: SectionTitle(title: 'Deudas personales', subtitle: 'Préstamos, cuotas y saldos privados.', icon: Icons.receipt_long_outlined)),
              TextButton.icon(onPressed: _showDebtSheet, icon: const Icon(Icons.add), label: const Text('Nueva')),
            ],
          ),
          if (debts.isEmpty) const Text('No hay deudas personales activas.', style: TextStyle(color: Colors.black54)),
          for (final debt in debts)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(debt.direction == 'i_owe' ? Icons.call_made : Icons.call_received, color: debt.direction == 'i_owe' ? Colors.red : Colors.green),
              title: Text(debt.title, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('${debt.counterparty.isEmpty ? 'Sin persona' : debt.counterparty}${debt.dueDate == null ? '' : ' · vence ${debt.dueDate}'}'),
              trailing: Text(money.format(debt.remainingAmount), style: const TextStyle(fontWeight: FontWeight.w900)),
              onTap: () => _showDebtPaymentSheet(debt),
              onLongPress: () => _cancelDebt(debt),
            ),
        ],
      ),
    );
  }

  Widget _line(String label, String value, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Future<void> _showProfileSheet() async {
    final current = snapshot?.profile ?? const PersonalProfile(name: '');
    final nameController = TextEditingController(text: current.name);
    final savingController = TextEditingController(text: current.monthlySavingGoal == 0 ? '' : current.monthlySavingGoal.toStringAsFixed(0));
    final providerController = TextEditingController(text: current.aiProviderLabel);
    final apiKeyController = TextEditingController();
    bool aiEnabled = current.localAiEnabled;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(left: 18, right: 18, top: 18, bottom: MediaQuery.of(context).viewInsets.bottom + 18),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Configuración privada', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),
                TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Tu nombre')),
                const SizedBox(height: 10),
                TextField(controller: savingController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Meta mensual de ahorro')),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: aiEnabled,
                  onChanged: (value) => setModalState(() => aiEnabled = value),
                  title: const Text('Preparar IA personal'),
                  subtitle: const Text('La clave queda guardada solo en este dispositivo.'),
                ),
                if (aiEnabled) ...[
                  TextField(controller: providerController, decoration: const InputDecoration(labelText: 'Nombre del proveedor IA')),
                  const SizedBox(height: 10),
                  TextField(controller: apiKeyController, obscureText: true, decoration: const InputDecoration(labelText: 'API key opcional')),
                ],
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () async {
                    final profile = current.copyWith(
                      name: nameController.text.trim(),
                      monthlySavingGoal: _parseMoney(savingController.text),
                      localAiEnabled: aiEnabled,
                      aiProviderLabel: providerController.text.trim().isEmpty ? 'API IA personal' : providerController.text.trim(),
                      hasApiKey: current.hasApiKey || apiKeyController.text.trim().isNotEmpty,
                    );
                    await store.saveProfile(profile, apiKey: apiKeyController.text.trim().isEmpty ? null : apiKeyController.text.trim());
                    if (mounted) Navigator.pop(context);
                    await _load();
                  },
                  child: const Text('Guardar configuración'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showHouseholdImpactSyncSheet(PersonalLocalSnapshot data, _HouseholdImpact impact) async {
    if (data.activeAccounts.isEmpty) return;
    final options = <String, double>{
      'proportional_cost': impact.householdSharedCost,
      'paid_by_me': impact.householdPaidByMe,
    };
    String selectedType = options.entries.firstWhere((entry) => entry.value > 0, orElse: () => options.entries.first).key;
    PersonalAccount selectedAccount = data.activeAccounts.first;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => StatefulBuilder(
        builder: (context, setModalState) {
          final amount = options[selectedType] ?? 0;
          final duplicate = _hasHouseholdSyncedExpense(data, selectedType, impact.month);
          final description = _householdSyncDescription(selectedType, impact);
          final canSave = amount > 0 && !duplicate;

          return Padding(
            padding: EdgeInsets.only(left: 18, right: 18, top: 18, bottom: MediaQuery.of(context).viewInsets.bottom + 18),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Agregar impacto del hogar a Personal', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text(
                    'Esto crea un gasto personal local y no modifica los gastos comunes del hogar. Elegí una sola lectura para evitar duplicados.',
                    style: TextStyle(color: Colors.black54, height: 1.25),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<PersonalAccount>(
                    value: selectedAccount,
                    items: data.activeAccounts.map((item) => DropdownMenuItem(value: item, child: Text(item.name))).toList(),
                    onChanged: (value) => setModalState(() => selectedAccount = value ?? selectedAccount),
                    decoration: const InputDecoration(labelText: 'Cuenta personal'),
                  ),
                  const SizedBox(height: 12),
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    value: 'proportional_cost',
                    groupValue: selectedType,
                    onChanged: impact.householdSharedCost > 0 ? (value) => setModalState(() => selectedType = value ?? selectedType) : null,
                    title: Text('Costo proporcional del hogar · ${money.format(impact.householdSharedCost)}'),
                    subtitle: const Text('Lo que te correspondía pagar del hogar. Útil para medir tu costo mensual real.'),
                  ),
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    value: 'paid_by_me',
                    groupValue: selectedType,
                    onChanged: impact.householdPaidByMe > 0 ? (value) => setModalState(() => selectedType = value ?? selectedType) : null,
                    title: Text('Pagos reales hechos por mí · ${money.format(impact.householdPaidByMe)}'),
                    subtitle: const Text('Lo que salió efectivamente de tus cuentas para gastos comunes.'),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: kPrimary.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: kPrimary.withOpacity(0.12)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Se registrará: ${money.format(amount)}', style: const TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        Text(description, style: const TextStyle(color: Colors.black54)),
                        const SizedBox(height: 4),
                        const Text('Categoría sugerida: Hogar compartido', style: TextStyle(color: Colors.black54)),
                      ],
                    ),
                  ),
                  if (duplicate) ...[
                    const SizedBox(height: 10),
                    const Text(
                      'Ya existe un gasto personal creado desde el hogar para este período y este tipo de impacto. Eliminá ese movimiento si querés volver a crearlo.',
                      style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('No sincronizar'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: canSave
                              ? () async {
                                  await _createHouseholdImpactExpense(data, impact, selectedAccount, selectedType, amount, description);
                                  if (mounted) Navigator.pop(context);
                                  await _load();
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impacto del hogar agregado a Personal.')));
                                  }
                                }
                              : null,
                          child: const Text('Guardar gasto'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  bool _hasHouseholdSyncedExpense(PersonalLocalSnapshot data, String sourceType, String sourceMonth) {
    return data.expenses.any((item) => item.source == 'household' && item.sourceType == sourceType && item.sourceMonth == sourceMonth);
  }

  String _householdSyncDescription(String sourceType, _HouseholdImpact impact) {
    if (sourceType == 'paid_by_me') {
      return 'Pagos reales hechos por mí en la casa · ${impact.month}';
    }
    return 'Costo proporcional del hogar · ${impact.month}';
  }

  DateTime _personalExpenseDateFor(PersonalLocalSnapshot data) {
    final parts = data.month.split('-');
    if (parts.length == 2) {
      final year = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      if (year != null && month != null && month >= 1 && month <= 12) {
        return DateTime(year, month, 1);
      }
    }
    return DateTime.now();
  }

  Future<PersonalCategory> _householdSharedCategory(PersonalLocalSnapshot data) async {
    for (final category in data.categories) {
      final name = category.name.toLowerCase().trim();
      if (category.id == 'hogar_compartido' || name == 'hogar compartido') return category;
    }
    return store.createCategory(name: 'Hogar compartido');
  }

  Future<void> _createHouseholdImpactExpense(
    PersonalLocalSnapshot data,
    _HouseholdImpact impact,
    PersonalAccount account,
    String sourceType,
    double amount,
    String description,
  ) async {
    if (amount <= 0) return;
    final category = await _householdSharedCategory(data);
    await store.createExpense(
      accountId: account.id,
      amount: amount,
      category: category,
      description: description,
      date: _personalExpenseDateFor(data),
      source: 'household',
      sourceMonth: impact.month,
      sourceType: sourceType,
    );
  }

  Future<void> _showAccountSheet() async {
    final nameController = TextEditingController(text: 'Efectivo');
    final typeController = TextEditingController(text: 'efectivo');
    final balanceController = TextEditingController();
    await _simpleSheet(
      title: 'Nueva cuenta personal',
      children: [
        TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Nombre de la cuenta')),
        const SizedBox(height: 10),
        TextField(controller: typeController, decoration: const InputDecoration(labelText: 'Tipo: banco, efectivo, billetera, tarjeta')),
        const SizedBox(height: 10),
        TextField(controller: balanceController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Saldo inicial')),
      ],
      onSave: () async {
        await store.createAccount(name: nameController.text, type: typeController.text, initialBalance: _parseMoney(balanceController.text));
      },
    );
  }

  Future<void> _showCategorySheet() async {
    final nameController = TextEditingController();
    await _simpleSheet(
      title: 'Nueva categoría',
      children: [
        TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Nombre de la categoría')),
        const SizedBox(height: 8),
        const Text('Se usará para gastos y presupuestos personales.', style: TextStyle(color: Colors.black54)),
      ],
      onSave: () async {
        await store.createCategory(name: nameController.text);
      },
    );
  }

  Future<void> _showBudgetSheet() async {
    final data = snapshot!;
    PersonalCategory selected = data.activeExpenseCategories.isNotEmpty ? data.activeExpenseCategories.first : defaultPersonalCategories().first;
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(left: 18, right: 18, top: 18, bottom: MediaQuery.of(context).viewInsets.bottom + 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Presupuesto personal', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              DropdownButtonFormField<PersonalCategory>(
                value: selected,
                items: data.activeExpenseCategories.map((item) => DropdownMenuItem(value: item, child: Text(item.name))).toList(),
                onChanged: (value) => setModalState(() => selected = value ?? selected),
                decoration: const InputDecoration(labelText: 'Categoría'),
              ),
              const SizedBox(height: 10),
              TextField(controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Límite para este mes')),
              const SizedBox(height: 10),
              TextField(controller: noteController, decoration: const InputDecoration(labelText: 'Nota opcional')),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  await store.upsertBudget(categoryId: selected.id, month: data.month, amount: _parseMoney(amountController.text), note: noteController.text);
                  if (mounted) Navigator.pop(context);
                  await _load();
                },
                child: const Text('Guardar presupuesto'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showIncomeSheet() async {
    final data = snapshot!;
    PersonalAccount selected = data.activeAccounts.first;
    final amountController = TextEditingController();
    final sourceController = TextEditingController(text: 'Salario');
    final noteController = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(left: 18, right: 18, top: 18, bottom: MediaQuery.of(context).viewInsets.bottom + 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Ingreso personal', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              DropdownButtonFormField<PersonalAccount>(
                value: selected,
                items: data.activeAccounts.map((item) => DropdownMenuItem(value: item, child: Text(item.name))).toList(),
                onChanged: (value) => setModalState(() => selected = value ?? selected),
                decoration: const InputDecoration(labelText: 'Cuenta'),
              ),
              const SizedBox(height: 10),
              TextField(controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Monto')),
              const SizedBox(height: 10),
              TextField(controller: sourceController, decoration: const InputDecoration(labelText: 'Origen')),
              const SizedBox(height: 10),
              TextField(controller: noteController, decoration: const InputDecoration(labelText: 'Nota opcional')),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  await store.createIncome(accountId: selected.id, amount: _parseMoney(amountController.text), source: sourceController.text, note: noteController.text);
                  if (mounted) Navigator.pop(context);
                  await _load();
                },
                child: const Text('Guardar ingreso'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showExpenseSheet() async {
    final data = snapshot!;
    PersonalAccount selectedAccount = data.activeAccounts.first;
    PersonalCategory selectedCategory = data.activeExpenseCategories.isNotEmpty ? data.activeExpenseCategories.first : defaultPersonalCategories().first;
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(left: 18, right: 18, top: 18, bottom: MediaQuery.of(context).viewInsets.bottom + 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Gasto personal', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              DropdownButtonFormField<PersonalAccount>(
                value: selectedAccount,
                items: data.activeAccounts.map((item) => DropdownMenuItem(value: item, child: Text(item.name))).toList(),
                onChanged: (value) => setModalState(() => selectedAccount = value ?? selectedAccount),
                decoration: const InputDecoration(labelText: 'Cuenta'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<PersonalCategory>(
                value: selectedCategory,
                items: data.activeExpenseCategories.map((item) => DropdownMenuItem(value: item, child: Text(item.name))).toList(),
                onChanged: (value) => setModalState(() => selectedCategory = value ?? selectedCategory),
                decoration: const InputDecoration(labelText: 'Categoría'),
              ),
              const SizedBox(height: 10),
              TextField(controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Monto')),
              const SizedBox(height: 10),
              TextField(controller: descriptionController, decoration: const InputDecoration(labelText: 'Descripción')),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  await store.createExpense(accountId: selectedAccount.id, amount: _parseMoney(amountController.text), category: selectedCategory, description: descriptionController.text);
                  if (mounted) Navigator.pop(context);
                  await _load();
                },
                child: const Text('Guardar gasto'),
              ),
            ],
          ),
        ),
      ),
    );
  }


  Future<void> _showTaskSheet() async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final dueController = TextEditingController();
    final alertController = TextEditingController();
    String priority = 'normal';
    bool monthly = false;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(left: 18, right: 18, top: 18, bottom: MediaQuery.of(context).viewInsets.bottom + 18),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tarea personal', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),
                TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Título')),
                const SizedBox(height: 10),
                TextField(controller: descriptionController, decoration: const InputDecoration(labelText: 'Descripción opcional')),
                const SizedBox(height: 10),
                TextField(controller: dueController, decoration: const InputDecoration(labelText: 'Vencimiento opcional AAAA-MM-DD')),
                const SizedBox(height: 10),
                TextField(controller: alertController, decoration: const InputDecoration(labelText: 'Alerta opcional AAAA-MM-DD')),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: priority,
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('Baja')),
                    DropdownMenuItem(value: 'normal', child: Text('Normal')),
                    DropdownMenuItem(value: 'high', child: Text('Alta')),
                    DropdownMenuItem(value: 'urgent', child: Text('Urgente')),
                  ],
                  onChanged: (value) => setModalState(() => priority = value ?? 'normal'),
                  decoration: const InputDecoration(labelText: 'Prioridad'),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: monthly,
                  onChanged: (value) => setModalState(() => monthly = value),
                  title: const Text('Repetir mensualmente', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: const Text('Al completarla se crea el pendiente del mes siguiente.'),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () async {
                    await store.createTask(
                      title: titleController.text,
                      description: descriptionController.text,
                      dueDate: dueController.text.trim().isEmpty ? null : dueController.text.trim(),
                      alertDate: alertController.text.trim().isEmpty ? null : alertController.text.trim(),
                      priority: priority,
                      repeatRule: monthly ? 'monthly' : 'none',
                    );
                    if (mounted) Navigator.pop(context);
                    await _load();
                  },
                  child: const Text('Guardar tarea'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showDebtSheet() async {
    final titleController = TextEditingController(text: 'Deuda personal');
    final personController = TextEditingController();
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    final dueController = TextEditingController();
    String direction = 'i_owe';
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(left: 18, right: 18, top: 18, bottom: MediaQuery.of(context).viewInsets.bottom + 18),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Deuda personal', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),
                TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Título')),
                const SizedBox(height: 10),
                TextField(controller: personController, decoration: const InputDecoration(labelText: 'Con quién')),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: direction,
                  items: const [
                    DropdownMenuItem(value: 'i_owe', child: Text('Yo debo')),
                    DropdownMenuItem(value: 'owes_me', child: Text('Me deben')),
                  ],
                  onChanged: (value) => setModalState(() => direction = value ?? 'i_owe'),
                  decoration: const InputDecoration(labelText: 'Tipo'),
                ),
                const SizedBox(height: 10),
                TextField(controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Monto')),
                const SizedBox(height: 10),
                TextField(controller: dueController, decoration: const InputDecoration(labelText: 'Vencimiento opcional AAAA-MM-DD')),
                const SizedBox(height: 10),
                TextField(controller: noteController, decoration: const InputDecoration(labelText: 'Nota opcional')),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () async {
                    await store.createDebt(
                      title: titleController.text,
                      counterparty: personController.text,
                      direction: direction,
                      amount: _parseMoney(amountController.text),
                      dueDate: dueController.text.trim().isEmpty ? null : dueController.text.trim(),
                      note: noteController.text,
                    );
                    if (mounted) Navigator.pop(context);
                    await _load();
                  },
                  child: const Text('Guardar deuda'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showDebtPaymentSheet(PersonalDebt debt) async {
    final amountController = TextEditingController();
    await _simpleSheet(
      title: 'Abono a ${debt.title}',
      children: [
        Text('Pendiente: ${money.format(debt.remainingAmount)}'),
        const SizedBox(height: 10),
        TextField(controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Monto abonado')),
        const SizedBox(height: 8),
        const Text('Toque largo sobre una deuda permite cancelarla.', style: TextStyle(color: Colors.black54)),
      ],
      onSave: () async {
        await store.registerDebtPayment(debtId: debt.id, amount: _parseMoney(amountController.text));
      },
    );
  }

  Future<void> _simpleSheet({required String title, required List<Widget> children, required Future<void> Function() onSave}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => Padding(
        padding: EdgeInsets.only(left: 18, right: 18, top: 18, bottom: MediaQuery.of(context).viewInsets.bottom + 18),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              ...children,
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  await onSave();
                  if (mounted) Navigator.pop(context);
                  await _load();
                },
                child: const Text('Guardar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteIncome(PersonalIncome income) async {
    await store.deleteIncome(income.id);
    await _load();
  }

  Future<void> _deleteExpense(PersonalExpense expense) async {
    await store.deleteExpense(expense.id);
    await _load();
  }

  Future<void> _deactivateAccount(PersonalAccount account) async {
    await store.deactivateAccount(account.id);
    await _load();
  }

  Future<void> _cancelDebt(PersonalDebt debt) async {
    await store.cancelDebt(debt.id);
    await _load();
  }

  Future<void> _completeTask(PersonalTask task) async {
    await store.completeTask(task.id);
    await _load();
  }

  Future<void> _cancelTask(PersonalTask task) async {
    await store.cancelTask(task.id);
    await _load();
  }

  String _priorityText(String value) {
    switch (value) {
      case 'low':
        return 'baja';
      case 'high':
        return 'alta';
      case 'urgent':
        return 'urgente';
      default:
        return 'normal';
    }
  }

  double _parseMoney(String raw) {
    final normalized = raw.trim().replaceAll('.', '').replaceAll(',', '.');
    if (normalized.isEmpty) return 0;
    return double.tryParse(normalized) ?? 0;
  }
}
