import '../error/failures.dart';

/// A value of type [T] or a failure of type [F].
///
/// Used as the return type of every domain operation that can fail in an
/// expected way. Pattern-match with `switch`:
///
/// ```dart
/// switch (await repo.connect(id)) {
///   case Ok(:final value): ...
///   case Err(:final failure): ...
/// }
/// ```
sealed class Result<T, F extends Failure> {
  const Result();

  /// Success shortcut.
  const factory Result.ok(T value) = Ok<T, F>;

  /// Failure shortcut.
  const factory Result.err(F failure) = Err<T, F>;

  /// Whether this is an [Ok].
  bool get isOk => this is Ok<T, F>;

  /// The value, or `null` when this is an [Err].
  T? get valueOrNull => switch (this) {
    Ok(:final value) => value,
    Err() => null,
  };

  /// The failure, or `null` when this is an [Ok].
  F? get failureOrNull => switch (this) {
    Ok() => null,
    Err(:final failure) => failure,
  };

  /// Collapses both branches into one value.
  R fold<R>(R Function(F failure) onErr, R Function(T value) onOk) =>
      switch (this) {
        Ok(:final value) => onOk(value),
        Err(:final failure) => onErr(failure),
      };

  /// Transforms the success value, keeping failures untouched.
  Result<R, F> map<R>(R Function(T value) transform) => switch (this) {
    Ok(:final value) => Ok(transform(value)),
    Err(:final failure) => Err(failure),
  };
}

/// Successful [Result].
final class Ok<T, F extends Failure> extends Result<T, F> {
  const Ok(this.value);

  /// The produced value.
  final T value;

  @override
  bool operator ==(Object other) => other is Ok<T, F> && other.value == value;

  @override
  int get hashCode => Object.hash(Ok, value);

  @override
  String toString() => 'Ok($value)';
}

/// Failed [Result].
final class Err<T, F extends Failure> extends Result<T, F> {
  const Err(this.failure);

  /// Why the operation failed.
  final F failure;

  @override
  bool operator ==(Object other) =>
      other is Err<T, F> && other.failure == failure;

  @override
  int get hashCode => Object.hash(Err, failure);

  @override
  String toString() => 'Err($failure)';
}

/// `Result<void, Failure>` success constant.
const Result<void, Failure> okVoid = Ok<void, Failure>(null);
