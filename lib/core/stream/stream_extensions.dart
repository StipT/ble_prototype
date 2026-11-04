import 'dart:async';

/// Small stream helpers (avoids pulling in rxdart for one operator).
extension StartWithExtension<T> on Stream<T> {
  /// Emits `current()` to every new listener, then forwards this stream.
  ///
  /// Used for "state" streams (link state, adapter state) where a late
  /// listener must learn the current value immediately. Unlike an `async*`
  /// generator, cancelling the result completes promptly.
  Stream<T> startWith(T Function() current) {
    late StreamController<T> controller;
    StreamSubscription<T>? sub;
    controller = StreamController<T>(
      onListen: () {
        controller.add(current());
        sub = listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onPause: () => sub?.pause(),
      onResume: () => sub?.resume(),
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }
}
