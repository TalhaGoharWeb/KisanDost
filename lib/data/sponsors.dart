/// Sponsor acknowledgements shown in the app (ہمارے اسپانسرز screen).
///
/// Kisan Dost is free for farmers, forever. Sponsors support the app's
/// development voluntarily — sponsorship never unlocks features and
/// never changes what any farmer sees or can do (see the website's
/// transparency page for the full principles).
///
/// HOW TO ADD A SPONSOR (next release):
/// 1. Put the sponsor's logo image in `assets/sponsors/`
///    (PNG or JPG, square-ish, at least 400×400 px).
/// 2. Add one [Sponsor] entry to [kSponsors] below with the logo's
///    asset path, the sponsor's name, and their company/brand name.
/// 3. Ship the next release — the app is fully offline, so sponsor
///    logos are bundled assets, never downloaded.
class Sponsor {
  /// Asset path of the sponsor's logo, e.g. 'assets/sponsors/acme.png'.
  final String logoAsset;

  /// The sponsor's personal name (or the display name they chose).
  final String name;

  /// Company / brand / organization name.
  final String company;

  /// Optional short line shown under the name, e.g. a city or a note
  /// of thanks. Keep it in everyday Urdu.
  final String? note;

  const Sponsor({
    required this.logoAsset,
    required this.name,
    required this.company,
    this.note,
  });
}

/// All current sponsors. Empty until the first sponsor is confirmed —
/// the screen shows an honest invitation state while this is empty.
const List<Sponsor> kSponsors = <Sponsor>[
  // Example (remove the comment markers when adding a real sponsor):
  // Sponsor(
  //   logoAsset: 'assets/sponsors/example.png',
  //   name: 'محمد احمد',
  //   company: 'احمد زرعی سٹور',
  //   note: 'شکریہ!',
  // ),
];
