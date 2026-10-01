// PDF report generation for Kisan Dost.
//
// Urdu text is rendered by embedding a PNG captured from real Flutter
// widgets (see widgets/report_widgets.dart) — never by the `pdf` package's
// text engine, whose RTL/bidi handling renders Urdu reversed/misordered
// (verified by spike, 2026-10-01).
//
// Flow: build report widget → [captureReportPng] (offscreen overlay +
// RepaintBoundary) → [pngToPdfBytes] (embed full-bleed PNG in one PDF page).
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Captures [child] (a report widget, e.g. [PnlReportWidget]) as a PNG.
///
/// The widget is inserted into an offscreen [OverlayEntry] so the user never
/// sees it; a modal progress indicator should be shown by the caller while
/// this runs. Throws a Urdu [StateError]-style [Exception] when capture
/// fails — callers surface it as a snackbar.
Future<Uint8List> captureReportPng(
  BuildContext context,
  Widget child, {
  double width = 720,
  double pixelRatio = 2.0,
}) async {
  final key = GlobalKey();
  final overlay = Overlay.of(context);
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      // Far offscreen: laid out and painted, but never visible.
      top: -20000,
      left: 0,
      child: Material(
        color: Colors.white,
        child: SizedBox(
          width: width,
          child: RepaintBoundary(key: key, child: child),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  try {
    // Wait for the overlay content to be laid out and painted. endOfFrame
    // waits for real frame completion (not a magic delay), so this works in
    // the live app and under WidgetTester alike. Two frames for safety: the
    // first builds the inserted entry, the second guarantees its paint.
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    final obj = key.currentContext?.findRenderObject();
    if (obj is! RenderRepaintBoundary) {
      throw Exception('رپورٹ تیار نہیں ہو سکی — دوبارہ کوشش کریں');
    }
    final image = await obj.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw Exception('رپورٹ تیار نہیں ہو سکی — دوبارہ کوشش کریں');
    }
    return byteData.buffer.asUint8List();
  } finally {
    entry.remove();
  }
}

/// Embeds a report PNG as a single full-page PDF. Pure function — the only
/// PDF-generating code in the app, and the only place `package:pdf` text
/// rendering would live (it doesn't: all text arrives as pixels).
Future<Uint8List> pngToPdfBytes(Uint8List pngBytes) async {
  final doc = pw.Document();
  final image = pw.MemoryImage(pngBytes);
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Center(
        child: pw.Image(image, fit: pw.BoxFit.contain),
      ),
    ),
  );
  return doc.save();
}
