import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:knot/api/api_client.dart';
import 'package:knot/controllers/dashboard_controller.dart';

void main() {
  late DashboardController controller;

  setUp(() {
    Get.testMode = true;
    final api = ApiClient(baseUrl: 'http://localhost:9999');
    controller = DashboardController(api);
  });

  tearDown(() => Get.reset());

  group('DashboardController - initial state', () {
    test('protocols is empty', () {
      expect(controller.protocols, isEmpty);
    });

    test('statuses is empty', () {
      expect(controller.statuses, isEmpty);
    });

    test('totalUpload is 0', () {
      expect(controller.totalUpload.value, 0);
    });

    test('totalDownload is 0', () {
      expect(controller.totalDownload.value, 0);
    });

    test('rssMB is 0.0', () {
      expect(controller.rssMB.value, 0.0);
    });

    test('cpuPercent is 0.0', () {
      expect(controller.cpuPercent.value, 0.0);
    });

    test('threadCount is 0', () {
      expect(controller.threadCount.value, 0);
    });

    test('poolTotal is 0', () {
      expect(controller.poolTotal.value, 0);
    });

    test('uptimeSeconds is 0.0', () {
      expect(controller.uptimeSeconds.value, 0.0);
    });

    test('trafficHistory is empty', () {
      expect(controller.trafficHistory, isEmpty);
    });
  });

  group('DashboardController - updateFromMetrics', () {
    test('updates memory metrics', () {
      controller.updateFromMetrics({
        'memory': {'rss_mb': 256.5},
      });

      expect(controller.rssMB.value, 256.5);
    });

    test('updates cpu metrics', () {
      controller.updateFromMetrics({
        'cpu': {'usage_percent': 45.2, 'thread_count': 8},
      });

      expect(controller.cpuPercent.value, 45.2);
      expect(controller.threadCount.value, 8);
    });

    test('updates connection metrics', () {
      controller.updateFromMetrics({
        'connections': {'pool_total': 25},
      });

      expect(controller.poolTotal.value, 25);
    });

    test('updates uptime from totals', () {
      controller.updateFromMetrics({
        'totals': {'uptime_s': 3600.5},
      });

      expect(controller.uptimeSeconds.value, 3600.5);
    });

    test('handles all metrics at once', () {
      controller.updateFromMetrics({
        'memory': {'rss_mb': 128.0},
        'cpu': {'usage_percent': 12.0, 'thread_count': 4},
        'connections': {'pool_total': 10},
        'totals': {'uptime_s': 100.0},
      });

      expect(controller.rssMB.value, 128.0);
      expect(controller.cpuPercent.value, 12.0);
      expect(controller.threadCount.value, 4);
      expect(controller.poolTotal.value, 10);
      expect(controller.uptimeSeconds.value, 100.0);
    });

    test('handles empty metrics data', () {
      controller.updateFromMetrics({});

      expect(controller.rssMB.value, 0.0);
      expect(controller.cpuPercent.value, 0.0);
    });

    test('handles null values within nested maps', () {
      controller.updateFromMetrics({
        'memory': {'rss_mb': null},
        'cpu': {'usage_percent': null, 'thread_count': null},
        'connections': {'pool_total': null},
        'totals': {'uptime_s': null},
      });

      expect(controller.rssMB.value, 0.0);
      expect(controller.cpuPercent.value, 0.0);
      expect(controller.threadCount.value, 0);
      expect(controller.poolTotal.value, 0);
      expect(controller.uptimeSeconds.value, 0.0);
    });

    test('handles int values via num cast', () {
      controller.updateFromMetrics({
        'memory': {'rss_mb': 100}, // int, not double
        'cpu': {'usage_percent': 50, 'thread_count': 4},
        'totals': {'uptime_s': 3600},
      });

      expect(controller.rssMB.value, 100.0);
      expect(controller.cpuPercent.value, 50.0);
      expect(controller.uptimeSeconds.value, 3600.0);
    });
  });

  group('DashboardController - addTrafficPoint', () {
    test('adds a traffic point', () {
      controller.addTrafficPoint(1024);

      expect(controller.trafficHistory.length, 1);
      expect(controller.trafficHistory[0].bytes, 1024);
      expect(controller.trafficHistory[0].time, isPositive);
    });

    test('adds multiple traffic points', () {
      controller.addTrafficPoint(100);
      controller.addTrafficPoint(200);
      controller.addTrafficPoint(300);

      expect(controller.trafficHistory.length, 3);
      expect(controller.trafficHistory[0].bytes, 100);
      expect(controller.trafficHistory[2].bytes, 300);
    });

    test('limits history to 60 points', () {
      for (var i = 0; i < 70; i++) {
        controller.addTrafficPoint(i * 10);
      }

      expect(controller.trafficHistory.length, 60);
      // First 10 should have been evicted; first remaining is index 10
      expect(controller.trafficHistory[0].bytes, 100); // i=10 => 100
    });

    test('time is monotonically increasing', () {
      controller.addTrafficPoint(10);
      controller.addTrafficPoint(20);

      expect(controller.trafficHistory[1].time,
          greaterThanOrEqualTo(controller.trafficHistory[0].time));
    });
  });
}
