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

/// The view of HTTP/2 settings at any given time is a combination of initial values and acknowledged
/// updates sent via SETTINGS frames. This requires a structure to keep track of this holistic view of
/// the current settings.
///
/// This specific requirement makes this structure a useful place to keep track of pending SETTINGS ACKs
/// from remote peers.
struct HTTP2SettingsState {
    /// The current value of the HTTP/2 settings.
    private var currentSettingsValues: [HTTP2SettingsParameter: UInt32]

    /// An array of unacknowledged SETTINGS frames. These settings will be applied
    /// when the SETTINGS frame is acknowledged.
    private var unacknowlegedSettingsFrames: [HTTP2Settings]

    /// A callback that is invoked whenever a setting value has changed.
    typealias OnValueChangeCallback = (_ setting: HTTP2SettingsParameter, _ oldValue: UInt32?, _ newValue: UInt32) throws -> Void

    init(localState: Bool) {
        // Create the settings dictionary, and ensure it has space for the known SETTINGS values.
        self.currentSettingsValues = [.headerTableSize: 4096, .enablePush: 1, .initialWindowSize: HTTP2SettingsState.defaultInitialWindowSize, .maxFrameSize: 1<<14]
        self.currentSettingsValues.reserveCapacity(8)

        // Create space for the unacknowledged SETTINGS frame data to be stored. In general this will be empty,
        // and the vastly most-common case is to have only one entry here. Additionally, the settings state
        // for the remote peer should never have an un-ACKed SETTINGS frame, as we auto-ACK all SETTINGS.
        // As a result, we never reserve more than 1 entry. Users that emit multiple SETTINGS frames without
        // acknowledgement will incur some memory management overhead.
        self.unacknowlegedSettingsFrames = Array()
        if localState {
            self.unacknowlegedSettingsFrames.reserveCapacity(1)
        }
    }

    /// Creates an empty state, suitable for use as a dummy value when trying to avoid CoW operations.
    private init() {
        self.currentSettingsValues = [:]
        self.unacknowlegedSettingsFrames = []
    }

    /// Obtain the current value of a settings parameter.
    subscript(_ parameter: HTTP2SettingsParameter) -> UInt32? {
        get {
            return self.currentSettingsValues[parameter]
        }
    }

    /// The current value of SETTINGS_INITIAL_WINDOW_SIZE.
    var initialWindowSize: UInt32 {
        // We can force-unwrap here as this setting always has a value.
        return self[.initialWindowSize]!
    }

    /// The current value of SETTINGS_ENABLE_PUSH.
    var enablePush: UInt32 {
        // We can force-unwrap here as this setting always has a value.
        return self[.enablePush]!
    }

    /// The default value of SETTINGS_INITIAL_WINDOW_SIZE.
    static let defaultInitialWindowSize: UInt32 = 65535

    /// Called when SETTINGS are about to be emitted to the network.
    ///
    /// This function assumes that settings have been validated by the state machine.
    ///
    /// - parameters:
    ///     - settings: The settings to emit.
    mutating func emitSettings(_ settings: HTTP2Settings) {
        self.unacknowlegedSettingsFrames.append(settings)
    }

    /// Called when a SETTINGS ACK has been received.
    ///
    /// This applies the pending SETTINGS values. If there are no pending SETTINGS values, this will throw.
    ///
    /// - parameters:
    ///     - onValueChange: A callback that will be invoked once for each setting change.
    mutating func receiveSettingsAck(onValueChange: OnValueChangeCallback) throws {
        guard self.unacknowlegedSettingsFrames.count > 0 else {
            throw NIOHTTP2Errors.ReceivedBadSettings()
        }

        try self.applySettings(self.unacknowlegedSettingsFrames.removeFirst(), onValueChange: onValueChange)
    }

    /// Called when a SETTINGS frame has been received from the network.
    ///
    /// This function assumes that settings have been validated by the state machine.
    ///
    /// We auto-ACK all SETTINGS, so this applies the settings immediately.
    ///
    /// - parameters:
    ///     - settings: The received settings.
    ///     - onValueChange: A callback that will be invoked once for each setting change.
    mutating func receiveSettings(_ settings: HTTP2Settings, onValueChange: OnValueChangeCallback) rethrows {
        return try self.applySettings(settings, onValueChange: onValueChange)
    }

    /// Applies the given HTTP/2 settings to this state.
    ///
    /// This function assumes that settings have been validated by the state machine.
    ///
    /// - parameters:
    ///     - settings: The settings to apply.
    ///     - onValueChange: A callback that will be invoked once for each setting change.
    private mutating func applySettings(_ settings: HTTP2Settings, onValueChange: OnValueChangeCallback) rethrows {
        for setting in settings {
            let oldValue = self.currentSettingsValues.updateValue(setting._value, forKey: setting.parameter)
            try onValueChange(setting.parameter, oldValue, setting._value)
        }
    }

    /// Obtain an empty dummy value, suitable for using as a temporary to avoid CoW operations.
    static func dummyValue() -> HTTP2SettingsState {
        return HTTP2SettingsState()
    }
}
