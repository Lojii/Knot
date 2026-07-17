import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knot/widgets/common/app_text_field.dart';

void main() {
  testWidgets('renders hint, forwards onChanged', (tester) async {
    String? changed;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppTextField(hintText: 'Search...', onChanged: (v) => changed = v),
      ),
    ));
    expect(find.text('Search...'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'abc');
    expect(changed, 'abc');
  });
}
