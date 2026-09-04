import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/app_models.dart';
import '../services/api_service.dart';
import '../services/friendly_messages.dart';
import '../widgets/app_card.dart';
import '../widgets/app_shell.dart';

class DebtsScreen extends StatefulWidget {
  final ApiService api;
  final List<Member> members;
  final String month;
  final int currentMemberId;
  final Future<void> Function()? onChanged;

  const DebtsScreen({
    super.key,
    required this.api,
    required this.members,
    required this.month,
    required this.currentMemberId,
    this.onChanged,
  });

  @override
  State<DebtsScreen> createState() => _DebtsScreenState();
}

class _DebtsScreenState extends State<DebtsScreen> {
  final money =
      NumberFormat.currency(locale: 'es_AR', symbol: r'$ ', decimalDigits: 2);
  bool loading = true;
  bool showHistory = false;
  String? error;
  List<DebtItem> debts = [];
  List<CreditBalanceItem> credits = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final loaded =
          await widget.api.getDebts(includeCancelled: true);
      final loadedCredits =
          await widget.api.getCreditBalances(activeOnly: true);
      if (!mounted) return;
      setState(() {
        debts = loaded;
        credits = loadedCredits;
      });
    } catch (e) {
      if (mounted) setState(() => error = friendlyMessage(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _generateAutomaticDebt() async {
    try {
      await widget.api.createAutomaticDebts(widget.month);
      await _refresh();
      if (widget.onChanged != null) await widget.onChanged!();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Ajuste automático registrado como deuda.')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyMessage(e))));
    }
  }

  bool get _canOperate {
    return widget.members.any(
      (member) =>
          member.id == widget.currentMemberId &&
          (member.role == 'owner' || member.role == 'admin'),
    );
  }

  Future<void> _reconcilePreviousCredits() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Revisar saldos anteriores'),
        content: const Text(
          'Se revisar\u00e1n pagos anticipados confirmados y se crear\u00e1n \u00fanicamente los saldos a favor que falten. No se modifica un cr\u00e9dito que ya fue usado.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Revisar')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final result = await widget.api.reconcileAdvanceCredits();
      await _refresh();
      if (widget.onChanged != null) await widget.onChanged!();
      if (!mounted) return;
      final changed = result['changed'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(changed
              ? 'Saldos anteriores revisados y reparados.'
              : 'La revisi\u00f3n termin\u00f3: no hab\u00eda saldos pendientes de reparar.'),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleDebts = debts.where((debt) {
      final archived = debt.status == 'paid' || debt.status == 'cancelled';
      return showHistory ? archived : !archived;
    }).toList();
    final activeTotal = debts
        .where((d) => d.status == 'active' || d.status == 'partial')
        .fold<double>(0, (sum, debt) => sum + debt.remainingAmount);
    final pendingTotal =
        debts.fold<double>(0, (sum, debt) => sum + debt.pendingAmount);
    final myCredits = credits
        .where((c) =>
            c.ownerMemberId == widget.currentMemberId &&
            c.status == 'available' &&
            c.remainingAmount > 0.01)
        .toList();

    final creditGroups = <int, List<CreditBalanceItem>>{};
    for (final credit in myCredits) {
      creditGroups.putIfAbsent(credit.counterpartyMemberId, () => []).add(credit);
    }
    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: const Text('Deudas y abonos'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh))
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: widget.members.length < 2 ? null : _showCreateDebtSheet,
        icon: const Icon(Icons.add),
        label: const Text('Deuda'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 96),
            children: [
              AppCard(
                gradient: const LinearGradient(
                    colors: [Color(0xFF6D28D9), Color(0xFF4C1D95)]),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Acuerdos entre integrantes',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Colors.white)),
                    const SizedBox(height: 8),
                    Text(
                      'Los abonos quedan pendientes hasta que la persona que recibe confirme. Si se paga de más, se genera saldo a favor.',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.86), height: 1.25),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _MiniStat(
                            label: 'Pendiente activo',
                            value: money.format(activeTotal),
                            icon: Icons.payments_outlined),
                        _MiniStat(
                            label: 'Por confirmar',
                            value: money.format(pendingTotal),
                            icon: Icons.hourglass_top_rounded),
                        _MiniStat(
                            label: 'Mi saldo a favor',
                            value: money.format(myCredits.fold<double>(
                                0, (s, c) => s + c.remainingAmount)),
                            icon: Icons.savings_outlined),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      onPressed: _generateAutomaticDebt,
                      icon: const Icon(Icons.auto_awesome_outlined),
                      label: Text(
                          'Registrar ajuste proporcional de ${widget.month}'),
                    ),
                    if (_canOperate)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: OutlinedButton.icon(
                          onPressed: _reconcilePreviousCredits,
                          icon: const Icon(Icons.history_rounded),
                          label: const Text('Revisar saldos anteriores'),
                        ),
                      ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: showHistory,
                      onChanged: (value) => setState(() => showHistory = value),
                      title: const Text('Ver historial de deudas',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800)),
                      subtitle: Text(
                          'Las deudas saldadas o canceladas quedan en historial.',
                          style:
                              TextStyle(color: Colors.white.withOpacity(0.72))),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (!showHistory && myCredits.isNotEmpty) ...[
                const SectionTitle(
                    title: 'Saldos a favor',
                    subtitle:
                        'Créditos confirmados que podés conservar o aplicar a deudas compatibles.',
                    icon: Icons.savings_outlined),
                for (final group in creditGroups.values) ...[
                  Builder(
                    builder: (context) {
                      final credit = group.first;
                      final total = group.fold<double>(0, (sum, item) => sum + item.remainingAmount);
                      final eligibleDebts = _eligibleDebtsForCredit(credit);
                      return Column(children: [_CreditBalanceCard(
                        title:
                            '${money.format(total)} a favor con ${_memberName(credit.counterpartyMemberId)}',
                        reason: 'Saldo disponible total. Se usarán primero los créditos más antiguos.',
                        compatibleDebtCount: eligibleDebts.length,
                        onApply: eligibleDebts.isEmpty
                            ? null
                            : () => _showApplyCreditSheet(group),
                      ), ExpansionTile(
                        title: Text('Ver detalle (${group.length} créditos)'),
                        children: [for (final item in group) ListTile(
                          title: Text('Crédito #${item.id} · ${money.format(item.remainingAmount)}'),
                          subtitle: Text(item.reason),
                        )],
                      )]);
                    },
                  ),
                  const SizedBox(height: 10),
                ],
              ],
              if (error != null) FriendlyError(message: error!),
              if (loading)
                const Center(
                    child: Padding(
                        padding: EdgeInsets.all(40),
                        child: CircularProgressIndicator())),
              SectionTitle(
                  title: showHistory ? 'Historial de deudas' : 'Deudas pendientes',
                  subtitle: showHistory
                      ? 'Saldadas y canceladas. Conservan sus abonos y confirmaciones.'
                      : 'Las deudas pasan al historial cuando el pago queda confirmado.',
                  icon: showHistory ? Icons.history : Icons.handshake_outlined),
              if (!loading && visibleDebts.isEmpty)
                EmptyState(
                    icon: Icons.handshake_outlined,
                    title: showHistory ? 'Sin deudas en el historial' : 'Sin deudas pendientes',
                    message: showHistory
                        ? 'Las deudas saldadas o canceladas aparecerán aquí.'
                        : 'Podés consultar las deudas anteriores en el historial.'),
              for (final debt in visibleDebts) ...[
                _DebtCard(
                  debt: debt,
                  money: money,
                  memberName: _memberName,
                  currentMemberId: widget.currentMemberId,
                  onPay: _canPay(debt) ? () => _showPaymentSheet(debt) : null,
                  onPayments: () => _showPayments(debt),
                  onCancel: debt.status == 'active' &&
                          debt.paidAmount <= 0.01 &&
                          debt.pendingAmount <= 0.01
                      ? () => _cancelDebt(debt)
                      : null,
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 80),
            ],
          ),
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

  bool _canPay(DebtItem debt) {
    return (debt.status == 'active' || debt.status == 'partial') &&
        debt.remainingAmount > 0.01 &&
        debt.debtorMemberId == widget.currentMemberId;
  }

  String _memberName(int id) {
    return widget.members
        .firstWhere(
          (m) => m.id == id,
          orElse: () => Member(
              id: id,
              householdId: 0,
              name: 'Integrante $id',
              color: '#000000',
              role: 'member',
              isActive: true),
        )
        .name;
  }

  double _parseMoney(String raw) {
    final clean = raw.trim().replaceAll('.', '').replaceAll(',', '.');
    final value = double.tryParse(clean);
    if (value == null || value <= 0) throw Exception('Ingresá un monto válido');
    return value;
  }

  Future<void> _showCreateDebtSheet() async {
    Member debtor = widget.members.first;
    Member creditor =
        widget.members.length > 1 ? widget.members[1] : widget.members.first;
    final amountController = TextEditingController();
    final reasonController = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
              left: 18,
              right: 18,
              top: 18,
              bottom: MediaQuery.of(context).viewInsets.bottom + 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Nueva deuda manual',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              DropdownButtonFormField<Member>(
                value: debtor,
                items: widget.members
                    .map((m) => DropdownMenuItem(
                        value: m, child: Text('Debe ${m.name}')))
                    .toList(),
                onChanged: (value) =>
                    setModalState(() => debtor = value ?? debtor),
                decoration: const InputDecoration(labelText: 'Deudor'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<Member>(
                value: creditor,
                items: widget.members
                    .map((m) =>
                        DropdownMenuItem(value: m, child: Text('A ${m.name}')))
                    .toList(),
                onChanged: (value) =>
                    setModalState(() => creditor = value ?? creditor),
                decoration: const InputDecoration(labelText: 'Acreedor'),
              ),
              const SizedBox(height: 10),
              TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Monto')),
              const SizedBox(height: 10),
              TextField(
                  controller: reasonController,
                  decoration: const InputDecoration(labelText: 'Motivo')),
              const SizedBox(height: 16),
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar')),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () async {
                  try {
                    await widget.api.createManualDebt(
                      debtorMemberId: debtor.id,
                      creditorMemberId: creditor.id,
                      amount: _parseMoney(amountController.text),
                      reason: reasonController.text.trim(),
                    );
                    if (mounted) Navigator.pop(context);
                    await _refresh();
                    if (widget.onChanged != null) await widget.onChanged!();
                  } catch (e) {
                    if (mounted)
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(friendlyMessage(e))));
                  }
                },
                child: const Text('Guardar deuda'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showPaymentSheet(DebtItem debt) async {
    final amountController =
        TextEditingController(text: debt.remainingAmount.toStringAsFixed(2).replaceAll('.', ','));
    final noteController = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetContext) => SingleChildScrollView(child: Padding(
        padding: EdgeInsets.only(
            left: 18,
            right: 18,
            top: 18,
            bottom: MediaQuery.of(context).viewInsets.bottom + 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sheetTitle(sheetContext, 'Registrar abono a ${_memberName(debt.creditorMemberId)}'),
            const SizedBox(height: 8),
            Text('Saldo pendiente: ${money.format(debt.remainingAmount)}'),
            const SizedBox(height: 6),
            const Text(
                'Quedará pendiente hasta que la otra persona confirme. Si abonás de más, el excedente será saldo a favor.',
                style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 14),
            TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Monto transferido/abonado')),
            const SizedBox(height: 10),
            TextField(
                controller: noteController,
                decoration: const InputDecoration(labelText: 'Nota opcional')),
            const SizedBox(height: 16),
            TextButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: const Text('Cancelar')),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () async {
                try {
                  await widget.api.addDebtPayment(
                    debtId: debt.id,
                    amount: _parseMoney(amountController.text),
                    note: noteController.text.trim(),
                    date: DateTime.now(),
                  );
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                  if (!mounted) return;
                  await _refresh();
                  if (widget.onChanged != null) await widget.onChanged!();
                  if (mounted)
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                            'Abono registrado. Falta confirmación del receptor.')));
                } catch (e) {
                  if (mounted)
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(friendlyMessage(e))));
                }
              },
              child: const Text('Registrar abono pendiente'),
            ),
          ],
        ),
      )),
    );
  }

  Widget _sheetTitle(BuildContext sheetContext, String title, {bool enabled = true}) => Row(
    children: [
      Expanded(child: Text(title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
      IconButton(tooltip: 'Cerrar', icon: const Icon(Icons.close),
          onPressed: enabled ? () => Navigator.pop(sheetContext) : null),
    ],
  );

  Future<void> _showPayments(DebtItem debt) async {
    try {
      final payments = await widget.api.getDebtPayments(debt.id);
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          minChildSize: 0.35,
          maxChildSize: 0.92,
          builder: (context, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.all(18),
            children: [
              const Text('Abonos y confirmaciones',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                  'Los abonos pendientes no descuentan deuda hasta que quien recibe confirme.',
                  style: TextStyle(color: Colors.black54)),
              const SizedBox(height: 12),
              if (payments.isEmpty)
                const Text('Esta deuda todavía no tiene abonos.'),
              for (final payment in payments)
                _PaymentTile(
                  payment: payment,
                  money: money,
                  memberName: _memberName,
                  canConfirm: payment.status == 'pending' &&
                      widget.currentMemberId == debt.creditorMemberId,
                  canReject: payment.status == 'pending' &&
                      widget.currentMemberId == debt.creditorMemberId,
                  onConfirm: () => _confirmPayment(debt, payment),
                  onReject: () => _rejectPayment(debt, payment),
                ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyMessage(e))));
    }
  }

  Future<void> _confirmPayment(DebtItem debt, DebtPaymentItem payment) async {
    try {
      await widget.api
          .confirmDebtPayment(debtId: debt.id, paymentId: payment.id);
      if (mounted) Navigator.pop(context);
      await _refresh();
      if (widget.onChanged != null) await widget.onChanged!();
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Abono confirmado.')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyMessage(e))));
    }
  }

  Future<void> _rejectPayment(DebtItem debt, DebtPaymentItem payment) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Rechazar abono'),
        content: TextField(
            controller: reasonController,
            decoration: const InputDecoration(labelText: 'Motivo opcional')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Volver')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Rechazar')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.api.rejectDebtPayment(
          debtId: debt.id,
          paymentId: payment.id,
          reason: reasonController.text.trim());
      if (mounted) Navigator.pop(context);
      await _refresh();
      if (widget.onChanged != null) await widget.onChanged!();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyMessage(e))));
    }
  }

  List<DebtItem> _eligibleDebtsForCredit(CreditBalanceItem credit) {
    if (credit.status != 'available' || credit.remainingAmount <= 0.01 ||
        credit.ownerMemberId != widget.currentMemberId) return [];
    return debts
        .where((d) =>
            (d.status == 'active' || d.status == 'partial') &&
            d.debtorMemberId == credit.ownerMemberId &&
            d.creditorMemberId == credit.counterpartyMemberId &&
            d.remainingAmount > 0.01)
        .toList();
  }

  Future<void> _showApplyCreditSheet(List<CreditBalanceItem> sources) async {
    final credit = sources.first;
    final available = sources.fold<double>(0, (sum, item) => sum + item.remainingAmount);
    var submitting = false;
    final eligible = _eligibleDebtsForCredit(credit);
    if (eligible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'No hay deudas activas compatibles. El saldo queda disponible para próximos períodos.')),
      );
      return;
    }
    DebtItem selected = eligible.first;
    final amountController = TextEditingController(
        text: available
            .clamp(0, selected.remainingAmount)
            .toStringAsFixed(2).replaceAll('.', ','));
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => StatefulBuilder(
        builder: (context, setModalState) => PopScope(canPop: !submitting, child: SingleChildScrollView(child: Padding(
          padding: EdgeInsets.only(
              left: 18,
              right: 18,
              top: 18,
              bottom: MediaQuery.of(context).viewInsets.bottom + 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sheetTitle(context, 'Aplicar saldo a favor', enabled: !submitting),
              const SizedBox(height: 8),
              Text(
                'Disponible: ${money.format(available)}. Podés usarlo total o parcialmente para compensar una deuda activa con ${_memberName(credit.counterpartyMemberId)}.',
                style: const TextStyle(color: Colors.black54, height: 1.25),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<DebtItem>(
                value: selected,
                items: eligible
                    .map((d) => DropdownMenuItem(
                          value: d,
                          child: Text(
                              'Deuda #${d.id} · pendiente ${money.format(d.remainingAmount)}'),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value == null || submitting) return;
                  setModalState(() {
                    selected = value;
                    amountController.text = available
                        .clamp(0, selected.remainingAmount)
                        .toStringAsFixed(2).replaceAll('.', ',');
                  });
                },
                decoration:
                    const InputDecoration(labelText: 'Deuda a compensar'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Monto a aplicar',
                  helperText:
                      'Máximo: ${money.format(available.clamp(0, selected.remainingAmount))}',
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                  onPressed: submitting ? null : () => Navigator.pop(context),
                  child: const Text('Cancelar')),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.swap_horiz_rounded),
                  onPressed: submitting ? null : () async {
                    setModalState(() => submitting = true);
                    try {
                      final amount = _parseMoney(amountController.text);
                      final maxAmount = available
                          .clamp(0, selected.remainingAmount)
                          .toDouble();
                      if ((amount * 100).round() > (maxAmount * 100).round()) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(
                                  'El monto máximo aplicable es ${money.format(maxAmount)}.')),
                        );
                        return;
                      }
                      await widget.api.applyAvailableCredit(
                        debtId: selected.id,
                        amount: amount,
                      );
                      if (context.mounted) Navigator.pop(context);
                      if (!mounted) return;
                      await _refresh();
                      if (widget.onChanged != null) await widget.onChanged!();
                    } catch (e) {
                      if (mounted)
                        ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(content: Text(friendlyMessage(e))));
                    } finally {
                      if (context.mounted) setModalState(() => submitting = false);
                    }
                  },
                  label: Text(submitting ? 'Aplicando...' : 'Aplicar saldo'),
                ),
              ),
            ],
          ),
        ))),
      ),
    );
  }

  Future<void> _cancelDebt(DebtItem debt) async {
    try {
      await widget.api.cancelDebt(debt.id, reason: 'Cancelada desde la app');
      await _refresh();
      if (widget.onChanged != null) await widget.onChanged!();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyMessage(e))));
    }
  }
}

class _CreditBalanceCard extends StatelessWidget {
  final String title;
  final String reason;
  final int compatibleDebtCount;
  final VoidCallback? onApply;

  const _CreditBalanceCard({
    required this.title,
    required this.reason,
    required this.compatibleDebtCount,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final hasCompatibleDebts = compatibleDebtCount > 0 && onApply != null;
    final safeTitle = title.trim().isEmpty ? 'Saldo disponible' : title.trim();
    final safeReason =
        reason.trim().isEmpty ? 'Saldo confirmado disponible.' : reason.trim();
    final statusText = hasCompatibleDebts
        ? compatibleDebtCount == 1
            ? 'Tenés 1 deuda compatible para compensar.'
            : 'Tenés $compatibleDebtCount deudas compatibles para compensar.'
        : 'Se conserva para próximas deudas con esta persona.';

    final iconBox = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: kPrimary.withOpacity(0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Icon(Icons.savings_rounded, color: kPrimary),
    );

    final statusBox = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: hasCompatibleDebts
            ? kPrimary.withOpacity(0.08)
            : Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: hasCompatibleDebts
                ? kPrimary.withOpacity(0.18)
                : Colors.black.withOpacity(0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            hasCompatibleDebts
                ? Icons.check_circle_outline_rounded
                : Icons.schedule_rounded,
            size: 17,
            color: hasCompatibleDebts ? kPrimary : Colors.black54,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              statusText,
              softWrap: true,
              style: TextStyle(
                color: hasCompatibleDebts ? kPrimary : Colors.black54,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                height: 1.22,
              ),
            ),
          ),
        ],
      ),
    );

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              iconBox,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      safeTitle,
                      softWrap: true,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        height: 1.18,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      safeReason,
                      softWrap: true,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12.5,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          statusBox,
          if (hasCompatibleDebts) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: onApply,
                icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                label: const Text('Aplicar a deuda'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _MiniStat(
      {required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.14),
          borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: Colors.white),
        const SizedBox(height: 8),
        Text(label,
            style: TextStyle(
                color: Colors.white.withOpacity(0.72),
                fontSize: 12,
                fontWeight: FontWeight.w700)),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900)),
      ]),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  final DebtPaymentItem payment;
  final NumberFormat money;
  final String Function(int id) memberName;
  final bool canConfirm;
  final bool canReject;
  final VoidCallback onConfirm;
  final VoidCallback onReject;

  const _PaymentTile({
    required this.payment,
    required this.money,
    required this.memberName,
    required this.canConfirm,
    required this.canReject,
    required this.onConfirm,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final statusText = switch (payment.status) {
      'confirmed' => 'Confirmado',
      'rejected' => 'Rechazado',
      'voided' => 'Anulado',
      _ => 'Pendiente',
    };
    final statusColor = switch (payment.status) {
      'confirmed' => Colors.green,
      'rejected' => Colors.red,
      'voided' => Colors.black54,
      _ => Colors.orange,
    };
    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
                child: Text(money.format(payment.amount),
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w900))),
            Chip(
                label: Text(statusText),
                backgroundColor: statusColor.withOpacity(0.12),
                labelStyle:
                    TextStyle(color: statusColor, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 4),
          Text(
              'Registró: ${memberName(payment.paidByMemberId)} · Fecha: ${payment.date}',
              style: const TextStyle(color: Colors.black54)),
          if (payment.status == 'confirmed') ...[
            const SizedBox(height: 4),
            Text('Aplicado a deuda: ${money.format(payment.appliedAmount)}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            if (payment.creditAmount > 0.01)
              Text('Excedente a favor: ${money.format(payment.creditAmount)}',
                  style: const TextStyle(
                      color: Colors.green, fontWeight: FontWeight.w800)),
          ],
          if (payment.status == 'rejected' &&
              payment.rejectedReason.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Motivo: ${payment.rejectedReason}',
                style: const TextStyle(color: Colors.red)),
          ],
          if (payment.note.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(payment.note),
          ],
          if (canConfirm || canReject) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              ElevatedButton.icon(
                  onPressed: onConfirm,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Confirmar recibido')),
              OutlinedButton.icon(
                  onPressed: onReject,
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Rechazar')),
            ]),
          ],
        ],
      ),
    );
  }
}

class _DebtCard extends StatelessWidget {
  final DebtItem debt;
  final NumberFormat money;
  final String Function(int id) memberName;
  final int currentMemberId;
  final VoidCallback? onPay;
  final VoidCallback onPayments;
  final VoidCallback? onCancel;

  const _DebtCard({
    required this.debt,
    required this.money,
    required this.memberName,
    required this.currentMemberId,
    required this.onPayments,
    this.onPay,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final sourceText = debt.source == 'automatic'
        ? 'Ajuste mensual ${debt.sourceMonth ?? ''}'
        : 'Manual';
    final statusText = switch (debt.status) {
      'paid' => 'Saldada',
      'partial' => 'Parcial',
      'cancelled' => 'Cancelada',
      _ => 'Activa',
    };

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${memberName(debt.debtorMemberId)} → ${memberName(debt.creditorMemberId)}',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ),
              Chip(label: Text(statusText)),
            ],
          ),
          const SizedBox(height: 4),
          Text(sourceText, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Text('Original: ${money.format(debt.originalAmount)}'),
          Text('Confirmado: ${money.format(debt.paidAmount)}'),
          if (debt.pendingAmount > 0.01)
            Text(
                'Pendiente de confirmación: ${money.format(debt.pendingAmount)}',
                style: const TextStyle(
                    color: Colors.orange, fontWeight: FontWeight.bold)),
          Text('Pendiente real: ${money.format(debt.remainingAmount)}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          if (debt.reason.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(debt.reason),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                  onPressed: onPayments,
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('Abonos')),
              if (onPay != null)
                ElevatedButton.icon(
                    onPressed: onPay,
                    icon: const Icon(Icons.payments),
                    label: const Text('Abonar')),
              if (onCancel != null)
                TextButton.icon(
                    onPressed: onCancel,
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Cancelar')),
            ],
          ),
        ],
      ),
    );
  }
}
