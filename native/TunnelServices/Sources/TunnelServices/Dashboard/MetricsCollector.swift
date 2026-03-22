//
//  MetricsCollector.swift
//  TunnelServices
//
//  Collects system metrics (RSS, CPU, thread count, pool stats).
//  Safe to call from a background DispatchQueue — NOT on NIO EventLoop
//  because the underlying mach syscalls may block.
//

import Foundation

public struct SystemMetrics {
    public let rssMB: Double
    public let rssBytes: Int64
    public let cpuPercent: Double
    public let threadCount: Int
    public let poolTotal: Int
    public let poolBreakdown: [(key: String, count: Int)]
    public let mitmFailedHosts: Int
    public let uptimeSeconds: Double
}

public enum MetricsCollector {

    /// Collect all metrics. Call from a background queue, not an EventLoop.
    public static func collect(task: CaptureTask, startTime: TimeInterval) -> SystemMetrics {
        let rss = currentRSS()
        let (cpu, threads) = currentCPUUsage()

        return SystemMetrics(
            rssMB: Double(rss) / 1_048_576,
            rssBytes: rss,
            cpuPercent: cpu,
            threadCount: threads,
            poolTotal: task.connectionPool.count,
            poolBreakdown: task.connectionPool.perKeyBreakdown(),
            mitmFailedHosts: task.mitmFailedHosts.count,
            uptimeSeconds: Date().timeIntervalSince1970 - startTime
        )
    }

    // MARK: - Private helpers

    static func currentRSS() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }

    static func currentCPUUsage() -> (percent: Double, threads: Int) {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        let kr = task_threads(mach_task_self_, &threadList, &threadCount)
        guard kr == KERN_SUCCESS, let threads = threadList else { return (0, 0) }

        var totalCPU: Double = 0
        for i in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var infoCount = mach_msg_type_number_t(
                MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<natural_t>.size
            )
            _ = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &infoCount)
                }
            }
            if info.flags & TH_FLAGS_IDLE == 0 {
                totalCPU += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100
            }
        }
        vm_deallocate(
            mach_task_self_,
            vm_address_t(bitPattern: threads),
            vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_t>.size)
        )
        return (totalCPU, Int(threadCount))
    }
}
