import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/local_personal_models.dart';
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

class _PersonalLocalScreenState extends State<PersonalLocalScreen> {
  static const double _desktopContentMaxWidth = 1280;
  final store = LocalPersonalStore();
  final money = NumberFormat.currency(locale: 'es_AR', symbol: r'$ ', decimalDigits: 0);
  bool loading = true;
  String? error;
  PersonalLocalSnapshot? snapshot;

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
    } catch (e) {
      if (mounted) setState(() => error = friendlyMessage(e));
    } finally {
      if (mounted) setState(() => loading = false);
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
