import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knot/widgets/common/hoverable.dart';

void main() {
  testWidgets('builder receives hover state and onTap fires', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: Hoverable(
          onTap: () => tapped = true,
          builder: (context, hovered) => Container(
            width: 60,
            height: 24,
            color: hovered ? Colors.blue : Colors.transparent,
            child: Text(hovered ? 'hover' : 'idle'),
          ),
        ),
      ),
    ));

    expect(find.text('idle'), findsOneWidget);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(Hoverable)));
    await tester.pump();
    expect(find.text('hover'), findsOneWidget);

    await tester.tap(find.byType(Hoverable));
    expect(tapped, isTrue);
  });

  testWidgets('hover state clears when pointer exits', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: Hoverable(
          onTap: () {},
          builder: (context, hovered) => SizedBox(
            width: 60,
            height: 24,
            child: Text(hovered ? 'hover' : 'idle'),
          ),
        ),
      ),
    ));

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    await gesture.moveTo(tester.getCenter(find.byType(Hoverable)));
    await tester.pump();
    expect(find.text('hover'), findsOneWidget);

    await gesture.moveTo(Offset.zero);
    await tester.pump();
    expect(find.text('idle'), findsOneWidget);
  });

  testWidgets('cursor: explicit override wins; no onTap resolves to basic',
      (tester) async {
    MouseCursor cursorOf(Finder hoverable) {
      final region = tester.widget<MouseRegion>(find.descendant(
        of: hoverable,
        matching: find.byType(MouseRegion),
      ));
      return region.cursor;
    }

    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: Hoverable(
          onTap: () {},
          cursor: SystemMouseCursors.resizeColumn,
          builder: (context, hovered) =>
              const SizedBox(width: 60, height: 24),
        ),
      ),
    ));
    expect(
      cursorOf(find.byType(Hoverable)),
      SystemMouseCursors.resizeColumn,
    );

    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: Hoverable(
          builder: (context, hovered) =>
              const SizedBox(width: 60, height: 24),
        ),
      ),
    ));
    expect(cursorOf(find.byType(Hoverable)), SystemMouseCursors.basic);
  });

  testWidgets('onSecondaryTapUp fires on right click', (tester) async {
    var fired = false;
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: Hoverable(
          onSecondaryTapUp: (details) => fired = true,
          builder: (context, hovered) =>
              const SizedBox(width: 60, height: 24),
        ),
      ),
    ));

    await tester.tap(find.byType(Hoverable), buttons: kSecondaryButton);
    expect(fired, isTrue);
  });
}
