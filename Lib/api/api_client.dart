import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/task_model.dart';
import '../models/flow_summary.dart';
import '../models/flow_detail.dart';

class ApiClient {
  final String baseUrl;
  final http.Client _client = http.Client();

  ApiClient({this.baseUrl = 'http://localhost:9090'});

  Future<List<TaskModel>> getTasks() async {
    final resp = await _client.get(Uri.parse('$baseUrl/api/tasks'))
        .timeout(const Duration(seconds: 10));
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = json['data'] as List? ?? [];
    return list.map((e) => TaskModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<({List<FlowSummary> items, int total})> getFlows({
    required int taskId,
    int page = 1,
    int size = 50,
    String? protocol,
    String? host,
    String? keyword,
    String? status,
  }) async {
    final params = <String, String>{
      'page': '$page',
      'size': '$size',
    };
    if (protocol != null) params['protocol'] = protocol;
    if (host != null) params['host'] = host;
    if (keyword != null) params['keyword'] = keyword;
    if (status != null) params['status'] = status;

    final uri = Uri.parse('$baseUrl/api/tasks/$taskId/flows').replace(queryParameters: params);
    final resp = await _client.get(uri).timeout(const Duration(seconds: 10));
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final data = json['data'] as Map<String, dynamic>? ?? {};
    final items = (data['items'] as List? ?? [])
        .map((e) => FlowSummary.fromJson(e as Map<String, dynamic>))
        .toList();
    return (items: items, total: (data['total'] as int?) ?? 0);
  }

  Future<FlowDetail> getFlowDetail(int taskId, String flowId) async {
    final resp = await _client.get(
      Uri.parse('$baseUrl/api/tasks/$taskId/flows/$flowId'),
    ).timeout(const Duration(seconds: 10));
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return FlowDetail.fromJson(json);
  }

  Future<String> getPayload(int taskId, String flowId, String direction, {bool preview = false}) async {
    final url = '$baseUrl/api/tasks/$taskId/flows/$flowId/$direction${preview ? "?preview=true" : ""}';
    final resp = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    return resp.body;
  }

  Future<Map<String, dynamic>> getFlowStats(int taskId) async {
    final resp = await _client.get(Uri.parse('$baseUrl/api/tasks/$taskId/flows/stats'))
        .timeout(const Duration(seconds: 10));
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return json['data'] as Map<String, dynamic>? ?? {};
  }

  Future<bool> checkConnection() async {
    try {
      await _client.get(Uri.parse('$baseUrl/api/tasks')).timeout(const Duration(seconds: 3));
      return true;
    } catch (_) {
      return false;
    }
  }

  void dispose() => _client.close();
}
