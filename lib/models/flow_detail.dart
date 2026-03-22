class ConnectionInfo {
  final String srcIp, dstIp;
  final int srcPort, dstPort;
  final String state;
  final String? tlsVersion, tlsCipher, tlsSni;

  ConnectionInfo({
    this.srcIp = '', this.dstIp = '',
    this.srcPort = 0, this.dstPort = 0,
    this.state = '',
    this.tlsVersion, this.tlsCipher, this.tlsSni,
  });

  factory ConnectionInfo.fromJson(Map<String, dynamic> json) => ConnectionInfo(
    srcIp: (json['srcIp'] as String?) ?? '',
    dstIp: (json['dstIp'] as String?) ?? '',
    srcPort: (json['srcPort'] as int?) ?? 0,
    dstPort: (json['dstPort'] as int?) ?? 0,
    state: (json['state'] as String?) ?? '',
    tlsVersion: json['tlsVersion'] as String?,
    tlsCipher: json['tlsCipher'] as String?,
    tlsSni: json['tlsSni'] as String?,
  );
}

class FlowDetail {
  final Map<String, dynamic> raw; // full JSON for metadata access
  final ConnectionInfo? connection;

  FlowDetail({required this.raw, this.connection});

  factory FlowDetail.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? json;
    return FlowDetail(
      raw: data,
      connection: data['connection'] != null
        ? ConnectionInfo.fromJson(data['connection'] as Map<String, dynamic>)
        : null,
    );
  }

  String get flowId => raw['flowId'] as String? ?? '';
  double? get connectAt => (raw['connectAt'] as num?)?.toDouble();
  double? get connectedAt => (raw['connectedAt'] as num?)?.toDouble();
  double? get tlsDoneAt => (raw['tlsDoneAt'] as num?)?.toDouble();
  double? get reqEndAt => (raw['reqEndAt'] as num?)?.toDouble();
  double? get rspStartAt => (raw['rspStartAt'] as num?)?.toDouble();
}
