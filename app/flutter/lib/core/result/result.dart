import '../errors/uam_failure.dart';

/// Minimal result type for operations that fail with a typed [UamFailure].
sealed class Result<T> {
  const Result();

  /// Successful result carrying [value].
  const factory Result.success(T value) = Success<T>;

  /// Failed result carrying [failure].
  const factory Result.failure(UamFailure failure) = Failure<T>;

  /// Whether this is a successful result.
  bool get isSuccess;

  /// Value when successful, otherwise null.
  T? get valueOrNull;

  /// Failure when unsuccessful, otherwise null.
  UamFailure? get failureOrNull;
}

/// Successful [Result].
final class Success<T> extends Result<T> {
  const Success(this.value);

  /// Result value.
  final T value;

  @override
  bool get isSuccess => true;

  @override
  T get valueOrNull => value;

  @override
  UamFailure? get failureOrNull => null;
}

/// Failed [Result].
final class Failure<T> extends Result<T> {
  const Failure(this.failure);

  /// Failure description.
  final UamFailure failure;

  @override
  bool get isSuccess => false;

  @override
  T? get valueOrNull => null;

  @override
  UamFailure get failureOrNull => failure;
}
