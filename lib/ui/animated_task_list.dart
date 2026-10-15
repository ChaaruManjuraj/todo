import 'package:flutter/material.dart';

/// 200ms, or instant when the system asks to reduce motion.
Duration motion(BuildContext context) => MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : const Duration(milliseconds: 200);

class ListEntry {
  const ListEntry(this.key, this.child);

  /// Stable identity across rebuilds; an entry that vanishes animates out, a new one animates in.
  final String key;
  final Widget child;
}

class _Slot {
  _Slot(this.key, this.child, {this.enter = false, this.exiting = false});
  final String key;
  final Widget child;
  final bool enter, exiting;
}

/// A column of [ListEntry]s where inserts fade/expand in and removals fade/collapse out.
class AnimatedTaskList extends StatefulWidget {
  const AnimatedTaskList({super.key, required this.entries});

  final List<ListEntry> entries;

  @override
  State<AnimatedTaskList> createState() => _AnimatedTaskListState();
}

class _AnimatedTaskListState extends State<AnimatedTaskList> {
  late List<_Slot> _slots = [
    for (final e in widget.entries) _Slot(e.key, e.child)
  ];

  @override
  void didUpdateWidget(AnimatedTaskList old) {
    super.didUpdateWidget(old);
    final animate = motion(context) != Duration.zero;
    final known = {for (final s in _slots) s.key};
    final keep = {for (final e in widget.entries) e.key};
    final next = [
      for (final e in widget.entries)
        _Slot(e.key, e.child, enter: animate && !known.contains(e.key))
    ];
    if (animate) {
      // Removed entries stay in place (after the entry that preceded them) until they finish collapsing.
      String? anchor;
      for (final s in _slots) {
        if (keep.contains(s.key)) {
          anchor = s.key;
          continue;
        }
        final at =
            anchor == null ? 0 : next.indexWhere((n) => n.key == anchor) + 1;
        next.insert(at, _Slot(s.key, s.child, exiting: true));
        anchor = s.key;
      }
    }
    _slots = next;
  }

  void _exited(String key) =>
      setState(() => _slots.removeWhere((s) => s.key == key && s.exiting));

  @override
  Widget build(BuildContext context) => ListView(children: [
        for (final s in _slots)
          _Animated(
              key: ValueKey(s.key),
              enter: s.enter,
              exiting: s.exiting,
              onExited: () => _exited(s.key),
              child: s.child),
      ]);
}

class _Animated extends StatefulWidget {
  const _Animated(
      {super.key,
      required this.enter,
      required this.exiting,
      required this.onExited,
      required this.child});

  final bool enter, exiting;
  final VoidCallback onExited;
  final Widget child;

  @override
  State<_Animated> createState() => _AnimatedState();
}

class _AnimatedState extends State<_Animated>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: widget.enter ? 0 : 1);
  late final _curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.dismissed && widget.exiting) widget.onExited();
    });
    if (widget.enter) _c.forward();
  }

  @override
  void didUpdateWidget(_Animated old) {
    super.didUpdateWidget(old);
    if (widget.exiting && !old.exiting) _c.reverse();
    if (!widget.exiting && old.exiting) _c.forward(); // came back (e.g. Undo) before it finished leaving
  }

  @override
  void dispose() {
    _curve.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizeTransition(
        sizeFactor: _curve,
        axisAlignment: -1,
        child: FadeTransition(opacity: _curve, child: widget.child),
      );
}
