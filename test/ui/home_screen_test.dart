import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo/app.dart';
import 'package:todo/data/memory_repo.dart';
import 'package:todo/domain/task.dart';
import 'package:todo/ui/clock.dart';
import 'package:todo/ui/theme_controller.dart';

final t0 = DateTime.utc(2026, 10, 1);
var fakeNow = DateTime(2026, 10, 15, 11, 0);

Task mk(String id, {String? date, String? time, bool reminder = false, bool done = false, DateTime? doneAt, List<String> people = const []}) =>
    Task(id: id, name: 'task $id', startDate: date, startTime: time, reminder: reminder, done: done, doneAt: doneAt, people: people, createdAt: t0, updatedAt: t0);

Future<Clock> pumpApp(WidgetTester tester, List<Task> tasks, {ThemeController? theme}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final clock = Clock(now: () => fakeNow, tick: null);
  await tester.pumpWidget(TodoApp(repo: MemoryRepo(tasks), clock: clock, theme: theme ?? await ThemeController.load()));
  await tester.pump();
  return clock;
}

double top(WidgetTester t, String text) => t.getTopLeft(find.text(text)).dy;

void main() {
  setUp(() => fakeNow = DateTime(2026, 10, 15, 11, 0));

  testWidgets('sections render in order with their tasks', (tester) async {
    await pumpApp(tester, [
      mk('n'),
      mk('l', date: '2026-12-01'),
      mk('tm', date: '2026-10-16'),
      mk('t', date: '2026-10-15'),
      mk('p', date: '2026-10-01'),
      mk('c', done: true, doneAt: fakeNow),
    ]);
    final headers = ['Past', 'Today', 'Tomorrow', 'Later', 'No date', 'Completed'];
    final ys = [for (final h in headers) top(tester, h)];
    expect(ys, orderedEquals([...ys]..sort()));
    for (final id in ['n', 'l', 'tm', 't', 'p', 'c']) {
      expect(find.text('task $id'), findsOneWidget);
    }
  });

  testWidgets('empty sections are hidden', (tester) async {
    await pumpApp(tester, [mk('t', date: '2026-10-15')]);
    expect(find.text('Today'), findsOneWidget);
    for (final h in ['Past', 'Tomorrow', 'Later', 'No date', 'Completed']) {
      expect(find.text(h), findsNothing);
    }
  });

  testWidgets('row shows time range, people, and the date in Later', (tester) async {
    await pumpApp(tester, [
      mk('a', date: '2026-10-15', time: '10:00', people: ['Ann']).copyWith(endTime: '11:00'),
      mk('b', date: '2026-10-20'),
    ]);
    expect(find.text('10:00–11:00'), findsOneWidget);
    expect(find.text('Ann'), findsOneWidget);
    expect(find.text('Tue 20 Oct'), findsOneWidget);
  });

  testWidgets('completed tasks are struck through', (tester) async {
    await pumpApp(tester, [mk('c', done: true, doneAt: fakeNow)]);
    final style = tester.widget<Text>(find.text('task c')).style;
    expect(style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('completed older than 24h are hidden until "Show all completed"', (tester) async {
    await pumpApp(tester, [mk('old', done: true, doneAt: fakeNow.subtract(const Duration(days: 3)))]);
    expect(find.text('task old'), findsNothing);
    await tester.tap(find.byType(PopupMenuButton<Object>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show all completed'));
    await tester.pumpAndSettle();
    expect(find.text('task old'), findsOneWidget);
  });

  testWidgets('Due appears after the clock ticks past the reminder time', (tester) async {
    final clock = await pumpApp(tester, [mk('r', date: '2026-10-15', time: '12:00', reminder: true)]);
    expect(find.text('Due'), findsNothing);
    fakeNow = DateTime(2026, 10, 15, 12, 1);
    clock.refresh();
    await tester.pump();
    expect(find.text('Due'), findsOneWidget);
  });

  testWidgets('Due also appears when the app resumes', (tester) async {
    await pumpApp(tester, [mk('r', date: '2026-10-15', time: '12:00', reminder: true)]);
    fakeNow = DateTime(2026, 10, 15, 12, 30);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('Due'), findsOneWidget);
  });

  testWidgets('no Due without a reminder, and not for done tasks', (tester) async {
    await pumpApp(tester, [
      mk('a', date: '2026-10-01'),
      mk('b', date: '2026-10-01', reminder: true, done: true, doneAt: fakeNow),
    ]);
    expect(find.text('Due'), findsNothing);
  });

  testWidgets('bell and checkbox carry semantic labels', (tester) async {
    final h = tester.ensureSemantics();
    await pumpApp(tester, [mk('r', date: '2026-10-15', reminder: true)]);
    expect(find.bySemanticsLabel(RegExp('Reminder on')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Mark "task r" done')), findsOneWidget);
    h.dispose();
  });

  testWidgets('picking Dark in the menu switches the theme', (tester) async {
    await pumpApp(tester, []);
    await tester.tap(find.byType(PopupMenuButton<Object>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.byType(Scaffold))).brightness, Brightness.dark);
  });

  test('theme defaults to system and persists across a restart', () async {
    SharedPreferences.setMockInitialValues({});
    final first = await ThemeController.load();
    expect(first.value, ThemeMode.system);
    await first.set(ThemeMode.dark);
    expect((await ThemeController.load()).value, ThemeMode.dark);
  });
}
