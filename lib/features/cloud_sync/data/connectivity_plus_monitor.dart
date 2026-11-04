import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../domain/connectivity_monitor.dart';

/// [ConnectivityMonitor] on `connectivity_plus`: online when any network
/// interface other than `none` is up.
class ConnectivityPlusMonitor implements ConnectivityMonitor {
  /// Uses [connectivity] (defaults to the plugin singleton).
  ConnectivityPlusMonitor([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  static bool _isOnline(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  @override
  Stream<bool> get online {
    late StreamController<bool> controller;
    StreamSubscription<List<ConnectivityResult>>? sub;
    var changed = false;
    controller = StreamController<bool>(
      onListen: () {
        sub = _connectivity.onConnectivityChanged.listen((r) {
          changed = true;
          controller.add(_isOnline(r));
        }, onError: controller.addError);
        // Current value first, unless a change already arrived.
        unawaited(
          _connectivity.checkConnectivity().then((r) {
            if (!changed && !controller.isClosed) controller.add(_isOnline(r));
          }, onError: (Object _) {}),
        );
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream.distinct();
  }
}

/// [ConnectivityMonitor] that never reports a change (no Firebase, tests).
class StaticConnectivityMonitor implements ConnectivityMonitor {
  /// Always reports [isOnline].
  const StaticConnectivityMonitor({this.isOnline = true});

  /// The constant state.
  final bool isOnline;

  @override
  Stream<bool> get online => Stream.value(isOnline);
}
