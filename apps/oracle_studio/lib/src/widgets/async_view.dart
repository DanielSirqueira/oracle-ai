import 'package:flutter/material.dart';

import '../core/l10n.dart';

/// Uniform loading/error/data rendering for page futures.
class AsyncView<T> extends StatelessWidget {
  final Future<T> future;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback? onRetry;
  const AsyncView({
    super.key,
    required this.future,
    required this.builder,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 36),
                    const SizedBox(height: 12),
                    Text(
                      '${l10n.t('common.loadError')}: ${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                    if (onRetry != null) ...[
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh),
                        label: Text(l10n.t('app.retry')),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }
        return builder(context, snapshot.data as T);
      },
    );
  }
}

/// Small labeled chip used across detail panes.
class MetaChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  const MetaChip(this.label, {super.key, this.icon});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: icon == null ? null : Icon(icon, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Master/detail two-pane layout used by the browser pages.
class MasterDetail extends StatelessWidget {
  final Widget master;
  final Widget detail;
  const MasterDetail({super.key, required this.master, required this.detail});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 2, child: master),
        const VerticalDivider(width: 1),
        Expanded(flex: 3, child: detail),
      ],
    );
  }
}
