// Print-ready report widgets for PDF export.
//
// These widgets are NEVER shown on screen directly. They are rendered
// offscreen inside an [OverlayEntry], captured with [RenderRepaintBoundary]
// into a PNG, and embedded into a PDF (see pdf_report_service.dart).
//
// Why images instead of `pdf` text: the `pdf` package's RTL/bidi handling
// is broken for Urdu (verified by spike 2026-10-01 — text renders
// reversed/misordered). Capturing Flutter-rendered widgets guarantees the
// exact same correct Urdu shaping the farmer sees in the app.
//
// Design notes: fixed logical width (720), white background, generous
// Nastaleeq line heights (2.0) so nothing clips.
import 'package:flutter/material.dart';
import 'digit_text.dart';
import '../models/party.dart';
import '../services/export_service.dart';
import '../services/money.dart';
import '../services/pnl_summary.dart';
import '../l10n/strings.dart';

const String _font = 'Jameel Noori Nastaleeq';
const double _reportWidth = 720.0;

TextStyle _ts(double size, {FontWeight? weight, Color? color}) => TextStyle(
  fontFamily: _font,
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: 2.0,
);

/// Whole-farm P&L report (فارم رپورٹ).
class PnlReportWidget extends StatelessWidget {
  final PnlReportData data;

  const PnlReportWidget({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final pnl = data.pnl;
    final isProfit = pnl.netPaisa >= 0;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        width: _reportWidth,
        color: Colors.white,
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'فارم رپورٹ',
              style: _ts(34, weight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            Text(
              'منافع و نقصان کا حساب',
              style: _ts(20, color: Colors.grey.shade700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'رپورٹ کی تاریخ: ${data.generatedOn}',
              style: _ts(15, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            _summaryBox(
              pnl.totalSalesPaisa,
              pnl.totalExpensesPaisa,
              pnl.netPaisa,
              isProfit,
            ),
            const SizedBox(height: 24),
            Text('فصل وار حساب', style: _ts(22, weight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (pnl.crops.isEmpty)
              Text(
                'کوئی فصل درج نہیں ہے',
                style: _ts(16, color: Colors.grey.shade600),
              )
            else
              for (final c in pnl.crops) _cropLine(c, data.cropNameUrdu),
            const SizedBox(height: 24),
            Text(
              'کسان دوست سے تیار کردہ',
              style: _ts(13, color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryBox(int sales, int expenses, int net, bool isProfit) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isProfit ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isProfit ? Colors.green.shade200 : Colors.red.shade200,
        ),
      ),
      child: Column(
        children: [
          _moneyRow('کل آمدنی (فروخت)', sales, Colors.green.shade800),
          _moneyRow('کل اخراجات', expenses, Colors.red.shade800),
          const Divider(),
          _moneyRow(
            isProfit ? 'خالص بچت' : 'خالص نقصان',
            net.abs(),
            isProfit ? Colors.green.shade900 : Colors.red.shade900,
            bold: true,
          ),
        ],
      ),
    );
  }

  Widget _moneyRow(String label, int paisa, Color color, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: _ts(16, color: Colors.black87)),
          DigitText(
            Money(paisa).format(),
            style: _ts(18, weight: bold ? FontWeight.bold : null, color: color),
          ),
        ],
      ),
    );
  }

  Widget _cropLine(CropPnlResult c, Map<String, String> nameUrdu) {
    final season = c.details.cropSeason;
    final urduName = nameUrdu[season.cropName] ?? season.cropName;
    final isProfit = c.netPaisa >= 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$urduName (${season.variety})',
            style: _ts(18, weight: FontWeight.bold),
          ),
          Text(
            'زمین: ${c.details.farmDisplayName} — کھیت: ${c.details.fieldDisplayName}',
            style: _ts(14, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 4),
          _cropMoneyRow('آمدنی', c.incomePaisa, Colors.green.shade800),
          _cropMoneyRow('اخراجات', c.expensesPaisa, Colors.red.shade800),
          _cropMoneyRow(
            isProfit ? 'بچت' : 'نقصان',
            c.netPaisa.abs(),
            isProfit ? Colors.green.shade900 : Colors.red.shade900,
            bold: true,
          ),
        ],
      ),
    );
  }

  Widget _cropMoneyRow(
    String label,
    int paisa,
    Color color, {
    bool bold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('$label:', style: _ts(15, color: Colors.black87)),
          DigitText(
            Money(paisa).format(),
            style: _ts(16, weight: bold ? FontWeight.bold : null, color: color),
          ),
        ],
      ),
    );
  }
}

/// Payment receipt (رسید) for one party ledger entry.
class ReceiptWidget extends StatelessWidget {
  final ReceiptData data;

  const ReceiptWidget({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final e = data.entry;
    final typeLabel = partyEntryTypeUrdu(e.type);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        width: _reportWidth,
        color: Colors.white,
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'رسید',
              style: _ts(34, weight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            Text(
              'پارٹی کھاتہ',
              style: _ts(20, color: Colors.grey.shade700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            _row('پارٹی', data.partyName),
            _row('قسم', typeLabel),
            _row('رقم', Money(e.amountPaisa.abs()).format()),
            _row(Strings.date, e.date),
            if (e.note != null && e.note!.isNotEmpty) _row('نوٹ', e.note!),
            const Divider(height: 28),
            _row(
              'اس اندراج کے بعد بیلنس',
              _balanceText(data.balanceAfterPaisa),
            ),
            const SizedBox(height: 20),
            Text(
              'کسان دوست سے تیار کردہ — ${data.generatedOn}',
              style: _ts(13, color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _balanceText(int balance) {
    if (balance > 0) return '${Money(balance).format()} (پارٹی سے لینا ہے)';
    if (balance < 0) {
      return '${Money(balance.abs()).format()} (پارٹی کو دینا ہے)';
    }
    return 'حساب برابر';
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: _ts(16, color: Colors.grey.shade700)),
          Flexible(
            child: Text(
              value,
              style: _ts(18, weight: FontWeight.bold),
              textAlign: TextAlign.left,
            ),
          ),
        ],
      ),
    );
  }
}
