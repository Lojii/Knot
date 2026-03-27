import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/task_model.dart';
import '../models/flow_summary.dart';
import '../models/flow_detail.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiClient {
  String baseUrl;
  final http.Client _client = http.Client();

  ApiClient({this.baseUrl = 'http://localhost:9090'});

  // ── Helpers ──

  /// Unwrap standard JSON envelope {code, data} with status check.
  Map<String, dynamic> _unwrap(http.Response resp) {
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ApiException(resp.statusCode, resp.body);
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return json['data'] as Map<String, dynamic>? ?? {};
  }

  /// Unwrap envelope and return 'data' as a List.
  List _unwrapList(http.Response resp) {
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ApiException(resp.statusCode, resp.body);
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return json['data'] as List? ?? [];
  }

  /// Check status for non-JSON responses (payload bytes, etc).
  void _checkStatus(http.Response resp) {
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ApiException(resp.statusCode, resp.body);
    }
  }

  // ── Tasks ──

  Future<List<TaskModel>> getTasks() async {
    final resp = await _client.get(Uri.parse('$baseUrl/api/tasks'))
        .timeout(const Duration(seconds: 10));
    final list = _unwrapList(resp);
    return list.map((e) => TaskModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> renameTask(int taskId, String name) async {
    final resp = await _client.patch(
      Uri.parse('$baseUrl/api/tasks/$taskId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name}),
    ).timeout(const Duration(seconds: 10));
    _checkStatus(resp);
  }

  Future<void> deleteTask(int taskId) async {
    final resp = await _client.delete(Uri.parse('$baseUrl/api/tasks/$taskId'))
        .timeout(const Duration(seconds: 10));
    _checkStatus(resp);
  }

  Future<void> batchDeleteTasks(List<int> ids) async {
    final resp = await _client.post(
      Uri.parse('$baseUrl/api/tasks/batch-delete'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'ids': ids}),
    ).timeout(const Duration(seconds: 30));
    _checkStatus(resp);
  }

  // ── Flows ──

  Future<({List<FlowSummary> items, int total})> getFlows({
    required int taskId,
    int page = 1,
    int size = 50,
    String? protocol,
    String? host,
    String? keyword,
    String? status,
  }) async {
    final params = <String, String>{'page': '$page', 'size': '$size'};
    if (protocol != null) params['protocol'] = protocol;
    if (host != null) params['host'] = host;
    if (keyword != null) params['keyword'] = keyword;
    if (status != null) params['status'] = status;

    final uri = Uri.parse('$baseUrl/api/tasks/$taskId/flows').replace(queryParameters: params);
    final resp = await _client.get(uri).timeout(const Duration(seconds: 10));
    final data = _unwrap(resp);
    final items = (data['items'] as List? ?? [])
        .map((e) => FlowSummary.fromJson(e as Map<String, dynamic>))
        .toList();
    return (items: items, total: (data['total'] as int?) ?? 0);
  }

  Future<FlowDetail> getFlowDetail(int taskId, String flowId) async {
    final resp = await _client.get(
      Uri.parse('$baseUrl/api/tasks/$taskId/flows/$flowId'),
    ).timeout(const Duration(seconds: 10));
    _checkStatus(resp);
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return FlowDetail.fromJson(json);
  }

  Future<({List<String> protocols, List<String> contentTypes})> getFlowFilters(int taskId) async {
    final resp = await _client.get(Uri.parse('$baseUrl/api/tasks/$taskId/flows/filters'))
        .timeout(const Duration(seconds: 10));
    final data = _unwrap(resp);
    final protocols = (data['protocols'] as List?)?.map((e) => e as String).toList() ?? [];
    final contentTypes = (data['contentTypes'] as List?)?.map((e) => e as String).toList() ?? [];
    return (protocols: protocols, contentTypes: contentTypes);
  }

  Future<List<({String host, int count})>> getFlowDomains(int taskId, {String? protocol, String? keyword}) async {
    final params = <String, String>{};
    if (protocol != null) params['protocol'] = protocol;
    if (keyword != null) params['keyword'] = keyword;
    final uri = Uri.parse('$baseUrl/api/tasks/$taskId/flows/domains')
        .replace(queryParameters: params.isEmpty ? null : params);
    final resp = await _client.get(uri).timeout(const Duration(seconds: 10));
    final data = _unwrap(resp);
    final items = data['items'] as List? ?? [];
    return items.map((e) {
      final m = e as Map<String, dynamic>;
      return (host: m['host'] as String? ?? '', count: (m['count'] as int?) ?? 0);
    }).toList();
  }

  Future<Map<String, dynamic>> getFlowStats(int taskId) async {
    final resp = await _client.get(Uri.parse('$baseUrl/api/tasks/$taskId/flows/stats'))
        .timeout(const Duration(seconds: 10));
    return _unwrap(resp);
  }

  // ── Payloads ──

  Future<Uint8List> getPayloadBytes(int taskId, String flowId, String direction, {bool preview = false}) async {
    final url = '$baseUrl/api/tasks/$taskId/flows/$flowId/$direction${preview ? "?preview=true" : ""}';
    final resp = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    _checkStatus(resp);
    return resp.bodyBytes;
  }

  Future<Uint8List> getDecodedPayloadBytes(int taskId, String flowId, String direction) async {
    final url = '$baseUrl/api/tasks/$taskId/flows/$flowId/decoded/$direction';
    final resp = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
    _checkStatus(resp);
    return resp.bodyBytes;
  }

  // ── Connection check ──

  Future<bool> checkConnection() async {
    try {
      final resp = await _client.get(Uri.parse('$baseUrl/api/tasks')).timeout(const Duration(seconds: 3));
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  // ── Map Local Rules ──

  Future<List<Map<String, dynamic>>> getMapLocalRules() async {
    final resp = await _client.get(Uri.parse('$baseUrl/api/rules/map-local'))
        .timeout(const Duration(seconds: 10));
    return List<Map<String, dynamic>>.from(_unwrapList(resp));
  }

  Future<void> createMapLocalRule(Map<String, dynamic> rule) async {
    final resp = await _client.post(Uri.parse('$baseUrl/api/rules/map-local'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(rule))
        .timeout(const Duration(seconds: 10));
    _checkStatus(resp);
  }

  Future<void> deleteMapLocalRule(int id) async {
    final resp = await _client.delete(Uri.parse('$baseUrl/api/rules/map-local/$id'))
        .timeout(const Duration(seconds: 10));
    _checkStatus(resp);
  }

  Future<void> toggleMapLocalRule(int id) async {
    final resp = await _client.patch(Uri.parse('$baseUrl/api/rules/map-local/$id/toggle'))
        .timeout(const Duration(seconds: 10));
    _checkStatus(resp);
  }

  // ── Breakpoint Rules ──

  Future<List<Map<String, dynamic>>> getBreakpointRules() async {
    final resp = await _client.get(Uri.parse('$baseUrl/api/rules/breakpoint'))
        .timeout(const Duration(seconds: 10));
    return List<Map<String, dynamic>>.from(_unwrapList(resp));
  }

  Future<void> createBreakpointRule(Map<String, dynamic> rule) async {
    final resp = await _client.post(Uri.parse('$baseUrl/api/rules/breakpoint'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(rule))
        .timeout(const Duration(seconds: 10));
    _checkStatus(resp);
  }

  Future<void> deleteBreakpointRule(int id) async {
    final resp = await _client.delete(Uri.parse('$baseUrl/api/rules/breakpoint/$id'))
        .timeout(const Duration(seconds: 10));
    _checkStatus(resp);
  }

  Future<void> toggleBreakpointRule(int id) async {
    final resp = await _client.patch(Uri.parse('$baseUrl/api/rules/breakpoint/$id/toggle'))
        .timeout(const Duration(seconds: 10));
    _checkStatus(resp);
  }

  // ── Breakpoint Resume ──

  Future<void> resumeBreakpoint(String flowId, String action, {Map<String, dynamic>? modifiedRequest}) async {
    final body = <String, dynamic>{'action': action};
    if (modifiedRequest != null) body['modifiedRequest'] = modifiedRequest;
    final resp = await _client.patch(Uri.parse('$baseUrl/api/breakpoint/$flowId/resume'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body))
        .timeout(const Duration(seconds: 10));
    _checkStatus(resp);
  }

  void dispose() => _client.close();
}
