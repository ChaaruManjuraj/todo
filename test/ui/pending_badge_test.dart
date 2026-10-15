import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo/app.dart';
import 'package:todo/data/memory_repo.dart';
import 'package:todo/ui/clock.dart';
import 'package:todo/ui/theme_controller.dart';

void main() {
  Future<MemoryRepo> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = MemoryRepo();
    await tester.pumpWidget(TodoApp(repo: repo, clock: Clock(now: () => DateTime(2026, 10, 15), tick: null), theme: await ThemeController.load()));
    await tester.pump();
    return repo;
  }

  testWidgets('nothing is shown when there are no pending writes', (tester) async {
    await pump(tester);
    expect(find.textContaining('pending'), findsNothing);
  });

  testWidgets('pending writes show "offline · N pending" only after 3 seconds', (tester) async {
    final repo = await pump(tester);
    repo.pending.value = 2;
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('pending'), findsNothing); // a normal save clears before this
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('offline · 2 pending'), findsOneWidget);
    repo.pending.value = 3;
    await tester.pump();
    expect(find.text('offline · 3 pending'), findsOneWidget);
  });

  testWidgets('it disappears as soon as the outbox empties', (tester) async {
    final repo = await pump(tester);
    repo.pending.value = 1;
    await tester.pump(const Duration(seconds: 4));
    expect(find.textContaining('pending'), findsOneWidget);
    repo.pending.value = 0;
    await tester.pump();
    expect(find.textContaining('pending'), findsNothing);
  });

  testWidgets('a write that clears before 3 seconds never shows it', (tester) async {
    final repo = await pump(tester);
    repo.pending.value = 1;
    await tester.pump(const Duration(seconds: 1));
    repo.pending.value = 0;
    await tester.pump(const Duration(seconds: 5));
    expect(find.textContaining('pending'), findsNothing);
  });
}
