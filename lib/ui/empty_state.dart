import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

bool get _hasKeyboardShortcuts => kIsWeb || const {TargetPlatform.linux, TargetPlatform.windows, TargetPlatform.macOS}.contains(defaultTargetPlatform);

/// Shown when there is nothing to list. Says how to add a task instead of just "nothing here".
class EmptyState extends StatelessWidget {
  const EmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Image.asset('assets/logo/logo.png', width: 88, height: 88, semanticLabel: 'TODO'),
          const SizedBox(height: 20),
          Text('Nothing to do', style: text.titleMedium),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              _hasKeyboardShortcuts
                  ? 'Type a task above and press Enter. Press N from anywhere to jump back to the bar.'
                  : 'Type a task above and tap done on your keyboard to add it.',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ]),
      ),
    );
  }
}
