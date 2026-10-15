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

Task mk(String id, String name, {String? date, String? time, bool reminder = false, bool done = false, List<String> people = const []}) => Task(
    id: id,
    name: name,
    startDate: date,
    startTime: time,
    reminder: reminder,
    done: done,
    doneAt: done ? fakeNow : null,
    people: people,
    createdAt: t0,
    updatedAt: t0);

final tasks = [
  mk('p', 'Send invoice', date: '2026-10-13', time: '09:00', reminder: true, people: ['Priya']),
  mk('t', 'Review the pull request', date: '2026-10-15', time: '14:00', reminder: true, people: ['Sam']),
  mk('n', 'Read the design docs'),
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

Future<void> pump(WidgetTester tester, {required bool dark, bool signedOut = false}) async {
  tester.view.physicalSize = const Size(390, 800) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'themeMode': dark ? 'dark' : 'light'});
  final clock = Clock(now: () => fakeNow, tick: null);
  final theme = await ThemeController.load();
  await tester.pumpWidget(signedOut
      ? TodoApp(clock: clock, theme: theme, auth: _SignedOut(), repoFor: (_) => MemoryRepo())
      : TodoApp(repo: MemoryRepo(tasks), clock: clock, theme: theme));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    group('$mode theme', () {
      testWidgets('task list: tap targets are at least 48dp and labeled', (tester) async {
        final h = tester.ensureSemantics();
        await pump(tester, dark: dark);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        h.dispose();
      });

      testWidgets('task list: rendered text has enough contrast', (tester) async {
        final h = tester.ensureSemantics();
        await pump(tester, dark: dark);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        h.dispose();
      });

      testWidgets('detail sheet: tap targets, labels and contrast', (tester) async {
        final h = tester.ensureSemantics();
        await pump(tester, dark: dark);
        await tester.tap(find.text('Review the pull request'));
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        h.dispose();
      });

      testWidgets('sign-in: tap targets, labels and contrast', (tester) async {
        final h = tester.ensureSemantics();
        await pump(tester, dark: dark, signedOut: true);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        h.dispose();
      });
    });
  }
}
