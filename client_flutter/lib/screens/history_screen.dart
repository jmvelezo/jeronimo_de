import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/app_models.dart';
import '../services/api_service.dart';
import '../services/friendly_messages.dart';
import '../widgets/app_card.dart';
import '../widgets/app_shell.dart';

class HistoryScreen extends StatefulWidget {
  final ApiService api;
  final List<Member> members;
  final String currentMonth;
  final Future<void> Function() onChanged;

  const HistoryScreen({
    super.key,
    required this.api,
    required this.members,
    required this.currentMonth,
    required this.onChanged,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final money = NumberFormat.currency(locale: 'es_AR', symbol: r'$ ', decimalDigits: 0);
  bool loading = true;
  String? error;
  List<MonthlyCloseItem> closes = [];
  List<MonthPeriodStatusItem> periodStatuses = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _nextMonth(String month) {
    final parts = month.split('-');
    final year = int.tryParse(parts.first) ?? DateTime.now().year;
    final mon = int.tryParse(parts.length > 1 ? parts[1] : '') ?? DateTime.now().month;
    final next = DateTime(year, mon + 1, 1);
    return "${next.year.toString().padLeft(4, '0')}-${next.month.toString().padLeft(2, '0')}";
  }

  String _periodStatusLabel(MonthPeriodStatusItem period) {
    if (period.isActive && period.isClosed) return 'Activo cerrado';
    if (period.isActive) return 'Mes operativo activo';
    if (period.isClosed) return 'Mes cerrado';
    return 'Con datos, sin cierre';
  }

  String _periodStatusDetail(MonthPeriodStatusItem period) {
    final parts = <String>[];
    if (period.incomeCount > 0) parts.add('${period.incomeCount} ingresos');
    if (period.expenseCount > 0) parts.add('${period.expenseCount} gastos');
    if (period.advancePaymentCount > 0) parts.add('${period.advancePaymentCount} pagos anticipados');
    if (parts.isEmpty) return 'Sin movimientos cargados todavía.';
    return parts.join(' · ');
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final loaded = await widget.api.getMonthlyCloses();
      final statuses = await widget.api.getMonthPeriodStatuses();
      setState(() {
        closes = loaded;
        periodStatuses = statuses;
      });
    } catch (e) {
      setState(() => error = friendlyMessage(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _closeCurrentMonth() async {
    final nextMonth = _nextMonth(widget.currentMonth);
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Cerrar ${widget.currentMonth}'),
        content: Text(
          'Se guarda una foto del mes en el historial. Luego ${widget.currentMonth} queda protegido contra cambios accidentales y el mes operativo pasa a $nextMonth vacío para cargar ingresos y gastos desde cero. No se borra ningún dato del mes cerrado.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cerrar mes y pasar al siguiente'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await widget.api.closeMonth(widget.currentMonth, advanceToNext: true);
      await _load();
      await widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Mes cerrado. Se abrió el período $nextMonth para empezar de cero.')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyMessage(e))));
    }
  }


  Future<void> _resetActivePeriodBasic() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Reiniciar ${widget.currentMonth}'),
        content: Text(
          'Esto deja en cero ingresos, gastos comunes y pagos anticipados de ${widget.currentMonth}. '
          'No toca meses cerrados, deudas formales, abonos de deudas, saldos a favor ni plantillas.\n\n'
          'Usalo solo si este período quedó contaminado con datos del mes anterior o de pruebas.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.cleaning_services_outlined),
            label: const Text('Reiniciar período'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final result = await widget.api.resetActivePeriodBasic();
      await _load();
      await widget.onChanged();
      if (mounted) {
        final month = result['month'] ?? widget.currentMonth;
        final deletedIncomes = result['deleted_incomes'] ?? 0;
        final deletedExpenses = result['deleted_expenses'] ?? 0;
        final deletedAdvancePayments = result['deleted_advance_payments'] ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$month reiniciado: $deletedIncomes ingresos, $deletedExpenses gastos y $deletedAdvancePayments pagos anticipados eliminados.')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyMessage(e))));
    }
  }

  Future<void> _reopenMonth(String month) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Reabrir $month'),
        content: const Text('El cierre se elimina para permitir correcciones. Los gastos y deudas ya cargadas no se borran.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reabrir')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await widget.api.reopenMonth(month, reason: 'Corrección manual desde app');
      await _load();
      await widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$month quedó reabierto.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      appBar: AppBar(title: const Text('Historial y cierre')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 96),
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Cierre mensual', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text('Mes activo: ${widget.currentMonth}'),
                  const SizedBox(height: 6),
                  const Text(
                    'El mes operativo solo cambia cuando cerrás el período. No avanza solo por fecha calendario.',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _closeCurrentMonth,
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Cerrar mes y pasar al siguiente'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _resetActivePeriodBasic,
                    icon: const Icon(Icons.cleaning_services_outlined),
                    label: const Text('Reiniciar período activo'),
                  ),
                  const SizedBox(height: 8),
                  const Text('El cierre protege el mes contra cambios accidentales. Si pasás al siguiente período, ingresos y gastos arrancan vacíos sin borrar el historial. La app no cambia de período por calendario.'),
                  const SizedBox(height: 6),
                  const Text('Reiniciar período activo vacía ingresos, gastos y pagos anticipados del período actual no cerrado. No toca meses cerrados, deudas formales, abonos de deudas ni saldos a favor.'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Períodos registrados', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  if (!loading && periodStatuses.isEmpty)
                    const Text('Todavía no hay meses con datos registrados.'),
                  for (final period in periodStatuses) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text('${period.month} · ${_periodStatusLabel(period)}'),
                      subtitle: Text('${_periodStatusDetail(period)} · Ingresos ${money.format(period.totalIncome)} · Gastos ${money.format(period.totalSharedExpenses)}'),
                    ),
                    const Divider(height: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (error != null) Text(error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            if (loading) const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
            if (!loading && closes.isEmpty)
              const AppCard(child: Text('Todavía no hay meses cerrados.')),
            for (final close in closes) ...[
              _CloseCard(
                close: close,
                members: widget.members,
                money: money,
                onReopen: () => _reopenMonth(close.month),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
      bottomNavigationBar: JeronimoBottomNav(
        currentIndex: kBottomNavMasIndex,
        onDestinationSelected: _handleBottomNav,
      ),
    );
  }

  void _handleBottomNav(int index) {
    if (index == kBottomNavMasIndex) return;
    if (Navigator.of(context).canPop()) Navigator.of(context).pop(index);
  }
}

class _CloseCard extends StatelessWidget {
  final MonthlyCloseItem close;
  final List<Member> members;
  final NumberFormat money;
  final VoidCallback onReopen;

  const _CloseCard({required this.close, required this.members, required this.money, required this.onReopen});

  String _memberName(int id) => members.firstWhere(
        (m) => m.id == id,
        orElse: () => Member(id: id, householdId: 0, name: 'Integrante $id', color: '#000000', role: 'member', isActive: true),
      ).name;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: Text(close.month, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        subtitle: Text('Gastos: ${money.format(close.totalSharedExpenses)} · Ingresos: ${money.format(close.totalIncome)}'),
        children: [
          const SizedBox(height: 8),
          if ((close.summary.warning ?? '').isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(close.summary.warning!, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 8),
          ],
          for (final member in close.summary.members)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${member.name}: le correspondía ${money.format(member.shouldPay)}, pagó ${money.format(member.actuallyPaid)}.',
                ),
              ),
            ),
          if (close.summary.settlements.isNotEmpty) ...[
            const Divider(),
            const Align(alignment: Alignment.centerLeft, child: Text('Ajuste del mes', style: TextStyle(fontWeight: FontWeight.bold))),
            const SizedBox(height: 6),
            for (final settlement in close.summary.settlements)
              Align(
                alignment: Alignment.centerLeft,
                child: Text('${_memberName(settlement.debtorMemberId)} le debía ${money.format(settlement.amount)} a ${_memberName(settlement.creditorMemberId)}'),
              ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onReopen,
              icon: const Icon(Icons.lock_open_outlined),
              label: const Text('Reabrir para corregir'),
            ),
          ),
        ],
      ),
    );
  }
}
