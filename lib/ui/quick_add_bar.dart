import 'dart:math';

import 'package:flutter/material.dart';

final _rng = Random();

/// Unique enough for a personal task list; Firestore accepts any string id.
String newTaskId() => '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_rng.nextInt(1 << 31).toRadixString(36)}';

/// Type a name, press Enter: a task with no date.
class QuickAddBar extends StatefulWidget {
  const QuickAddBar({super.key, required this.onSubmit, required this.focusNode});

  final ValueChanged<String> onSubmit;
  final FocusNode focusNode;

  @override
  State<QuickAddBar> createState() => _QuickAddBarState();
}

class _QuickAddBarState extends State<QuickAddBar> {
  final _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _submit(String v) {
    final name = v.trim();
    if (name.isNotEmpty) {
      widget.onSubmit(name);
      _ctl.clear();
    }
    widget.focusNode.requestFocus(); // Enter would otherwise drop focus on some platforms
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: TextField(
          controller: _ctl,
          focusNode: widget.focusNode,
          maxLength: 200,
          buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
          textInputAction: TextInputAction.done,
          onSubmitted: _submit,
          decoration: InputDecoration(
            hintText: 'Add a task',
            prefixIcon: Icon(Icons.add_rounded, color: Theme.of(context).colorScheme.primary),
            border: _pill(Theme.of(context).colorScheme.outlineVariant),
            enabledBorder: _pill(Theme.of(context).colorScheme.outlineVariant),
            focusedBorder: _pill(Theme.of(context).colorScheme.primary, width: 2),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      );
}

OutlineInputBorder _pill(Color color, {double width = 1}) =>
    OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide(color: color, width: width));
