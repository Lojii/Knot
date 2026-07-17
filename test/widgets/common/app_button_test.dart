import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knot/widgets/common/app_button.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

  testWidgets('renders label and fires onPressed', (tester) async {
    var pressed = false;
    await tester.pumpWidget(wrap(AppButton(
      label: 'Save',
      onPressed: () => pressed = true,
    )));
    expect(find.text('Save'), findsOneWidget);
    await tester.tap(find.text('Save'));
    expect(pressed, isTrue);
  });

  testWidgets('disabled button renders at reduced opacity', (tester) async {
    await tester.pumpWidget(wrap(const AppButton(
      label: 'Save',
      onPressed: null,
    )));
    final opacity = tester.widget<Opacity>(
      find.ancestor(of: find.text('Save'), matching: find.byType(Opacity)).first,
    );
    expect(opacity.opacity, 0.4);
  });

  testWidgets('shows tooltip and icon', (tester) async {
    await tester.pumpWidget(wrap(const AppButton(
      label: 'Start',
      icon: Icons.play_arrow,
      tooltip: 'Start capture',
      onPressed: null,
    )));
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byType(Tooltip), findsOneWidget);
  });
}
