//
//  ProxyServer.swift
//  TunnelServices
//
//  Clean server bootstrap and lifecycle management.
//  Replaces the bootstrap configuration in MitmService.
//

import Foundation
import NIO

public class ProxyServer {

    private let masterGroup: MultiThreadedEventLoopGroup
    private let workerGroup: MultiThreadedEventLoopGroup
    private var localChannel: Channel?
    private var wifiChannel: Channel?

    public init(
        masterThreads: Int = System.coreCount,
        workerThreads: Int = System.coreCount * 3
    ) {
        self.masterGroup = MultiThreadedEventLoopGroup(numberOfThreads: masterThreads)
        self.workerGroup = MultiThreadedEventLoopGroup(numberOfThreads: workerThreads)
    }

    // MARK: - Server Lifecycle

    public func start(task: CaptureTask, callback: @escaping (Result<Void, Error>) -> Void) {
        task.startTime = Date().timeIntervalSince1970
        task.createFileFolder()
        task.numberOfUse = task.numberOfUse + 1
        try? task.update()

        if task.localEnable == 1 {
            DispatchQueue.global().async {
                self.startServer(
                    host: task.localIP,
                    port: task.localPort,
                    task: task,
                    isWifi: false
                ) { result in
                    switch result {
                    case .success:
                        callback(.success(()))
                    case .failure(let error):
                        callback(.failure(error))
                    }
                }
            }
        }

        if task.wifiEnable == 1, task.wifiIP != "" {
            DispatchQueue.global().async {
                self.startServer(
                    host: task.wifiIP,
                    port: task.wifiPort,
                    task: task,
                    isWifi: true
                ) { _ in }
            }
        }
    }

    private func startServer(
        host: String,
        port: Int,
        task: CaptureTask,
        isWifi: Bool,
        callback: @escaping (Result<Void, Error>) -> Void
    ) {
        let bootstrap = ServerBootstrap(group: masterGroup, childGroup: workerGroup)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelInitializer { channel in
                let recorder = SessionRecorder(task: task)
                let tcpChildren = ProtocolRegistry.shared.tcpChildren
                return channel.pipeline.addHandler(
                    ProtocolDispatcher(task: task, nodes: tcpChildren, recorder: recorder),
                    name: "dispatcher", position: .first
                )
            }
            .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
            .childChannelOption(ChannelOptions.allowRemoteHalfClosure, value: false)
            .childChannelOption(ChannelOptions.connectTimeout, value: TimeAmount.seconds(ProxyConfig.SSL.connectTimeout))

        guard let channel = try? bootstrap.bind(host: host, port: port).wait() else {
            let errorMsg = "\(isWifi ? "Wifi" : "Local") Address was unable to bind. \(host):\(port)"
            AxLogger.log(errorMsg, level: .Error)
            if isWifi {
                task.wifiState = -1
            } else {
                task.localState = -1
                task.note = task.note + errorMsg
            }
            try? task.update()
            callback(.failure(ServerChannelError(errCode: -1, localizedDescription: errorMsg)))
            return
        }

        if isWifi {
            wifiChannel = channel
            task.wifiState = 1
        } else {
            localChannel = channel
            task.localState = 1
        }
        try? task.update()

        AxLogger.log("\(isWifi ? "Wifi" : "Local") Server started on \(channel.localAddress?.description ?? "unknown")", level: .Info)
        callback(.success(()))

        // Block until channel closes
        try? channel.closeFuture.wait()

        if isWifi {
            task.wifiState = 0
        } else {
            task.localState = 0
        }
        try? task.update()
    }

    // MARK: - Shutdown

    public func stop(completionHandler: (() -> Void)? = nil) {
        localChannel?.close(mode: .input, promise: nil)
        wifiChannel?.close(mode: .input, promise: nil)

        masterGroup.shutdownGracefully { error in
            if let e = error {
                AxLogger.log("master shutdown error: \(e)", level: .Error)
            }
        }
        workerGroup.shutdownGracefully { error in
            if let e = error {
                AxLogger.log("worker shutdown error: \(e)", level: .Error)
            }
        }

        completionHandler?()
    }

    public func stopWifi() {
        wifiChannel?.close(mode: .input, promise: nil)
        wifiChannel = nil
    }
}
