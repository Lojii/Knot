//
//  AppGroupIPC.swift
//  TunnelServices
//
//  Lightweight IPC replacement for MMWormhole using UserDefaults + Darwin notifications.
//  Supports communication between the main app and Network Extension via App Groups.
//

import Foundation

public class AppGroupIPC {
    private let groupIdentifier: String
    private let defaults: UserDefaults?
    private var listeners = [String: (Any?) -> Void]()

    public init(groupIdentifier: String) {
        self.groupIdentifier = groupIdentifier
        self.defaults = UserDefaults(suiteName: groupIdentifier)
    }

    deinit {
        listeners.keys.forEach { stopListening(identifier: $0) }
    }

    // MARK: - Send

    public func passMessage(_ message: Any?, identifier: String) {
        defaults?.set(message, forKey: "ipc_\(identifier)")
        defaults?.synchronize()
        notifyDarwin(identifier: identifier)
    }

    // MARK: - Listen

    public func listenForMessage(identifier: String, listener: @escaping (Any?) -> Void) {
        listeners[identifier] = listener
        let name = darwinNotificationName(for: identifier)
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { (_, observer, name, _, _) in
                guard let observer = observer else { return }
                let ipc = Unmanaged<AppGroupIPC>.fromOpaque(observer).takeUnretainedValue()
                if let cfName = name {
                    let nameStr = cfName.rawValue as String
                    let identifier = nameStr.components(separatedBy: ".ipc.").last ?? nameStr
                    if let callback = ipc.listeners[identifier] {
                        let value = ipc.defaults?.object(forKey: "ipc_\(identifier)")
                        callback(value)
                    }
                }
            },
            name as CFString,
            nil,
            .deliverImmediately
        )
    }

    public func stopListening(identifier: String) {
        listeners.removeValue(forKey: identifier)
        let name = darwinNotificationName(for: identifier)
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(rawValue: name as CFString),
            nil
        )
    }

    // MARK: - Private

    private func darwinNotificationName(for identifier: String) -> String {
        return "\(groupIdentifier).ipc.\(identifier)"
    }

    private func notifyDarwin(identifier: String) {
        let name = darwinNotificationName(for: identifier)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(rawValue: name as CFString),
            nil,
            nil,
            true
        )
    }
}
