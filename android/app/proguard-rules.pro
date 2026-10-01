# Kisan Dost — release ProGuard / R8 rules.
#
# Why this file is almost empty (deliberate):
# - Flutter plugins register through GeneratedPluginRegistrant (compile-time,
#   no reflection), so R8's defaults plus the Flutter Gradle plugin's rules
#   are sufficient for sqflite, path_provider, share_plus, file_picker and
#   flutter_local_notifications.
# - Every native component (AlarmReceiver, BootReceiver, AlarmService,
#   AlarmActivity, FileProvider) is referenced from AndroidManifest.xml, so
#   R8 keeps them automatically.
# - The keep below is belt-and-braces for our own Kotlin package so the
#   exact-alarm / boot-receiver wiring can never be stripped by an
#   over-aggressive shrink in a future AGP/R8 version.
-keep class com.talhagohar.kisandost.** { *; }
