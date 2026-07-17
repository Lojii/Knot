import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knot/theme/app_theme.dart';
import 'package:knot/widgets/common/app_button.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: Center(child: child)),
      );

  BoxDecoration decorationOf(WidgetTester tester, String label) {
    final container = tester.widget<Container>(
      find.ancestor(of: find.text(label), matching: find.byType(Container)).first,
    );
    return container.decoration! as BoxDecoration;
  }

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

  testWidgets('primary variant renders solid primary background without border',
      (tester) async {
    await tester.pumpWidget(wrap(AppButton(
      label: 'Send',
      variant: AppButtonVariant.primary,
      onPressed: () {},
    )));
    final decoration = decorationOf(tester, 'Send');
    expect(decoration.color, AppTheme.lightMode.colors.primary);
    expect(decoration.border, isNull);
  });

  testWidgets('secondary variant renders transparent background with border',
      (tester) async {
    await tester.pumpWidget(wrap(AppButton(
      label: 'Cancel',
      variant: AppButtonVariant.secondary,
      onPressed: () {},
    )));
    final decoration = decorationOf(tester, 'Cancel');
    expect(decoration.color, Colors.transparent);
    expect(decoration.border, isNotNull);
  });

  testWidgets('destructive variant renders red label text', (tester) async {
    await tester.pumpWidget(wrap(AppButton(
      label: 'Delete',
      variant: AppButtonVariant.destructive,
      onPressed: () {},
    )));
    final text = tester.widget<Text>(find.text('Delete'));
    expect(text.style?.color, AppTheme.lightMode.colors.diffRemoved);
  });

  testWidgets('isLoading shows spinner and blocks onPressed', (tester) async {
    var pressed = false;
    await tester.pumpWidget(wrap(AppButton(
      label: 'Send',
      isLoading: true,
      onPressed: () => pressed = true,
    )));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.text('Send'));
    expect(pressed, isFalse);
  });
}
