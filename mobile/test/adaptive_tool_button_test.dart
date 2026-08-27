import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moongate/widgets/adaptive_tool_button.dart';

Widget _host(double width, {String label = 'File System'}) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: AdaptiveToolButton(
              icon: Icons.folder_open_rounded,
              label: label,
              onPressed: () {},
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('a wide button shows icon and label', (tester) async {
    await tester.pumpWidget(_host(220));
    expect(find.text('File System'), findsOneWidget);
    expect(find.byIcon(Icons.folder_open_rounded), findsOneWidget);
  });

  testWidgets('a narrow button collapses to a tooltipped icon', (tester) async {
    await tester.pumpWidget(_host(60));
    expect(find.text('File System'), findsNothing);
    expect(find.byIcon(Icons.folder_open_rounded), findsOneWidget);
    expect(find.byTooltip('File System'), findsOneWidget);
  });

  testWidgets('a short label keeps its text where a long one would not',
      (tester) async {
    // Half a 2-column tile is roughly this wide; "Console" fits there while
    // the widths the narrow test uses would not.
    await tester.pumpWidget(_host(140, label: 'Console'));
    expect(find.text('Console'), findsOneWidget);
  });
}
