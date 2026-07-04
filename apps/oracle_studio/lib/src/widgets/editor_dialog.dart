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
            child: Text(l10n.t('common.cancel'))),
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

class FieldRow extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final int maxLines;
  final String? hint;
  final bool enabled;
  const FieldRow(
    this.label,
    this.controller, {
    super.key,
    this.maxLines = 1,
    this.hint,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        enabled: enabled,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}

/// Standard editor dialog frame (title + scrollable form + Cancelar/Salvar).
Future<bool?> showEditorDialog(
  BuildContext context, {
  required String title,
  required List<Widget> Function(BuildContext context, StateSetter setState) fields,
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
                      child: Text(error!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: saving ? null : () => Navigator.pop(context, false),
                child: Text(l10n.t('common.cancel'))),
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
              child: Text(saving ? l10n.t('common.saving') : l10n.t('common.save')),
            ),
          ],
        ),
      );
    },
  );
}

List<String> parseTags(String raw) => raw
    .split(',')
    .map((t) => t.trim())
    .where((t) => t.isNotEmpty)
    .toList();
