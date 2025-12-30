import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// Stores SNCF Connect session for booking
class SncfConnectSession {
  final bool isAuthenticated;
  final String? firstName;
  final String? lastName;
  final String? email;
  final String? visitorId;
  final DateTime? authenticatedAt;

  SncfConnectSession({
    this.isAuthenticated = false,
    this.firstName,
    this.lastName,
    this.email,
    this.visitorId,
    this.authenticatedAt,
  });

  String? get displayName {
    if (firstName != null && lastName != null) {
      return '$firstName $lastName';
    }
    return firstName ?? lastName ?? email;
  }

  Map<String, dynamic> toJson() => {
    'isAuthenticated': isAuthenticated,
    'firstName': firstName,
    'lastName': lastName,
    'email': email,
    'visitorId': visitorId,
    'authenticatedAt': authenticatedAt?.toIso8601String(),
  };

  factory SncfConnectSession.fromJson(Map<String, dynamic> json) {
    return SncfConnectSession(
      isAuthenticated: json['isAuthenticated'] ?? false,
      firstName: json['firstName'],
      lastName: json['lastName'],
      email: json['email'],
      visitorId: json['visitorId'],
      authenticatedAt: json['authenticatedAt'] != null
          ? DateTime.tryParse(json['authenticatedAt'])
          : null,
    );
  }
}

/// Singleton store for SNCF Connect session
class SncfConnectStore {
  static final SncfConnectStore _instance = SncfConnectStore._internal();
  factory SncfConnectStore() => _instance;
  SncfConnectStore._internal();

  static const String _prefsKey = 'sncf_connect_session';

  SncfConnectSession? _session;

  bool get isAuthenticated => _session?.isAuthenticated ?? false;
  SncfConnectSession? get session => _session;

  Future<void> loadSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_prefsKey);
      if (jsonStr != null) {
        final json = jsonDecode(jsonStr);
        _session = SncfConnectSession.fromJson(json);
        debugPrint('[SncfConnectStore] Loaded session: ${_session?.displayName}');
      }
    } catch (e) {
      debugPrint('[SncfConnectStore] Error loading session: $e');
    }
  }

  Future<void> storeSession(SncfConnectSession session) async {
    _session = session;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(session.toJson()));
      debugPrint('[SncfConnectStore] Stored session: ${session.displayName}');
    } catch (e) {
      debugPrint('[SncfConnectStore] Error storing session: $e');
    }
  }

  Future<void> clearSession() async {
    _session = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
      debugPrint('[SncfConnectStore] Session cleared');
    } catch (e) {
      debugPrint('[SncfConnectStore] Error clearing session: $e');
    }
  }
}
