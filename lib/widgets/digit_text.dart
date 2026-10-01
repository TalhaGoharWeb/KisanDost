import 'package:flutter/material.dart';

/// Text rendered in the app's numeric font (Noto Sans) with tabular figures.
///
/// All money amounts (via [Money.format]) and quantities should use this
/// widget instead of [Text]: Jameel Noori Nastaleeq's digits are decorative
/// and hard to scan, while Noto Sans digits are clear and — with
/// [FontFeature.tabularFigures] — line up in columns and tables.
///
/// Non-Latin characters (e.g. the "روپے" in "1,250 روپے") fall back to
/// Jameel Noori Nastaleeq via [fontFamilyFallback], so mixed strings keep
/// their Urdu styling. This is a display-only concern: parsing stays in
/// [Money]/[Quantity], which accept both Western and Urdu digits.
class DigitText extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final int? maxLines;
  final TextOverflow? overflow;

  const DigitText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.textDirection,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style;
    return Text(
      data,
      style: base
          .merge(style)
          .copyWith(
            fontFamily: 'Noto Sans',
            fontFamilyFallback: const ['Jameel Noori Nastaleeq'],
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
      textAlign: textAlign,
      textDirection: textDirection,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
