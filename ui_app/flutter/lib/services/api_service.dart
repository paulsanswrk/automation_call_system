import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class ApiService {
  static const _baseUrl = 'https://act2026.mooo.com';

  static SupabaseClient get _supabase => Supabase.instance.client;

  static String? get _accessToken => _supabase.auth.currentSession?.accessToken;

  static Map<String, String> get _authHeaders => {
    'Authorization': 'Bearer ${_accessToken ?? ''}',
    'Content-Type': 'application/json',
  };

  // ─── Generic methods ───

  static Future<http.Response> get(String path) async {
    return http.get(
      Uri.parse('$_baseUrl$path'),
      headers: _authHeaders,
    );
  }

  static Future<http.Response> post(String path, {Object? body}) async {
    return http.post(
      Uri.parse('$_baseUrl$path'),
      headers: _authHeaders,
      body: body != null ? jsonEncode(body) : null,
    );
  }

  static Future<http.Response> delete(String path, {Object? body}) async {
    return http.delete(
      Uri.parse('$_baseUrl$path'),
      headers: _authHeaders,
      body: body != null ? jsonEncode(body) : null,
    );
  }

  // ─── WebSocket URL builder ───

  static String wsUrl(String path) {
    final token = _accessToken ?? '';
    return 'wss://act2026.mooo.com$path?token=${Uri.encodeComponent(token)}';
  }
}
