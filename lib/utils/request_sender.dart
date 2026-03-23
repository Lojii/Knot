import 'package:http/http.dart' as http;
import '../models/flow_summary.dart';

/// Result of a repeated request.
class RepeatResult {
  final int statusCode;
  final Duration elapsed;
  final String body;
  final Map<String, String> headers;

  RepeatResult({
    required this.statusCode,
    required this.elapsed,
    required this.body,
    required this.headers,
  });
}

/// Utility for sending/repeating captured HTTP requests.
class RequestSender {
  /// Repeat a captured request using data from FlowSummary and detail metadata.
  static Future<RepeatResult> repeat(
    FlowSummary flow,
    Map<String, dynamic> detail,
  ) async {
    // Build URL
    final protocol = flow.protocol.toLowerCase();
    final scheme = (protocol == 'https' || protocol == 'h2') ? 'https' : 'http';
    final host = flow.host;
    final uri = flow.uri;
    final url = '$scheme://$host$uri';

    // Extract method
    final method = flow.method.isNotEmpty ? flow.method : 'GET';

    // Extract headers from detail metadata
    final metadata = detail['metadata'] as Map<String, dynamic>? ?? {};
    final reqHeaders = <String, String>{};
    final headersList = metadata['requestHeaders'] as List?;
    if (headersList != null) {
      for (final h in headersList) {
        final pair = h as List;
        final key = (pair.first as String).toLowerCase();
        // Skip hop-by-hop and proxy headers
        if (key == 'host' ||
            key == 'connection' ||
            key == 'proxy-connection' ||
            key == 'transfer-encoding' ||
            key == 'content-length') {
          continue;
        }
        reqHeaders[pair.first as String] = pair.last as String;
      }
    }

    // Build and send request
    final request = http.Request(method, Uri.parse(url));
    request.headers.addAll(reqHeaders);

    final stopwatch = Stopwatch()..start();
    final streamedResponse = await http.Client().send(request);
    final response = await http.Response.fromStream(streamedResponse);
    stopwatch.stop();

    return RepeatResult(
      statusCode: response.statusCode,
      elapsed: stopwatch.elapsed,
      body: response.body,
      headers: response.headers,
    );
  }

  /// Extract headers map from detail metadata for pre-filling compose.
  static Map<String, String> extractHeaders(Map<String, dynamic> detail) {
    final metadata = detail['metadata'] as Map<String, dynamic>? ?? {};
    final headers = <String, String>{};
    final headersList = metadata['requestHeaders'] as List?;
    if (headersList != null) {
      for (final h in headersList) {
        final pair = h as List;
        final key = (pair.first as String).toLowerCase();
        if (key == 'host' || key == 'connection' || key == 'transfer-encoding' || key == 'content-length') {
          continue;
        }
        headers[pair.first as String] = pair.last as String;
      }
    }
    return headers;
  }

  /// Build a full URL string from a FlowSummary.
  static String buildUrl(FlowSummary flow) {
    final protocol = flow.protocol.toLowerCase();
    final scheme = (protocol == 'https' || protocol == 'h2') ? 'https' : 'http';
    return '$scheme://${flow.host}${flow.uri}';
  }
}
