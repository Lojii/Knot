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

  testWidgets('forwards onSubmitted', (tester) async {
    String? submitted;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppTextField(onSubmitted: (v) => submitted = v),
      ),
    ));
    await tester.enterText(find.byType(TextField), 'query');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(submitted, 'query');
  });

  testWidgets('forwards custom style', (tester) async {
    const custom = TextStyle(fontFamily: 'X', fontSize: 9);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: AppTextField(style: custom),
      ),
    ));
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.style, custom);
  });

  testWidgets('forwards multiline params: expands, maxLines null, textAlignVertical',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 100,
          child: AppTextField(
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
          ),
        ),
      ),
    ));
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.expands, isTrue);
    expect(field.maxLines, isNull);
    expect(field.textAlignVertical, TextAlignVertical.top);
  });

  testWidgets('forwards suffixIcon and suffixIconConstraints', (tester) async {
    const constraints = BoxConstraints(minWidth: 0, minHeight: 0);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: AppTextField(
          suffixIcon: Icon(Icons.clear),
          suffixIconConstraints: constraints,
        ),
      ),
    ));
    final field = tester.widget<TextField>(find.byType(TextField));
    expect((field.decoration!.suffixIcon as Icon).icon, Icons.clear);
    expect(field.decoration!.suffixIconConstraints, constraints);
    expect(find.byIcon(Icons.clear), findsOneWidget);
  });
}
