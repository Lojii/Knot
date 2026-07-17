import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knot/widgets/common/app_toast.dart';

void main() {
  testWidgets('showAppToast displays message and auto-dismisses', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => showAppToast(context, 'Copied!'),
            child: const Text('go'),
          );
        }),
      ),
    ));

    await tester.tap(find.text('go'));
    await tester.pump();
    expect(find.text('Copied!'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2100));
    expect(find.text('Copied!'), findsNothing);
  });

  testWidgets('second toast replaces the first', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (c) { ctx = c; return const SizedBox(); })),
    ));
    showAppToast(ctx, 'first');
    await tester.pump();
    showAppToast(ctx, 'second');
    await tester.pump();
    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2100));
  });
}
