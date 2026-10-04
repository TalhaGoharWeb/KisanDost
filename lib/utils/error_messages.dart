/// Central catalogue of farmer-facing error messages (crash-safety audit
/// 2026-10-04).
///
/// Rules:
/// - Every message is simple, friendly URDU. No English jargon, no file
///   paths, no exception class names, no numbers the farmer didn't type.
/// - Technical details are NEVER shown to the farmer. They go to
///   [debugPrint] only, so developers can diagnose from a debug build.
/// - Every message implies or states a safe recovery path ("دوبارہ کوشش
///   کریں" / what still works).
library;

import 'package:flutter/material.dart';

/// Kinds of failures the app can hit. Screens and services map whatever
/// they catch to one of these instead of interpolating `$e` into UI text.
enum FailureKind {
  /// SQLite open/query/migration failed.
  database,

  /// Disk full or directory not writable.
  storage,

  /// A record the UI expected is gone (deleted, never existed, bad id).
  missingRecord,

  /// The data on disk is not what we wrote (bad backup, malformed prefs).
  corruptData,

  /// Notification plugin / channel failure.
  notification,

  /// AlarmManager / exact-alarm scheduling failure.
  alarm,

  /// A permission the feature needs was denied.
  permission,

  /// Share sheet / file sharing failed.
  sharing,

  /// Importing an external file failed.
  import,

  /// Anything else we didn't classify.
  unknown,
}

/// Simple, friendly Urdu message per failure kind. Each one names a safe
/// next step; none leaks technical details.
String urduMessageFor(FailureKind kind) {
  switch (kind) {
    case FailureKind.database:
      return 'ریکارڈ کھولنے میں مشکل پیش آئی۔ ایپ بند کر کے دوبارہ کھولیں — آپ کا ڈیٹا محفوظ ہے۔';
    case FailureKind.storage:
      return 'فون کی میموری بھری ہوئی لگتی ہے۔ کچھ جگہ خالی کر کے دوبارہ کوشش کریں۔';
    case FailureKind.missingRecord:
      return 'یہ ریکارڈ اب موجود نہیں ہے۔ فہرست تازہ کر کے دوبارہ دیکھیں۔';
    case FailureKind.corruptData:
      return 'یہ فائل خراب لگتی ہے اور استعمال نہیں ہو سکتی۔ کوئی دوسری فائل آزمائیں۔';
    case FailureKind.notification:
      return 'یاد دہانی لگانے میں مشکل پیش آئی۔ آپ کا ریکارڈ محفوظ ہو گیا ہے — یاد دہانی بعد میں دوبارہ لگائیں۔';
    case FailureKind.alarm:
      return 'الارم لگانے میں مشکل پیش آئی۔ آپ کا ریکارڈ محفوظ ہے — الارم بعد میں دوبارہ لگائیں۔';
    case FailureKind.permission:
      return 'اجازت نہیں ملی، اس لیے یہ کام نہیں ہو سکا۔ فون کی سیٹنگز میں اجازت دے کر دوبارہ کوشش کریں۔';
    case FailureKind.sharing:
      return 'شیئر کرنے میں مشکل پیش آئی۔ دوبارہ کوشش کریں۔';
    case FailureKind.import:
      return 'فائل درآمد نہیں ہو سکی۔ درست بیک اپ فائل منتخب کر کے دوبارہ کوشش کریں۔';
    case FailureKind.unknown:
      return 'کچھ غلط ہو گیا۔ دوبارہ کوشش کریں — اگر مسئلہ رہے تو ایپ بند کر کے دوبارہ کھولیں۔';
  }
}

/// Best-effort guess of the failure kind from a caught error. Used when the
/// call site doesn't know the category. Never throws.
FailureKind guessKind(Object error) {
  final text = error.toString().toLowerCase();
  if (text.contains('database') ||
      text.contains('sqlite') ||
      text.contains('no such table') ||
      text.contains('syntax error')) {
    return FailureKind.database;
  }
  if (text.contains('enospc') ||
      text.contains('no space') ||
      text.contains('disk') ||
      text.contains('readonly') ||
      text.contains('read-only')) {
    return FailureKind.storage;
  }
  if (text.contains('permission') || text.contains('denied')) {
    return FailureKind.permission;
  }
  if (text.contains('share') || text.contains('no activity')) {
    return FailureKind.sharing;
  }
  return FailureKind.unknown;
}

/// Logs the technical error for developers and returns the farmer-facing
/// Urdu message. Call this inside every catch block that surfaces an error.
String friendlyErrorMessage(Object error, [FailureKind? kind]) {
  debugPrint('KisanDost error [${kind ?? guessKind(error)}]: $error');
  return urduMessageFor(kind ?? guessKind(error));
}

/// Shows a red snackbar with a simple Urdu message for [error]. The raw
/// error is only logged via [debugPrint] — it never reaches the screen.
/// Safe to call from any catch block; no-ops if the context is unmounted.
void showFriendlyError(
  BuildContext context,
  Object error, [
  FailureKind? kind,
]) {
  final message = friendlyErrorMessage(error, kind);
  // Capture the messenger before any await gap; the caller is synchronous
  // here so context is valid, but guard anyway.
  try {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 16)),
        backgroundColor: Colors.red,
      ),
    );
  } catch (e) {
    debugPrint('KisanDost: failed to show error snackbar: $e');
  }
}
