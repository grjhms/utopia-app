import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:utopia_app/widgets/superuser_badge.dart';

void main() {
  testWidgets('SuperUserBadge renders Icon with Icons.verified_rounded', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SuperUserBadge(size: 20),
        ),
      ),
    );

    expect(find.byType(SuperUserBadge), findsOneWidget);
    expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
  });
}

