//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

/// A collection of HTTP/2 settings.
///
/// This is a typealias because we may change this into a custom structure at some stage.
public typealias HTTP2Settings = [HTTP2Setting]

/// A HTTP/2 settings parameter that allows representing both known and unknown HTTP/2
/// settings parameters.
public struct HTTP2SettingsParameter {
    internal let networkRepresentation: UInt16

    /// Create a `HTTP2SettingsParameter` that is not known to NIO.
    ///
    /// If this is a known parameter, use one of the static values.
    public init(extensionSetting: Int) {
        self.networkRepresentation = UInt16(extensionSetting)
    }

    /// Initialize a `HTTP2SettingsParameter` from nghttp2's representation.
    internal init(fromNetwork value: Int32) {
        self.networkRepresentation = UInt16(value)
    }
    
    /// Initialize a `HTTP2SettingsParameter` from a network `UInt16`.
    internal init(fromPayload value: UInt16) {
        self.networkRepresentation = value
    }

    /// A helper to initialize the static parameters.
    private init(_ value: UInt16) {
        self.networkRepresentation = value
    }

    /// Corresponds to SETTINGS_HEADER_TABLE_SIZE
    public static let headerTableSize = HTTP2SettingsParameter(1)

    /// Corresponds to SETTINGS_ENABLE_PUSH.
    public static let enablePush = HTTP2SettingsParameter(2)

    /// Corresponds to SETTINGS_MAX_CONCURRENT_STREAMS
    public static let maxConcurrentStreams = HTTP2SettingsParameter(3)

    /// Corresponds to SETTINGS_INITIAL_WINDOW_SIZE
    public static let initialWindowSize = HTTP2SettingsParameter(4)

    /// Corresponds to SETTINGS_MAX_FRAME_SIZE
    public static let maxFrameSize = HTTP2SettingsParameter(5)

    /// Corresponds to SETTINGS_MAX_HEADER_LIST_SIZE
    public static let maxHeaderListSize = HTTP2SettingsParameter(6)
    
    /// Corresponds to SETTINGS_ENABLE_CONNECT_PROTOCOL from RFC 8441.
    public static let enableConnectProtocol = HTTP2SettingsParameter(8)
}

extension HTTP2SettingsParameter: Equatable { }

extension HTTP2SettingsParameter: Hashable { }

/// A single setting for HTTP/2, a combination of a `HTTP2SettingsParameter` and its value.
public struct HTTP2Setting {
    /// The settings parameter for this setting.
    public var parameter: HTTP2SettingsParameter

    /// The value of the settings parameter. This must be a 32-bit number.
    public var value: Int {
        get {
            return Int(self._value)
        }
        set {
            self._value = UInt32(newValue)
        }
    }

    /// The value of the setting. Swift doesn't like using explicitly-sized integers in general,
    /// so we use this as an internal implementation detail and expose it via a computed Int
    /// property.
    internal var _value: UInt32

    /// Create a new `HTTP2Setting`.
    public init(parameter: HTTP2SettingsParameter, value: Int) {
        self.parameter = parameter
        self._value = UInt32(value)
    }
}

extension HTTP2Setting: Equatable {
    public static func ==(lhs: HTTP2Setting, rhs: HTTP2Setting) -> Bool {
        return lhs.parameter == rhs.parameter && lhs._value == rhs._value
    }
}
