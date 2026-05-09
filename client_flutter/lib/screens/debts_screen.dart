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
  final money = NumberFormat.currency(locale: 'es_AR', symbol: r'$ ', decimalDigits: 0);
  bool loading = true;
  bool includeCancelled = false;
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
      final loaded = await widget.api.getDebts(includeCancelled: includeCancelled);
      final loadedCredits = await widget.api.getCreditBalances(activeOnly: true);
      setState(() {
        debts = loaded;
        credits = loadedCredits;
      });
    } catch (e) {
      setState(() => error = friendlyMessage(e));
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ajuste automático registrado como deuda.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeTotal = debts
        .where((d) => d.status == 'active' || d.status == 'partial')
        .fold<double>(0, (sum, debt) => sum + debt.remainingAmount);
    final pendingTotal = debts.fold<double>(0, (sum, debt) => sum + debt.pendingAmount);
    final myCredits = credits.where((c) => c.ownerMemberId == widget.currentMemberId && c.remainingAmount > 0.01).toList();

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: const Text('Deudas y abonos'),
        actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh))],
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
                gradient: const LinearGradient(colors: [Color(0xFF6D28D9), Color(0xFF4C1D95)]),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Acuerdos entre integrantes', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                    const SizedBox(height: 8),
                    Text(
                      'Los abonos quedan pendientes hasta que la persona que recibe confirme. Si se paga de más, se genera saldo a favor.',
                      style: TextStyle(color: Colors.white.withOpacity(0.86), height: 1.25),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _MiniStat(label: 'Pendiente activo', value: money.format(activeTotal), icon: Icons.payments_outlined),
                        _MiniStat(label: 'Por confirmar', value: money.format(pendingTotal), icon: Icons.hourglass_top_rounded),
                        _MiniStat(label: 'Mi saldo a favor', value: money.format(myCredits.fold<double>(0, (s, c) => s + c.remainingAmount)), icon: Icons.savings_outlined),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      onPressed: _generateAutomaticDebt,
                      icon: const Icon(Icons.auto_awesome_outlined),
                      label: Text('Registrar ajuste proporcional de ${widget.month}'),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: includeCancelled,
                      onChanged: (value) async {
                        setState(() => includeCancelled = value);
                        await _refresh();
                      },
                      title: const Text('Mostrar deudas canceladas', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                      subtitle: Text('Las deudas saldadas o canceladas quedan en historial.', style: TextStyle(color: Colors.white.withOpacity(0.72))),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (myCredits.isNotEmpty) ...[
                const SectionTitle(title: 'Saldos a favor', subtitle: 'Créditos confirmados que podés conservar o aplicar a deudas compatibles.', icon: Icons.savings_outlined),
                for (final credit in myCredits) ...[
                  Builder(
                    builder: (context) {
                      final eligibleDebts = _eligibleDebtsForCredit(credit);
                      return _CreditBalanceCard(
                        title: '${money.format(credit.remainingAmount)} a favor con ${_memberName(credit.counterpartyMemberId)}',
                        reason: credit.reason,
                        compatibleDebtCount: eligibleDebts.length,
                        onApply: eligibleDebts.isEmpty ? null : () => _showApplyCreditSheet(credit),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                ],
              ],
              if (error != null) FriendlyError(message: error!),
              if (loading) const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())),
              if (!loading && debts.isEmpty)
                const EmptyState(icon: Icons.handshake_outlined, title: 'Sin deudas registradas', message: 'Podés crear una deuda manual o registrar el ajuste proporcional del mes.'),
              for (final debt in debts) ...[
                _DebtCard(
                  debt: debt,
                  money: money,
                  memberName: _memberName,
                  currentMemberId: widget.currentMemberId,
                  onPay: _canPay(debt) ? () => _showPaymentSheet(debt) : null,
                  onPayments: () => _showPayments(debt),
                  onCancel: debt.status == 'active' && debt.paidAmount <= 0.01 && debt.pendingAmount <= 0.01 ? () => _cancelDebt(debt) : null,
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
    return (debt.status == 'active' || debt.status == 'partial') && debt.remainingAmount > 0.01 && debt.debtorMemberId == widget.currentMemberId;
  }

  String _memberName(int id) {
    return widget.members
        .firstWhere(
          (m) => m.id == id,
          orElse: () => Member(id: id, householdId: 0, name: 'Integrante $id', color: '#000000', role: 'member', isActive: true),
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
    Member creditor = widget.members.length > 1 ? widget.members[1] : widget.members.first;
    final amountController = TextEditingController();
    final reasonController = TextEditingController();

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
              const Text('Nueva deuda manual', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              DropdownButtonFormField<Member>(
                value: debtor,
                items: widget.members.map((m) => DropdownMenuItem(value: m, child: Text('Debe ${m.name}'))).toList(),
                onChanged: (value) => setModalState(() => debtor = value ?? debtor),
                decoration: const InputDecoration(labelText: 'Deudor'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<Member>(
                value: creditor,
                items: widget.members.map((m) => DropdownMenuItem(value: m, child: Text('A ${m.name}'))).toList(),
                onChanged: (value) => setModalState(() => creditor = value ?? creditor),
                decoration: const InputDecoration(labelText: 'Acreedor'),
              ),
              const SizedBox(height: 10),
              TextField(controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Monto')), 
              const SizedBox(height: 10),
              TextField(controller: reasonController, decoration: const InputDecoration(labelText: 'Motivo')), 
              const SizedBox(height: 16),
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
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyMessage(e))));
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
    final amountController = TextEditingController(text: debt.remainingAmount.toStringAsFixed(0));
    final noteController = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(left: 18, right: 18, top: 18, bottom: MediaQuery.of(context).viewInsets.bottom + 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Registrar abono a ${_memberName(debt.creditorMemberId)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Saldo pendiente: ${money.format(debt.remainingAmount)}'),
            const SizedBox(height: 6),
            const Text('Quedará pendiente hasta que la otra persona confirme. Si abonás de más, el excedente será saldo a favor.', style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 14),
            TextField(controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Monto transferido/abonado')),
            const SizedBox(height: 10),
            TextField(controller: noteController, decoration: const InputDecoration(labelText: 'Nota opcional')), 
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                try {
                  await widget.api.addDebtPayment(
                    debtId: debt.id,
                    amount: _parseMoney(amountController.text),
                    note: noteController.text.trim(),
                    date: DateTime.now(),
                  );
                  if (mounted) Navigator.pop(context);
                  await _refresh();
                  if (widget.onChanged != null) await widget.onChanged!();
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Abono registrado. Falta confirmación del receptor.')));
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyMessage(e))));
                }
              },
              child: const Text('Registrar abono pendiente'),
            ),
          ],
        ),
      ),
    );
  }

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
              const Text('Abonos y confirmaciones', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Los abonos pendientes no descuentan deuda hasta que quien recibe confirme.', style: TextStyle(color: Colors.black54)),
              const SizedBox(height: 12),
              if (payments.isEmpty) const Text('Esta deuda todavía no tiene abonos.'),
              for (final payment in payments) _PaymentTile(
                payment: payment,
                money: money,
                memberName: _memberName,
                canConfirm: payment.status == 'pending' && widget.currentMemberId == debt.creditorMemberId,
                canReject: payment.status == 'pending' && widget.currentMemberId == debt.creditorMemberId,
                onConfirm: () => _confirmPayment(debt, payment),
                onReject: () => _rejectPayment(debt, payment),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyMessage(e))));
    }
  }

  Future<void> _confirmPayment(DebtItem debt, DebtPaymentItem payment) async {
    try {
      await widget.api.confirmDebtPayment(debtId: debt.id, paymentId: payment.id);
      if (mounted) Navigator.pop(context);
      await _refresh();
      if (widget.onChanged != null) await widget.onChanged!();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Abono confirmado.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyMessage(e))));
    }
  }

  Future<void> _rejectPayment(DebtItem debt, DebtPaymentItem payment) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rechazar abono'),
        content: TextField(controller: reasonController, decoration: const InputDecoration(labelText: 'Motivo opcional')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Volver')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Rechazar')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.api.rejectDebtPayment(debtId: debt.id, paymentId: payment.id, reason: reasonController.text.trim());
      if (mounted) Navigator.pop(context);
      await _refresh();
      if (widget.onChanged != null) await widget.onChanged!();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyMessage(e))));
    }
  }

  List<DebtItem> _eligibleDebtsForCredit(CreditBalanceItem credit) {
    return debts
        .where((d) =>
            (d.status == 'active' || d.status == 'partial') &&
            d.debtorMemberId == credit.ownerMemberId &&
            d.creditorMemberId == credit.counterpartyMemberId &&
            d.remainingAmount > 0.01)
        .toList();
  }

  Future<void> _showApplyCreditSheet(CreditBalanceItem credit) async {
    final eligible = _eligibleDebtsForCredit(credit);
    if (eligible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay deudas activas compatibles. El saldo queda disponible para próximos períodos.')),
      );
      return;
    }
    DebtItem selected = eligible.first;
    final amountController = TextEditingController(text: credit.remainingAmount.clamp(0, selected.remainingAmount).toStringAsFixed(0));
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
              const Text('Aplicar saldo a favor', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                'Disponible: ${money.format(credit.remainingAmount)}. Podés usarlo total o parcialmente para compensar una deuda activa con ${_memberName(credit.counterpartyMemberId)}.',
                style: const TextStyle(color: Colors.black54, height: 1.25),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<DebtItem>(
                value: selected,
                items: eligible
                    .map((d) => DropdownMenuItem(
                          value: d,
                          child: Text('Deuda #${d.id} · pendiente ${money.format(d.remainingAmount)}'),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setModalState(() {
                    selected = value;
                    amountController.text = credit.remainingAmount.clamp(0, selected.remainingAmount).toStringAsFixed(0);
                  });
                },
                decoration: const InputDecoration(labelText: 'Deuda a compensar'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Monto a aplicar',
                  helperText: 'Máximo: ${money.format(credit.remainingAmount.clamp(0, selected.remainingAmount))}',
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.swap_horiz_rounded),
                  onPressed: () async {
                    try {
                      final amount = _parseMoney(amountController.text);
                      final maxAmount = credit.remainingAmount.clamp(0, selected.remainingAmount).toDouble();
                      if (amount > maxAmount + 0.01) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('El monto máximo aplicable es ${money.format(maxAmount)}.')),
                        );
                        return;
                      }
                      await widget.api.applyCreditBalance(
                        creditId: credit.id,
                        debtId: selected.id,
                        amount: amount,
                        note: 'Compensación desde saldo a favor',
                      );
                      if (mounted) Navigator.pop(context);
                      await _refresh();
                      if (widget.onChanged != null) await widget.onChanged!();
                    } catch (e) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyMessage(e))));
                    }
                  },
                  label: const Text('Aplicar saldo'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _cancelDebt(DebtItem debt) async {
    try {
      await widget.api.cancelDebt(debt.id, reason: 'Cancelada desde la app');
      await _refresh();
      if (widget.onChanged != null) await widget.onChanged!();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyMessage(e))));
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
    final hasCompatibleDebts = compatibleDebtCount > 0;
    final statusText = hasCompatibleDebts
        ? compatibleDebtCount == 1
            ? 'Tenés 1 deuda compatible para compensar.'
            : 'Tenés $compatibleDebtCount deudas compatibles para compensar.'
        : 'Se conserva para próximas deudas con esta persona.';

    final textBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          softWrap: true,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          reason.isEmpty ? 'Saldo confirmado disponible.' : reason,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          softWrap: true,
          style: const TextStyle(color: Colors.black54, fontSize: 12, height: 1.25),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: hasCompatibleDebts ? kPrimary.withOpacity(0.08) : Colors.black.withOpacity(0.04),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: hasCompatibleDebts ? kPrimary.withOpacity(0.18) : Colors.black.withOpacity(0.06)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hasCompatibleDebts ? Icons.check_circle_outline_rounded : Icons.schedule_rounded,
                size: 15,
                color: hasCompatibleDebts ? kPrimary : Colors.black54,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  statusText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: hasCompatibleDebts ? kPrimary : Colors.black54,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final applyButton = OutlinedButton.icon(
      onPressed: onApply,
      icon: const Icon(Icons.swap_horiz_rounded, size: 18),
      label: const Text('Aplicar a deuda'),
    );

    return AppCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth <= 560;
          final icon = Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: kPrimary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.savings_rounded, color: kPrimary),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    icon,
                    const SizedBox(width: 12),
                    Expanded(child: textBlock),
                  ],
                ),
                if (hasCompatibleDebts) ...[
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerLeft, child: applyButton),
                ],
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              icon,
              const SizedBox(width: 12),
              Expanded(child: textBlock),
              if (hasCompatibleDebts) ...[
                const SizedBox(width: 12),
                Flexible(flex: 0, child: applyButton),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _MiniStat({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.14), borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: Colors.white),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.72), fontSize: 12, fontWeight: FontWeight.w700)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
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
            Expanded(child: Text(money.format(payment.amount), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
            Chip(label: Text(statusText), backgroundColor: statusColor.withOpacity(0.12), labelStyle: TextStyle(color: statusColor, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 4),
          Text('Registró: ${memberName(payment.paidByMemberId)} · Fecha: ${payment.date}', style: const TextStyle(color: Colors.black54)),
          if (payment.status == 'confirmed') ...[
            const SizedBox(height: 4),
            Text('Aplicado a deuda: ${money.format(payment.appliedAmount)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            if (payment.creditAmount > 0.01) Text('Excedente a favor: ${money.format(payment.creditAmount)}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w800)),
          ],
          if (payment.status == 'rejected' && payment.rejectedReason.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Motivo: ${payment.rejectedReason}', style: const TextStyle(color: Colors.red)),
          ],
          if (payment.note.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(payment.note),
          ],
          if (canConfirm || canReject) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              ElevatedButton.icon(onPressed: onConfirm, icon: const Icon(Icons.check_circle_outline), label: const Text('Confirmar recibido')),
              OutlinedButton.icon(onPressed: onReject, icon: const Icon(Icons.cancel_outlined), label: const Text('Rechazar')),
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
    final sourceText = debt.source == 'automatic' ? 'Ajuste mensual ${debt.sourceMonth ?? ''}' : 'Manual';
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
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
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
          if (debt.pendingAmount > 0.01) Text('Pendiente de confirmación: ${money.format(debt.pendingAmount)}', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
          Text('Pendiente real: ${money.format(debt.remainingAmount)}', style: const TextStyle(fontWeight: FontWeight.bold)),
          if (debt.reason.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(debt.reason),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(onPressed: onPayments, icon: const Icon(Icons.receipt_long), label: const Text('Abonos')),
              if (onPay != null) ElevatedButton.icon(onPressed: onPay, icon: const Icon(Icons.payments), label: const Text('Abonar')),
              if (onCancel != null) TextButton.icon(onPressed: onCancel, icon: const Icon(Icons.cancel_outlined), label: const Text('Cancelar')),
            ],
          ),
        ],
      ),
    );
  }
}
