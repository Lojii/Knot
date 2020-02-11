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

/// A protocol implemented by HTTP/2 connection state machine states with local settings.
///
/// This protocol provides implementations that can apply changes to the local settings.
protocol HasLocalSettings {
    var role: HTTP2ConnectionStateMachine.ConnectionRole { get }

    var localSettings: HTTP2SettingsState { get set }

    var streamState: ConnectionStreamState { get set }

    var inboundFlowControlWindow: HTTP2FlowControlWindow { get set }
}

extension HasLocalSettings {
    mutating func receiveSettingsAck(frameEncoder: inout HTTP2FrameEncoder) -> StateMachineResultWithEffect {
        // We do a little switcheroo here to avoid problems with overlapping accesses to
        // self. It's a little more complex than normal because HTTP2SettingsState has
        // two CoWable objects, and we don't want to CoW either of them, so we shove a dummy
        // value in `self` to avoid that.
        var temporarySettings = HTTP2SettingsState.dummyValue()
        swap(&temporarySettings, &self.localSettings)
        defer {
            swap(&temporarySettings, &self.localSettings)
        }

        var effect = NIOHTTP2ConnectionStateChange.LocalSettingsChanged()

        do {
            try temporarySettings.receiveSettingsAck { (setting, originalValue, newValue) in
                switch setting {
                case .maxConcurrentStreams:
                    if self.role == .client {
                        self.streamState.maxServerInitiatedStreams = newValue
                    } else {
                        self.streamState.maxClientInitiatedStreams = newValue
                    }
                case .headerTableSize:
                    frameEncoder.headerEncoder.maximumDynamicTableSize = Int(newValue)
                case .initialWindowSize:
                    // We default the value of SETTINGS_INITIAL_WINDOW_SIZE, so originalValue mustn't be nil.
                    // The max value of SETTINGS_INITIAL_WINDOW_SIZE is Int32.max, so we can safely fit it into that here.
                    let delta = Int32(newValue) - Int32(originalValue!)

                    try self.streamState.forAllStreams {
                        try $0.localInitialWindowSizeChanged(by: delta)
                    }

                    // We do a += here because the value may change multiple times in one settings block. This way, we correctly
                    // respect that possibility.
                    effect.streamWindowSizeChange += Int(delta)
                case .maxFrameSize:
                    effect.newMaxFrameSize = newValue
                case .maxHeaderListSize:
                    effect.newMaxHeaderListSize = newValue
                default:
                    // No operation required
                    return
                }
            }
            return .init(result: .succeed, effect: .localSettingsChanged(effect))
        } catch {
            return .init(result: .connectionError(underlyingError: error, type: .protocolError), effect: nil)
        }
    }
}
