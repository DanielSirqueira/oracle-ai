import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../core/brand.dart';

/// Renders agent-authored markdown (rule/memory/skill content, session
/// messages) instead of showing the raw source. Text stays selectable, and
/// fenced code blocks get the app's dark "snippet" treatment with a copy
/// button.
///
/// Falls back to the app's dark theme text styles automatically — GptMarkdown
/// derives headings/links from the ambient [ThemeData] when no explicit theme
/// extension is registered.
class MarkdownView extends StatelessWidget {
  final String data;
  final TextStyle? style;
  const MarkdownView(this.data, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: GptMarkdown(
        data,
        style: style ?? Theme.of(context).textTheme.bodyMedium,
        codeBuilder: _codeBlock,
      ),
    );
  }

  Widget _codeBlock(BuildContext context, String name, String code, bool closed) {
    // Strip a single trailing newline the parser tends to keep.
    final text = code.endsWith('\n') ? code.substring(0, code.length - 1) : code;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: OracleBrand.gray950,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: OracleBrand.gray700),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (name.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(name.trim(),
                      style: const TextStyle(
                          fontSize: 11, color: OracleBrand.gray400)),
                ),
              const Spacer(),
              IconButton(
                tooltip: 'Copy',
                iconSize: 15,
                visualDensity: VisualDensity.compact,
                onPressed: () => Clipboard.setData(ClipboardData(text: text)),
                icon: const Icon(Icons.copy, color: OracleBrand.gray400),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(text,
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                      height: 1.45,
                      color: OracleBrand.gray100)),
            ),
          ),
        ],
      ),
    );
  }
}
