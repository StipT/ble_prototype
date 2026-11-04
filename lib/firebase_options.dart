// STUB — replace by running `flutterfire configure` for a real project.
//
// These placeholder values target the demo project `demo-ppg` (see
// `.firebaserc`). Firebase treats `demo-*` project ids as emulator-only, so
// the app works against the local emulator suite without any real project,
// API key, or login:
//
//   cd functions && npm run serve           # auth 9099, firestore 8080, functions 5001
//   flutter run --dart-define=USE_EMULATOR=true
//
// Against a real Firebase project these values are rejected; generate the
// real file with:
//
//   dart pub global activate flutterfire_cli
//   flutterfire configure --project=<your-project-id>
//
// which overwrites this file (and adds google-services.json /
// GoogleService-Info.plist). Then enable Anonymous sign-in in the console and
// deploy the rules and function: `firebase deploy --only firestore,functions`.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Firebase options per platform (same API as the generated file).
class DefaultFirebaseOptions {
  /// Options for the current platform.
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => android,
      TargetPlatform.iOS || TargetPlatform.macOS => ios,
      _ => throw UnsupportedError(
        'No Firebase options for $defaultTargetPlatform; '
        'run `flutterfire configure`.',
      ),
    };
  }

  /// Emulator-only demo project id.
  static const projectId = 'demo-ppg';

  /// Android placeholder (well-formed app id; the emulators ignore it).
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:000000000000:android:0000000000000000',
    messagingSenderId: '000000000000',
    projectId: projectId,
  );

  /// iOS placeholder. The iOS SDK validates the app id format, so it must
  /// look like `1:<number>:ios:<hex>`.
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:000000000000:ios:0000000000000000',
    messagingSenderId: '000000000000',
    projectId: projectId,
    iosBundleId: 'com.invoketech.dev.blePrototype',
  );

  /// Web placeholder (web is not a target of this app).
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:000000000000:web:0000000000000000',
    messagingSenderId: '000000000000',
    projectId: projectId,
  );
}
