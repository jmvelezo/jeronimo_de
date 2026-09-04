import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jeronimo_de/models/app_models.dart';
import 'package:jeronimo_de/screens/debts_screen.dart';
import 'package:jeronimo_de/services/api_service.dart';

DebtItem debt(int id, String status) => DebtItem(
  id: id, debtorMemberId: 1, creditorMemberId: 2, source: 'manual',
  sourceMonth: null, originalAmount: 100.25,
  paidAmount: status == 'paid' ? 100.25 : 0, pendingAmount: 0,
  remainingAmount: status == 'paid' ? 0 : 100.25,
  reason: 'Registro $id', status: status,
);

CreditBalanceItem credit(int id, double amount, {String status = 'available'}) => CreditBalanceItem(
  id: id, ownerMemberId: 1, counterpartyMemberId: 2, sourcePaymentId: null,
  originalAmount: amount, remainingAmount: amount, status: status,
  reason: 'Crédito $id', createdAt: '',
);

class FakeApi extends ApiService {
  FakeApi() : super(baseUrl: 'http://unused.invalid');
  List<DebtItem> rows = [debt(1, 'active'), debt(2, 'paid'), debt(3, 'cancelled')];
  List<CreditBalanceItem> balances = [];
  double? applied;
  Completer<void>? gate;
  int applicationCalls = 0;
  @override
  Future<List<DebtItem>> getDebts({bool includeCancelled = false}) async {
    expect(includeCancelled, isTrue);
    return rows;
  }
  @override
  Future<List<CreditBalanceItem>> getCreditBalances({bool activeOnly = true}) async => balances;
  @override
  Future<void> applyAvailableCredit({required int debtId,
      required double amount}) async {
    applicationCalls++;
    if (gate != null) await gate!.future;
    applied = amount;
    rows = [debt(1, 'paid'), debt(2, 'paid'), debt(3, 'cancelled')];
    balances = [];
  }
}

Future<void> openScreen(WidgetTester tester, FakeApi api) async {
  tester.view.resetPhysicalSize();
  tester.view.physicalSize = const Size(1100, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: DebtsScreen(
    api: api, members: [
      Member(id: 1, householdId: 1, name: 'Uno', color: '#000000', role: 'member', isActive: true),
      Member(id: 2, householdId: 1, name: 'Dos', color: '#000000', role: 'member', isActive: true),
    ], month: '2026-09', currentMemberId: 1,
  )));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('bloquea un segundo envío y el cierre durante la aplicación', (tester) async {
    final api = FakeApi()..balances = [credit(1, 100.25)]..gate = Completer<void>();
    await openScreen(tester, api);
    await tester.tap(find.text('Aplicar a deuda'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar saldo'));
    await tester.pump();
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.close)).onPressed, isNull);
    await tester.tap(find.text('Aplicando...'));
    await tester.pump();
    expect(api.applicationCalls, 1);
    api.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
  });
  testWidgets('varios créditos con la misma persona tienen un único botón y total', (tester) async {
    final api = FakeApi()..balances = [credit(1, 40.10), credit(2, 60.15)];
    await openScreen(tester, api);
    expect(find.text('Aplicar a deuda'), findsOneWidget);
    await tester.tap(find.text('Aplicar a deuda'));
    await tester.pumpAndSettle();
    expect(find.text('100,25'), findsOneWidget);
    await tester.tap(find.text('Aplicar saldo'));
    await tester.pumpAndSettle();
    expect(api.applied, 100.25);
  });
  testWidgets('separa pendientes del historial sin borrar registros', (tester) async {
    await openScreen(tester, FakeApi());
    expect(find.text('Registro 1'), findsOneWidget);
    expect(find.text('Registro 2'), findsNothing);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text('Registro 1'), findsNothing);
    expect(find.text('Registro 2'), findsOneWidget);
    expect(find.text('Registro 3'), findsOneWidget);
  });

  testWidgets('abono conserva centavos y la X cierra sólo el formulario', (tester) async {
    await openScreen(tester, FakeApi());
    await tester.ensureVisible(find.text('Abonar'));
    await tester.tap(find.text('Abonar'));
    await tester.pumpAndSettle();
    expect(find.text('100,25'), findsOneWidget);
    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(DebtsScreen), findsOneWidget);
  });

  testWidgets('oculta créditos agotados y muestra centavos sin redondear a cero', (tester) async {
    final api = FakeApi()..balances = [credit(1, 0), credit(2, 0.25), credit(3, 30, status: 'used')];
    await openScreen(tester, api);
    expect(find.text('Crédito 1'), findsNothing);
    expect(find.text('Crédito 3'), findsNothing);
    await tester.tap(find.text('Aplicar a deuda'));
    await tester.pumpAndSettle();
    expect(find.text('0,25'), findsOneWidget);
    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(api.applied, isNull);
  });

  testWidgets('al saldar con crédito pasa automáticamente al historial', (tester) async {
    final api = FakeApi()..balances = [credit(1, 100.25)];
    await openScreen(tester, api);
    await tester.tap(find.text('Aplicar a deuda'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar saldo'));
    await tester.pumpAndSettle();
    expect(api.applied, 100.25);
    expect(find.text('Registro 1'), findsNothing);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text('Registro 1'), findsOneWidget);
  });
}
