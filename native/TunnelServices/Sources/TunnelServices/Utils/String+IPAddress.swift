//
//  String+IPAddress.swift
//  TunnelServices
//
//  IP address detection extension.
//

import Foundation

extension String {
    func isIPAddress() -> Bool {
        var ipv4Addr = in_addr()
        var ipv6Addr = in6_addr()
        return self.withCString { ptr in
            inet_pton(AF_INET, ptr, &ipv4Addr) == 1 ||
            inet_pton(AF_INET6, ptr, &ipv6Addr) == 1
        }
    }
}
