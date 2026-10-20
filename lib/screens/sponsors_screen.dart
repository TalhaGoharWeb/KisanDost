import 'package:flutter/material.dart';

import '../data/sponsors.dart';
import '../theme/app_theme.dart';

/// ہمارے اسپانسرز — acknowledges the people and companies whose voluntary
/// support keeps Kisan Dost free for every farmer.
///
/// Sponsorship is acknowledgement only: it never unlocks features and
/// never changes the app for anyone (owner's transparency principles).
class SponsorsScreen extends StatelessWidget {
  const SponsorsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ہمارے اسپانسرز',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      body:
          kSponsors.isEmpty
              ? const _NoSponsorsYet()
              : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const _IntroText(),
                  const SizedBox(height: 16),
                  for (final sponsor in kSponsors) ...[
                    _SponsorCard(sponsor: sponsor),
                    const SizedBox(height: 12),
                  ],
                  const _FooterNote(),
                ],
              ),
    );
  }
}

class _IntroText extends StatelessWidget {
  const _IntroText();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'کسان دوست ہر کسان کے لیے بالکل مفت ہے۔ یہ ادارے اور شخصیات رضاکارانہ '
      'طور پر ایپ کی بہتری میں تعاون کرتے ہیں — ہم ان کے شکر گزار ہیں۔',
      style: TextStyle(fontSize: 17, height: 1.9),
      textAlign: TextAlign.center,
    );
  }
}

class _SponsorCard extends StatelessWidget {
  final Sponsor sponsor;

  const _SponsorCard({required this.sponsor});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(
          children: [
            // Sponsor logo (bundled asset — the app is fully offline).
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset(
                sponsor.logoAsset,
                width: 120,
                height: 120,
                fit: BoxFit.contain,
                errorBuilder:
                    (context, error, stackTrace) => Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.handshake,
                        size: 56,
                        color: AppTheme.primaryColor,
                      ),
                    ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              sponsor.name,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                fontFamily: 'Jameel Noori Nastaleeq',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              sponsor.company,
              style: TextStyle(fontSize: 18, color: Colors.grey.shade700),
              textAlign: TextAlign.center,
            ),
            if (sponsor.note != null) ...[
              const SizedBox(height: 8),
              Text(
                sponsor.note!,
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FooterNote extends StatelessWidget {
  const _FooterNote();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Text(
        'تعاون مکمل طور پر رضاکارانہ ہے — اس سے ایپ میں کوئی خاص سہولت '
        'نہیں کھلتی۔ کسان دوست آج مفت ہے اور ہمیشہ مفت رہے گی۔',
        style: TextStyle(fontSize: 15, height: 1.9),
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// Shown while there are no sponsors yet: an honest invitation instead
/// of a fake list. Contact is the developer email from the website.
class _NoSponsorsYet extends StatelessWidget {
  const _NoSponsorsYet();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.handshake, size: 80, color: AppTheme.primaryColor),
          SizedBox(height: 24),
          Text(
            'ابھی کوئی اسپانسر نہیں',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              fontFamily: 'Jameel Noori Nastaleeq',
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 16),
          Text(
            'کسان دوست ہر کسان کے لیے بالکل مفت ہے اور ہمیشہ مفت رہے گی۔ '
            'اگر آپ یا آپ کا ادارہ اس ایپ کی بہتری میں تعاون کرنا چاہے تو '
            'ہم آپ کا نام اور لوگو یہاں شکرگزاری کے ساتھ لگائیں گے۔',
            style: TextStyle(fontSize: 17, height: 2.0),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 24),
          Text(
            'رابطہ: muhaqqiqcreates@gmail.com',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 16),
          Text(
            'تعاون مکمل طور پر رضاکارانہ ہے — اس سے ایپ میں کوئی خاص '
            'سہولت نہیں کھلتی۔',
            style: TextStyle(fontSize: 15, height: 1.9),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
