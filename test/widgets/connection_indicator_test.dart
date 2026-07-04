import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:knot/api/ws_client.dart';
import 'package:knot/i18n/translations.dart';
import 'package:knot/widgets/connection_indicator.dart';
import 'package:knot/theme/app_theme.dart';

void main() {
  setUpAll(() {
    AppTheme.loadFromJson('{}');
  });

  Widget buildWidget(WsStatus status) {
    return GetMaterialApp(
      translations: AppTranslations(),
      locale: const Locale('en', 'US'),
      home: Scaffold(
        body: ConnectionIndicator(status: status),
      ),
    );
  }

  group('ConnectionIndicator', () {
    testWidgets('shows "Connected" with green for connected status',
        (tester) async {
      await tester.pumpWidget(buildWidget(WsStatus.connected));

      expect(find.text('Connected'), findsOneWidget);

      final text = tester.widget<Text>(find.text('Connected'));
      expect(text.style?.color, AppTheme.lightMode.colors.statusConnected);

      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, AppTheme.lightMode.colors.statusConnected);
    });

    testWidgets('shows "Connecting..." with orange for connecting status',
        (tester) async {
      await tester.pumpWidget(buildWidget(WsStatus.connecting));

      expect(find.text('Connecting...'), findsOneWidget);

      final text = tester.widget<Text>(find.text('Connecting...'));
      expect(text.style?.color, AppTheme.lightMode.colors.statusConnecting);

      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, AppTheme.lightMode.colors.statusConnecting);
    });

    testWidgets('shows "Disconnected" with red for disconnected status',
        (tester) async {
      await tester.pumpWidget(buildWidget(WsStatus.disconnected));

      expect(find.text('Disconnected'), findsOneWidget);

      final text = tester.widget<Text>(find.text('Disconnected'));
      expect(text.style?.color, AppTheme.lightMode.colors.statusDisconnected);

      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, AppTheme.lightMode.colors.statusDisconnected);
    });

    testWidgets('renders dot with circle shape', (tester) async {
      await tester.pumpWidget(buildWidget(WsStatus.connected));

      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
    });

    testWidgets('dot matches connectionDotSize', (tester) async {
      await tester.pumpWidget(buildWidget(WsStatus.connected));

      final container = tester.widget<Container>(find.byType(Container));
      expect(container.constraints?.maxWidth, AppTheme.sizing.connectionDotSize);
      expect(container.constraints?.maxHeight, AppTheme.sizing.connectionDotSize);
    });
  });
}
