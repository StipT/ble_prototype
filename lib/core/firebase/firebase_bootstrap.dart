import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';
import '../config/app_config.dart';

/// Emulator ports, matching `firebase.json`.
abstract final class EmulatorPorts {
  /// Firebase Auth emulator.
  static const auth = 9099;

  /// Cloud Firestore emulator.
  static const firestore = 8080;

  /// Cloud Functions emulator (the client never calls functions directly;
  /// the chunk trigger runs inside the emulator suite).
  static const functions = 5001;
}

/// Initializes Firebase according to [config]. Returns whether Firebase is
/// usable; on `false` the app runs with cloud sync disabled.
///
/// With `USE_EMULATOR=true`, Auth and Firestore are pointed at
/// `EMULATOR_HOST` (default `localhost`). The FlutterFire SDKs map
/// `localhost` to `10.0.2.2` on the Android emulator automatically (the
/// emulator's alias for the host machine); on a physical phone pass the
/// computer's LAN IP and start the emulators bound to `0.0.0.0`.
Future<bool> initializeFirebase(AppConfig config) async {
  if (!config.enableFirebase) return false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    final firestore = FirebaseFirestore.instance
      // Drift is the offline store; Firestore's own cache would only hold a
      // second copy of every uploaded chunk. Must be set before first use.
      ..settings = const Settings(persistenceEnabled: false);
    if (config.useEmulator) {
      await FirebaseAuth.instance.useAuthEmulator(
        config.emulatorHost,
        EmulatorPorts.auth,
      );
      firestore.useFirestoreEmulator(
        config.emulatorHost,
        EmulatorPorts.firestore,
      );
    }
    return true;
  } on Object catch (e, st) {
    debugPrint('Firebase init failed, cloud sync disabled: $e\n$st');
    return false;
  }
}
