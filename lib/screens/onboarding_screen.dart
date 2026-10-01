import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/demo_data_service.dart';
import '../services/onboarding_service.dart';
import 'dashboard_screen.dart';

/// First-run onboarding: 3 simple Urdu pages with large targets.
/// Page 3 offers the choice — start fresh ("شروع کریں") or explore with
/// sample data ("ڈیمو دیکھیں"). Either path marks onboarding complete so
/// this screen never shows again.
///
/// [onCompleted] is a test seam: when provided it is called instead of
/// navigating to the dashboard.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.onCompleted});

  final Future<void> Function()? onCompleted;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pages = PageController();
  int _index = 0;
  bool _busy = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _finish({required bool demo}) async {
    if (_busy) return;
    // Capture before any await (use_build_context_synchronously).
    final demoService = context.read<DemoDataService>();
    setState(() => _busy = true);
    try {
      if (demo) {
        if (await demoService.hasRealData()) {
          final proceed = await _confirmDemoWithData();
          if (proceed != true) {
            if (mounted) setState(() => _busy = false);
            return;
          }
        }
        if (!mounted) return;
        await demoService.enterDemoFromContext(context);
      }
      await OnboardingService.completeOnboarding();
      if (widget.onCompleted != null) {
        await widget.onCompleted!();
      } else if (mounted) {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('کوشش ناکام ہوئی: $e')));
      }
    }
  }

  /// Warns when real data already exists: demo rows are ADDED alongside,
  /// and exiting demo removes only the demo rows.
  Future<bool?> _confirmDemoWithData() {
    return showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('آپ کا اپنا ڈیٹا موجود ہے'),
            content: const Text(
              'ڈیمو کا نمونہ ڈیٹا آپ کے اصل ڈیٹا کے ساتھ شامل کیا جائے گا۔\n'
              'ڈیمو ختم کرنے پر صرف ڈیمو کا ڈیٹا حذف ہوگا — آپ کا ڈیٹا محفوظ رہے گا۔',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('منسوخ کریں'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('ڈیمو شروع کریں'),
              ),
            ],
          ),
    );
  }

  void _skip() => _finish(demo: false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: _busy ? null : _skip,
            child: const Text('چھوڑیں', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _index = i),
                children: const [
                  _OnboardingPage(
                    icon: Icons.agriculture,
                    title: 'کسان دوست',
                    body:
                        'آپ کی ڈیجیٹل ڈائری\nکھیت کا حساب کتاب اب آپ کی جیب میں',
                  ),
                  _OnboardingPage(
                    icon: Icons.list_alt,
                    title: 'سب کچھ ایک جگہ',
                    body:
                        '• خرچے لکھیں\n'
                        '• پیداوار اور فروخت کا ریکارڈ\n'
                        '• منافع و نقصان دیکھیں\n'
                        '• کام کی یاددہانی (الارم کی اجازت درکار ہے)',
                  ),
                  _ChoicePage(),
                ],
              ),
            ),
            _dots(),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child:
                  _index < 2
                      ? SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: FilledButton(
                          onPressed:
                              _busy
                                  ? null
                                  : () => _pages.nextPage(
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeOut,
                                  ),
                          child: const Text(
                            'آگے بڑھیں',
                            style: TextStyle(fontSize: 18),
                          ),
                        ),
                      )
                      : Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: FilledButton(
                              onPressed:
                                  _busy ? null : () => _finish(demo: false),
                              child:
                                  _busy
                                      ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 3,
                                        ),
                                      )
                                      : const Text(
                                        'شروع کریں',
                                        style: TextStyle(fontSize: 18),
                                      ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: OutlinedButton(
                              onPressed:
                                  _busy ? null : () => _finish(demo: true),
                              child: const Text(
                                'ڈیمو دیکھیں',
                                style: TextStyle(fontSize: 18),
                              ),
                            ),
                          ),
                        ],
                      ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _dots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final active = i == _index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? Colors.green.shade700 : Colors.grey.shade400,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Icon(icon, size: 56, color: Colors.green.shade700),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                body,
                style: const TextStyle(fontSize: 18, height: 1.7),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoicePage extends StatelessWidget {
  const _ChoicePage();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'کیسے شروع کریں؟',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 16),
          Text(
            'اپنا اصل ڈیٹا درج کریں، یا پہلے نمونہ ڈیٹا کے ساتھ ایپ آزمائیں۔',
            style: TextStyle(fontSize: 18, height: 1.8),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
