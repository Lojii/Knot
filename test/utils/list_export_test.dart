import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:knot/utils/list_export.dart';
import 'package:knot/models/flow_summary.dart';

void main() {
  FlowSummary _makeFlow({
    String flowId = 'f-1',
    String method = 'GET',
    String host = 'example.com',
    String uri = '/api/data',
    int port = 443,
    String protocol = 'HTTPS',
    int status = 200,
    int downloadBytes = 1024,
    int uploadBytes = 128,
    double startedAt = 1700000000.0,
    double? durationMs = 150.0,
    String contentType = 'application/json',
  }) {
    return FlowSummary(
      flowId: flowId,
      protocol: protocol,
      host: host,
      port: port,
      startedAt: startedAt,
      durationMs: durationMs,
      uploadBytes: uploadBytes,
      downloadBytes: downloadBytes,
      status: status,
      searchKey1: method,
      searchKey2: uri,
      searchKey3: '$status',
      searchKey4: contentType,
    );
  }

  group('ListExport.toCsv', () {
    test('empty list produces only header row', () {
      final csv = ListExport.toCsv([]);
      final lines = csv.trim().split('\n');
      expect(lines.length, 1);
      expect(lines[0], 'Method,Host,Path,Status,Size,Time,Protocol');
    });

    test('single flow produces header + one data row', () {
      final csv = ListExport.toCsv([_makeFlow()]);
      final lines = csv.trim().split('\n');
      expect(lines.length, 2);
      expect(lines[1], 'GET,example.com,/api/data,200,1024,150,HTTPS');
    });

    test('multiple flows produce correct number of rows', () {
      final flows = [
        _makeFlow(flowId: 'f-1', method: 'GET', host: 'a.com', uri: '/1', status: 200),
        _makeFlow(flowId: 'f-2', method: 'POST', host: 'b.com', uri: '/2', status: 201),
        _makeFlow(flowId: 'f-3', method: 'DELETE', host: 'c.com', uri: '/3', status: 204),
      ];
      final csv = ListExport.toCsv(flows);
      final lines = csv.trim().split('\n');
      expect(lines.length, 4); // header + 3 rows
    });

    test('field mapping is correct (method, host, path, status, size, time, protocol)', () {
      final flow = _makeFlow(
        method: 'PUT',
        host: 'api.io',
        uri: '/v2/resource',
        status: 204,
        downloadBytes: 0,
        durationMs: 42.0,
        protocol: 'H2',
      );
      final csv = ListExport.toCsv([flow]);
      final lines = csv.trim().split('\n');
      expect(lines[1], 'PUT,api.io,/v2/resource,204,0,42,H2');
    });

    test('null durationMs produces empty time field', () {
      final flow = _makeFlow(durationMs: null);
      final csv = ListExport.toCsv([flow]);
      final lines = csv.trim().split('\n');
      // Should have empty time field: GET,example.com,/api/data,200,1024,,HTTPS
      expect(lines[1], contains(',200,1024,,HTTPS'));
    });

    test('host with comma is escaped in quotes', () {
      // Unlikely but tests CSV escaping
      final flow = _makeFlow(host: 'host,with,commas');
      final csv = ListExport.toCsv([flow]);
      expect(csv, contains('"host,with,commas"'));
    });

    test('path with comma is escaped in quotes', () {
      final flow = _makeFlow(uri: '/path?a=1,2');
      final csv = ListExport.toCsv([flow]);
      expect(csv, contains('"'));
    });

    test('host with double quotes is escaped', () {
      final flow = _makeFlow(host: 'host"with"quotes');
      final csv = ListExport.toCsv([flow]);
      // Double quotes should be doubled inside CSV
      expect(csv, contains('"host""with""quotes"'));
    });

    test('host with newline is escaped', () {
      final flow = _makeFlow(host: 'host\nwith\nnewlines');
      final csv = ListExport.toCsv([flow]);
      expect(csv, contains('"host\nwith\nnewlines"'));
    });
  });

  group('ListExport.toJson', () {
    test('empty list returns empty JSON array', () {
      final json = ListExport.toJson([]);
      final parsed = jsonDecode(json) as List;
      expect(parsed, isEmpty);
    });

    test('single flow returns array with one object', () {
      final json = ListExport.toJson([_makeFlow()]);
      final parsed = jsonDecode(json) as List;
      expect(parsed.length, 1);
    });

    test('multiple flows return correct count', () {
      final flows = [
        _makeFlow(flowId: 'f-1'),
        _makeFlow(flowId: 'f-2'),
        _makeFlow(flowId: 'f-3'),
      ];
      final json = ListExport.toJson(flows);
      final parsed = jsonDecode(json) as List;
      expect(parsed.length, 3);
    });

    test('JSON includes all expected fields', () {
      final flow = _makeFlow(
        flowId: 'f-42',
        method: 'POST',
        host: 'api.example.com',
        uri: '/v1/create',
        status: 201,
        downloadBytes: 512,
        durationMs: 99.0,
        protocol: 'H2',
        uploadBytes: 256,
        contentType: 'application/json',
      );
      final json = ListExport.toJson([flow]);
      final parsed = (jsonDecode(json) as List).first as Map<String, dynamic>;

      expect(parsed['method'], 'POST');
      expect(parsed['host'], 'api.example.com');
      expect(parsed['path'], '/v1/create');
      expect(parsed['status'], 201);
      expect(parsed['size'], 512);
      expect(parsed['time'], 99);
      expect(parsed['protocol'], 'H2');
      expect(parsed['flowId'], 'f-42');
      expect(parsed['uploadBytes'], 256);
      expect(parsed['contentType'], 'application/json');
    });

    test('null durationMs produces null time in JSON', () {
      final flow = _makeFlow(durationMs: null);
      final json = ListExport.toJson([flow]);
      final parsed = (jsonDecode(json) as List).first as Map<String, dynamic>;
      expect(parsed['time'], isNull);
    });

    test('output is valid JSON with indentation', () {
      final flow = _makeFlow();
      final json = ListExport.toJson([flow]);
      // Should contain indentation
      expect(json, contains('  '));
      // Should parse without error
      expect(() => jsonDecode(json), returnsNormally);
    });

    test('startedAt is included', () {
      final flow = _makeFlow(startedAt: 1700000000.0);
      final json = ListExport.toJson([flow]);
      final parsed = (jsonDecode(json) as List).first as Map<String, dynamic>;
      expect(parsed['startedAt'], 1700000000.0);
    });
  });
}
