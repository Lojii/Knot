class TaskModel {
  final int id;
  final String name;
  final double createdAt;
  final double? startedAt;
  final double? stoppedAt;
  final int status;
  final int? flowCount;
  final int? uploadBytes;
  final int? downloadBytes;

  TaskModel({
    required this.id,
    required this.name,
    required this.createdAt,
    this.startedAt,
    this.stoppedAt,
    this.status = 0,
    this.flowCount,
    this.uploadBytes,
    this.downloadBytes,
  });

  factory TaskModel.fromJson(Map<String, dynamic> json) => TaskModel(
    id: json['id'] as int,
    name: (json['name'] as String?) ?? '',
    createdAt: (json['createdAt'] as num).toDouble(),
    startedAt: (json['startedAt'] as num?)?.toDouble(),
    stoppedAt: (json['stoppedAt'] as num?)?.toDouble(),
    status: (json['status'] as int?) ?? 0,
    flowCount: json['flowCount'] as int?,
    uploadBytes: json['uploadBytes'] as int?,
    downloadBytes: json['downloadBytes'] as int?,
  );
}
