import 'package:fl_clash/widgets/popup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<PopupOpen> pumpBox(WidgetTester tester) async {
    late PopupOpen open;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: CommonPopupBox(
              targetBuilder: (value) {
                open = value;
                return const SizedBox(width: 40, height: 40);
              },
              popup: const SizedBox(width: 80, height: 80, key: Key('popup')),
            ),
          ),
        ),
      ),
    );
    return open;
  }

  testWidgets('opening pushes the popup above the target', (tester) async {
    final open = await pumpBox(tester);

    open();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('popup')), findsOneWidget);
  });

  testWidgets('dismissing the barrier closes the popup', (tester) async {
    final open = await pumpBox(tester);
    open();
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('popup')), findsNothing);
  });
}
