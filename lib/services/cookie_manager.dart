import 'package:flutter/foundation.dart';

class CookieManager {
  static final CookieManager _instance = CookieManager._internal();
  factory CookieManager() => _instance;
  CookieManager._internal();

  final Map<String, String> _cookies = {};
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  void setCookies(List<String> cookieStrings) {
    _cookies.clear();
    for (final cookie in cookieStrings) {
      // Parse cookie string: "name=value; path=/; ..."
      final parts = cookie.split(';');
      if (parts.isNotEmpty) {
        final nameValue = parts[0].trim().split('=');
        if (nameValue.length >= 2) {
          final name = nameValue[0];
          final value = nameValue.sublist(1).join('=');
          _cookies[name] = value;
        }
      }
    }
    _isInitialized = _cookies.isNotEmpty;
    debugPrint('[CookieManager] ${_cookies.length} cookies loaded');
    debugPrint('[CookieManager] Keys: ${_cookies.keys.toList()}');
  }

  String getCookieHeader() {
    return _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  bool hasDataDomeCookie() {
    return _cookies.keys.any((k) => k.toLowerCase().contains('datadome'));
  }

  void clear() {
    _cookies.clear();
    _isInitialized = false;
  }
}
