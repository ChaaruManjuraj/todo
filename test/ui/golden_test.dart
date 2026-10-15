// Screenshots of the main screens. Regenerate after an intentional visual change:
//   flutter test --update-goldens test/ui/golden_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo/app.dart';
import 'package:todo/auth/auth_service.dart';
import 'package:todo/data/memory_repo.dart';
import 'package:todo/domain/task.dart';
import 'package:todo/ui/clock.dart';
import 'package:todo/ui/theme_controller.dart';

import 'test_fonts.dart';

final t0 = DateTime.utc(2026, 10, 1);
final fakeNow = DateTime(2026, 10, 15, 11, 0);

Task mk(String id, String name, {String? date, String? time, String? endTime, bool reminder = false, bool done = false, List<String> people = const []}) => Task(
    id: id,
    name: name,
    startDate: date,
    startTime: time,
    endTime: endTime,
    reminder: reminder,
    done: done,
    doneAt: done ? fakeNow.subtract(const Duration(hours: 1)) : null,
    people: people,
    createdAt: t0,
    updatedAt: t0);

final sample = [
  mk('p', 'Send invoice to Priya', date: '2026-10-13', time: '09:00', reminder: true, people: ['Priya']),
  mk('t1', 'Review the pull request', date: '2026-10-15', time: '14:00', endTime: '15:00', reminder: true, people: ['Sam', 'Ana']),
  mk('t2', 'Pick up the dry cleaning', date: '2026-10-15'),
  mk('tm', 'Plan the weekend trip', date: '2026-10-16', time: '09:30', people: ['Ana']),
  mk('l', 'Renew passport', date: '2026-11-02'),
  mk('n', 'Read the new design docs'),
  mk('c', 'Book the dentist', done: true),
];

class _SignedOut implements AuthService {
  @override
  Stream<String?> uid() => Stream.value(null);
  @override
  Future<void> signIn() async {}
  @override
  Future<void> signOut() async {}
}

Future<void> pumpApp(WidgetTester tester, {required Size size, required bool dark, List<Task>? tasks, bool signedOut = false}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'themeMode': dark ? 'dark' : 'light'});
  final clock = Clock(now: () => fakeNow, tick: null);
  final theme = await ThemeController.load();
  await tester.pumpWidget(signedOut
      ? TodoApp(clock: clock, theme: theme, auth: _SignedOut(), repoFor: (_) => MemoryRepo())
      : TodoApp(repo: MemoryRepo(tasks ?? sample), clock: clock, theme: theme));
  await tester.pumpAndSettle();
}

const phone = Size(390, 800);
const wide = Size(1100, 760);

void main() {
  setUpAll(loadAppFonts);

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    testWidgets('list, phone, $mode', (tester) async {
      await pumpApp(tester, size: phone, dark: dark);
      await expectLater(find.byType(TodoApp), matchesGoldenFile('../goldens/list_phone_$mode.png'));
    });

    testWidgets('list with the detail panel open, wide, $mode', (tester) async {
      await pumpApp(tester, size: wide, dark: dark);
      await tester.tap(find.text('Review the pull request'));
      await tester.pumpAndSettle();
      await expectLater(find.byType(TodoApp), matchesGoldenFile('../goldens/list_wide_$mode.png'));
    });

    testWidgets('detail sheet, phone, $mode', (tester) async {
      await pumpApp(tester, size: phone, dark: dark);
      await tester.tap(find.text('Review the pull request'));
      await tester.pumpAndSettle();
      await expectLater(find.byType(TodoApp), matchesGoldenFile('../goldens/detail_sheet_$mode.png'));
    });

    testWidgets('sign-in, phone, $mode', (tester) async {
      await pumpApp(tester, size: phone, dark: dark, signedOut: true);
      await expectLater(find.byType(TodoApp), matchesGoldenFile('../goldens/sign_in_$mode.png'));
    });
  }

  testWidgets('empty state, phone, light', (tester) async {
    await pumpApp(tester, size: phone, dark: false, tasks: const []);
    await expectLater(find.byType(TodoApp), matchesGoldenFile('../goldens/empty_light.png'));
  });
}
