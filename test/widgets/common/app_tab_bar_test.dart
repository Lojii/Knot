import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knot/theme/app_theme.dart';
import 'package:knot/widgets/common/app_tab_bar.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: child),
      );

  testWidgets('renders tabs, highlights active, fires onChanged', (tester) async {
    int? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppTabBar(
          tabs: const ['List', 'Waterfall'],
          activeIndex: 0,
          onChanged: (i) => selected = i,
        ),
      ),
    ));
    expect(find.text('List'), findsOneWidget);
    expect(find.text('Waterfall'), findsOneWidget);
    await tester.tap(find.text('Waterfall'));
    expect(selected, 1);
  });

  testWidgets('renders optional leading label', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppTabBar(
          tabs: const ['Headers', 'Body'],
          activeIndex: 0,
          onChanged: (_) {},
          label: 'REQUEST',
        ),
      ),
    ));
    expect(find.text('REQUEST'), findsOneWidget);
  });

  testWidgets('active tab pill uses detailTab.activeBackground, inactive is transparent',
      (tester) async {
    await tester.pumpWidget(wrap(AppTabBar(
      tabs: const ['List', 'Waterfall'],
      activeIndex: 0,
      onChanged: (_) {},
    )));

    final containers = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) => c.decoration is BoxDecoration)
        .toList();

    final activeDecoration = containers[0].decoration! as BoxDecoration;
    final inactiveDecoration = containers[1].decoration! as BoxDecoration;

    expect(activeDecoration.color, AppTheme.lightMode.detailTab.activeBackground);
    expect(inactiveDecoration.color, Colors.transparent);
  });

  testWidgets('hovering an inactive tab shows a 50%-alpha pill', (tester) async {
    await tester.pumpWidget(wrap(AppTabBar(
      tabs: const ['List', 'Waterfall'],
      activeIndex: 0,
      onChanged: (_) {},
    )));

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();

    await gesture.moveTo(tester.getCenter(find.text('Waterfall')));
    await tester.pumpAndSettle();

    final container = tester.widget<Container>(
      find.ancestor(of: find.text('Waterfall'), matching: find.byType(Container)).first,
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(
      decoration.color,
      AppTheme.lightMode.detailTab.activeBackground.withValues(alpha: 0.5),
    );
  });

  testWidgets('hovering the active tab keeps full activeBackground', (tester) async {
    await tester.pumpWidget(wrap(AppTabBar(
      tabs: const ['List', 'Waterfall'],
      activeIndex: 0,
      onChanged: (_) {},
    )));

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();

    await gesture.moveTo(tester.getCenter(find.text('List')));
    await tester.pumpAndSettle();

    final container = tester.widget<Container>(
      find.ancestor(of: find.text('List'), matching: find.byType(Container)).first,
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.color, AppTheme.lightMode.detailTab.activeBackground);
  });

  testWidgets('horizontalPadding overrides the default pill padding', (tester) async {
    await tester.pumpWidget(wrap(AppTabBar(
      tabs: const ['List', 'Waterfall'],
      activeIndex: 0,
      onChanged: (_) {},
      horizontalPadding: AppTheme.spacing.sm,
    )));

    final container = tester.widget<Container>(
      find.ancestor(of: find.text('List'), matching: find.byType(Container)).first,
    );
    expect(
      container.padding,
      EdgeInsets.symmetric(horizontal: AppTheme.spacing.sm, vertical: 2),
    );
  });

  testWidgets('tabs expose button semantics; active tab is selected', (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(wrap(AppTabBar(
      tabs: const ['List', 'Waterfall'],
      activeIndex: 0,
      onChanged: (_) {},
    )));

    final active = tester.getSemantics(find.text('List'));
    expect(active.flagsCollection.isButton, isTrue);
    expect(active.flagsCollection.isSelected, Tristate.isTrue);

    final inactive = tester.getSemantics(find.text('Waterfall'));
    expect(inactive.flagsCollection.isButton, isTrue);
    expect(inactive.flagsCollection.isSelected, isNot(Tristate.isTrue));

    handle.dispose();
  });
}
