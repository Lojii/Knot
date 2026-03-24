class FlowSummary {
  final String flowId;
  final String protocol;
  final String host;
  final int port;
  final double startedAt;
  final double? endedAt;
  final double? durationMs;
  final int uploadBytes;
  final int downloadBytes;
  final int status;
  final String summary;
  final String searchKey1; // method
  final String searchKey2; // uri
  final String searchKey3; // statusCode
  final String searchKey4; // contentType
  final int protoFlags;
  final int connReuse;

  FlowSummary({
    required this.flowId,
    required this.protocol,
    required this.host,
    this.port = 0,
    required this.startedAt,
    this.endedAt,
    this.durationMs,
    this.uploadBytes = 0,
    this.downloadBytes = 0,
    this.status = 0,
    this.summary = '',
    this.searchKey1 = '',
    this.searchKey2 = '',
    this.searchKey3 = '',
    this.searchKey4 = '',
    this.protoFlags = 0,
    this.connReuse = 0,
  });

  String get method => searchKey1;
  String get uri => searchKey2;
  String get statusCode => searchKey3;
  String get contentType => searchKey4;

  factory FlowSummary.fromJson(Map<String, dynamic> json) => FlowSummary(
    flowId: json['flowId'] as String,
    protocol: (json['protocol'] as String?) ?? '',
    host: (json['host'] as String?) ?? '',
    port: (json['port'] as int?) ?? 0,
    startedAt: (json['startedAt'] as num?)?.toDouble() ?? 0,
    endedAt: (json['endedAt'] as num?)?.toDouble(),
    durationMs: (json['durationMs'] as num?)?.toDouble(),
    uploadBytes: (json['uploadBytes'] as int?) ?? 0,
    downloadBytes: (json['downloadBytes'] as int?) ?? 0,
    status: (json['status'] as int?) ?? 0,
    summary: (json['summary'] as String?) ?? '',
    searchKey1: (json['searchKey1'] as String?) ?? '',
    searchKey2: (json['searchKey2'] as String?) ?? '',
    searchKey3: (json['searchKey3'] as String?) ?? '',
    searchKey4: (json['searchKey4'] as String?) ?? '',
    protoFlags: (json['protoFlags'] as int?) ?? 0,
    connReuse: (json['connReuse'] as int?) ?? 0,
  );
}
