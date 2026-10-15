import 'package:flutter/material.dart';

/// Chips for the chosen people plus a text field that suggests names used on other tasks.
class PeopleField extends StatefulWidget {
  const PeopleField({super.key, required this.selected, required this.suggestions, required this.onChanged});

  final List<String> selected;
  final List<String> suggestions;
  final ValueChanged<List<String>> onChanged;

  /// True while keyboard focus is inside a [PeopleField] (Enter adds a chip there, it must not save).
  static bool hasFocus() => FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<PeopleField>() != null;

  @override
  State<PeopleField> createState() => _PeopleFieldState();
}

class _PeopleFieldState extends State<PeopleField> {
  TextEditingController? _ctl;

  void _add(String name) {
    final n = name.trim();
    if (n.isNotEmpty && !widget.selected.contains(n)) widget.onChanged([...widget.selected, n]);
    // Clear after the autocomplete has finished writing the selection into the field.
    WidgetsBinding.instance.addPostFrameCallback((_) => _ctl?.clear());
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (widget.selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(spacing: 8, runSpacing: 4, children: [
              for (final p in widget.selected)
                InputChip(label: Text(p), onDeleted: () => widget.onChanged([...widget.selected]..remove(p))),
            ]),
          ),
        Autocomplete<String>(
          optionsBuilder: (v) {
            final q = v.text.trim().toLowerCase();
            if (q.isEmpty) return const [];
            return widget.suggestions.where((s) => s.toLowerCase().contains(q) && !widget.selected.contains(s));
          },
          onSelected: _add,
          fieldViewBuilder: (context, ctl, focus, _) {
            _ctl = ctl;
            return TextField(
              controller: ctl,
              focusNode: focus,
              decoration: const InputDecoration(labelText: 'People', hintText: 'Add a name and press Enter', border: OutlineInputBorder()),
              onSubmitted: (v) {
                _add(v);
                focus.requestFocus();
              },
            );
          },
        ),
      ]);
}
