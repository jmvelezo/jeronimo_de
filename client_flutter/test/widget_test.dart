// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:jeronimo_de/main.dart';
import 'package:jeronimo_de/screens/login_screen.dart';

void main() {
  testWidgets('muestra la pantalla inicial', (WidgetTester tester) async {
    await tester.pumpWidget(const JeronimoDeApp());
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
