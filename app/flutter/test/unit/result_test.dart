import 'package:flutter_test/flutter_test.dart';
import 'package:uam/core/errors/uam_failure.dart';
import 'package:uam/core/result/result.dart';

void main() {
  test('success exposes its value', () {
    const Result<int> result = Result.success(42);
    expect(result.isSuccess, isTrue);
    expect(result.valueOrNull, 42);
    expect(result.failureOrNull, isNull);
  });

  test('failure exposes a typed failure', () {
    const result = Result<int>.failure(
      UamFailure(
        code: UamFailureCode.bridgeUnavailable,
        message: 'missing core',
      ),
    );
    expect(result.isSuccess, isFalse);
    expect(result.valueOrNull, isNull);
    expect(result.failureOrNull?.code, UamFailureCode.bridgeUnavailable);
  });
}
