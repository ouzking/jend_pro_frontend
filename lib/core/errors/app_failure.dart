import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Catégorie d'erreur, utilisée par l'UI pour choisir l'illustration et l'action.
enum FailureKind { network, auth, permission, validation, notFound, conflict, unknown }

/// Erreur applicative unique, déjà traduite pour l'utilisateur.
///
/// Les repositories convertissent toutes les exceptions Supabase en
/// [AppFailure] : l'UI n'a jamais à connaître PostgREST ou GoTrue.
class AppFailure implements Exception {
  const AppFailure(this.kind, this.message, {this.code, this.detail});

  final FailureKind kind;

  /// Message prêt à afficher (français).
  final String message;

  /// Code machine stable renvoyé par le backend (`INSUFFICIENT_STOCK`…).
  final String? code;

  /// Complément JSON éventuel (`detail` des RPC).
  final Map<String, dynamic>? detail;

  bool get isRetryable => kind == FailureKind.network || kind == FailureKind.unknown;

  factory AppFailure.from(Object error) {
    if (error is AppFailure) return error;
    if (error is AuthException) return _fromAuth(error);
    if (error is PostgrestException) return _fromPostgrest(error);
    if (error is StorageException) {
      return AppFailure(FailureKind.unknown, _messages['STORAGE']!, code: error.statusCode);
    }
    if (error is FunctionException) {
      final body = error.details;
      final code = body is Map ? body['error']?.toString() : null;
      return _fromCode(code, sqlState: null);
    }
    if (error is SocketException || error is TimeoutException || error is HttpException) {
      return const AppFailure(FailureKind.network, _networkMessage, code: 'NETWORK');
    }
    final text = error.toString();
    if (text.contains('SocketException') || text.contains('ClientException') || text.contains('Failed host lookup')) {
      return const AppFailure(FailureKind.network, _networkMessage, code: 'NETWORK');
    }
    return const AppFailure(FailureKind.unknown, _unknownMessage);
  }

  static AppFailure _fromPostgrest(PostgrestException e) {
    final failure = _fromCode(e.message, sqlState: e.code);
    return AppFailure(failure.kind, failure.message, code: failure.code, detail: _parseDetail(e.details));
  }

  static AppFailure _fromCode(String? code, {required String? sqlState}) {
    final known = code != null ? _messages[code] : null;
    if (known != null) {
      return AppFailure(_kindFor(code!, sqlState), known, code: code);
    }
    switch (sqlState) {
      case '23505':
        return const AppFailure(
          FailureKind.conflict,
          'Cette valeur est déjà utilisée (SKU, code-barres ou nom).',
          code: 'UNIQUE_VIOLATION',
        );
      case '23514':
        return const AppFailure(
          FailureKind.validation,
          'Une valeur saisie est invalide. Vérifiez le formulaire.',
          code: 'CHECK_VIOLATION',
        );
      case '42501':
      case 'PGRST301':
        return const AppFailure(
          FailureKind.permission,
          'Vous n’avez pas l’autorisation d’effectuer cette action.',
          code: 'PERMISSION_DENIED',
        );
      case 'PGRST116':
        return const AppFailure(FailureKind.notFound, 'Élément introuvable.', code: 'NOT_FOUND');
    }
    return AppFailure(FailureKind.unknown, _unknownMessage, code: code);
  }

  static AppFailure _fromAuth(AuthException e) {
    final code = e.code;
    final message = switch (code) {
      'invalid_credentials' => 'E-mail ou mot de passe incorrect.',
      'email_not_confirmed' => 'Confirmez votre adresse e-mail avant de vous connecter.',
      'user_already_exists' || 'email_exists' => 'Un compte existe déjà avec cet e-mail.',
      'weak_password' => 'Mot de passe trop faible : 8 caractères minimum.',
      'same_password' => 'Le nouveau mot de passe doit être différent de l’ancien.',
      'over_email_send_rate_limit' ||
      'over_request_rate_limit' => 'Trop de tentatives. Patientez quelques minutes puis réessayez.',
      'email_address_invalid' || 'validation_failed' => 'Adresse e-mail invalide.',
      'session_expired' ||
      'session_not_found' ||
      'refresh_token_not_found' => 'Votre session a expiré. Reconnectez-vous.',
      'signup_disabled' => 'Les inscriptions sont momentanément fermées.',
      'reauthentication_needed' => 'Pour votre sécurité, reconnectez-vous puis réessayez.',
      _ => null,
    };
    if (message != null) {
      return AppFailure(FailureKind.auth, message, code: code);
    }
    if (e is AuthRetryableFetchException) {
      return const AppFailure(FailureKind.network, _networkMessage, code: 'NETWORK');
    }
    return AppFailure(FailureKind.auth, 'Connexion impossible. Vérifiez vos informations.', code: code);
  }

  static FailureKind _kindFor(String code, String? sqlState) {
    if (code == 'NOT_AUTHENTICATED') return FailureKind.auth;
    if (sqlState == '42501' || code.contains('PERMISSION') || code == 'ROLE_ABOVE_CALLER') {
      return FailureKind.permission;
    }
    if (sqlState == 'P0002' || code.endsWith('_NOT_FOUND')) return FailureKind.notFound;
    if (sqlState == '22023') return FailureKind.validation;
    return FailureKind.conflict;
  }

  static Map<String, dynamic>? _parseDetail(Object? details) {
    if (details is Map<String, dynamic>) return details;
    if (details is String && details.trimLeft().startsWith('{')) {
      try {
        final decoded = jsonDecode(details);
        if (decoded is Map<String, dynamic>) return decoded;
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  static const _networkMessage = 'Connexion internet indisponible. Vérifiez votre réseau puis réessayez.';
  static const _unknownMessage = 'Une erreur inattendue est survenue. Réessayez dans un instant.';

  /// Contrat d'erreurs du backend (business-rules.md §13), traduit.
  static const _messages = <String, String>{
    'NOT_AUTHENTICATED': 'Votre session a expiré. Reconnectez-vous.',
    'PERMISSION_DENIED': 'Vous n’avez pas l’autorisation d’effectuer cette action.',
    'ROLE_ABOVE_CALLER': 'Vous ne pouvez pas attribuer ou modifier un rôle supérieur au vôtre.',
    'CANNOT_MODIFY_SELF': 'Vous ne pouvez pas modifier votre propre rôle ou statut.',
    'LAST_OWNER': 'L’entreprise doit toujours avoir au moins un propriétaire actif.',
    'ALREADY_MEMBER': 'Cette personne est déjà membre ou invitée.',
    'BUSINESS_LIMIT_REACHED': 'Vous avez atteint le nombre maximal d’entreprises.',
    'USER_NOT_FOUND': 'Aucun compte n’existe avec cet e-mail.',
    'MEMBER_NOT_FOUND': 'Membre introuvable.',
    'ROLE_NOT_FOUND': 'Rôle introuvable.',
    'ROLE_NOT_IN_BUSINESS': 'Ce rôle n’appartient pas à cette entreprise.',
    'AUTH_INVITE_FAILED': 'L’e-mail d’invitation n’a pas pu être envoyé. Réessayez plus tard.',
    'INVITATION_NOT_FOUND': 'Cette invitation n’existe plus.',
    'INVALID_TIMEZONE': 'Fuseau horaire invalide.',
    'INVALID_STATUS': 'Statut invalide.',
    'INVALID_QUANTITY': 'Quantité invalide.',
    'INVALID_QUANTITY_SIGN': 'Le sens de la quantité ne correspond pas au type de mouvement.',
    'REASON_REQUIRED': 'Indiquez un motif.',
    'SAME_LOCATION': 'Choisissez deux emplacements différents.',
    'INSUFFICIENT_STOCK': 'Stock insuffisant pour ce produit.',
    'INITIAL_ALREADY_SET': 'Le stock initial a déjà été saisi pour ce produit.',
    'PRODUCT_NOT_STOCKED': 'Ce produit n’est pas suivi en stock.',
    'FRACTIONAL_QUANTITY_NOT_ALLOWED': 'Ce produit se vend uniquement à l’unité (quantité entière).',
    'LOCATION_ARCHIVED': 'Cet emplacement est archivé.',
    'LOCATION_HAS_STOCK': 'Impossible d’archiver un emplacement qui contient du stock.',
    'CATEGORY_TOO_DEEP': 'Les catégories sont limitées à deux niveaux.',
    'PRODUCT_NOT_FOUND': 'Produit introuvable.',
    'LOCATION_NOT_FOUND': 'Emplacement introuvable.',
    'CUSTOMER_NOT_FOUND': 'Client introuvable.',
    'AMOUNT_EXCEEDS_BALANCE': 'Le montant dépasse ce que doit le client.',
    'CREDIT_LIMIT_EXCEEDED': 'Le plafond de crédit de ce client serait dépassé.',
    'CUSTOMER_HAS_BALANCE': 'Ce client a encore une dette : il ne peut pas être archivé.',
    'CUSTOMER_ARCHIVED': 'Ce client est archivé.',
    'INVALID_AMOUNT': 'Montant invalide.',
    'ITEMS_REQUIRED': 'Ajoutez au moins un produit.',
    'INVALID_ITEM': 'Une ligne du panier est invalide.',
    'DUPLICATE_PRODUCT': 'Un même produit apparaît deux fois.',
    'DISCOUNT_EXCEEDS_TOTAL': 'La remise dépasse le montant concerné.',
    'INVALID_PURCHASE_STATUS': 'Cette action n’est pas possible pour le statut actuel de l’achat.',
    'PURCHASE_NOT_EDITABLE': 'Cet achat n’est plus modifiable.',
    'PURCHASE_HAS_PAYMENTS': 'Cet achat a déjà des paiements : il ne peut pas être annulé.',
    'TOTAL_BELOW_AMOUNT_PAID': 'Le nouveau total est inférieur aux acomptes déjà versés.',
    'SUPPLIER_NOT_FOUND': 'Fournisseur introuvable.',
    'PURCHASE_NOT_FOUND': 'Achat introuvable.',
    'CLIENT_REFERENCE_REQUIRED': 'Référence de vente manquante.',
    'INVALID_PAYMENT': 'Paiement invalide.',
    'PAYMENT_EXCEEDS_TOTAL': 'Le paiement dépasse le total. Saisissez uniquement le montant dû.',
    'PLAN_LIMIT_REACHED': 'La limite de votre abonnement est atteinte.',
    'PRODUCT_ARCHIVED': 'Ce produit est archivé et ne peut plus être vendu.',
    'CUSTOMER_REQUIRED_FOR_CREDIT': 'Choisissez un client pour vendre à crédit.',
    'SALE_ALREADY_CANCELLED': 'Cette vente est déjà annulée.',
    'APPEND_ONLY': 'Cet historique ne peut pas être modifié.',
    'INVALID_INPUT': 'Informations invalides. Vérifiez le formulaire.',
    'STORAGE': 'Le fichier n’a pas pu être envoyé. Vérifiez sa taille et son format.',
  };

  @override
  String toString() => 'AppFailure($kind, $code): $message';
}
