import 'dart:math';

/// Random 128-bit identifier as 32 lowercase hex characters.
///
/// Safe for Firestore document IDs (no `/`, not `.`/`..`, < 1500 bytes).
String newId([Random? random]) {
  final r = random ?? Random.secure();
  return List<String>.generate(
    16,
    (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}
