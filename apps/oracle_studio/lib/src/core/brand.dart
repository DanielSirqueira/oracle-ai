import 'package:flutter/material.dart';

/// Oracle AI visual identity — colors lifted from the logo (violet database →
/// blue arc on a deep dark field) plus the shared theme and brand widgets.
class OracleBrand {
  OracleBrand._();

  static const violet = Color(0xFF7C5CF0);
  static const violetDeep = Color(0xFF5B3FD6);
  static const blue = Color(0xFF3B82F6);
  static const bg = Color(0xFF15141F);
  static const surface = Color(0xFF1E1C2E);
  static const surfaceHigh = Color(0xFF262438);

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
      surface: bg,
      surfaceContainerLow: const Color(0xFF191826),
      surfaceContainerHighest: surfaceHigh,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      visualDensity: VisualDensity.comfortable,
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: violet.withValues(alpha: 0.16)),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: const Color(0xFF191826),
        indicatorColor: violet.withValues(alpha: 0.28),
        selectedIconTheme: const IconThemeData(color: Colors.white),
        selectedLabelTextStyle:
            const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ),
      dividerTheme: DividerThemeData(color: violet.withValues(alpha: 0.12)),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: violet, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: violet,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: surfaceHigh,
        contentTextStyle: TextStyle(color: Colors.white),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceHigh,
        side: BorderSide(color: violet.withValues(alpha: 0.2)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

/// Page header: gradient title + a short gradient underline accent.
class BrandHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const BrandHeader(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GradientTitle(title),
            const SizedBox(height: 6),
            Container(
              width: 56,
              height: 3,
              decoration: BoxDecoration(
                gradient: OracleBrand.gradient,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
  }
}
