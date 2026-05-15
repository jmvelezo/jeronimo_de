import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/app_models.dart';
import '../services/api_service.dart';
import '../services/friendly_messages.dart';
import '../widgets/app_card.dart';
import '../widgets/app_shell.dart';

class TasksScreen extends StatefulWidget {
  final ApiService api;
  final List<Member> members;
  final VoidCallback? onChanged;

  const TasksScreen({super.key, required this.api, required this.members, this.onChanged});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final money = NumberFormat.currency(locale: 'es_AR', symbol: r'$ ', decimalDigits: 0);
  bool loading = true;
  bool includeDone = false;
  bool aiLoading = false;
  String? error;
  String selectedFilter = 'all';
  List<HouseholdTaskItem> tasks = [];
  HouseholdTaskSummary? summary;

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
      final loadedTasks = await widget.api.getTasks(includeDone: includeDone);
      final loadedSummary = await widget.api.getTaskSummary();
      if (mounted) {
        setState(() {
          tasks = loadedTasks;
          summary = loadedSummary;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = friendlyMessage(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  List<HouseholdTaskItem> get filteredTasks {
    if (selectedFilter == 'all') return tasks;
    return tasks.where((task) => _kindKey(task) == selectedFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final visibleTasks = filteredTasks;
    return Scaffold(
      extendBody: true,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateTaskSheet,
        icon: const Icon(Icons.add_task_outlined),
        label: const Text('Nueva tarea'),
      ),
      body: AppGradientBackground(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 90),
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            children: [
              AppHeroHeader(
                eyebrow: 'Pendientes comunes',
                title: 'Tareas y proyectos',
                subtitle: 'Pagos, compras, ahorro y alertas del hogar.',
                icon: Icons.notifications_active_outlined,
                assetIconPath: kBrandNavTareas,
                trailing: IconButton(onPressed: _load, icon: const Icon(Icons.refresh, color: Colors.white)),
              ),
              const SizedBox(height: 14),
              if (error != null) ...[FriendlyError(message: error!), const SizedBox(height: 12)],
              if (summary != null) _summaryStrip(summary!),
              const SizedBox(height: 12),
              _filterStrip(),
              const SizedBox(height: 12),
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: includeDone,
                  onChanged: (value) async {
                    setState(() => includeDone = value);
                    await _load();
                  },
                  title: const Text('Mostrar completadas y canceladas', style: TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: const Text('Por defecto se muestran solo pendientes.'),
                  secondary: const Icon(Icons.history_toggle_off_outlined, color: kPrimary),
                ),
              ),
              const SizedBox(height: 12),
              if (loading) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
              if (!loading && visibleTasks.isEmpty)
                EmptyState(
                  icon: _emptyIcon(),
                  title: selectedFilter == 'all' ? 'Sin tareas pendientes' : 'Sin elementos en este filtro',
                  message: 'Agregá tareas, pagos, proyectos de compra o planes de ahorro para organizar el hogar.',
                ),
              for (final task in visibleTasks) ...[
                _taskCard(task),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
      bottomNavigationBar: JeronimoBottomNav(
        currentIndex: kBottomNavTareasIndex,
        onDestinationSelected: _handleBottomNav,
      ),
    );
  }

  void _handleBottomNav(int index) {
    if (index == kBottomNavTareasIndex) return;
    if (Navigator.of(context).canPop()) Navigator.of(context).pop(index);
  }

  Widget _summaryStrip(HouseholdTaskSummary item) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 760;
          final width = isWide ? (constraints.maxWidth - 24) / 4 : (constraints.maxWidth - 10) / 2;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SummaryPill(width: width, label: 'Pendientes', value: item.pendingCount.toString(), icon: Icons.checklist_outlined, color: kPrimary),
              _SummaryPill(width: width, label: 'Vencidas', value: item.overdueCount.toString(), icon: Icons.warning_amber_rounded, color: kDanger),
              _SummaryPill(width: width, label: 'Próximas', value: item.dueSoonCount.toString(), icon: Icons.event_outlined, color: kWarning),
              _SummaryPill(width: width, label: 'Para mí', value: item.assignedToMeCount.toString(), icon: Icons.person_pin_circle_outlined, color: kSuccess),
            ],
          );
        },
      ),
    );
  }

  Widget _filterStrip() {
    final filters = [
      ('all', 'Todo', Icons.all_inclusive),
      ('manual', 'Tareas', Icons.task_alt_outlined),
      ('payment', 'Pagos', Icons.payments_outlined),
      ('purchase', 'Compras', Icons.shopping_bag_outlined),
      ('savings', 'Ahorro', Icons.savings_outlined),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final item in filters) ...[
            ChoiceChip(
              selected: selectedFilter == item.$1,
              onSelected: (_) => setState(() => selectedFilter = item.$1),
              avatar: Icon(item.$3, size: 18, color: selectedFilter == item.$1 ? Colors.white : kPrimary),
              label: Text(item.$2, style: TextStyle(fontWeight: FontWeight.w900, color: selectedFilter == item.$1 ? Colors.white : kInk)),
              selectedColor: kPrimary,
              backgroundColor: Colors.white,
              side: BorderSide(color: kPrimary.withOpacity(0.16)),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _taskCard(HouseholdTaskItem task) {
    final assigned = task.assignedMemberId == null ? 'Sin responsable' : _memberName(task.assignedMemberId!);
    final color = _alertColor(task);
    final isDone = task.status == 'done';
    final isCancelled = task.status == 'cancelled';
    final kind = _kindKey(task);
    final isProject = kind == 'purchase' || kind == 'savings';
    return AppCard(
      color: isDone || isCancelled ? Colors.white.withOpacity(0.68) : Colors.white,
      border: Border.all(color: color.withOpacity(0.18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(16)),
                child: Icon(_taskIcon(task), color: color),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(task.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
              _priorityChip(task.priority, color),
            ],
          ),
          if (task.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(task.description, style: const TextStyle(color: Colors.black54, height: 1.25)),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _miniChip(_kindIcon(kind), _kindLabel(kind)),
              _miniChip(Icons.person_outline, assigned),
              if (task.dueDate != null) _miniChip(Icons.event_outlined, 'Vence ${task.dueDate}'),
              if (task.alertDate != null) _miniChip(Icons.notifications_none, 'Alerta ${task.alertDate}'),
              if (task.repeatRule == 'monthly') _miniChip(Icons.repeat_outlined, 'Mensual'),
              if (task.trackingFrequency != 'manual') _miniChip(Icons.manage_search_outlined, 'Seguimiento ${_frequencyLabel(task.trackingFrequency)}'),
              _miniChip(Icons.info_outline, _statusLabel(task.status)),
            ],
          ),
          if (isProject) ...[
            const SizedBox(height: 12),
            _projectBox(task),
          ],
          if (task.status == 'pending') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _completeTask(task),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Completar'),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(onPressed: () => _cancelTask(task), icon: const Icon(Icons.close_outlined), tooltip: 'Cancelar'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _projectBox(HouseholdTaskItem task) {
    final linksCount = task.productLinks.split('\n').where((line) => line.trim().isNotEmpty).length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kLavender.withOpacity(0.55),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kPrimary.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (task.budgetAmount > 0) _miniChip(Icons.savings_outlined, 'Presupuesto ${money.format(task.budgetAmount)}'),
              _miniChip(Icons.link_outlined, '$linksCount link(s)'),
              _miniChip(Icons.currency_exchange_outlined, 'ARS base'),
            ],
          ),
          if (task.lastAiSummary.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Último análisis IA', style: TextStyle(color: kPrimaryDark.withOpacity(0.82), fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(task.lastAiSummary, maxLines: 5, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black54, height: 1.28)),
            if (task.lastAiCheckAt != null) ...[
              const SizedBox(height: 4),
              Text('Actualizado: ${task.lastAiCheckAt}', style: const TextStyle(color: Colors.black45, fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ] else ...[
            const SizedBox(height: 8),
            const Text('Sin análisis IA todavía. Podés actualizar para guardar una recomendación con trazabilidad.', style: TextStyle(color: Colors.black54, height: 1.25)),
          ],
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: aiLoading ? null : () => _refreshTaskAi(task),
            icon: aiLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome_outlined),
            label: const Text('Actualizar con IA'),
          ),
        ],
      ),
    );
  }

  Widget _miniChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: kPrimary.withOpacity(0.08), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 16, color: kPrimary), const SizedBox(width: 5), Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800))],
      ),
    );
  }

  Widget _priorityChip(String priority, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withOpacity(0.10), borderRadius: BorderRadius.circular(999)),
      child: Text(_priorityLabel(priority), style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w900)),
    );
  }

  Future<void> _showCreateTaskSheet() async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final dueController = TextEditingController();
    final alertController = TextEditingController();
    final budgetController = TextEditingController();
    final linksController = TextEditingController();
    final sourcesController = TextEditingController();
    String priority = 'normal';
    String repeatRule = 'none';
    String sourceType = 'manual';
    String trackingFrequency = 'manual';
    Member? selectedMember = widget.members.isEmpty ? null : widget.members.first;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (context, setModalState) {
          final isProject = sourceType == 'purchase' || sourceType == 'savings';
          return Container(
            decoration: const BoxDecoration(color: Color(0xFFF8F5FF), borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
            padding: EdgeInsets.only(left: 18, right: 18, top: 18, bottom: MediaQuery.of(context).viewInsets.bottom + 18),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Nuevo pendiente del hogar', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  const Text('Puede ser una tarea simple, un pago, una compra planificada o un ahorro.', style: TextStyle(color: Colors.black54)),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: sourceType,
                    items: const [
                      DropdownMenuItem(value: 'manual', child: Text('Tarea normal')),
                      DropdownMenuItem(value: 'payment', child: Text('Pago pendiente')),
                      DropdownMenuItem(value: 'purchase', child: Text('Compra / proyecto')),
                      DropdownMenuItem(value: 'savings', child: Text('Plan de ahorro')),
                    ],
                    onChanged: (value) => setModalState(() => sourceType = value ?? 'manual'),
                    decoration: const InputDecoration(labelText: 'Tipo'),
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Título')),
                  const SizedBox(height: 10),
                  TextField(controller: descriptionController, minLines: 1, maxLines: 3, decoration: const InputDecoration(labelText: 'Descripción opcional')),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<Member?>(
                    value: selectedMember,
                    items: [
                      const DropdownMenuItem<Member?>(value: null, child: Text('Sin responsable')),
                      ...widget.members.map((m) => DropdownMenuItem<Member?>(value: m, child: Text(m.name))),
                    ],
                    onChanged: (value) => setModalState(() => selectedMember = value),
                    decoration: const InputDecoration(labelText: 'Responsable'),
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: dueController, decoration: const InputDecoration(labelText: 'Fecha objetivo / vencimiento AAAA-MM-DD')),
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
                  if (isProject) ...[
                    const SizedBox(height: 10),
                    TextField(controller: budgetController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Presupuesto en ARS')),
                    const SizedBox(height: 10),
                    TextField(controller: linksController, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: 'Links de productos o tiendas', hintText: 'Un link por línea')),
                    const SizedBox(height: 10),
                    TextField(controller: sourcesController, minLines: 1, maxLines: 3, decoration: const InputDecoration(labelText: 'Tiendas/fuentes sugeridas', hintText: 'Mercado Libre, tienda local, etc.')),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: trackingFrequency,
                      items: const [
                        DropdownMenuItem(value: 'manual', child: Text('Manual')),
                        DropdownMenuItem(value: 'weekly', child: Text('Semanal')),
                        DropdownMenuItem(value: 'biweekly', child: Text('Quincenal')),
                        DropdownMenuItem(value: 'monthly', child: Text('Mensual')),
                      ],
                      onChanged: (value) => setModalState(() => trackingFrequency = value ?? 'manual'),
                      decoration: const InputDecoration(labelText: 'Seguimiento IA'),
                    ),
                  ],
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: repeatRule == 'monthly',
                    onChanged: (value) => setModalState(() => repeatRule = value ? 'monthly' : 'none'),
                    title: const Text('Repetir mensualmente', style: TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: const Text('Al completarla se crea la del mes siguiente.'),
                  ),
                  const SizedBox(height: 16),
                  BigActionButton(
                    onPressed: () async {
                      final budget = double.tryParse(budgetController.text.replaceAll('.', '').replaceAll(',', '.')) ?? 0;
                      await widget.api.createTask(
                        title: titleController.text.trim(),
                        description: descriptionController.text.trim(),
                        assignedMemberId: selectedMember?.id,
                        dueDate: dueController.text.trim().isEmpty ? null : dueController.text.trim(),
                        alertDate: alertController.text.trim().isEmpty ? null : alertController.text.trim(),
                        priority: priority,
                        repeatRule: repeatRule,
                        sourceType: sourceType,
                        budgetAmount: budget,
                        productLinks: linksController.text.trim(),
                        preferredSources: sourcesController.text.trim(),
                        trackingFrequency: trackingFrequency,
                      );
                      if (mounted) Navigator.pop(context);
                      widget.onChanged?.call();
                      await _load();
                    },
                    icon: Icons.save_outlined,
                    title: 'Guardar pendiente',
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _refreshTaskAi(HouseholdTaskItem task) async {
    setState(() => aiLoading = true);
    try {
      await widget.api.refreshTaskAi(task.id);
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seguimiento IA actualizado.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyMessage(e))));
    } finally {
      if (mounted) setState(() => aiLoading = false);
    }
  }

  Future<void> _completeTask(HouseholdTaskItem task) async {
    await widget.api.completeTask(task.id);
    widget.onChanged?.call();
    await _load();
  }

  Future<void> _cancelTask(HouseholdTaskItem task) async {
    await widget.api.cancelTask(task.id);
    widget.onChanged?.call();
    await _load();
  }

  String _memberName(int id) {
    return widget.members.firstWhere((m) => m.id == id, orElse: () => Member(id: id, householdId: 0, name: 'Integrante $id', color: '#000000', role: 'member', isActive: true)).name;
  }

  Color _alertColor(HouseholdTaskItem task) {
    if (task.alertLevel == 'overdue') return kDanger;
    if (task.alertLevel == 'high') return kWarning;
    if (task.alertLevel == 'soon') return kWarning;
    if (_kindKey(task) == 'purchase') return kPrimaryMid;
    if (_kindKey(task) == 'savings') return kSuccess;
    if (_kindKey(task) == 'payment') return kWarning;
    return kPrimary;
  }

  IconData _taskIcon(HouseholdTaskItem task) {
    if (task.status == 'done') return Icons.check_circle_outline;
    if (task.status == 'cancelled') return Icons.cancel_outlined;
    if (task.alertLevel == 'overdue') return Icons.warning_amber_rounded;
    return _kindIcon(_kindKey(task));
  }

  String _kindKey(HouseholdTaskItem task) {
    final raw = task.sourceType.trim().toLowerCase();
    if (raw == 'project') return 'purchase';
    if (raw == 'purchase' || raw == 'savings' || raw == 'payment') return raw;
    return 'manual';
  }

  IconData _kindIcon(String value) {
    switch (value) {
      case 'payment':
        return Icons.payments_outlined;
      case 'purchase':
        return Icons.shopping_bag_outlined;
      case 'savings':
        return Icons.savings_outlined;
      default:
        return Icons.task_alt_outlined;
    }
  }

  IconData _emptyIcon() => _kindIcon(selectedFilter == 'all' ? 'manual' : selectedFilter);

  String _kindLabel(String value) {
    switch (value) {
      case 'payment':
        return 'Pago';
      case 'purchase':
        return 'Compra/proyecto';
      case 'savings':
        return 'Ahorro';
      default:
        return 'Tarea';
    }
  }

  String _frequencyLabel(String value) {
    switch (value) {
      case 'weekly':
        return 'semanal';
      case 'biweekly':
        return 'quincenal';
      case 'monthly':
        return 'mensual';
      default:
        return 'manual';
    }
  }

  String _priorityLabel(String value) {
    switch (value) {
      case 'low':
        return 'Baja';
      case 'high':
        return 'Alta';
      case 'urgent':
        return 'Urgente';
      default:
        return 'Normal';
    }
  }

  String _statusLabel(String value) {
    switch (value) {
      case 'done':
        return 'Completada';
      case 'cancelled':
        return 'Cancelada';
      default:
        return 'Pendiente';
    }
  }
}

class _SummaryPill extends StatelessWidget {
  final double width;
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryPill({required this.width, required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.16)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: color.withOpacity(0.14), borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: const TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.w800)),
                Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
