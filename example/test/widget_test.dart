import 'package:flutter_test/flutter_test.dart';
import 'package:blurhashx_example/main.dart';

void main() {
  testWidgets('BlurHash example app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const BlurHashExampleApp());
    expect(find.text('BlurHashX Playground'), findsOneWidget);
  });
}
