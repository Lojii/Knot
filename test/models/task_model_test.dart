import 'package:flutter_test/flutter_test.dart';
import 'package:knot/models/task_model.dart';

void main() {
  group('TaskModel', () {
    test('fromJson parses all fields correctly', () {
      final json = {
        'id': 42,
        'name': 'Capture Session',
        'createdAt': 1711234567.123,
        'startedAt': 1711234568.0,
        'stoppedAt': 1711234999.0,
        'status': 2,
        'flowCount': 150,
        'uploadBytes': 1024,
        'downloadBytes': 2048,
      };
      final task = TaskModel.fromJson(json);

      expect(task.id, 42);
      expect(task.name, 'Capture Session');
      expect(task.createdAt, 1711234567.123);
      expect(task.startedAt, 1711234568.0);
      expect(task.stoppedAt, 1711234999.0);
      expect(task.status, 2);
      expect(task.flowCount, 150);
      expect(task.uploadBytes, 1024);
      expect(task.downloadBytes, 2048);
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'id': 1,
        'name': 'Minimal',
        'createdAt': 1000.0,
      };
      final task = TaskModel.fromJson(json);

      expect(task.id, 1);
      expect(task.name, 'Minimal');
      expect(task.createdAt, 1000.0);
      expect(task.startedAt, isNull);
      expect(task.stoppedAt, isNull);
      expect(task.status, 0); // default
      expect(task.flowCount, isNull);
      expect(task.uploadBytes, isNull);
      expect(task.downloadBytes, isNull);
    });

    test('fromJson handles null name gracefully', () {
      final json = {
        'id': 2,
        'name': null,
        'createdAt': 500.0,
      };
      final task = TaskModel.fromJson(json);

      expect(task.name, ''); // null coalesces to ''
    });

    test('fromJson handles null status gracefully', () {
      final json = {
        'id': 3,
        'name': 'Test',
        'createdAt': 100.0,
        'status': null,
      };
      final task = TaskModel.fromJson(json);

      expect(task.status, 0); // null coalesces to 0
    });

    test('fromJson accepts int createdAt via num cast', () {
      final json = {
        'id': 4,
        'name': 'IntTime',
        'createdAt': 1000, // int, not double
      };
      final task = TaskModel.fromJson(json);

      expect(task.createdAt, 1000.0);
    });

    test('fromJson accepts int startedAt/stoppedAt via num cast', () {
      final json = {
        'id': 5,
        'name': 'IntTimes',
        'createdAt': 100,
        'startedAt': 200,
        'stoppedAt': 300,
      };
      final task = TaskModel.fromJson(json);

      expect(task.startedAt, 200.0);
      expect(task.stoppedAt, 300.0);
    });
  });
}
