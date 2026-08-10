import 'dart:convert';

import 'package:flutter/services.dart';

import 'domain.dart';

class AuthSession {
  const AuthSession({
    required this.userId,
    required this.email,
    required this.role,
    required this.token,
    required this.issuedAt,
    required this.expiresAt,
  });

  final String userId;
  final String email;
  final Role role;
  final String token;
  final DateTime issuedAt;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt);

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'userId': userId,
      'email': email,
      'role': role.code,
      'token': token,
      'issuedAt': issuedAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
    };
  }

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      userId: (json['userId'] as String?) ?? '',
      email: (json['email'] as String?) ?? '',
      role: RoleCode.fromCode((json['role'] as String?) ?? 'USER'),
      token: (json['token'] as String?) ?? '',
      issuedAt: DateTime.tryParse((json['issuedAt'] as String?) ?? '') ??
          DateTime.now().toUtc(),
      expiresAt: DateTime.tryParse((json['expiresAt'] as String?) ?? '') ??
          DateTime.now().toUtc(),
    );
  }
}

class AuthRepository {
  AuthRepository({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('plateq.auth/session');

  final MethodChannel _channel;
  AuthSession? _memorySession;

  Future<AuthSession?> restoreSession() async {
    try {
      final raw = await _channel.invokeMethod<String>('getSession');
      final session = _decode(raw);
      if (session == null || session.isExpired) {
        await clearSession();
        return null;
      }
      _memorySession = session;
      return session;
    } on MissingPluginException {
      return _memorySession?.isExpired == true ? null : _memorySession;
    } on PlatformException {
      return _memorySession?.isExpired == true ? null : _memorySession;
    }
  }

  Future<AuthSession> authenticateDemo({
    required String email,
    required String password,
    required Role fallbackRole,
    required List<AppUser> users,
  }) async {
    if (password.trim().isEmpty) {
      throw const AuthException('Password is required.');
    }

    final normalizedEmail = email.trim().toLowerCase();
    final user = users.firstWhere(
      (item) => item.email.toLowerCase() == normalizedEmail,
      orElse: () => users.firstWhere(
        (item) => item.role == fallbackRole,
        orElse: () => users.first,
      ),
    );
    if (user.status != 'ACTIVE') {
      throw AuthException('${user.name} is disabled.');
    }

    final issuedAt = DateTime.now().toUtc();
    final session = AuthSession(
      userId: user.id,
      email: user.email,
      role: user.role,
      token: 'demo.${user.id}.${issuedAt.microsecondsSinceEpoch}',
      issuedAt: issuedAt,
      expiresAt: issuedAt.add(const Duration(hours: 12)),
    );
    await saveSession(session);
    return session;
  }

  Future<void> saveSession(AuthSession session) async {
    _memorySession = session;
    final encoded = jsonEncode(session.toJson());
    try {
      await _channel.invokeMethod<void>('saveSession', <String, Object?>{
        'session': encoded,
      });
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  Future<void> clearSession() async {
    _memorySession = null;
    try {
      await _channel.invokeMethod<void>('clearSession');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  AuthSession? _decode(String? raw) {
    try {
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return AuthSession.fromJson(Map<String, dynamic>.from(decoded));
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}
