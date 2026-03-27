/// Lightweight flow summary for domain tree building.
class FlowSummaryLight {
  final String flowId;
  final String host;
  final String protocol;
  final String method;
  final String path;
  final String statusCode;
  final String contentType;
  final int status;

  FlowSummaryLight({
    required this.flowId,
    required this.host,
    this.protocol = '',
    this.method = '',
    this.path = '',
    this.statusCode = '',
    this.contentType = '',
    this.status = 0,
  });

  factory FlowSummaryLight.fromJson(Map<String, dynamic> json) => FlowSummaryLight(
    flowId: (json['flowId'] as String?) ?? '',
    host: (json['host'] as String?) ?? '',
    protocol: (json['protocol'] as String?) ?? '',
    method: (json['method'] as String?) ?? '',
    path: (json['path'] as String?) ?? '',
    statusCode: (json['statusCode'] as String?) ?? '',
    contentType: (json['contentType'] as String?) ?? '',
    status: (json['status'] as int?) ?? 0,
  );
}
