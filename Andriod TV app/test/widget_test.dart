import 'package:flutter_test/flutter_test.dart';
import 'package:shapno_tv/main.dart';
import 'package:shapno_tv/services/api_service.dart';

void main() {
  testWidgets('Shapno TV Smoke test', (WidgetTester tester) async {
    final apiService = ApiService();
    await tester.pumpWidget(ShapnoTVApp(apiService: apiService));
    expect(find.text('SHAPNO'), findsOneWidget);
  });
}
