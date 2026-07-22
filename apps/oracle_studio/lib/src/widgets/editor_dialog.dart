import 'package:flutter/material.dart';

import '../core/l10n.dart';

/// Shared building blocks for the curation dialogs.

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String? okLabel,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.t('common.cancel')),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                )
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(okLabel ?? l10n.t('common.confirm')),
        ),
      ],
    ),
  );
  return result ?? false;
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Untitled UI form field: a label (and optional helper text) ABOVE the input,
/// not a floating label — clearer and more explanatory.
class FieldRow extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final int maxLines;
  final String? hint;

  /// Explanatory helper text shown under the label — use it to say what the
  /// field is for, so the form documents itself.
  final String? description;
  final bool enabled;
  final bool expandable;
  const FieldRow(
    this.label,
    this.controller, {
    super.key,
    this.maxLines = 1,
    this.hint,
    this.description,
    this.enabled = true,
    this.expandable = false,
  });

  Future<void> _openExpandedEditor(BuildContext context) async {
    final draft = TextEditingController(text: controller.text);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$label — ${l10n.t('flows.expandedEditor')}'),
        content: SizedBox(
          width: 720,
          child: TextField(
            controller: draft,
            autofocus: true,
            minLines: 12,
            maxLines: 22,
            enabled: enabled,
            decoration: InputDecoration(
              hintText: hint,
              alignLabelWithHint: true,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.t('common.cancel')),
          ),
          FilledButton(
            onPressed: enabled
                ? () => Navigator.pop(dialogContext, true)
                : null,
            child: Text(l10n.t('common.save')),
          ),
        ],
      ),
    );
    if (saved == true) controller.text = draft.text;
    draft.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
          if (description != null) ...[
            const SizedBox(height: 2),
            Text(description!, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            maxLines: maxLines,
            enabled: enabled,
            decoration: InputDecoration(
              hintText: hint,
              isDense: true,
              suffixIcon: expandable
                  ? IconButton(
                      tooltip: l10n.t('flows.expandField'),
                      icon: const Icon(Icons.open_in_full, size: 17),
                      onPressed: () => _openExpandedEditor(context),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Standard editor dialog frame (title + scrollable form + Cancelar/Salvar).
Future<bool?> showEditorDialog(
  BuildContext context, {
  required String title,
  required List<Widget> Function(BuildContext context, StateSetter setState)
  fields,
  required Future<String?> Function() onSave,
  double width = 640,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      String? error;
      var saving = false;
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: width,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...fields(context, setState),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(context, false),
              child: Text(l10n.t('common.cancel')),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      setState(() => saving = true);
                      final failure = await onSave();
                      if (failure == null) {
                        if (context.mounted) Navigator.pop(context, true);
                      } else {
                        setState(() {
                          saving = false;
                          error = failure;
                        });
                      }
                    },
              child: Text(
                saving ? l10n.t('common.saving') : l10n.t('common.save'),
              ),
            ),
          ],
        ),
      );
    },
  );
}

List<String> parseTags(String raw) =>
    raw.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
