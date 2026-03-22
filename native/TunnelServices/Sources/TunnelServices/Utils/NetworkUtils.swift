//
//  NetworkUtils.swift
//  TunnelServices
//
//  Utility methods previously on Session, now standalone.
//

import Foundation
import NIO
import NIOHTTP1

public enum NetworkUtils {

    public static func getIPAddress(socketAddress: SocketAddress?) -> String {
        if let address = socketAddress?.description {
            let array = address.components(separatedBy: "/")
            return array.last ?? address
        } else {
            return "unknow"
        }
    }

    public static func getUserAgent(target: String?) -> String {
        if target != nil {
            let firstTarget = target!.components(separatedBy: " ").first
            return firstTarget?.components(separatedBy: "/").first ?? target!
        }
        return ""
    }

    public static func getHeadsJson(headers: HTTPHeaders) -> String {
        var reqHeads = [String: String]()
        for kv in headers {
            reqHeads[kv.name] = kv.value
        }
        return reqHeads.toJson()
    }
}
