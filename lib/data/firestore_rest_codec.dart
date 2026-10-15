import '../domain/task.dart';

Map<String, Object?> _str(String? v) => v == null ? {'nullValue': null} : {'stringValue': v};
Map<String, Object?> _ts(DateTime? v) => v == null ? {'nullValue': null} : {'timestampValue': v.toUtc().toIso8601String()};

/// A [Task] as Firestore REST typed values (`stringValue`, `nullValue`, ...).
Map<String, Object?> toFirestoreFields(Task t) => {
      'name': {'stringValue': t.name},
      'startDate': _str(t.startDate),
      'startTime': _str(t.startTime),
      'endDate': _str(t.endDate),
      'endTime': _str(t.endTime),
      // An empty array has no "values" key on the wire.
      'people': {
        'arrayValue': t.people.isEmpty
            ? <String, Object?>{}
            : {
                'values': [for (final p in t.people) {'stringValue': p}]
              },
      },
      'notes': {'stringValue': t.notes},
      'reminder': {'booleanValue': t.reminder},
      'done': {'booleanValue': t.done},
      'doneAt': _ts(t.doneAt),
      'createdAt': _ts(t.createdAt),
      'updatedAt': _ts(t.updatedAt),
    };

/// Parses a REST document (`{name, fields, createTime, updateTime}`). The id is the last segment of `name`.
Task fromFirestoreDoc(Map<String, Object?> doc) {
  final f = (doc['fields'] as Map?)?.cast<String, Object?>() ?? const {};
  Object? v(String k, String type) => (f[k] as Map?)?[type];
  String? str(String k) => v(k, 'stringValue') as String?;
  DateTime? ts(String k) => v(k, 'timestampValue') is String ? DateTime.parse(v(k, 'timestampValue') as String).toUtc() : null;
  DateTime fallback(String key) => doc[key] is String ? DateTime.parse(doc[key] as String).toUtc() : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  final people = ((v('people', 'arrayValue') as Map?)?['values'] as List? ?? const []);
  return Task(
    id: (doc['name'] as String).split('/').last,
    name: str('name') ?? '',
    startDate: str('startDate'),
    startTime: str('startTime'),
    endDate: str('endDate'),
    endTime: str('endTime'),
    people: [for (final p in people) (p as Map)['stringValue'] as String],
    notes: str('notes') ?? '',
    reminder: v('reminder', 'booleanValue') as bool? ?? false,
    done: v('done', 'booleanValue') as bool? ?? false,
    doneAt: ts('doneAt'),
    createdAt: ts('createdAt') ?? fallback('createTime'),
    updatedAt: ts('updatedAt') ?? fallback('updateTime'),
  );
}
