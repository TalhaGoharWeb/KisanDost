// Widget + PDF tests for Phase 9 exports.
//
// Proves the risky part: a report widget rendered into an OFFSCREEN overlay
// entry can be captured as a PNG (full content, not viewport-clipped) and
// embedded into a real PDF file.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisan_dost/models/models.dart';
import 'package:kisan_dost/models/party.dart';
import 'package:kisan_dost/providers/crop_provider.dart';
import 'package:kisan_dost/services/export_service.dart';
import 'package:kisan_dost/services/pdf_report_service.dart';
import 'package:kisan_dost/services/pnl_summary.dart';
import 'package:kisan_dost/widgets/report_widgets.dart';

CropSeasonWithDetails _season(int id, String crop) => CropSeasonWithDetails(
  cropSeason: CropSeason(
    id: id,
    fieldId: 1,
    cropName: crop,
    variety: 'v',
    status: 'harvested',
    startDate: '2025-11-01',
  ),
  fields: const [],
  fieldNames: const ['f'],
  farmNames: const ['farm'],
  totalArea: 5,
);

CropPnlResult _crop(String crop, int income, int expenses) => CropPnlResult(
  details: _season(1, crop),
  incomePaisa: income,
  expensesPaisa: expenses,
  harvests: const [],
  activities: const [],
);

void main() {
  testWidgets('P&L report captures offscreen to full-content PNG', (
    tester,
  ) async {
    // 8 crop lines make the report much taller than any test surface —
    // if the capture were viewport-clipped, height would be small.
    final data = PnlReportData(
      pnl: FarmPnl(
        totalSalesPaisa: 8000000,
        totalExpensesPaisa: 3200000,
        crops: [for (var i = 0; i < 8; i++) _crop('Wheat', 1000000, 400000)],
      ),
      cropNameUrdu: const {'Wheat': 'گندم'},
      generatedOn: '2026-10-01',
    );

    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );

    // Start the capture (inserts the offscreen overlay synchronously), then
    // drive the two frames it waits for.
    final captureFuture = captureReportPng(ctx, PnlReportWidget(data: data));
    await tester.pump();
    await tester.pump();
    final png = await tester.runAsync(() => captureFuture);
    expect(png, isNotNull);
    expect(png!.lengthInBytes, greaterThan(10000));

    // Image decoding needs real async — keep it inside runAsync.
    final dims = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final dims = (image.width, image.height);
      image.dispose();
      return dims;
    });
    // Width = 720 logical * 2.0 pixel ratio.
    expect(dims?.$1, 1440);
    // Full content: 8 crop cards + summary — far taller than a phone screen.
    expect(dims?.$2, greaterThan(3000));
  });

  testWidgets('receipt widget renders with all fields', (tester) async {
    final data = ReceiptData(
      partyName: 'احمد',
      entry: PartyLedgerEntry(
        partyId: 1,
        type: PartyEntryType.wusooli,
        amountPaisa: 200000,
        date: '2026-09-15',
        note: 'نقد',
        createdAt: '2026-09-15',
      ),
      balanceAfterPaisa: 300000,
      generatedOn: '2026-10-01',
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ReceiptWidget(data: data))),
    );
    expect(find.text('رسید'), findsOneWidget);
    expect(find.text('احمد'), findsOneWidget);
    expect(find.text('وصولی'), findsOneWidget);
  });

  test('pngToPdfBytes produces a real PDF', () async {
    // Minimal valid PNG (1x1) — we only need the PDF wrapper here.
    final png = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
      0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, // IDAT
      0x54, 0x08, 0xD7, 0x63, 0xF8, 0xFF, 0xFF, 0x3F,
      0x00, 0x05, 0xFE, 0x02, 0xFE, 0xDC, 0xCC, 0x59,
      0xE7, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, // IEND
      0x44, 0xAE, 0x42, 0x60, 0x82,
    ]);
    final pdf = await pngToPdfBytes(png);
    expect(pdf.lengthInBytes, greaterThan(500));
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
  });
}
