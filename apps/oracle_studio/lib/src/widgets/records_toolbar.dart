import 'package:flutter/material.dart';

import '../core/brand.dart';
import '../core/l10n.dart';

/// Shared collection header used by every record browser in Studio.
class RecordsToolbar extends StatelessWidget {
  final String title;
  final String description;
  final TextEditingController? searchController;
  final String? searchHint;
  final ValueChanged<String>? onSearchChanged;
  final ValueChanged<String>? onSearchSubmitted;
  final VoidCallback onRefresh;
  final int? resultCount;
  final bool refreshing;
  final List<Widget> filters;
  final List<Widget> actions;

  const RecordsToolbar({
    super.key,
    required this.title,
    required this.description,
    required this.onRefresh,
    this.searchController,
    this.searchHint,
    this.onSearchChanged,
    this.onSearchSubmitted,
    this.resultCount,
    this.refreshing = false,
    this.filters = const [],
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: OracleBrand.gray400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              ..._spaced(actions),
              if (actions.isNotEmpty) const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: refreshing ? null : onRefresh,
                icon: refreshing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 18),
                label: Text(l10n.t('common.refresh')),
              ),
            ],
          ),
          if (searchController != null ||
              filters.isNotEmpty ||
              resultCount != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                if (searchController != null)
                  SizedBox(
                    width: 360,
                    child: TextField(
                      controller: searchController,
                      onChanged: onSearchChanged,
                      onSubmitted: onSearchSubmitted,
                      decoration: InputDecoration(
                        hintText: searchHint ?? l10n.t('records.search'),
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: searchController!.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: l10n.t('records.clearSearch'),
                                onPressed: () {
                                  searchController!.clear();
                                  onSearchChanged?.call('');
                                },
                                icon: const Icon(Icons.close, size: 18),
                              ),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                if (searchController != null && filters.isNotEmpty)
                  const SizedBox(width: 12),
                if (filters.isNotEmpty)
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: _spaced(filters)),
                    ),
                  )
                else
                  const Spacer(),
                if (resultCount != null) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$resultCount ${resultCount == 1 ? l10n.t('records.result') : l10n.t('records.results')}',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  static List<Widget> _spaced(List<Widget> widgets) {
    final result = <Widget>[];
    for (var i = 0; i < widgets.length; i++) {
      if (i > 0) result.add(const SizedBox(width: 8));
      result.add(widgets[i]);
    }
    return result;
  }
}

class RecordsEmptyState extends StatelessWidget {
  final String title;
  final String? description;
  final IconData icon;
  final Widget? action;

  const RecordsEmptyState({
    super.key,
    required this.title,
    this.description,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (description != null) ...[
              const SizedBox(height: 6),
              Text(
                description!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: OracleBrand.gray400),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    ),
  );
}
