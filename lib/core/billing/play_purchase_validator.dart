import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_helpers.dart';
import 'billing_entitlement.dart';
import 'play_billing_diag.dart';
import 'play_product_ids.dart';
import 'play_purchase_payload.dart';
import 'play_purchase_validation_result.dart';

/// Valida compras Play contra la Edge Function (autoridad).
abstract class PlayPurchaseValidator {
  Future<PlayPurchaseValidationResult> validate(PlayPurchasePayload payload);

  Future<BillingEntitlement> fetchEntitlement();
}

class SupabasePlayPurchaseValidator implements PlayPurchaseValidator {
  SupabasePlayPurchaseValidator({SupabaseClient? client})
    : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient? get _resolved => _clientOverride ?? SupabaseHelpers.client;

  static const functionName = 'validate-play-purchase';

  @override
  Future<PlayPurchaseValidationResult> validate(
    PlayPurchasePayload payload,
  ) async {
    final client = _resolved;
    final session = client?.auth.currentSession;
    if (client == null || session == null) {
      return _diagResult(
        PlayPurchaseValidationResult.failure(
          errorCode: PlayPurchaseValidationErrorCode.notAuthenticated,
          safeMessage: 'not_authenticated',
        ),
      );
    }

    final token = payload.purchaseToken.trim();
    final productId = payload.productId.trim();
    if (token.isEmpty) {
      return _diagResult(
        PlayPurchaseValidationResult.failure(
          errorCode: PlayPurchaseValidationErrorCode.missingToken,
          safeMessage: 'missing_purchase_token',
        ),
      );
    }
    if (productId != PlayProductIds.monthly &&
        productId != PlayProductIds.founderAnnual) {
      return _diagResult(
        PlayPurchaseValidationResult.failure(
          errorCode: PlayPurchaseValidationErrorCode.unexpectedProduct,
          safeMessage: 'unexpected_product',
        ),
      );
    }

    try {
      final response = await client.functions.invoke(
        functionName,
        body: payload.toValidationRequestBody(),
      );

      if (response.status == 401) {
        return _diagResult(
          PlayPurchaseValidationResult.failure(
            errorCode: PlayPurchaseValidationErrorCode.unauthorized,
            httpStatus: 401,
            safeMessage: 'unauthorized',
          ),
        );
      }
      if (response.status == 409) {
        return _diagResult(
          PlayPurchaseValidationResult.failure(
            errorCode: PlayPurchaseValidationErrorCode.conflict,
            httpStatus: 409,
            safeMessage: _conflictCode(response.data),
          ),
        );
      }
      if (response.status == 502) {
        return _diagResult(
          PlayPurchaseValidationResult.failure(
            errorCode: PlayPurchaseValidationErrorCode.googlePlayFailed,
            httpStatus: 502,
            safeMessage: 'google_play_validation_failed',
          ),
        );
      }
      if (response.status >= 500) {
        return _diagResult(
          PlayPurchaseValidationResult.failure(
            errorCode: PlayPurchaseValidationErrorCode.serverError,
            httpStatus: response.status,
            safeMessage: 'server_error',
          ),
        );
      }
      if (response.status != 200) {
        return _diagResult(
          PlayPurchaseValidationResult.failure(
            errorCode: PlayPurchaseValidationErrorCode.unknown,
            httpStatus: response.status,
            safeMessage: 'unexpected_status',
          ),
        );
      }

      final data = _asMap(response.data);
      if (data == null || data['ok'] != true) {
        return _diagResult(
          PlayPurchaseValidationResult.failure(
            errorCode: PlayPurchaseValidationErrorCode.unknown,
            httpStatus: 200,
            safeMessage: 'invalid_response',
          ),
        );
      }

      final entitlementMap = _asMap(data['entitlement']);
      final entitlement = entitlementMap != null
          ? BillingEntitlement.fromJson(entitlementMap)
          : BillingEntitlement.none;

      return _diagResult(
        PlayPurchaseValidationResult.success(
          entitlement: entitlement,
          acknowledged: data['acknowledged'] == true,
          acknowledgePending: data['acknowledge_pending'] == true,
        ),
      );
    } on FunctionException catch (e) {
      return _diagResult(_fromFunctionException(e));
    } catch (e, st) {
      debugPrint('PlayPurchaseValidator network/unknown: $e\n$st');
      final failed = PlayPurchaseValidationResult.failure(
        errorCode: PlayPurchaseValidationErrorCode.networkError,
        safeMessage: 'network_error',
      );
      KlooviBillingDiag.log('validation_http_result', {
        'http': 0,
        'ok': false,
        'code': sanitizedValidationDiagCode(failed) ?? 'network_error',
        'error': KlooviBillingDiag.sanitizeError(e),
      });
      return failed;
    }
  }

  PlayPurchaseValidationResult _diagResult(
    PlayPurchaseValidationResult result,
  ) {
    final fields = <String, Object?>{
      'http': result.httpStatus ?? 0,
      'ok': result.ok,
    };
    final code = sanitizedValidationDiagCode(result);
    if (code != null) {
      fields['code'] = code;
    }
    KlooviBillingDiag.log('validation_http_result', fields);
    return result;
  }

  @override
  Future<BillingEntitlement> fetchEntitlement() async {
    final client = _resolved;
    final session = client?.auth.currentSession;
    if (client == null || session == null) {
      return BillingEntitlement.none;
    }

    try {
      final raw = await client.rpc('get_my_billing_entitlement');
      final row = _firstRow(raw);
      if (row == null) return BillingEntitlement.none;
      return BillingEntitlement.fromJson(row);
    } catch (e, st) {
      debugPrint('get_my_billing_entitlement failed: $e\n$st');
      rethrow;
    }
  }

  PlayPurchaseValidationResult _fromFunctionException(FunctionException e) {
    final status = e.status;
    if (status == 401) {
      return PlayPurchaseValidationResult.failure(
        errorCode: PlayPurchaseValidationErrorCode.unauthorized,
        httpStatus: 401,
        safeMessage: 'unauthorized',
      );
    }
    if (status == 409) {
      return PlayPurchaseValidationResult.failure(
        errorCode: PlayPurchaseValidationErrorCode.conflict,
        httpStatus: 409,
        safeMessage: _conflictCode(e.details),
      );
    }
    if (status == 502) {
      return PlayPurchaseValidationResult.failure(
        errorCode: PlayPurchaseValidationErrorCode.googlePlayFailed,
        httpStatus: 502,
        safeMessage: 'google_play_validation_failed',
      );
    }
    if (status >= 500) {
      return PlayPurchaseValidationResult.failure(
        errorCode: PlayPurchaseValidationErrorCode.serverError,
        httpStatus: status,
        safeMessage: 'server_error',
      );
    }
    return PlayPurchaseValidationResult.failure(
      errorCode: PlayPurchaseValidationErrorCode.unknown,
      httpStatus: status,
      safeMessage: 'function_exception',
    );
  }

  static String _conflictCode(Object? data) {
    final map = _asMap(data);
    final error = map?['error'] as String?;
    if (error != null && error.trim().isNotEmpty) return error.trim();
    return 'conflict';
  }

  static Map<String, dynamic>? _asMap(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  static Map<String, dynamic>? _firstRow(Object? raw) {
    if (raw is List) {
      if (raw.isEmpty) return null;
      return _asMap(raw.first);
    }
    return _asMap(raw);
  }
}

/// Código seguro para `validation_http_result` (sin cuerpos ni mensajes).
@visibleForTesting
String? sanitizedValidationDiagCode(PlayPurchaseValidationResult result) {
  if (result.ok) return null;
  switch (result.errorCode) {
    case PlayPurchaseValidationErrorCode.notAuthenticated:
      return 'not_authenticated';
    case PlayPurchaseValidationErrorCode.networkError:
      return 'network_error';
    case PlayPurchaseValidationErrorCode.unauthorized:
      return 'http_401';
    case PlayPurchaseValidationErrorCode.conflict:
      return 'http_409';
    case PlayPurchaseValidationErrorCode.googlePlayFailed:
      return 'http_502';
    case PlayPurchaseValidationErrorCode.serverError:
      return 'http_5xx';
    case PlayPurchaseValidationErrorCode.notPro:
      return 'not_pro';
    case PlayPurchaseValidationErrorCode.missingToken:
      return 'missing_purchase_token';
    case PlayPurchaseValidationErrorCode.unexpectedProduct:
      return 'unexpected_product';
    case PlayPurchaseValidationErrorCode.unknown:
    case null:
      break;
  }
  final http = result.httpStatus;
  if (http == 401) return 'http_401';
  if (http == 409) return 'http_409';
  if (http == 502) return 'http_502';
  if (http != null && http >= 500) return 'http_5xx';
  return 'unknown';
}
