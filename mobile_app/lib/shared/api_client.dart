import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiClient {
  /// Resolves the correct base origin depending on the platform/environment.
  /// - Android emulator: 10.0.2.2 (loopback to host machine)
  /// - Everything else (iOS sim, Windows, Web, physical device): localhost or override
  static String get origin {
    // Override via compile-time env: flutter run --dart-define=API_ORIGIN=http://192.168.1.10:8100
    const envOrigin = String.fromEnvironment('API_ORIGIN', defaultValue: '');
    if (envOrigin.isNotEmpty) return envOrigin;

    // Android emulator special address
    if (defaultTargetPlatform == TargetPlatform.android && !kIsWeb) {
      return 'http://10.0.2.2:8100';
    }

    return 'http://localhost:8100';
  }

  static String get baseUrl => '$origin/api/v1';

  static String get wsUrl => '${origin.replaceFirst('http', 'ws')}/ws/queue';

  static String resolveUrl(String pathOrUrl) {
    if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
      return pathOrUrl;
    }
    if (pathOrUrl.startsWith('/')) {
      return '$origin$pathOrUrl';
    }
    return '$origin/$pathOrUrl';
  }

  Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> body, {String? token}) async {
    final response = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Future<dynamic> getJson(String path, {String? token}) async {
    final response = await http.get(
      Uri.parse('$baseUrl$path'),
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
    return _decode(response);
  }

  dynamic _decode(http.Response response) {
    final body = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) return body;
    throw Exception(body['detail'] ?? 'Request failed');
  }
}
