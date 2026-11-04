import 'package:flutter/material.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'core/bloc/app_bloc_observer.dart';
import 'core/config/app_config.dart';
import 'core/di/injection.dart';
import 'core/firebase/firebase_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Bloc.observer = const AppBlocObserver();
  final config = AppConfig.fromEnvironment();
  final firebaseReady = await initializeFirebase(config);
  // HydratedBloc persistence (last NFC-paired device): a Hive box in the
  // app-support directory (not user-visible Documents).
  final storage = await HydratedStorage.build(
    storageDirectory: HydratedStorageDirectory(
      (await getApplicationSupportDirectory()).path,
    ),
  );
  HydratedBloc.storage = storage;
  await configureDependencies(
    config,
    firebaseReady: firebaseReady,
    hydratedStorage: storage,
  );
  runApp(const PpgApp());
}
