import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jend_pro_mobile/core/errors/app_failure.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('erreurs RPC (contrat business-rules §13)', () {
    test('code métier connu → message traduit et catégorie', () {
      final f = AppFailure.from(const PostgrestException(message: 'CREDIT_LIMIT_EXCEEDED', code: 'P0001'));
      expect(f.code, 'CREDIT_LIMIT_EXCEEDED');
      expect(f.kind, FailureKind.conflict);
      expect(f.message, contains('plafond'));
    });

    test('PERMISSION_DENIED → permission', () {
      final f = AppFailure.from(const PostgrestException(message: 'PERMISSION_DENIED', code: '42501'));
      expect(f.kind, FailureKind.permission);
    });

    test('ressource absente (P0002) → notFound', () {
      final f = AppFailure.from(const PostgrestException(message: 'PRODUCT_NOT_FOUND', code: 'P0002'));
      expect(f.kind, FailureKind.notFound);
    });

    test('paramètre invalide (22023) → validation', () {
      final f = AppFailure.from(const PostgrestException(message: 'PAYMENT_EXCEEDS_TOTAL', code: '22023'));
      expect(f.kind, FailureKind.validation);
    });

    test('detail JSON exploité (INSUFFICIENT_STOCK)', () {
      final f = AppFailure.from(
        const PostgrestException(
          message: 'INSUFFICIENT_STOCK',
          code: 'P0001',
          details: '{"available": 2, "requested": 5}',
        ),
      );
      expect(f.detail, {'available': 2, 'requested': 5});
    });

    test('unicité PostgreSQL → conflit lisible', () {
      final f = AppFailure.from(const PostgrestException(message: 'duplicate key value', code: '23505'));
      expect(f.kind, FailureKind.conflict);
      expect(f.code, 'UNIQUE_VIOLATION');
    });

    test('RLS (42501 sans code métier) → permission', () {
      final f = AppFailure.from(
        const PostgrestException(message: 'new row violates row-level security policy', code: '42501'),
      );
      expect(f.kind, FailureKind.permission);
    });
  });

  group('erreurs d’authentification', () {
    test('identifiants invalides', () {
      final f = AppFailure.from(const AuthException('Invalid login credentials', code: 'invalid_credentials'));
      expect(f.kind, FailureKind.auth);
      expect(f.message, 'E-mail ou mot de passe incorrect.');
    });

    test('compte existant', () {
      final f = AppFailure.from(const AuthException('User already registered', code: 'user_already_exists'));
      expect(f.message, contains('existe déjà'));
    });
  });

  test('réseau → network, relançable', () {
    final f = AppFailure.from(const SocketException('Failed host lookup'));
    expect(f.kind, FailureKind.network);
    expect(f.isRetryable, isTrue);
  });

  test('inconnu → message générique, jamais le texte technique', () {
    final f = AppFailure.from(StateError('boom'));
    expect(f.kind, FailureKind.unknown);
    expect(f.message, isNot(contains('boom')));
  });
}
