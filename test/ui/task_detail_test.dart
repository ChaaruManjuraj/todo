import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo/app.dart';
import 'package:todo/data/memory_repo.dart';
import 'package:todo/domain/task.dart';
import 'package:todo/ui/clock.dart';
import 'package:todo/ui/task_detail.dart';
import 'package:todo/ui/theme_controller.dart';

final t0 = DateTime.utc(2026, 10, 1);
final fakeNow = DateTime(2026, 10, 15, 11, 0); // a Thursday

Task mk({String name = 'task a', String? date, String? time, bool reminder = false}) =>
    Task(id: 'a', name: name, startDate: date, startTime: time, reminder: reminder, createdAt: t0, updatedAt: t0);

class Probe {
  Task? saved;
  int deletes = 0, closes = 0;
}

Future<Probe> pumpDetail(WidgetTester tester, Task task, {List<String> people = const []}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final p = Probe();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: TaskDetail(
        task: task,
        knownPeople: people,
        now: fakeNow,
        onSave: (t) => p.saved = t,
        onDelete: () => p.deletes++,
        onClose: () => p.closes++,
      ),
    ),
  ));
  await tester.pump();
  return p;
}

OutlinedButton button(WidgetTester t, String text) => t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, text));
FilledButton saveButton(WidgetTester t) => t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'));

void main() {
  testWidgets('time, end and reminder controls are disabled without a start date', (tester) async {
    await pumpDetail(tester, mk());
    expect(button(tester, 'Start date').onPressed, isNotNull);
    for (final l in ['Start time', 'End date', 'End time']) {
      expect(button(tester, l).onPressed, isNull, reason: l);
    }
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
  });

  testWidgets('controls enable once a start date exists', (tester) async {
    await pumpDetail(tester, mk(date: '2026-10-15'));
    for (final l in ['Start time', 'End date', 'End time']) {
      expect(button(tester, l).onPressed, isNotNull, reason: l);
    }
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNotNull);
  });

  testWidgets('picking a start date through the picker sets it', (tester) async {
    final p = await pumpDetail(tester, mk());
    await tester.tap(find.widgetWithText(OutlinedButton, 'Start date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Thu 15 Oct'), findsOneWidget);
    await tester.tap(find.text('Save'));
    expect(p.saved!.startDate, '2026-10-15');
  });

  testWidgets('clearing the start date clears time, end and the reminder', (tester) async {
    final p = await pumpDetail(tester, mk(date: '2026-10-15', time: '10:00', reminder: true).copyWith(endDate: '2026-10-16', endTime: '11:00'));
    await tester.tap(find.byTooltip('Clear Start date'));
    await tester.pump();
    expect(button(tester, 'Start time').onPressed, isNull);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    await tester.tap(find.text('Save'));
    final s = p.saved!;
    expect([s.startDate, s.startTime, s.endDate, s.endTime], everyElement(isNull));
    expect(s.reminder, isFalse);
  });

  testWidgets('end before start shows an error and blocks saving', (tester) async {
    await pumpDetail(tester, mk(date: '2026-10-15', time: '10:00').copyWith(endTime: '09:00'));
    expect(find.text('End must be after start'), findsOneWidget);
    expect(saveButton(tester).onPressed, isNull);
  });

  testWidgets('an empty name blocks saving', (tester) async {
    await pumpDetail(tester, mk());
    await tester.enterText(find.widgetWithText(TextField, 'task a'), '');
    await tester.pump();
    expect(saveButton(tester).onPressed, isNull);
    expect(find.text('Name is required'), findsOneWidget);
  });

  testWidgets('people suggestions come from names on other tasks', (tester) async {
    final p = await pumpDetail(tester, mk(), people: ['Ann', 'Bo']);
    await tester.enterText(find.widgetWithText(TextField, 'People'), 'an');
    await tester.pumpAndSettle();
    expect(find.text('Ann'), findsOneWidget);
    expect(find.text('Bo'), findsNothing);
    await tester.tap(find.text('Ann'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'Ann'), findsOneWidget);
    await tester.tap(find.text('Save'));
    expect(p.saved!.people, ['Ann']);
  });

  testWidgets('a brand new name can be added with Enter, and removed', (tester) async {
    final p = await pumpDetail(tester, mk(), people: ['Ann']);
    await tester.enterText(find.widgetWithText(TextField, 'People'), 'Zed');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'Zed'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove Zed')); // tapping the chip removes the person
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'Zed'), findsNothing);
    await tester.tap(find.text('Save'));
    expect(p.saved!.people, isEmpty);
  });

  testWidgets('Enter saves, Esc closes', (tester) async {
    final p = await pumpDetail(tester, mk());
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(p.saved?.name, 'task a');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(p.closes, 1);
  });

  testWidgets('Enter does not save while typing in the notes field', (tester) async {
    final p = await pumpDetail(tester, mk());
    await tester.tap(find.widgetWithText(TextField, 'Notes'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(p.saved, isNull);
  });

  testWidgets('Delete calls onDelete', (tester) async {
    final p = await pumpDetail(tester, mk());
    await tester.tap(find.text('Delete'));
    expect(p.deletes, 1);
  });

  group('inside the home screen', () {
    Future<MemoryRepo> home(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final repo = MemoryRepo([mk()]);
      await tester.pumpWidget(TodoApp(repo: repo, clock: Clock(now: () => fakeNow, tick: null), theme: await ThemeController.load()));
      await tester.pump();
      return repo;
    }

    testWidgets('narrow screens use a bottom sheet; Esc closes it', (tester) async {
      await home(tester, const Size(400, 900));
      await tester.tap(find.text('task a'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(TaskDetail), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(TaskDetail), findsNothing);
    });

    testWidgets('wide screens use a side panel; Esc closes it', (tester) async {
      await home(tester, const Size(1200, 900));
      await tester.tap(find.text('task a'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(TaskDetail), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(TaskDetail), findsNothing);
    });

    testWidgets('editing and saving updates the list', (tester) async {
      final repo = await home(tester, const Size(1200, 900));
      await tester.tap(find.text('task a'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'task a'), 'Renamed');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect((await repo.watch().first).single.name, 'Renamed');
      expect(find.text('Renamed'), findsOneWidget);
      expect(find.byType(TaskDetail), findsNothing);
    });

    testWidgets('delete removes the task from the list', (tester) async {
      final repo = await home(tester, const Size(1200, 900));
      await tester.tap(find.text('task a'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('task a'), findsNothing); // hidden at once
      await tester.pump(const Duration(seconds: 6)); // ...deleted for real when the Undo snackbar expires
      await tester.pumpAndSettle();
      expect(await repo.watch().first, isEmpty);
    });
  });
}
