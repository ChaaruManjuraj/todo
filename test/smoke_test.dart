import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo/app.dart';
import 'package:todo/data/memory_repo.dart';
import 'package:todo/ui/clock.dart';
import 'package:todo/ui/theme_controller.dart';

void main() {
  testWidgets('app boots to an empty list', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final theme = await ThemeController.load();
    await tester.pumpWidget(TodoApp(repo: MemoryRepo(), clock: Clock(tick: null), theme: theme));
    await tester.pump();
    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('Nothing to do'), findsOneWidget);
  });
}
