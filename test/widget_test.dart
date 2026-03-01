import 'package:flutter_test/flutter_test.dart';

import 'package:ftp_client/main.dart';

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const FTPClientApp());

    // Wait for async operations
    await tester.pumpAndSettle();

    // Verify that the app shows the FTP Client title
    expect(find.text('FTP Client'), findsOneWidget);
  });
}
