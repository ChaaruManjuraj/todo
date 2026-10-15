// The REST wire format and the security rules, against a real Firestore emulator. Skipped when none is running:
//   firebase emulators:exec --only firestore --project todo-ba12a "flutter test test/data/rest_emulator_test.dart"
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:todo/data/rest_repo.dart';
import 'package:todo/domain/task.dart';

final emulator = Platform.environment['FIRESTORE_EMULATOR_HOST'];

/// The emulator accepts unsigned JWTs and applies the rules to the uid inside.
String jwtFor(String uid) {
  String b64(Object j) => base64Url.encode(utf8.encode(jsonEncode(j))).replaceAll('=', '');
  return '${b64({'alg': 'none', 'typ': 'JWT'})}.${b64({'user_id': uid, 'sub': uid, 'iat': 0})}.';
}

Task mk(String id, {String name = 'Buy milk'}) {
  final now = DateTime.now().toUtc();
  return Task(
      id: id, name: name, startDate: '2026-10-15', startTime: '10:00', endTime: '11:00', people: ['Ann', 'Bo'], notes: 'n', reminder: true, createdAt: now, updatedAt: now);
}

void main() {
  late Directory dir;
  final opened = <RestRepo>[];

  Future<RestRepo> open(String uid) async {
    dir = Directory.systemTemp.createTempSync('restemu');
    final r = await RestRepo.open(
      client: http.Client(),
      idToken: ({bool forceRefresh = false}) async => jwtFor(uid),
      cacheDir: dir,
      uid: uid,
      project: 'todo-ba12a',
      host: 'http://$emulator',
      poll: null,
    );
    opened.add(r);
    return r;
  }

  tearDown(() {
    for (final r in opened) {
      r.dispose();
    }
    opened.clear();
  });

  group('against the Firestore emulator', skip: emulator == null ? 'no emulator (FIRESTORE_EMULATOR_HOST unset)' : false, () {
    test('a task written by one device is read back intact by another', () async {
      final a = await open('alice');
      await a.upsert(mk('t1'));
      await a.refresh();
      expect(a.pending.value, 0);

      final b = await open('alice'); // a fresh cache, as on a second computer
      await b.refresh();
      final got = (await b.watch().first).singleWhere((t) => t.id == 't1');
      expect(got.name, 'Buy milk');
      expect([got.startDate, got.startTime, got.endTime], ['2026-10-15', '10:00', '11:00']);
      expect(got.people, ['Ann', 'Bo']);
      expect(got.reminder, isTrue);
      expect(got.updatedAt.isAfter(DateTime.utc(2025)), isTrue);
    });

    test('an edit replaces the task and a delete removes it', () async {
      final a = await open('alice2');
      await a.upsert(mk('t1', name: 'one'));
      await a.refresh();
      await a.upsert(mk('t1', name: 'two'));
      await a.refresh();
      expect((await a.watch().first).single.name, 'two');
      await a.delete('t1');
      await a.refresh();
      final b = await open('alice2');
      await b.refresh();
      expect(await b.watch().first, isEmpty);
    });

    test('the rules reject a malformed task, and it is dropped from the outbox', () async {
      final a = await open('alice3');
      await a.upsert(mk('bad', name: 'x' * 201));
      await a.refresh();
      expect(a.pending.value, 0);
      final b = await open('alice3');
      await b.refresh();
      expect(await b.watch().first, isEmpty);
    });

    test("one user can't read another user's tasks", () async {
      final owner = await open('owner');
      await owner.upsert(mk('secret'));
      await owner.refresh();
      // same collection path as the owner, but authenticated as someone else
      final intruder = await RestRepo.open(
        client: http.Client(),
        idToken: ({bool forceRefresh = false}) async => jwtFor('mallory'),
        cacheDir: Directory.systemTemp.createTempSync('restemu'),
        uid: 'owner',
        project: 'todo-ba12a',
        host: 'http://$emulator',
        poll: null,
      );
      opened.add(intruder);
      await intruder.refresh();
      expect(await intruder.watch().first, isEmpty);
    });
  });
}
