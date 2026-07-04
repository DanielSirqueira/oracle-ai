import 'package:flutter/material.dart';

/// Uniform loading/error/data rendering for page futures.
class AsyncView<T> extends StatelessWidget {
  final Future<T> future;
  final Widget Function(BuildContext context, T data) builder;
  const AsyncView({super.key, required this.future, required this.builder});

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
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Erro ao carregar: ${snapshot.error}'),
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
