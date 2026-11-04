/// Reports whether the phone has a network path.
///
/// Abstracted so the cloud-sync bloc can be tested without the
/// `connectivity_plus` platform channel. Note that "online" only means a
/// network interface is up (Wi-Fi, cellular, ...), not that Firebase is
/// reachable; a failed upload still goes through the normal backoff.
abstract interface class ConnectivityMonitor {
  /// Emits the current state first, then every change.
  Stream<bool> get online;
}
