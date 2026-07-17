import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knot/widgets/common/empty_state.dart';

void main() {
  testWidgets('renders icon, title, description and action', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EmptyState(
          icon: Icons.inbox,
          title: 'No requests',
          description: 'Start capturing to see traffic',
          action: TextButton(onPressed: () {}, child: const Text('Start')),
        ),
      ),
    ));
    expect(find.byIcon(Icons.inbox), findsOneWidget);
    expect(find.text('No requests'), findsOneWidget);
    expect(find.text('Start capturing to see traffic'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('description and action are optional', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: EmptyState(icon: Icons.inbox, title: 'Empty')),
    ));
    expect(find.text('Empty'), findsOneWidget);
  });
}
