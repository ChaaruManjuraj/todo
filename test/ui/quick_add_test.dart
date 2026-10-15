import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo/app.dart';
import 'package:todo/data/memory_repo.dart';
import 'package:todo/domain/task.dart';
import 'package:todo/ui/clock.dart';
import 'package:todo/ui/theme_controller.dart';

final t0 = DateTime.utc(2026, 10, 1);
final fakeNow = DateTime(2026, 10, 15, 11, 0);

Future<MemoryRepo> pumpHome(WidgetTester tester, {List<Task> tasks = const [], Size size = const Size(800, 2400)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final repo = MemoryRepo(tasks);
  await tester.pumpWidget(TodoApp(repo: repo, clock: Clock(now: () => fakeNow, tick: null), theme: await ThemeController.load()));
  await tester.pump();
  return repo;
}

void main() {
  testWidgets('typing a name and pressing Enter adds a task under "No date"', (tester) async {
    await pumpHome(tester);
    await tester.enterText(find.byType(TextField), 'Buy milk');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('No date'), findsOneWidget);
    expect(find.text('Buy milk'), findsOneWidget);
    // the bar is cleared and ready for the next one
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
  });

  testWidgets('blank input creates nothing', (tester) async {
    final repo = await pumpHome(tester);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(await repo.watch().first, isEmpty);
  });

  testWidgets('N focuses the quick-add bar', (tester) async {
    await pumpHome(tester);
    expect(tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus, isTrue);
  });

  testWidgets('N does not steal focus while typing in another field', (tester) async {
    await pumpHome(tester, tasks: [Task(id: 'a', name: 'task a', createdAt: t0, updatedAt: t0)], size: const Size(1200, 2400));
    await tester.tap(find.text('task a')); // wide layout: opens the side panel, name field autofocuses
    await tester.pumpAndSettle();
    final quick = tester.widget<TextField>(find.byType(TextField).first).focusNode!;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pump();
    expect(quick.hasFocus, isFalse);
  });
}
