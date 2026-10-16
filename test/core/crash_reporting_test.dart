import 'package:flutter_test/flutter_test.dart';
import 'package:jend_pro_mobile/core/errors/app_failure.dart';
import 'package:jend_pro_mobile/core/monitoring/crash_reporting.dart';

void main() {
  test('seules les vraies anomalies sont remontées', () {
    for (final kind in [
      FailureKind.network,
      FailureKind.auth,
      FailureKind.permission,
      FailureKind.validation,
      FailureKind.notFound,
      FailureKind.conflict,
    ]) {
      expect(CrashReporting.shouldReport(AppFailure(kind, 'prévu')), isFalse, reason: '$kind');
    }
    expect(CrashReporting.shouldReport(const AppFailure(FailureKind.unknown, 'inattendu')), isTrue);
    expect(CrashReporting.shouldReport(StateError('bug')), isTrue);
    expect(CrashReporting.enabled, isFalse, reason: 'inactif sans SENTRY_DSN');
  });
}
