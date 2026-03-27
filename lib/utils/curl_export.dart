import '../controllers/detail_controller.dart';

/// Builds a cURL command string from flow detail data.
class CurlExport {
  /// Constructs a cURL command from the raw flow detail JSON map.
  ///
  /// Includes method, URL, request headers, and body hint for
  /// POST/PUT/PATCH requests.
  static String fromFlowDetail(Map<String, dynamic> raw) {
    final method = (raw['searchKey1'] as String?) ?? 'GET';
    final uri = (raw['searchKey2'] as String?) ?? '/';
    final host = (raw['host'] as String?) ?? '';
    final protocol = (raw['protocol'] as String?) ?? '';

    // Build the full URL
    final scheme = protocol.toUpperCase().contains('HTTPS') ||
        protocol.toUpperCase().contains('H2')
        ? 'https'
        : 'http';
    final port = (raw['port'] as int?) ?? 0;
    final portSuffix = (port > 0 && port != 80 && port != 443) ? ':$port' : '';
    final fullUrl = '$scheme://$host$portSuffix$uri';

    final parts = <String>['curl'];

    // Method
    if (method.toUpperCase() != 'GET') {
      parts.add("-X '${_escapeShell(method.toUpperCase())}'");
    }

    // URL
    parts.add("'${_escapeShell(fullUrl)}'");

    // Request headers
    final reqHeaders = DetailController.parseHeaders(raw, 'reqHeaders');
    for (final h in reqHeaders) {
      // Skip pseudo-headers and host (already in URL)
      if (h.$1.startsWith(':')) continue;
      parts.add("-H '${_escapeShell('${h.$1}: ${h.$2}')}'");
    }

    // Body hint for methods that typically have a body
    final upperMethod = method.toUpperCase();
    if (upperMethod == 'POST' ||
        upperMethod == 'PUT' ||
        upperMethod == 'PATCH') {
      parts.add("--data '<request body>'");
    }

    return parts.join(' \\\n  ');
  }

  static String _escapeShell(String s) {
    return s.replaceAll("'", "'\\''");
  }
}
