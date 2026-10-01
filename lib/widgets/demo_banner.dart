import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/demo_data_service.dart';

/// Persistent demo-mode banner: clearly labels the sample data and offers
/// one-tap exit. Hidden entirely when demo mode is off.
class DemoBanner extends StatelessWidget {
  const DemoBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DemoDataService>(
      builder: (context, demo, _) {
        if (!demo.isActive) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.amber.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amber.shade700),
          ),
          child: Row(
            children: [
              Icon(
                Icons.science_outlined,
                color: Colors.amber.shade900,
                size: 28,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'ڈیمو ڈیٹا — یہ اصل ڈیٹا نہیں ہے',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: 'معلومات',
                icon: const Icon(Icons.info_outline),
                onPressed:
                    () => showDialog(
                      context: context,
                      builder:
                          (ctx) => AlertDialog(
                            title: const Text('ڈیمو موڈ'),
                            content: const Text(
                              'یہ نمونہ ڈیٹا ہے تاکہ آپ ایپ آزما سکیں۔\n\n'
                              '• ڈیمو ختم کرنے پر صرف ڈیمو کا ڈیٹا حذف ہوگا۔\n'
                              '• ڈیمو کے دوران بنایا گیا بیک اپ ڈیمو ڈیٹا پر مشتمل ہوگا۔',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(),
                                child: const Text('ٹھیک ہے'),
                              ),
                            ],
                          ),
                    ),
              ),
              TextButton(
                onPressed: () => _confirmExit(context, demo),
                child: const Text(
                  'ڈیمو ختم کریں',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmExit(BuildContext context, DemoDataService demo) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('ڈیمو ختم کریں؟'),
            content: const Text(
              'ڈیمو کا نمونہ ڈیٹا حذف کر دیا جائے گا۔ آپ کا اپنا ڈیٹا محفوظ رہے گا۔',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('منسوخ کریں'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('ختم کریں'),
              ),
            ],
          ),
    );
    if (proceed != true || !context.mounted) return;
    final result = await demo.exitDemo();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.ok ? 'ڈیمو ڈیٹا حذف کر دیا گیا' : result.message!),
      ),
    );
  }
}
