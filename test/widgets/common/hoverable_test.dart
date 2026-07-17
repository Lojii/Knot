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
}
