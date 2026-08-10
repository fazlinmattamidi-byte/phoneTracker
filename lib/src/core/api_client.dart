import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'auth_repository.dart';
import 'domain.dart';

enum ApiEnvironment {
  demo,
  staging,
  production,
}

class PlateqApiConfig {
  const PlateqApiConfig({
    required this.environment,
    required this.baseUrl,
    this.timeout = const Duration(seconds: 20),
    this.maxRetries = 2,
  });

  final ApiEnvironment environment;
  final Uri? baseUrl;
  final Duration timeout;
  final int maxRetries;

  bool get hasBackend => baseUrl != null;

  factory PlateqApiConfig.fromEnvironment() {
    const rawBaseUrl = String.fromEnvironment('PLATEQ_API_BASE_URL');
    const rawEnvironment =
        String.fromEnvironment('PLATEQ_API_ENV', defaultValue: 'demo');
    final baseUrl =
        rawBaseUrl.trim().isEmpty ? null : Uri.tryParse(rawBaseUrl.trim());
    return PlateqApiConfig(
      environment: switch (rawEnvironment.trim().toLowerCase()) {
        'production' || 'prod' => ApiEnvironment.production,
        'staging' || 'stage' => ApiEnvironment.staging,
        _ => ApiEnvironment.demo,
      },
      baseUrl: baseUrl?.hasScheme == true ? baseUrl : null,
    );
  }
}

class PlateqApiClient {
  PlateqApiClient({
    required PlateqApiConfig config,
    HttpClient? httpClient,
  })  : _config = config,
        _httpClient = httpClient ?? HttpClient();

  final PlateqApiConfig _config;
  final HttpClient _httpClient;

  Future<AuthSession> login({
    required String email,
    required String password,
    required List<AppUser> fallbackUsers,
    required Role fallbackRole,
  }) async {
    if (!_config.hasBackend) {
      return AuthRepository().authenticateDemo(
        email: email,
        password: password,
        fallbackRole: fallbackRole,
        users: fallbackUsers,
      );
    }

    final response = await postJson(
      '/auth/login',
      <String, Object?>{
        'email': email,
        'password': password,
      },
    );
    final role = RoleCode.fromCode((response['role'] as String?) ?? 'USER');
    final issuedAt = DateTime.now().toUtc();
    final expiresAt =
        DateTime.tryParse((response['expiresAt'] as String?) ?? '') ??
            issuedAt.add(const Duration(hours: 12));
    return AuthSession(
      userId: (response['userId'] as String?) ?? '',
      email: (response['email'] as String?) ?? email,
      role: role,
      token: (response['accessToken'] as String?) ?? '',
      issuedAt: issuedAt,
      expiresAt: expiresAt,
    );
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    AuthSession? session,
  }) {
    return _sendJson('GET', path, session: session);
  }

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, Object?> body, {
    AuthSession? session,
  }) {
    return _sendJson('POST', path, body: body, session: session);
  }

  Future<Map<String, dynamic>> _sendJson(
    String method,
    String path, {
    Map<String, Object?>? body,
    AuthSession? session,
  }) async {
    final baseUrl = _config.baseUrl;
    if (baseUrl == null) {
      throw const PlateqApiException(
        code: 'BACKEND_NOT_CONFIGURED',
        message: 'Production API base URL is not configured.',
      );
    }

    Object? lastError;
    for (var attempt = 0; attempt <= _config.maxRetries; attempt++) {
      try {
        final uri = baseUrl.resolve(path);
        final request =
            await _httpClient.openUrl(method, uri).timeout(_config.timeout);
        request.headers.contentType = ContentType.json;
        request.headers
            .set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
        if (session != null) {
          request.headers
              .set(HttpHeaders.authorizationHeader, 'Bearer ${session.token}');
        }
        if (body != null) {
          request.write(jsonEncode(body));
        }
        final response = await request.close().timeout(_config.timeout);
        final raw = await utf8.decodeStream(response).timeout(_config.timeout);
        final decoded = raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw);
        final payload = decoded is Map
            ? Map<String, dynamic>.from(decoded)
            : <String, dynamic>{};
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return payload;
        }
        throw PlateqApiException(
          code: '${response.statusCode}',
          message: (payload['message'] as String?) ?? response.reasonPhrase,
          details: payload,
        );
      } catch (error) {
        lastError = error;
        if (attempt == _config.maxRetries || error is PlateqApiException) {
          break;
        }
        await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
      }
    }

    if (lastError is PlateqApiException) throw lastError;
    throw PlateqApiException(
      code: 'NETWORK_ERROR',
      message: lastError?.toString() ?? 'Unknown network error',
    );
  }
}

class PlateqApiException implements Exception {
  const PlateqApiException({
    required this.code,
    required this.message,
    this.details,
  });

  final String code;
  final String message;
  final Map<String, dynamic>? details;

  @override
  String toString() => '$code: $message';
}
