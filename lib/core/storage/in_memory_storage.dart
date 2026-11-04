import 'package:hydrated_bloc/hydrated_bloc.dart';

/// A [Storage] for `HydratedBloc` that keeps everything in a map.
///
/// Used by tests (no file system, no Hive) and as the default when
/// `configureDependencies` is not given the on-disk `HydratedStorage` that
/// `main()` builds. State persisted here is lost when the process exits.
class InMemoryStorage implements Storage {
  /// Creates an empty storage, optionally pre-seeded with [initial] values
  /// (handy to simulate "the app was restarted with this saved state").
  InMemoryStorage([Map<String, dynamic>? initial]) : _values = {...?initial};

  final Map<String, dynamic> _values;

  /// Read-only view of everything written so far (for test assertions).
  Map<String, dynamic> get values => Map.unmodifiable(_values);

  @override
  dynamic read(String key) => _values[key];

  @override
  Future<void> write(String key, dynamic value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<void> clear() async => _values.clear();

  @override
  Future<void> close() async {}
}
