import 'package:flutter_test/flutter_test.dart';

import 'package:panda_ledger/main.dart';

void main() {
  testWidgets('App renders', (WidgetTester tester) async {
    await tester.pumpWidget(const PandaLedgerApp());
    expect(find.text('🐼 熊猫记账'), findsOneWidget);
  });
}
