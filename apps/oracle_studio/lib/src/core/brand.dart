import 'package:flutter/material.dart';

/// Oracle AI design system — Untitled UI-inspired dark theme carrying the
/// brand palette (violet → blue from the logo) over a refined gray scale,
/// Inter typography, bordered surfaces and structured settings components.
class OracleBrand {
  OracleBrand._();

  // Brand (from the logo)
  static const violet = Color(0xFF7C5CF0);
  static const violetSoft = Color(0xFF9B82F5);
  static const blue = Color(0xFF3B82F6);

  // Untitled-style gray scale (dark mode)
  static const gray950 = Color(0xFF0C111D); // page background
  static const gray900 = Color(0xFF161B26); // cards / surfaces
  static const gray800 = Color(0xFF1F242F); // elevated / hover
  static const gray700 = Color(0xFF333741); // borders
  static const gray500 = Color(0xFF85888E); // tertiary text
  static const gray400 = Color(0xFF94969C); // secondary text
  static const gray100 = Color(0xFFF5F5F6); // primary text

  // Aliases kept for shared widgets
  static const surface = gray900;
  static const surfaceHigh = gray800;

  // Semantic
  static const success = Color(0xFF17B26A);
  static const error = Color(0xFFF04438);
  static const warning = Color(0xFFF79009);

  static const gradient = LinearGradient(
    colors: [violet, blue],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static ThemeData theme() {
    final scheme = ColorScheme.fromSeed(seedColor: violet, brightness: Brightness.dark)
        .copyWith(
      primary: violet,
      secondary: blue,
      surface: gray950,
      surfaceContainerLow: gray900,
      surfaceContainerHighest: gray800,
      outline: gray700,
      error: error,
      onSurface: gray100,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Inter',
      colorScheme: scheme,
      scaffoldBackgroundColor: gray950,
      visualDensity: VisualDensity.comfortable,
      textTheme: const TextTheme(
        headlineSmall: TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.4),
        titleLarge: TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.3),
        titleMedium: TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.2),
        bodySmall: TextStyle(color: gray400, height: 1.5),
        bodyMedium: TextStyle(height: 1.55),
        labelLarge: TextStyle(fontWeight: FontWeight.w500),
      ),
      cardTheme: CardThemeData(
        color: gray900,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: gray700),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: gray900,
        indicatorColor: violet.withValues(alpha: 0.22),
        selectedIconTheme: const IconThemeData(color: violetSoft),
        unselectedIconTheme: const IconThemeData(color: gray500),
        selectedLabelTextStyle: const TextStyle(
            color: gray100, fontWeight: FontWeight.w600, fontSize: 12, fontFamily: 'Inter'),
        unselectedLabelTextStyle:
            const TextStyle(color: gray500, fontSize: 12, fontFamily: 'Inter'),
      ),
      dividerTheme: const DividerThemeData(color: gray700, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: gray950,
        labelStyle: const TextStyle(color: gray400),
        hintStyle: const TextStyle(color: gray500),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: gray700),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: gray700),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: violet, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: violet,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Inter'),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: gray100,
          side: const BorderSide(color: gray700),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Inter'),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: gray400,
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Inter'),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: gray800,
        contentTextStyle: TextStyle(color: gray100, fontFamily: 'Inter'),
        behavior: SnackBarBehavior.floating,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: gray800,
        labelStyle: const TextStyle(color: gray400, fontSize: 12, fontFamily: 'Inter'),
        side: const BorderSide(color: gray700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      listTileTheme: const ListTileThemeData(
        selectedTileColor: Color(0x227C5CF0),
        iconColor: gray400,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.white : gray400),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? violet : gray800),
        trackOutlineColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? violet : gray700),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: gray900,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: gray700),
        ),
      ),
      dataTableTheme: const DataTableThemeData(
        headingTextStyle: TextStyle(
            color: gray400, fontWeight: FontWeight.w600, fontSize: 12, fontFamily: 'Inter'),
      ),
    );
  }
}

/// The round Oracle icon (book + database) at [size].
class OracleLogo extends StatelessWidget {
  final double size;
  const OracleLogo({super.key, this.size = 32});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 4),
      child: Image.asset('assets/icon.png', width: size, height: size, fit: BoxFit.cover),
    );
  }
}

/// Title text painted with the brand gradient.
class GradientTitle extends StatelessWidget {
  final String text;
  final TextStyle? style;
  const GradientTitle(this.text, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.headlineSmall;
    return ShaderMask(
      shaderCallback: (bounds) => OracleBrand.gradient.createShader(bounds),
      child: Text(text,
          style: base?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
    );
  }
}

/// Page header: title + optional supporting text + trailing actions —
/// the Untitled UI "page header" pattern.
class BrandHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const BrandHeader(this.title, {super.key, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GradientTitle(title),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Settings section: card with a header (title + supporting text) and
/// children separated by dividers — the Untitled UI settings pattern.
class SectionCard extends StatelessWidget {
  final String title;
  final String? description;
  final List<Widget> children;
  final Widget? action;
  const SectionCard({
    super.key,
    required this.title,
    this.description,
    required this.children,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    if (description != null) ...[
                      const SizedBox(height: 2),
                      Text(description!, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
              if (action != null) action!,
            ]),
            const SizedBox(height: 8),
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// One settings row: label + supporting text on the left, control on the
/// right. Stacks the control below when it needs the full width.
class SettingRow extends StatelessWidget {
  final String label;
  final String? description;
  final Widget control;
  final bool stacked;
  const SettingRow({
    super.key,
    required this.label,
    this.description,
    required this.control,
    this.stacked = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.w500)),
        if (description != null) ...[
          const SizedBox(height: 2),
          Text(description!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: stacked
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              text,
              const SizedBox(height: 10),
              control,
            ])
          : Row(children: [
              Expanded(flex: 3, child: text),
              const SizedBox(width: 24),
              Flexible(flex: 2, child: Align(alignment: Alignment.centerRight, child: control)),
            ]),
    );
  }
}

/// Status pill with a colored dot (Untitled UI badge).
class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  const StatusBadge(this.label, {super.key, this.color = OracleBrand.success});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
