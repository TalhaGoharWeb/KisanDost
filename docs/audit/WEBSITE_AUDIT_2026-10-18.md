# Kisan Dost Website Audit — 2026-10-18

**Scope:** `docs/` (GitHub Pages source on `main`), live site https://talhagoharweb.github.io/KisanDost/,
repo https://github.com/TalhaGoharWeb/KisanDost, README screenshot gallery, `docs/screenshots/` (17 files).
**Method:** full static source inspection of all 4 HTML pages, `style.css`, `site.js`; link/asset verification
via HTTP; image dimension checks. No browser automation available in this environment (no chromium/playwright) —
rendered-layout defects below are verified against source, not screenshots; this is stated per finding.

## 1. Current strengths (verified)

1. **Real screenshots already in use.** The gallery on both landing pages uses 8 genuine app screenshots
   (`dashboard, crops, expenses, harvest, profit-loss, inventory, tasks, ushr`) — no fabricated UI in the gallery.
2. **Single shared stylesheet + vanilla JS.** No frameworks, no build step; GitHub Pages serves `docs/` directly.
   Relative links throughout — safe under the `/KisanDost/` base path.
3. **RTL/LTR handled natively.** `dir` attributes on `<html>`, CSS logical properties
   (`margin-inline`, `padding-inline`, `inset-inline`, `text-align:start`) used throughout.
4. **Good interaction foundations.** Sticky nav with `scroll-padding-top:96px` (anchors not hidden),
   burger menu that closes on link tap, FAQ accordion, reveal-on-scroll with `prefers-reduced-motion` support.
5. **Tables don't break mobile.** All doc-page tables and the version table are wrapped in `.table-wrap`
   with horizontal scroll.
6. **Links verified working.** APK (Drive, HTTP 200), both `.docx` files present in repo and linked,
   GitHub repo links, all `#anchor` targets resolve on all 4 pages, both language toggles work.
7. **SEO/meta basics present.** `lang`, `dir`, viewport, description, favicon, lazy-loading on gallery images.

## 2. Confirmed visual defects (source-verified)

| # | Defect | Severity |
|---|--------|----------|
| D1 | **Hero uses a fabricated phone mockup.** The `.phone` block renders an invented Urdu "dashboard" (made-up tasks, fake amounts like "روپے 2,450") in HTML/CSS — not the real app. The mission brief explicitly forbids substituting invented dashboards for real screenshots. Must be replaced with `screenshots/dashboard.jpg` in a device frame. | **High** |
| D2 | **Palette does not match the brief.** Current greens (`#123a1c` family) predate the specified palette (`#174B35 / #247A4B / #4F9859 / #D9AE50 / #FAF8F0 / #EEF3E8 / #24352B / #66736A`). Full design-system rebuild required. | **High** |
| D3 | **Feature grid is 12 visually identical cards.** The brief requires grouped features with visual hierarchy, not "a massive, visually identical card grid". Two of the 14 specified features (batai, reports) are folded into other cards. | **Medium** |
| D4 | **No dedicated trust/simplicity strip.** The brief's Section 3 (offline-first, Urdu-first, agricultural record-keeping, free) has no section; only 3 hero checkmarks. | **Medium** |
| D5 | **Gallery has no lightbox** and shows only 8 of the 15 specified screenshots (missing: activities, party-ledger, theka, batai, farms, reports, settings). | **Medium** |
| D6 | **English FAQ has 6 items, Urdu has 7** — the demo-data question ("How do I clear demo data?") is missing in English. | **Low** |
| D7 | **Urdu nav has no Screenshots link** (`#features #how #docs #faq #versions`); English nav does (`#shots`). Inconsistent. | **Low** |
| D8 | **Physical property in RTL-unsafe spot:** `en.html` download band uses `style="right:-40px"` instead of `inset-inline-end`. Works in LTR but violates the logical-properties rule. | **Low** |
| D9 | **Dead CSS after hero replacement:** ~60 lines of `.phone/.mock-*` rules become unused once D1 is fixed — remove to keep the stylesheet honest. | **Low** |

## 3. Responsive layout defects (source-verified)

| # | Defect | Severity |
|---|--------|----------|
| R1 | `table.ver` has `min-width:560px`, forcing horizontal scroll on phones. Acceptable but improvable. | **Low** |
| R2 | `.hero-art` stacks farmer art + phone on mobile with no size coordination; after D1 fix, the device frame must scale smoothly (brief §6.10) — the old fixed `290px` phone width is removed with the mockup. | **Medium** |
| R3 | `.doc-body` long Urdu paragraphs have no `max-width`; on wide desktop the measure exceeds comfortable reading length for Nastaliq. | **Low** |

No unintended horizontal scroll sources found beyond R1 (`overflow-x:hidden` on body is a backstop, not masking a known overflow — verified by auditing all fixed-width rules).

## 4. Navigation and interaction problems

| # | Problem | Severity |
|---|--------|----------|
| N1 | Burger button has no `aria-expanded` / `aria-controls`; FAQ buttons have no `aria-expanded`. Screen-reader users get no state. | **Medium** |
| N2 | No `:focus-visible` styles anywhere — keyboard users can't see focus. | **Medium** |
| N3 | Mobile nav has no Escape-to-close; focus is not moved into the menu. | **Medium** |
| N4 | No skip-to-content link. | **Low** |

## 5. Typography and RTL issues

- **Font decision (licensing):** The brief prefers Jameel Noori Nastaleeq but requires license verification before
  self-hosting. The Jameel Noori license for web embedding is **unverified** — decision: keep **Noto Nastaliq Urdu**
  (OFL) via Google Fonts CDN, which is already in use and license-clean. Noted here per the brief's requirement.
- Urdu digits vs Latin digits: screenshots show Urdu digits; site metadata (SHA-256, versions) correctly stays Latin —
  no change needed.
- Nastaliq line-height (2.1 body) is generous but correct for the script; hero `h1` already clamped for mobile.
- No bidi reversals found in mixed Urdu/English strings (checked version table, `dl-note` uses `direction:ltr`).

## 6. Screenshots

All 17 files in `docs/screenshots/` verified present and readable. Dimensions:

| File | Size | Notes |
|------|------|-------|
| dashboard.jpg | 297×1600 | **Narrow crop** (center slice of a 720px shot). Usable in hero frame; small intrinsic width — do not upscale beyond ~320px display width. |
| settings.jpg | 291×1600 | Same narrow-crop situation. Fine for gallery. |
| 15 others | ~716–720×1600–1905 | Full phone screenshots, consistent 9:20-ish ratio. |

`about.jpg` and `splash.jpg` exist but are not in the brief's 15 featured gallery items — kept in repo, unused on page
(splash could suit the hero side art; decided against — keep hero focused on the dashboard).

## 7. Performance and accessibility problems

| # | Problem | Severity |
|---|--------|----------|
| P1 | **No image optimization.** 17 screenshots ≈ 1.6MB total (fine), but decorative PNGs are heavy: `logo.png` 536KB displayed at 44px, `farmer.png` 707KB, `tractor.png` 536KB, `wheat.png` 473KB. Resize/compress these. | **Medium** |
| P2 | No WebP/AVIF derivatives, no `srcset`. (Mitigation: keep originals; add WebP via `<picture>`.) | **Low** |
| P3 | Gallery `<img>` tags lack `width`/`height` → layout-shift risk (CLS). Hero image should be eager, not lazy. | **Medium** |
| P4 | N1–N4 accessibility gaps (above). No automated a11y check possible in sandbox — manual review only. | **Medium** |

## 8. Broken links / deployment risks

**None found.** APK (Drive) 200, `.docx` files in repo, all anchors resolve, `docs/` on `main` is the Pages source,
no build step to break. Risk to watch: Google Fonts CDN blocked → Nastaliq falls back to system serif (acceptable,
already specified in the font stack).

## 9. Prioritized changes (what this audit drives)

1. **(High)** Replace hero mockup with real `dashboard.jpg` in a CSS device frame; rebuild palette per brief. 
2. **(High)** Group the 14 features with visual hierarchy + selected real screenshots.
3. **(Medium)** Add trust strip; 15-image gallery + accessible lightbox; fix N1–N4; optimize images (P1–P3).
4. **(Low)** FAQ parity (EN demo-data question); Urdu nav `#shots` link; R1/R3 polish; remove dead CSS.

## 10. Git baseline

`main` @ `90bc7b4` ("Add 17 real device screenshots to README and landing page"), working tree clean.
Website-only changes below this point; no Flutter app code touched.
