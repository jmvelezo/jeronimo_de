import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/app_models.dart';
import '../services/api_service.dart';
import '../services/friendly_messages.dart';
import '../widgets/app_card.dart';
import '../widgets/app_shell.dart';

class ExpensesScreen extends StatefulWidget {
  final ApiService api;
  final List<Member> members;
  final String month;
  final Future<void> Function()? onChanged;

  const ExpensesScreen({
    super.key,
    required this.api,
    required this.members,
    required this.month,
    this.onChanged,
  });

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final money = NumberFormat.currency(locale: 'es_AR', symbol: r'$ ', decimalDigits: 0);
  bool loading = true;
  String? error;
  List<ExpenseItem> expenses = [];

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
      final loaded = await widget.api.getExpenses(widget.month);
      setState(() => expenses = loaded);
    } catch (e) {
      setState(() => error = friendlyMessage(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = expenses.fold<double>(0, (sum, expense) => sum + expense.amount);
    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: Text('Gastos ${widget.month}'),
        actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh))],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 96),
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Gastos cargados', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    Text('Total del mes: ${money.format(total)}', style: const TextStyle(fontSize: 16)),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (error != null) Text(error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              if (loading) const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())),
              if (!loading && expenses.isEmpty) const AppCard(child: Text('Todavía no hay gastos cargados para este mes.')),
              for (final expense in expenses) ...[
                AppCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${expense.category} · ${money.format(expense.amount)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${expense.date} · Pagó ${_memberName(expense.paidByMemberId)}${expense.description.isNotEmpty ? '\n${expense.description}' : ''}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deleteExpense(expense.id),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
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

  String _memberName(int id) {
    return widget.members
        .firstWhere(
          (m) => m.id == id,
          orElse: () => Member(id: id, householdId: 0, name: 'Integrante $id', color: '#000000', role: 'member', isActive: true),
        )
        .name;
  }

  Future<void> _deleteExpense(int expenseId) async {
    try {
      await widget.api.deleteExpense(expenseId);
      await _refresh();
      if (widget.onChanged != null) await widget.onChanged!();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyMessage(e))));
    }
  }
}
