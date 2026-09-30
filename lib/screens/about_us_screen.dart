import 'package:flutter/material.dart';

class AboutUsScreen extends StatelessWidget {
  const AboutUsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ایپ کے بارے میں', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.deepPurple.shade600,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // App Logo / Avatar
            Center(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(32),
                  child: Image.asset(
                    'assets/images/ic_launcher.png',
                    width: 140,
                    height: 140,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // App Name
            const Text(
              'کسان دوست',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
                fontFamily: 'Jameel Noori Nastaleeq',
              ),
            ),
            
            // Tagline
            Text(
              'آپ کا ڈیجیٹل زرعی روزنامچہ',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                color: Colors.grey.shade600,
                fontFamily: 'Jameel Noori Nastaleeq',
              ),
            ),
            const SizedBox(height: 8),
            
            // Version Info
            const Center(
              child: Chip(
                label: Text('ورژن 1.0.0 (مکمل آف لائن)', style: TextStyle(fontWeight: FontWeight.bold)),
                backgroundColor: deepPurpleHighlight,
                labelStyle: TextStyle(color: Colors.deepPurple),
              ),
            ),
            const SizedBox(height: 24),

            // Main Info Card
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ایپ کا مقصد:',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.deepPurple),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'کسان دوست ایپ خاص طور پر پاکستانی کسانوں کے لیے بنائی گئی ہے تاکہ وہ اپنی روزمرہ کی زرعی سرگرمیوں کا حساب کتاب آسانی سے رکھ سکیں۔',
                      style: TextStyle(fontSize: 16, height: 1.6, color: Colors.grey.shade800),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'اس ایپ کے ذریعے آپ درج ذیل کام کر سکتے ہیں:',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
                    ),
                    const SizedBox(height: 8),
                    _buildFeatureItem('اپنی فصلوں اور کاشت کا مکمل ریکارڈ رکھنا۔'),
                    _buildFeatureItem('روزمرہ کے تمام اخراجات اور آمدنی کا حساب۔'),
                    _buildFeatureItem('گودام میں کھاد، بیج اور ادویات کا اسٹاک مینیج کرنا۔'),
                    _buildFeatureItem('پیداوار، فروخت اور خالص منافع و نقصان کی خودکار کیلکولیشن۔'),
                    _buildFeatureItem('اہم زرعی سرگرمیوں کے لیے الارم یاد دہانیاں سیٹ کرنا۔'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Developer Card
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: const Padding(
                padding: EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Text(
                      'ڈیولپر کی تفصیلات:',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'محمد طلحہ فرید فاروقی',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Jameel Noori Nastaleeq',
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'یہ ایپ کسان بھائیوں کی سہولت کے لیے مکمل طور پر فری اور بغیر انٹرنیٹ کے کام کرنے کے لیے ڈیزائن کی گئی ہے۔',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline, size: 20, color: Colors.green),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 15, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
const deepPurpleHighlight = Color(0xFFF2E7FE);
