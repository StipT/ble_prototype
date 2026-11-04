import 'dart:developer' as developer;

import 'package:flutter_bloc/flutter_bloc.dart';

/// Global [BlocObserver] that logs every event, transition and error.
///
/// Installed once in `main()` via `Bloc.observer = AppBlocObserver()`.
/// Uses `dart:developer` so logs show up in DevTools with a `bloc` tag.
class AppBlocObserver extends BlocObserver {
  /// Creates the observer. Set [logTransitions] to `false` to keep only errors.
  const AppBlocObserver({this.logTransitions = true});

  /// Whether events and changes are logged.
  final bool logTransitions;

  /// High-frequency blocs whose per-packet changes would flood the log.
  static const _quiet = {'LiveWaveformBloc', 'PpgRecordingBloc'};

  bool _shouldLog(BlocBase<dynamic> bloc) =>
      logTransitions && !_quiet.contains(bloc.runtimeType.toString());

  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);
    if (_shouldLog(bloc)) {
      developer.log('${bloc.runtimeType} <- $event', name: 'bloc');
    }
  }

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    if (_shouldLog(bloc)) {
      developer.log('${bloc.runtimeType}: $change', name: 'bloc');
    }
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    developer.log(
      '${bloc.runtimeType} error',
      name: 'bloc',
      error: error,
      stackTrace: stackTrace,
    );
    super.onError(bloc, error, stackTrace);
  }
}
