import 'dart:convert';
import 'dart:io';

import '../domain/task.dart';

/// A write made locally that the server hasn't acknowledged yet.
class Op {
  Op.upsert(Task this.task, this.at)
      : id = task.id,
        delete = false;
  Op.delete(this.id, this.at)
      : task = null,
        delete = true;

  final String id;
  final bool delete;
  final Task? task;

  /// When the user made the change (device clock); compared with the server's `updatedAt` on conflict.
  final DateTime at;

  Map<String, Object?> toJson() => {'id': id, 'delete': delete, 'task': task?.toJson(), 'at': at.toUtc().toIso8601String()};

  factory Op.fromJson(Map<String, Object?> j) => j['delete'] == true
      ? Op.delete(j['id'] as String, DateTime.parse(j['at'] as String))
      : Op.upsert(Task.fromJson((j['task'] as Map).cast<String, Object?>()), DateTime.parse(j['at'] as String));
}

/// JSON files in the cache directory, written via a temp file so a crash can't leave half a file.
class JsonFile {
  JsonFile(Directory dir, String name) : _file = File('${dir.path}/$name');

  final File _file;

  Object? read() {
    try {
      return jsonDecode(_file.readAsStringSync());
    } on FileSystemException {
      return null; // first run
    } on FormatException {
      return null; // corrupt: start from the server's copy
    }
  }

  void write(Object? value) {
    final tmp = File('${_file.path}.tmp')..writeAsStringSync(jsonEncode(value), flush: true);
    tmp.renameSync(_file.path);
  }
}
