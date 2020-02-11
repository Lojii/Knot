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
import NIO
import NIOHPACK

/// A state machine that governs the connection-level state of a HTTP/2 connection.
///
/// ### Overview
///
/// A HTTP/2 protocol implementation is fundamentally built on a pair of interlocking state machines:
/// one for the connection as a whole, and then one for each stream on the connection. All frames sent
/// and received on a HTTP/2 connection cause state transitions in either or both of these state
/// machines, and the set of valid state transitions in these state machines forms the complete set of
/// valid frame sequences in HTTP/2.
///
/// Not all frames need to pass through both state machines. As a general heuristic, if a frame carries a
/// stream ID field, it must pass through both the connection state machine and the stream state machine for
/// the associated stream. If it does not, then it must only pass through the connection state machine. This
/// is not a *complete* description of the way the connection behaves (see the note about PRIORITY frames
/// below), but it's a good enough operating heuristic to get through the rest of the code.
///
/// The stream state machine is handled by `HTTP2StreamStateMachine`.
///
/// ### Function
///
/// The responsibilities of this state machine are as follows:
///
/// 1) Manage the connection setup process, ensuring that the approriate client/server preamble is sent and
///     received.
/// 2) Manage the inbound and outbound connection flow control windows.
/// 3) Keep track of the bi-directional values of HTTP/2 settings.
/// 4) Manage connection cleanup, shutdown, and quiescing.
///
/// ### Implementation
///
/// All state associated with a HTTP/2 connection lives inside a single Swift enum. This enum constrains when
/// state is available, ensuring that it is not possible to query data that is not meaningful in the given state.
/// Operations on this state machine occur by calling specific functions on the structure, which will spin the
/// enum as needed and perform whatever state transitions are required.
///
/// #### PRIORITY frames
///
/// A brief digression is required on HTTP/2 PRIORITY frames. These frames appear to be sent "on" a specific
/// stream, as they carry a stream ID like all other stream-specific frames. However, unlike all other stream
/// specific frames they can be sent for streams in *any* state (including idle and fullyQuiesced, meaning they can
/// be sent for streams that have never existed or that passed away long ago), and have no effect on the stream
/// state (causing no state transitions). They only ever affect the priority tree, which neither this object nor
/// any of the streams actually maintains.
///
/// For this reason, PRIORITY frames do not actually participate in the stream state machine: only the
/// connection one. This is unlike all other frames that carry stream IDs. Essentially, they are connection-scoped
/// frames that just incidentally have a stream ID on them, rather than stream-scoped frames like all the others.
struct HTTP2ConnectionStateMachine {
    /// The state required for a connection that is currently idle.
    fileprivate struct IdleConnectionState: ConnectionStateWithRole, ConnectionStateWithConfiguration {
        let role: ConnectionRole
        var headerBlockValidation: ValidationState
        var contentLengthValidation: ValidationState
    }

    /// The state required for a connection that has sent a connection preface.
    fileprivate struct PrefaceSentState: ConnectionStateWithRole, ConnectionStateWithConfiguration, MaySendFrames, HasLocalSettings, HasFlowControlWindows {
        let role: ConnectionRole
        var headerBlockValidation: ValidationState
        var contentLengthValidation: ValidationState
        var localSettings: HTTP2SettingsState
        var streamState: ConnectionStreamState
        var inboundFlowControlWindow: HTTP2FlowControlWindow
        var outboundFlowControlWindow: HTTP2FlowControlWindow

        var localInitialWindowSize: UInt32 {
            return HTTP2SettingsState.defaultInitialWindowSize
        }

        var remoteInitialWindowSize: UInt32 {
            return self.localSettings.initialWindowSize
        }

        init(fromIdle idleState: IdleConnectionState, localSettings settings: HTTP2SettingsState) {
            self.role = idleState.role
            self.headerBlockValidation = idleState.headerBlockValidation
            self.contentLengthValidation = idleState.contentLengthValidation
            self.localSettings = settings
            self.streamState = ConnectionStreamState()

            self.inboundFlowControlWindow = HTTP2FlowControlWindow(initialValue: settings.initialWindowSize)
            self.outboundFlowControlWindow = HTTP2FlowControlWindow(initialValue: HTTP2SettingsState.defaultInitialWindowSize)
        }
    }

    /// The state required for a connection that has received a connection preface.
    fileprivate struct PrefaceReceivedState: ConnectionStateWithRole, ConnectionStateWithConfiguration, MayReceiveFrames, HasRemoteSettings, HasFlowControlWindows {
        let role: ConnectionRole
        var headerBlockValidation: ValidationState
        var contentLengthValidation: ValidationState
        var remoteSettings: HTTP2SettingsState
        var streamState: ConnectionStreamState
        var inboundFlowControlWindow: HTTP2FlowControlWindow
        var outboundFlowControlWindow: HTTP2FlowControlWindow

        var localInitialWindowSize: UInt32 {
            return self.remoteSettings.initialWindowSize
        }

        var remoteInitialWindowSize: UInt32 {
            return HTTP2SettingsState.defaultInitialWindowSize
        }

        init(fromIdle idleState: IdleConnectionState, remoteSettings settings: HTTP2SettingsState) {
            self.role = idleState.role
            self.headerBlockValidation = idleState.headerBlockValidation
            self.contentLengthValidation = idleState.contentLengthValidation
            self.remoteSettings = settings
            self.streamState = ConnectionStreamState()

            self.inboundFlowControlWindow = HTTP2FlowControlWindow(initialValue: HTTP2SettingsState.defaultInitialWindowSize)
            self.outboundFlowControlWindow = HTTP2FlowControlWindow(initialValue: settings.initialWindowSize)
        }
    }

    /// The state required for a connection that is active.
    fileprivate struct ActiveConnectionState: ConnectionStateWithRole, ConnectionStateWithConfiguration, MaySendFrames, MayReceiveFrames, HasLocalSettings, HasRemoteSettings, HasFlowControlWindows {
        let role: ConnectionRole
        var headerBlockValidation: ValidationState
        var contentLengthValidation: ValidationState
        var localSettings: HTTP2SettingsState
        var remoteSettings: HTTP2SettingsState
        var streamState: ConnectionStreamState
        var inboundFlowControlWindow: HTTP2FlowControlWindow
        var outboundFlowControlWindow: HTTP2FlowControlWindow

        var localInitialWindowSize: UInt32 {
            return self.remoteSettings.initialWindowSize
        }

        var remoteInitialWindowSize: UInt32 {
            return self.localSettings.initialWindowSize
        }

        init(fromPrefaceReceived state: PrefaceReceivedState, localSettings settings: HTTP2SettingsState) {
            self.role = state.role
            self.headerBlockValidation = state.headerBlockValidation
            self.contentLengthValidation = state.contentLengthValidation
            self.remoteSettings = state.remoteSettings
            self.streamState = state.streamState
            self.localSettings = settings

            self.outboundFlowControlWindow = state.outboundFlowControlWindow
            self.inboundFlowControlWindow = state.inboundFlowControlWindow
        }

        init(fromPrefaceSent state: PrefaceSentState, remoteSettings settings: HTTP2SettingsState) {
            self.role = state.role
            self.headerBlockValidation = state.headerBlockValidation
            self.contentLengthValidation = state.contentLengthValidation
            self.localSettings = state.localSettings
            self.streamState = state.streamState
            self.remoteSettings = settings

            self.outboundFlowControlWindow = state.outboundFlowControlWindow
            self.inboundFlowControlWindow = state.inboundFlowControlWindow
        }
    }

    /// The state required for a connection that is quiescing, but where the local peer has not yet sent its
    /// preface.
    fileprivate struct QuiescingPrefaceReceivedState: ConnectionStateWithRole, ConnectionStateWithConfiguration, RemotelyQuiescingState, MayReceiveFrames, HasRemoteSettings, QuiescingState, HasFlowControlWindows {
        let role: ConnectionRole
        var headerBlockValidation: ValidationState
        var contentLengthValidation: ValidationState
        var remoteSettings: HTTP2SettingsState
        var streamState: ConnectionStreamState
        var inboundFlowControlWindow: HTTP2FlowControlWindow
        var outboundFlowControlWindow: HTTP2FlowControlWindow

        var lastLocalStreamID: HTTP2StreamID

        var localInitialWindowSize: UInt32 {
            return self.remoteSettings.initialWindowSize
        }

        var remoteInitialWindowSize: UInt32 {
            return HTTP2SettingsState.defaultInitialWindowSize
        }

        var quiescedByServer: Bool {
            return self.role == .client
        }

        init(fromPrefaceReceived state: PrefaceReceivedState, lastStreamID: HTTP2StreamID) {
            self.role = state.role
            self.headerBlockValidation = state.headerBlockValidation
            self.contentLengthValidation = state.contentLengthValidation
            self.remoteSettings = state.remoteSettings
            self.streamState = state.streamState
            self.inboundFlowControlWindow = state.inboundFlowControlWindow
            self.outboundFlowControlWindow = state.outboundFlowControlWindow

            self.lastLocalStreamID = lastStreamID
        }
    }

    /// The state required for a connection that is quiescing, but where the remote peer has not yet sent its
    /// preface.
    fileprivate struct QuiescingPrefaceSentState: ConnectionStateWithRole, ConnectionStateWithConfiguration, LocallyQuiescingState, MaySendFrames, HasLocalSettings, QuiescingState, HasFlowControlWindows {
        let role: ConnectionRole
        var headerBlockValidation: ValidationState
        var contentLengthValidation: ValidationState
        var localSettings: HTTP2SettingsState
        var streamState: ConnectionStreamState
        var inboundFlowControlWindow: HTTP2FlowControlWindow
        var outboundFlowControlWindow: HTTP2FlowControlWindow

        var lastRemoteStreamID: HTTP2StreamID

        var localInitialWindowSize: UInt32 {
            return HTTP2SettingsState.defaultInitialWindowSize
        }

        var remoteInitialWindowSize: UInt32 {
            return self.localSettings.initialWindowSize
        }

        var quiescedByServer: Bool {
            return self.role == .server
        }

        init(fromPrefaceSent state: PrefaceSentState, lastStreamID: HTTP2StreamID) {
            self.role = state.role
            self.headerBlockValidation = state.headerBlockValidation
            self.contentLengthValidation = state.contentLengthValidation
            self.localSettings = state.localSettings
            self.streamState = state.streamState
            self.inboundFlowControlWindow = state.inboundFlowControlWindow
            self.outboundFlowControlWindow = state.outboundFlowControlWindow

            self.lastRemoteStreamID = lastStreamID
        }
    }

    /// The state required for a connection that is quiescing due to the remote peer quiescing the connection.
    fileprivate struct RemotelyQuiescedState: ConnectionStateWithRole, ConnectionStateWithConfiguration, RemotelyQuiescingState, MayReceiveFrames, MaySendFrames, HasLocalSettings, HasRemoteSettings, QuiescingState, HasFlowControlWindows {
        let role: ConnectionRole
        var headerBlockValidation: ValidationState
        var contentLengthValidation: ValidationState
        var localSettings: HTTP2SettingsState
        var remoteSettings: HTTP2SettingsState
        var streamState: ConnectionStreamState
        var inboundFlowControlWindow: HTTP2FlowControlWindow
        var outboundFlowControlWindow: HTTP2FlowControlWindow

        var lastLocalStreamID: HTTP2StreamID

        var localInitialWindowSize: UInt32 {
            return self.remoteSettings.initialWindowSize
        }

        var remoteInitialWindowSize: UInt32 {
            return self.localSettings.initialWindowSize
        }

        var quiescedByServer: Bool {
            return self.role == .client
        }

        init(fromActive state: ActiveConnectionState, lastLocalStreamID streamID: HTTP2StreamID) {
            self.role = state.role
            self.headerBlockValidation = state.headerBlockValidation
            self.contentLengthValidation = state.contentLengthValidation
            self.localSettings = state.localSettings
            self.remoteSettings = state.remoteSettings
            self.streamState = state.streamState
            self.inboundFlowControlWindow = state.inboundFlowControlWindow
            self.outboundFlowControlWindow = state.outboundFlowControlWindow
            self.lastLocalStreamID = streamID
        }

        init(fromQuiescingPrefaceReceived state: QuiescingPrefaceReceivedState, localSettings settings: HTTP2SettingsState) {
            self.role = state.role
            self.headerBlockValidation = state.headerBlockValidation
            self.contentLengthValidation = state.contentLengthValidation
            self.remoteSettings = state.remoteSettings
            self.localSettings = settings
            self.streamState = state.streamState
            self.inboundFlowControlWindow = state.inboundFlowControlWindow
            self.outboundFlowControlWindow = state.outboundFlowControlWindow
            self.lastLocalStreamID = state.lastLocalStreamID
        }
    }

    /// The state required for a connection that is quiescing due to the local user quiescing the connection.
    fileprivate struct LocallyQuiescedState: ConnectionStateWithRole, ConnectionStateWithConfiguration, LocallyQuiescingState, MaySendFrames, MayReceiveFrames, HasLocalSettings, HasRemoteSettings, QuiescingState, HasFlowControlWindows {
        let role: ConnectionRole
        var headerBlockValidation: ValidationState
        var contentLengthValidation: ValidationState
        var localSettings: HTTP2SettingsState
        var remoteSettings: HTTP2SettingsState
        var streamState: ConnectionStreamState
        var inboundFlowControlWindow: HTTP2FlowControlWindow
        var outboundFlowControlWindow: HTTP2FlowControlWindow

        var lastRemoteStreamID: HTTP2StreamID

        var localInitialWindowSize: UInt32 {
            return self.remoteSettings.initialWindowSize
        }

        var remoteInitialWindowSize: UInt32 {
            return self.localSettings.initialWindowSize
        }

        var quiescedByServer: Bool {
            return self.role == .server
        }

        init(fromActive state: ActiveConnectionState, lastRemoteStreamID streamID: HTTP2StreamID) {
            self.role = state.role
            self.headerBlockValidation = state.headerBlockValidation
            self.contentLengthValidation = state.contentLengthValidation
            self.localSettings = state.localSettings
            self.remoteSettings = state.remoteSettings
            self.streamState = state.streamState
            self.inboundFlowControlWindow = state.inboundFlowControlWindow
            self.outboundFlowControlWindow = state.outboundFlowControlWindow
            self.lastRemoteStreamID = streamID
        }

        init(fromQuiescingPrefaceSent state: QuiescingPrefaceSentState, remoteSettings settings: HTTP2SettingsState) {
            self.role = state.role
            self.headerBlockValidation = state.headerBlockValidation
            self.contentLengthValidation = state.contentLengthValidation
            self.localSettings = state.localSettings
            self.remoteSettings = settings
            self.streamState = state.streamState
            self.inboundFlowControlWindow = state.inboundFlowControlWindow
            self.outboundFlowControlWindow = state.outboundFlowControlWindow
            self.lastRemoteStreamID = state.lastRemoteStreamID
        }
    }

    /// The state required for a connection that is quiescing due to both peers sending GOAWAY.
    fileprivate struct BothQuiescingState: ConnectionStateWithRole, ConnectionStateWithConfiguration, LocallyQuiescingState, RemotelyQuiescingState, MaySendFrames, MayReceiveFrames, HasLocalSettings, HasRemoteSettings, QuiescingState, HasFlowControlWindows {
        let role: ConnectionRole
        var headerBlockValidation: ValidationState
        var contentLengthValidation: ValidationState
        var localSettings: HTTP2SettingsState
        var remoteSettings: HTTP2SettingsState
        var streamState: ConnectionStreamState
        var inboundFlowControlWindow: HTTP2FlowControlWindow
        var outboundFlowControlWindow: HTTP2FlowControlWindow
        var lastLocalStreamID: HTTP2StreamID
        var lastRemoteStreamID: HTTP2StreamID

        var localInitialWindowSize: UInt32 {
            return self.remoteSettings.initialWindowSize
        }

        var remoteInitialWindowSize: UInt32 {
            return self.localSettings.initialWindowSize
        }

        var quiescedByServer: Bool {
            return true
        }

        init(fromRemotelyQuiesced state: RemotelyQuiescedState, lastRemoteStreamID streamID: HTTP2StreamID) {
            self.role = state.role
            self.headerBlockValidation = state.headerBlockValidation
            self.contentLengthValidation = state.contentLengthValidation
            self.localSettings = state.localSettings
            self.remoteSettings = state.remoteSettings
            self.streamState = state.streamState
            self.inboundFlowControlWindow = state.inboundFlowControlWindow
            self.outboundFlowControlWindow = state.outboundFlowControlWindow
            self.lastLocalStreamID = state.lastLocalStreamID

            self.lastRemoteStreamID = streamID
        }

        init(fromLocallyQuiesced state: LocallyQuiescedState, lastLocalStreamID streamID: HTTP2StreamID) {
            self.role = state.role
            self.headerBlockValidation = state.headerBlockValidation
            self.contentLengthValidation = state.contentLengthValidation
            self.localSettings = state.localSettings
            self.remoteSettings = state.remoteSettings
            self.streamState = state.streamState
            self.inboundFlowControlWindow = state.inboundFlowControlWindow
            self.outboundFlowControlWindow = state.outboundFlowControlWindow
            self.lastRemoteStreamID = state.lastRemoteStreamID

            self.lastLocalStreamID = streamID
        }
    }

    /// The state required for a connection that has completely quiesced.
    fileprivate struct FullyQuiescedState: ConnectionStateWithRole, ConnectionStateWithConfiguration, LocallyQuiescingState, RemotelyQuiescingState, SendAndReceiveGoawayState {
        let role: ConnectionRole
        var headerBlockValidation: ValidationState
        var contentLengthValidation: ValidationState
        var streamState: ConnectionStreamState
        var lastLocalStreamID: HTTP2StreamID
        var lastRemoteStreamID: HTTP2StreamID

        init<PreviousState: LocallyQuiescingState & RemotelyQuiescingState & SendAndReceiveGoawayState & ConnectionStateWithRole & ConnectionStateWithConfiguration>(previousState: PreviousState) {
            self.role = previousState.role
            self.headerBlockValidation = previousState.headerBlockValidation
            self.contentLengthValidation = previousState.contentLengthValidation
            self.streamState = previousState.streamState
            self.lastLocalStreamID = previousState.lastLocalStreamID
            self.lastRemoteStreamID = previousState.lastRemoteStreamID
        }

        init<PreviousState: LocallyQuiescingState & SendAndReceiveGoawayState & ConnectionStateWithRole & ConnectionStateWithConfiguration>(previousState: PreviousState) {
            self.role = previousState.role
            self.headerBlockValidation = previousState.headerBlockValidation
            self.contentLengthValidation = previousState.contentLengthValidation
            self.streamState = previousState.streamState
            self.lastLocalStreamID = .maxID
            self.lastRemoteStreamID = previousState.lastRemoteStreamID
        }

        init<PreviousState: RemotelyQuiescingState & SendAndReceiveGoawayState & ConnectionStateWithRole & ConnectionStateWithConfiguration>(previousState: PreviousState) {
            self.role = previousState.role
            self.headerBlockValidation = previousState.headerBlockValidation
            self.contentLengthValidation = previousState.contentLengthValidation
            self.streamState = previousState.streamState
            self.lastLocalStreamID = previousState.lastLocalStreamID
            self.lastRemoteStreamID = .maxID
        }
    }

    fileprivate enum State {
        /// The connection has not begun yet. This state is usually used while the underlying transport connection
        /// is being established. No data can be sent or received at this time.
        case idle(IdleConnectionState)

        /// Our preface has been sent, and we are awaiting the preface from the remote peer. In general we're more
        /// likely to enter this state as a client than a server, but users may choose to reduce latency by
        /// aggressively emitting the server preface before the client preface has been received. In either case,
        /// in this state we are waiting for the remote peer to send its preface.
        case prefaceSent(PrefaceSentState)

        /// We have received a preface from the remote peer, and we are waiting to send our own preface. In general
        /// we're more likely to enter this state as a server than as a client, but remote peers may be attempting
        /// to reduce latency by aggressively emitting the server preface before they have received our preface.
        /// In either case, in this state we are waiting for the local user to emit the preface.
        case prefaceReceived(PrefaceReceivedState)

        /// Both peers have exchanged their preface and the connection is fully active. In this state new streams
        /// may be created, potentially by either peer, and the connection is fully useable.
        case active(ActiveConnectionState)

        /// The remote peer has sent a GOAWAY frame that quiesces the connection, preventing the creation of new
        /// streams. However, there are still active streams that have been allowed to complete, so the connection
        /// is not entirely inactive.
        case remotelyQuiesced(RemotelyQuiescedState)

        /// The local user has sent a GOAWAY frame that quiesces the connection, preventing the creation of new
        /// streams. However, there are still active streams that have been allowed to complete, so the connection
        /// is not entirely inactive.
        case locallyQuiesced(LocallyQuiescedState)

        /// Both peers have emitted a GOAWAY frame that quiesces the connection, preventing the creation of new
        /// streams. However, there are still active streams that have been allowed to complete, so the connection
        /// is not entirely inactive.
        case bothQuiescing(BothQuiescingState)

        /// We have sent our preface, and sent a GOAWAY, but we haven't received the remote preface yet.
        /// This is a weird state, unlikely to be encountered in most programs, but it's technically possible.
        case quiescingPrefaceSent(QuiescingPrefaceSentState)

        /// We have received a preface, and received a GOAWAY, but we haven't sent our preface yet.
        /// This is a weird state, unlikely to be encountered in most programs, but it's technically possible.
        case quiescingPrefaceReceived(QuiescingPrefaceReceivedState)

        /// The connection has completed, either cleanly or with an error. In this state, no further activity may
        /// occur on the connection.
        case fullyQuiesced(FullyQuiescedState)

        /// This is not a real state: it's used when we are in the middle of a function invocation, to avoid CoWs
        /// when modifying the associated data.
        case modifying
    }

    /// The possible roles an endpoint may play in a connection.
    enum ConnectionRole {
        case server
        case client
    }

    /// The state of a specific validation option.
    enum ValidationState {
        case enabled
        case disabled
    }

    private var state: State

    init(role: ConnectionRole, headerBlockValidation: ValidationState = .enabled, contentLengthValidation: ValidationState = .enabled) {
        self.state = .idle(.init(role: role, headerBlockValidation: headerBlockValidation, contentLengthValidation: contentLengthValidation))
    }

    /// Whether this connection is closed.
    var fullyQuiesced: Bool {
        switch self.state {
        case .fullyQuiesced:
            return true
        default:
            return false
        }
    }

    /// Whether the preamble can be sent.
    var mustSendPreamble: Bool {
        switch self.state {
        case .idle, .prefaceReceived, .quiescingPrefaceReceived:
            return true
        default:
            return false
        }
    }
}

// MARK:- State modifying methods
//
// These methods form the implementation of the public API of the HTTP2ConnectionStateMachine. Each of these methods
// performs a state transition, and can be used to validate that a specific action is acceptable on a connection in this state.
extension HTTP2ConnectionStateMachine {
    /// Called when a SETTINGS frame has been received from the remote peer
    mutating func receiveSettings(_ payload: HTTP2Frame.FramePayload.Settings, frameEncoder: inout HTTP2FrameEncoder, frameDecoder: inout HTTP2FrameDecoder) -> (StateMachineResultWithEffect, PostFrameOperation) {
        switch payload {
        case .ack:
            // No action is ever required after receiving a settings ACK
            return (self.receiveSettingsAck(frameEncoder: &frameEncoder), .nothing)
        case .settings(let settings):
            return self.receiveSettingsChange(settings, frameDecoder: &frameDecoder)
        }
    }

    /// Called when the user has sent a settings update.
    ///
    /// Note that this function assumes that this is not a settings ACK, as settings ACK frames are not
    /// allowed to be sent by the user. They are always emitted by the implementation.
    mutating func sendSettings(_ settings: HTTP2Settings) -> StateMachineResultWithEffect {
        let validationResult = self.validateSettings(settings)

        guard case .succeed = validationResult else {
            return .init(result: validationResult, effect: nil)
        }

        switch self.state {
        case .idle(let state):
            self.avoidingStateMachineCoW { newState in
                var settingsState = HTTP2SettingsState(localState: true)
                settingsState.emitSettings(settings)
                newState = .prefaceSent(.init(fromIdle: state, localSettings: settingsState))
            }

        case .prefaceReceived(let state):
            self.avoidingStateMachineCoW { newState in
                var settingsState = HTTP2SettingsState(localState: true)
                settingsState.emitSettings(settings)
                newState = .active(.init(fromPrefaceReceived: state, localSettings: settingsState))
            }

        case .prefaceSent(var state):
            self.avoidingStateMachineCoW { newState in
                state.localSettings.emitSettings(settings)
                newState = .prefaceSent(state)
            }

        case .active(var state):
            self.avoidingStateMachineCoW { newState in
                state.localSettings.emitSettings(settings)
                newState = .active(state)
            }

        case .quiescingPrefaceSent(var state):
            self.avoidingStateMachineCoW { newState in
                state.localSettings.emitSettings(settings)
                newState = .quiescingPrefaceSent(state)
            }

        case .quiescingPrefaceReceived(let state):
            self.avoidingStateMachineCoW { newState in
                var settingsState = HTTP2SettingsState(localState: true)
                settingsState.emitSettings(settings)
                newState = .remotelyQuiesced(.init(fromQuiescingPrefaceReceived: state, localSettings: settingsState))
            }

        case .remotelyQuiesced(var state):
            self.avoidingStateMachineCoW { newState in
                state.localSettings.emitSettings(settings)
                newState = .remotelyQuiesced(state)
            }

        case .locallyQuiesced(var state):
            self.avoidingStateMachineCoW { newState in
                state.localSettings.emitSettings(settings)
                newState = .locallyQuiesced(state)
            }

        case .bothQuiescing(var state):
            self.avoidingStateMachineCoW { newState in
                state.localSettings.emitSettings(settings)
                newState = .bothQuiescing(state)
            }

        case .fullyQuiesced:
            return .init(result: .connectionError(underlyingError: NIOHTTP2Errors.IOOnClosedConnection(), type: .protocolError), effect: nil)

        case .modifying:
            preconditionFailure("Must not be left in modifying state")
        }

        return .init(result: .succeed, effect: nil)
    }

    /// Called when a HEADERS frame has been received from the remote peer.
    mutating func receiveHeaders(streamID: HTTP2StreamID, headers: HPACKHeaders, isEndStreamSet endStream: Bool) -> StateMachineResultWithEffect {
        switch self.state {
        case .prefaceReceived(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveHeaders(streamID: streamID, headers: headers, isEndStreamSet: endStream)
                newState = .prefaceReceived(state)
                return result
            }

        case .active(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveHeaders(streamID: streamID, headers: headers, isEndStreamSet: endStream)
                newState = .active(state)
                return result
            }

        case .locallyQuiesced(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveHeaders(streamID: streamID, headers: headers, isEndStreamSet: endStream)
                newState = .locallyQuiesced(state)
                newState.closeIfNeeded(state)
                return result
            }

        case .remotelyQuiesced(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveHeaders(streamID: streamID, headers: headers, isEndStreamSet: endStream)
                newState = .remotelyQuiesced(state)
                newState.closeIfNeeded(state)
                return result
            }

        case .bothQuiescing(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveHeaders(streamID: streamID, headers: headers, isEndStreamSet: endStream)
                newState = .bothQuiescing(state)
                newState.closeIfNeeded(state)
                return result
            }

        case .quiescingPrefaceReceived(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveHeaders(streamID: streamID, headers: headers, isEndStreamSet: endStream)
                newState = .quiescingPrefaceReceived(state)
                return result
            }

        case .idle, .prefaceSent, .quiescingPrefaceSent:
            // If we're still waiting for the remote preface, they are not allowed to send us a HEADERS frame yet!
            return .init(result: .connectionError(underlyingError: NIOHTTP2Errors.MissingPreface(), type: .protocolError), effect: nil)

        case .fullyQuiesced:
            return .init(result: .connectionError(underlyingError: NIOHTTP2Errors.IOOnClosedConnection(), type: .protocolError), effect: nil)

        case .modifying:
            preconditionFailure("Must not be left in modifying state")
        }
    }

    // Called when a HEADERS frame has been sent by the local user.
    mutating func sendHeaders(streamID: HTTP2StreamID, headers: HPACKHeaders, isEndStreamSet endStream: Bool) -> StateMachineResultWithEffect {
        switch self.state {
        case .prefaceSent(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.sendHeaders(streamID: streamID, headers: headers, isEndStreamSet: endStream)
                newState = .prefaceSent(state)
                return result
            }

        case .active(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.sendHeaders(streamID: streamID, headers: headers, isEndStreamSet: endStream)
                newState = .active(state)
                return result
            }

        case .locallyQuiesced(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.sendHeaders(streamID: streamID, headers: headers, isEndStreamSet: endStream)
                newState = .locallyQuiesced(state)
                newState.closeIfNeeded(state)
                return result
            }

        case .remotelyQuiesced(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.sendHeaders(streamID: streamID, headers: headers, isEndStreamSet: endStream)
                newState = .remotelyQuiesced(state)
                newState.closeIfNeeded(state)
                return result
            }

        case .bothQuiescing(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.sendHeaders(streamID: streamID, headers: headers, isEndStreamSet: endStream)
                newState = .bothQuiescing(state)
                newState.closeIfNeeded(state)
                return result
            }

        case .quiescingPrefaceSent(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.sendHeaders(streamID: streamID, headers: headers, isEndStreamSet: endStream)
                newState = .quiescingPrefaceSent(state)
                return result
            }

        case .idle, .prefaceReceived, .quiescingPrefaceReceived:
            // If we're still waiting for the local preface, we are not allowed to send a HEADERS frame yet!
            return .init(result: .connectionError(underlyingError: NIOHTTP2Errors.MissingPreface(), type: .protocolError), effect: nil)

        case .fullyQuiesced:
            return .init(result: .connectionError(underlyingError: NIOHTTP2Errors.IOOnClosedConnection(), type: .protocolError), effect: nil)

        case .modifying:
            preconditionFailure("Must not be left in modifying state")
        }
    }

    /// Called when a DATA frame has been received.
    mutating func receiveData(streamID: HTTP2StreamID, contentLength: Int, flowControlledBytes: Int, isEndStreamSet endStream: Bool) -> StateMachineResultWithEffect {
        switch self.state {
        case .prefaceReceived(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveData(streamID: streamID, contentLength: contentLength, flowControlledBytes: flowControlledBytes, isEndStreamSet: endStream)
                newState = .prefaceReceived(state)
                return result
            }

        case .active(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveData(streamID: streamID, contentLength: contentLength, flowControlledBytes: flowControlledBytes, isEndStreamSet: endStream)
                newState = .active(state)
                return result
            }

        case .locallyQuiesced(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveData(streamID: streamID, contentLength: contentLength, flowControlledBytes: flowControlledBytes, isEndStreamSet: endStream)
                newState = .locallyQuiesced(state)
                newState.closeIfNeeded(state)
                return result
            }

        case .remotelyQuiesced(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveData(streamID: streamID, contentLength: contentLength, flowControlledBytes: flowControlledBytes, isEndStreamSet: endStream)
                newState = .remotelyQuiesced(state)
                newState.closeIfNeeded(state)
                return result
            }

        case .bothQuiescing(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveData(streamID: streamID, contentLength: contentLength, flowControlledBytes: flowControlledBytes, isEndStreamSet: endStream)
                newState = .bothQuiescing(state)
                newState.closeIfNeeded(state)
                return result
            }

        case .quiescingPrefaceReceived(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveData(streamID: streamID, contentLength: contentLength, flowControlledBytes: flowControlledBytes, isEndStreamSet: endStream)
                newState = .quiescingPrefaceReceived(state)
                return result
            }

        case .idle, .prefaceSent, .quiescingPrefaceSent:
            // If we're still waiting for the remote preface, we are not allowed to receive a DATA frame yet!
            return .init(result: .connectionError(underlyingError: NIOHTTP2Errors.MissingPreface(), type: .protocolError), effect: nil)

        case .fullyQuiesced:
            return .init(result: .connectionError(underlyingError: NIOHTTP2Errors.IOOnClosedConnection(), type: .protocolError), effect: nil)

        case .modifying:
            preconditionFailure("Must not be left in modifying state")
        }
    }

    /// Called when a user is trying to send a DATA frame.
    mutating func sendData(streamID: HTTP2StreamID, contentLength: Int, flowControlledBytes: Int, isEndStreamSet endStream: Bool) -> StateMachineResultWithEffect {
        switch self.state {
        case .prefaceSent(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.sendData(streamID: streamID, contentLength: contentLength, flowControlledBytes: flowControlledBytes, isEndStreamSet: endStream)
                newState = .prefaceSent(state)
                return result
            }

        case .active(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.sendData(streamID: streamID, contentLength: contentLength, flowControlledBytes: flowControlledBytes, isEndStreamSet: endStream)
                newState = .active(state)
                return result
            }

        case .locallyQuiesced(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.sendData(streamID: streamID, contentLength: contentLength, flowControlledBytes: flowControlledBytes, isEndStreamSet: endStream)
                newState = .locallyQuiesced(state)
                newState.closeIfNeeded(state)
                return result
            }

        case .remotelyQuiesced(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.sendData(streamID: streamID, contentLength: contentLength, flowControlledBytes: flowControlledBytes, isEndStreamSet: endStream)
                newState = .remotelyQuiesced(state)
                newState.closeIfNeeded(state)
                return result
            }

        case .bothQuiescing(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.sendData(streamID: streamID, contentLength: contentLength, flowControlledBytes: flowControlledBytes, isEndStreamSet: endStream)
                newState = .bothQuiescing(state)
                newState.closeIfNeeded(state)
                return result
            }

        case .quiescingPrefaceSent(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.sendData(streamID: streamID, contentLength: contentLength, flowControlledBytes: flowControlledBytes, isEndStreamSet: endStream)
                newState = .quiescingPrefaceSent(state)
                return result
            }

        case .idle, .prefaceReceived, .quiescingPrefaceReceived:
            // If we're still waiting for the local preface, we are not allowed to send a DATA frame yet!
            return .init(result: .connectionError(underlyingError: NIOHTTP2Errors.MissingPreface(), type: .protocolError), effect: nil)

        case .fullyQuiesced:
            return .init(result: .connectionError(underlyingError: NIOHTTP2Errors.IOOnClosedConnection(), type: .protocolError), effect: nil)

        case .modifying:
            preconditionFailure("Must not be left in modifying state")
        }
    }

    func receivePriority() -> StateMachineResultWithEffect {
        // So long as we've received the preamble and haven't fullyQuiesced, a PRIORITY frame is basically always
        // an acceptable thing to receive. The only rule is that it mustn't form a cycle in the priority
        // tree, but we don't maintain enough state in this object to enforce that.
        switch self.state {
        case .prefaceReceived, .active, .locallyQuiesced, .remotelyQuiesced, .bothQuiescing, .quiescingPrefaceReceived:
            return StateMachineResultWithEffect(result: .succeed, effect: nil)

        case .idle, .prefaceSent, .quiescingPrefaceSent:
            return StateMachineResultWithEffect(result: .connectionError(underlyingError: NIOHTTP2Errors.MissingPreface(), type: .protocolError), effect: nil)

        case .fullyQuiesced:
            return StateMachineResultWithEffect(result: .connectionError(underlyingError: NIOHTTP2Errors.IOOnClosedConnection(), type: .protocolError), effect: nil)

        case .modifying:
            preconditionFailure("Must not be left in modifying state")
        }
    }

    func sendPriority() -> StateMachineResultWithEffect {
        // So long as we've sent the preamble and haven't fullyQuiesced, a PRIORITY frame is basically always
        // an acceptable thing to send. The only rule is that it mustn't form a cycle in the priority
        // tree, but we don't maintain enough state in this object to enforce that.
        switch self.state {
        case .prefaceSent, .active, .locallyQuiesced, .remotelyQuiesced, .bothQuiescing, .quiescingPrefaceSent:
            return .init(result: .succeed, effect: nil)

        case .idle, .prefaceReceived, .quiescingPrefaceReceived:
            return .init(result: .connectionError(underlyingError: NIOHTTP2Errors.MissingPreface(), type: .protocolError), effect: nil)

        case .fullyQuiesced:
            return .init(result: .connectionError(underlyingError: NIOHTTP2Errors.IOOnClosedConnection(), type: .protocolError), effect: nil)

        case .modifying:
            preconditionFailure("Must not be left in modifying state")
        }
    }

    /// Called when a RST_STREAM frame has been received.
    mutating func receiveRstStream(streamID: HTTP2StreamID, reason: HTTP2ErrorCode) -> StateMachineResultWithEffect {
        switch self.state {
        case .prefaceReceived(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveRstStream(streamID: streamID, reason: reason)
                newState = .prefaceReceived(state)
                return result
            }

        case .active(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveRstStream(streamID: streamID, reason: reason)
                newState = .active(state)
                return result
            }

        case .locallyQuiesced(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveRstStream(streamID: streamID, reason: reason)
                newState = .locallyQuiesced(state)
                newState.closeIfNeeded(state)
                return result
            }

        case .remotelyQuiesced(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveRstStream(streamID: streamID, reason: reason)
                newState = .remotelyQuiesced(state)
                newState.closeIfNeeded(state)
                return result
            }

        case .bothQuiescing(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveRstStream(streamID: streamID, reason: reason)
                newState = .bothQuiescing(state)
                newState.closeIfNeeded(state)
                return result
            }

        case .quiescingPrefaceReceived(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveRstStream(streamID: streamID, reason: reason)
                newState = .quiescingPrefaceReceived(state)
                return result
            }

        case .idle, .prefaceSent, .quiescingPrefaceSent:
            // We're waiting for the remote preface.
            return .init(result: .connectionError(underlyingError: NIOHTTP2Errors.MissingPreface(), type: .protocolError), effect: nil)

        case .fullyQuiesced:
            return .init(result: .connectionError(underlyingError: NIOHTTP2Errors.IOOnClosedConnection(), type: .protocolError), effect: nil)

        case .modifying:
            preconditionFailure("Must not be left in modifying state")
        }
    }

    /// Called when sending a RST_STREAM frame.
    mutating func sendRstStream(streamID: HTTP2StreamID, reason: HTTP2ErrorCode) -> StateMachineResultWithEffect {
        switch self.state {
        case .prefaceSent(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.sendRstStream(streamID: streamID, reason: reason)
                newState = .prefaceSent(state)
                return result
            }

        case .active(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.sendRstStream(streamID: streamID, reason: reason)
                newState = .active(state)
                return result
            }

        case .locallyQuiesced(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.sendRstStream(streamID: streamID, reason: reason)
                newState = .locallyQuiesced(state)
                newState.closeIfNeeded(state)
                return result
            }

        case .remotelyQuiesced(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.sendRstStream(streamID: streamID, reason: reason)
                newState = .remotelyQuiesced(state)
                newState.closeIfNeeded(state)
                return result
            }

        case .bothQuiescing(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.sendRstStream(streamID: streamID, reason: reason)
                newState = .bothQuiescing(state)
                newState.closeIfNeeded(state)
                return result
            }

        case .quiescingPrefaceSent(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.sendRstStream(streamID: streamID, reason: reason)
                newState = .quiescingPrefaceSent(state)
                return result
            }

        case .idle, .prefaceReceived, .quiescingPrefaceReceived:
            // We're waiting for the local preface.
            return .init(result: .connectionError(underlyingError: NIOHTTP2Errors.MissingPreface(), type: .protocolError), effect: nil)

        case .fullyQuiesced:
            return .init(result: .connectionError(underlyingError: NIOHTTP2Errors.IOOnClosedConnection(), type: .protocolError), effect: nil)

        case .modifying:
            preconditionFailure("Must not be left in modifying state")
        }
    }

    /// Called when a PUSH_PROMISE frame has been initiated on a given stream.
    ///
    /// If this method returns a stream error, the stream error should be assumed to apply to both the original
    /// and child stream.
    mutating func receivePushPromise(originalStreamID: HTTP2StreamID, childStreamID: HTTP2StreamID, headers: HPACKHeaders) -> StateMachineResultWithEffect {
        // In states that support a push promise we have two steps. Firstly, we want to create the child stream; then we want to
        // pass the PUSH_PROMISE frame through the stream state machine for the parent stream.
        //
        // The reason we do things in this order is that if for any reason the PUSH_PROMISE frame is invalid on the parent stream,
        // we want to take out both the child stream and the parent stream. We can only do that if we have a child stream state to
        // modify. For this reason, we unconditionally allow the remote peer to consume the stream. The only case where this is *not*
        // true is when the child stream itself cannot be validly created, because the stream ID used by the remote peer is invalid.
        // In this case this is a connection error, anyway, so we don't worry too much about it.
        switch self.state {
        case .prefaceReceived(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receivePushPromise(originalStreamID: originalStreamID, childStreamID: childStreamID, headers: headers)
                newState = .prefaceReceived(state)
                return result
            }

        case .active(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receivePushPromise(originalStreamID: originalStreamID, childStreamID: childStreamID, headers: headers)
                newState = .active(state)
                return result
            }

        case .locallyQuiesced(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receivePushPromise(originalStreamID: originalStreamID, childStreamID: childStreamID, headers: headers)
                newState = .locallyQuiesced(state)
                return result
            }

        case .remotelyQuiesced(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receivePushPromise(originalStreamID: originalStreamID, childStreamID: childStreamID, headers: headers)
                newState = .remotelyQuiesced(state)
                return result
            }

        case .bothQuiescing(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receivePushPromise(originalStreamID: originalStreamID, childStreamID: childStreamID, headers: headers)
                newState = .bothQuiescing(state)
                return result
            }

        case .quiescingPrefaceReceived(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receivePushPromise(originalStreamID: originalStreamID, childStreamID: childStreamID, headers: headers)
                newState = .quiescingPrefaceReceived(state)
                return result
            }

        case .idle, .prefaceSent, .quiescingPrefaceSent:
            // We're waiting for the remote preface.
            return .init(result: .connectionError(underlyingError: NIOHTTP2Errors.MissingPreface(), type: .protocolError), effect: nil)

        case .fullyQuiesced:
            return .init(result: .connectionError(underlyingError: NIOHTTP2Errors.IOOnClosedConnection(), type: .protocolError), effect: nil)

        case .modifying:
            preconditionFailure("Must not be left in modifying state")
        }
    }

    mutating func sendPushPromise(originalStreamID: HTTP2StreamID, childStreamID: HTTP2StreamID, headers: HPACKHeaders) -> StateMachineResultWithEffect {
        switch self.state {
        case .prefaceSent(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.sendPushPromise(originalStreamID: originalStreamID, childStreamID: childStreamID, headers: headers)
                newState = .prefaceSent(state)
                return result
            }

        case .active(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.sendPushPromise(originalStreamID: originalStreamID, childStreamID: childStreamID, headers: headers)
                newState = .active(state)
                return result
            }

        case .locallyQuiesced(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.sendPushPromise(originalStreamID: originalStreamID, childStreamID: childStreamID, headers: headers)
                newState = .locallyQuiesced(state)
                return result
            }

        case .remotelyQuiesced, .bothQuiescing:
            // We have been quiesced, and may not create new streams.
            return .init(result: .connectionError(underlyingError: NIOHTTP2Errors.CreatedStreamAfterGoaway(), type: .protocolError), effect: nil)

        case .quiescingPrefaceSent(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.sendPushPromise(originalStreamID: originalStreamID, childStreamID: childStreamID, headers: headers)
                newState = .quiescingPrefaceSent(state)
                return result
            }

        case .idle, .prefaceReceived, .quiescingPrefaceReceived:
            // We're waiting for the local preface.
            return .init(result: .connectionError(underlyingError: NIOHTTP2Errors.MissingPreface(), type: .protocolError), effect: nil)

        case .fullyQuiesced:
            return .init(result: .connectionError(underlyingError: NIOHTTP2Errors.IOOnClosedConnection(), type: .protocolError), effect: nil)

        case .modifying:
            preconditionFailure("Must not be left in modifying state")
        }
    }

    /// Called when a PING frame has been received from the network.
    mutating func receivePing(ackFlagSet: Bool) -> (StateMachineResultWithEffect, PostFrameOperation) {
        // Pings are pretty straightforward: they're basically always allowed. This is a bit weird, but I can find no text in
        // RFC 7540 that says that receiving PINGs with ACK flags set when no PING ACKs are expected is forbidden. This is
        // very strange, but we allow it.
        switch self.state {
        case .prefaceReceived, .active, .locallyQuiesced, .remotelyQuiesced, .bothQuiescing, .quiescingPrefaceReceived:
            return (.init(result: .succeed, effect: nil), ackFlagSet ? .nothing : .sendAck)

        case .idle, .prefaceSent, .quiescingPrefaceSent:
            // We're waiting for the remote preface.
            return (.init(result: .connectionError(underlyingError: NIOHTTP2Errors.MissingPreface(), type: .protocolError), effect: nil), .nothing)

        case .fullyQuiesced:
            return (.init(result: .connectionError(underlyingError: NIOHTTP2Errors.IOOnClosedConnection(), type: .protocolError), effect: nil), .nothing)

        case .modifying:
            preconditionFailure("Must not be left in modifying state")
        }
    }

    /// Called when a PING frame is about to be sent.
    mutating func sendPing() -> StateMachineResultWithEffect {
        // Pings are pretty straightforward: they're basically always allowed. This is a bit weird, but I can find no text in
        // RFC 7540 that says that sending PINGs with ACK flags set when no PING ACKs are expected is forbidden. This is
        // very strange, but we allow it.
        switch self.state {
        case .prefaceSent, .active, .locallyQuiesced, .remotelyQuiesced, .bothQuiescing, .quiescingPrefaceSent:
            return .init(result: .succeed, effect: nil)

        case .idle, .prefaceReceived, .quiescingPrefaceReceived:
            // We're waiting for the local preface.
            return .init(result: .connectionError(underlyingError: NIOHTTP2Errors.MissingPreface(), type: .protocolError), effect: nil)

        case .fullyQuiesced:
            return .init(result: .connectionError(underlyingError: NIOHTTP2Errors.IOOnClosedConnection(), type: .protocolError), effect: nil)

        case .modifying:
            preconditionFailure("Must not be left in modifying state")
        }
    }


    /// Called when we receive a GOAWAY frame.
    mutating func receiveGoaway(lastStreamID: HTTP2StreamID) -> StateMachineResultWithEffect {
        // GOAWAY frames are some of the most subtle frames in HTTP/2, they cause a number of state transitions all at once.
        // In particular, the value of lastStreamID heavily affects the state transitions we perform here.
        // In this case, all streams initiated by us that have stream IDs higher than lastStreamID will be closed, effective
        // immediately. If this leaves us with zero streams, the connection is fullyQuiesced. Otherwise, we are quiescing.
        switch self.state {
        case .prefaceReceived(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveGoAwayFrame(lastStreamID: lastStreamID)
                let newStateData = QuiescingPrefaceReceivedState(fromPrefaceReceived: state, lastStreamID: lastStreamID)
                newState = .quiescingPrefaceReceived(newStateData)
                return result
            }

        case .active(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveGoAwayFrame(lastStreamID: lastStreamID)
                let newStateData = RemotelyQuiescedState(fromActive: state, lastLocalStreamID: lastStreamID)
                newState = .remotelyQuiesced(newStateData)
                newState.closeIfNeeded(newStateData)
                return result
            }

        case .locallyQuiesced(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveGoAwayFrame(lastStreamID: lastStreamID)
                let newStateData = BothQuiescingState(fromLocallyQuiesced: state, lastLocalStreamID: lastStreamID)
                newState = .bothQuiescing(newStateData)
                newState.closeIfNeeded(newStateData)
                return result
            }

        case .remotelyQuiesced(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveGoAwayFrame(lastStreamID: lastStreamID)
                newState = .remotelyQuiesced(state)
                newState.closeIfNeeded(state)
                return result
            }

        case .bothQuiescing(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveGoAwayFrame(lastStreamID: lastStreamID)
                newState = .bothQuiescing(state)
                newState.closeIfNeeded(state)
                return result
            }

        case .quiescingPrefaceReceived(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveGoAwayFrame(lastStreamID: lastStreamID)
                newState = .quiescingPrefaceReceived(state)
                return result
            }

        case .idle, .prefaceSent, .quiescingPrefaceSent:
            // We're waiting for the preface.
            return .init(result: .connectionError(underlyingError: NIOHTTP2Errors.MissingPreface(), type: .protocolError), effect: nil)

        case .fullyQuiesced(var state):
            return self.avoidingStateMachineCoW { newState in
                // We allow duplicate GOAWAY here, so long as it ratchets correctly.
                let result = state.receiveGoAwayFrame(lastStreamID: lastStreamID)
                newState = .fullyQuiesced(state)
                return result
            }

        case .modifying:
            preconditionFailure("Must not be left in modifying state")
        }
    }

    /// Called when the user attempts to send a GOAWAY frame.
    mutating func sendGoaway(lastStreamID: HTTP2StreamID) -> StateMachineResultWithEffect {
        // GOAWAY frames are some of the most subtle frames in HTTP/2, they cause a number of state transitions all at once.
        // In particular, the value of lastStreamID heavily affects the state transitions we perform here.
        // In this case, all streams initiated by us that have stream IDs higher than lastStreamID will be closed, effective
        // immediately. If this leaves us with zero streams, the connection is fullyQuiesced. Otherwise, we are quiescing.
        switch self.state {
        case .prefaceSent(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.sendGoAwayFrame(lastStreamID: lastStreamID)
                let newStateData = QuiescingPrefaceSentState(fromPrefaceSent: state, lastStreamID: lastStreamID)
                newState = .quiescingPrefaceSent(newStateData)
                return result
            }

        case .active(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.sendGoAwayFrame(lastStreamID: lastStreamID)
                let newStateData = LocallyQuiescedState(fromActive: state, lastRemoteStreamID: lastStreamID)
                newState = .locallyQuiesced(newStateData)
                newState.closeIfNeeded(newStateData)
                return result
            }

        case .locallyQuiesced(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.sendGoAwayFrame(lastStreamID: lastStreamID)
                newState = .locallyQuiesced(state)
                newState.closeIfNeeded(state)
                return result
            }

        case .remotelyQuiesced(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.sendGoAwayFrame(lastStreamID: lastStreamID)
                let newStateData = BothQuiescingState(fromRemotelyQuiesced: state, lastRemoteStreamID: lastStreamID)
                newState = .bothQuiescing(newStateData)
                newState.closeIfNeeded(newStateData)
                return result
            }

        case .bothQuiescing(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.sendGoAwayFrame(lastStreamID: lastStreamID)
                newState = .bothQuiescing(state)
                newState.closeIfNeeded(state)
                return result
            }

        case .quiescingPrefaceSent(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.sendGoAwayFrame(lastStreamID: lastStreamID)
                newState = .quiescingPrefaceSent(state)
                return result
            }

        case .idle, .prefaceReceived, .quiescingPrefaceReceived:
            // We're waiting for the preface.
            return .init(result: .connectionError(underlyingError: NIOHTTP2Errors.MissingPreface(), type: .protocolError), effect: nil)

        case .fullyQuiesced(var state):
            return self.avoidingStateMachineCoW { newState in
                // We allow duplicate GOAWAY here, so long as it ratchets downwards.
                let result = state.sendGoAwayFrame(lastStreamID: lastStreamID)
                newState = .fullyQuiesced(state)
                return result
            }

        case .modifying:
            preconditionFailure("Must not be left in modifying state")
        }
    }

    /// Called when a WINDOW_UPDATE frame has been received.
    mutating func receiveWindowUpdate(streamID: HTTP2StreamID, windowIncrement: UInt32) -> StateMachineResultWithEffect {
        switch self.state {
        case .prefaceReceived(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveWindowUpdate(streamID: streamID, increment: windowIncrement)
                newState = .prefaceReceived(state)
                return result
            }

        case .active(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveWindowUpdate(streamID: streamID, increment: windowIncrement)
                newState = .active(state)
                return result
            }

        case .quiescingPrefaceReceived(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveWindowUpdate(streamID: streamID, increment: windowIncrement)
                newState = .quiescingPrefaceReceived(state)
                return result
            }

        case .locallyQuiesced(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveWindowUpdate(streamID: streamID, increment: windowIncrement)
                newState = .locallyQuiesced(state)
                return result
            }

        case .remotelyQuiesced(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveWindowUpdate(streamID: streamID, increment: windowIncrement)
                newState = .remotelyQuiesced(state)
                return result
            }

        case .bothQuiescing(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveWindowUpdate(streamID: streamID, increment: windowIncrement)
                newState = .bothQuiescing(state)
                return result
            }

        case .idle, .prefaceSent, .quiescingPrefaceSent:
            // We're waiting for the preface.
            return .init(result: .connectionError(underlyingError: NIOHTTP2Errors.MissingPreface(), type: .protocolError), effect: nil)

        case .fullyQuiesced:
            return .init(result: .connectionError(underlyingError: NIOHTTP2Errors.IOOnClosedConnection(), type: .protocolError), effect: nil)

        case .modifying:
            preconditionFailure("Must not be left in modifying state")
        }
    }

    /// Called when a WINDOW_UPDATE frame is sent.
    mutating func sendWindowUpdate(streamID: HTTP2StreamID, windowIncrement: UInt32) -> StateMachineResultWithEffect {
        switch self.state {
        case .prefaceSent(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.sendWindowUpdate(streamID: streamID, increment: windowIncrement)
                newState = .prefaceSent(state)
                return result
            }

        case .active(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.sendWindowUpdate(streamID: streamID, increment: windowIncrement)
                newState = .active(state)
                return result
            }

        case .quiescingPrefaceSent(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.sendWindowUpdate(streamID: streamID, increment: windowIncrement)
                newState = .quiescingPrefaceSent(state)
                return result
            }

        case .locallyQuiesced(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.sendWindowUpdate(streamID: streamID, increment: windowIncrement)
                newState = .locallyQuiesced(state)
                return result
            }

        case .remotelyQuiesced(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.sendWindowUpdate(streamID: streamID, increment: windowIncrement)
                newState = .remotelyQuiesced(state)
                return result
            }

        case .bothQuiescing(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.sendWindowUpdate(streamID: streamID, increment: windowIncrement)
                newState = .bothQuiescing(state)
                return result
            }

        case .idle, .prefaceReceived, .quiescingPrefaceReceived:
            // We're waiting for the preface.
            return .init(result: .connectionError(underlyingError: NIOHTTP2Errors.MissingPreface(), type: .protocolError), effect: nil)

        case .fullyQuiesced:
            return .init(result: .connectionError(underlyingError: NIOHTTP2Errors.IOOnClosedConnection(), type: .protocolError), effect: nil)

        case .modifying:
            preconditionFailure("Must not be left in modifying state")
        }
    }
}

// Mark:- Private helper methods
extension HTTP2ConnectionStateMachine {
    /// Called when we have received a SETTINGS frame from the remote peer. Applies the changes immediately.
    private mutating func receiveSettingsChange(_ settings: HTTP2Settings, frameDecoder: inout HTTP2FrameDecoder) -> (StateMachineResultWithEffect, PostFrameOperation) {
        let validationResult = self.validateSettings(settings)

        guard case .succeed = validationResult else {
            return (.init(result: validationResult, effect: nil), .nothing)
        }

        switch self.state {
        case .idle(let state):
            return self.avoidingStateMachineCoW { newState in
                var newStateData = PrefaceReceivedState(fromIdle: state, remoteSettings: HTTP2SettingsState(localState: false))
                let result = newStateData.receiveSettingsChange(settings, frameDecoder: &frameDecoder)
                newState = .prefaceReceived(newStateData)
                return result
            }

        case .prefaceSent(let state):
            return self.avoidingStateMachineCoW { newState in
                var newStateData = ActiveConnectionState(fromPrefaceSent: state, remoteSettings: HTTP2SettingsState(localState: false))
                let result = newStateData.receiveSettingsChange(settings, frameDecoder: &frameDecoder)
                newState = .active(newStateData)
                return result
            }

        case .prefaceReceived(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveSettingsChange(settings, frameDecoder: &frameDecoder)
                newState = .prefaceReceived(state)
                return result
            }

        case .active(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveSettingsChange(settings, frameDecoder: &frameDecoder)
                newState = .active(state)
                return result
            }

        case .remotelyQuiesced(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveSettingsChange(settings, frameDecoder: &frameDecoder)
                newState = .remotelyQuiesced(state)
                return result
            }

        case .locallyQuiesced(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveSettingsChange(settings, frameDecoder: &frameDecoder)
                newState = .locallyQuiesced(state)
                return result
            }

        case .bothQuiescing(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveSettingsChange(settings, frameDecoder: &frameDecoder)
                newState = .bothQuiescing(state)
                return result
            }

        case .quiescingPrefaceSent(let state):
            return self.avoidingStateMachineCoW { newState in
                var newStateData = LocallyQuiescedState(fromQuiescingPrefaceSent: state, remoteSettings: HTTP2SettingsState(localState: false))
                let result = newStateData.receiveSettingsChange(settings, frameDecoder: &frameDecoder)
                newState = .locallyQuiesced(newStateData)
                return result
            }

        case .quiescingPrefaceReceived(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveSettingsChange(settings, frameDecoder: &frameDecoder)
                newState = .quiescingPrefaceReceived(state)
                return result
            }

        case .fullyQuiesced:
            return (.init(result: .connectionError(underlyingError: NIOHTTP2Errors.IOOnClosedConnection(), type: .protocolError), effect: nil), .nothing)

        case .modifying:
            preconditionFailure("Must not be left in modifying state")
        }
    }

    private mutating func receiveSettingsAck(frameEncoder: inout HTTP2FrameEncoder) -> StateMachineResultWithEffect {
        // We can only receive a SETTINGS ACK after we've sent our own preface *and* the remote peer has
        // sent its own. That means we have to be active or quiescing.
        switch self.state {
        case .active(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveSettingsAck(frameEncoder: &frameEncoder)
                newState = .active(state)
                return result
            }

        case .locallyQuiesced(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveSettingsAck(frameEncoder: &frameEncoder)
                newState = .locallyQuiesced(state)
                return result
            }

        case .remotelyQuiesced(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveSettingsAck(frameEncoder: &frameEncoder)
                newState = .remotelyQuiesced(state)
                return result
            }

        case .bothQuiescing(var state):
            return self.avoidingStateMachineCoW { newState in
                let result = state.receiveSettingsAck(frameEncoder: &frameEncoder)
                newState = .bothQuiescing(state)
                return result
            }

        case .idle, .prefaceSent, .prefaceReceived, .quiescingPrefaceReceived, .quiescingPrefaceSent:
            return .init(result: .connectionError(underlyingError: NIOHTTP2Errors.ReceivedBadSettings(), type: .protocolError), effect: nil)

        case .fullyQuiesced:
            return .init(result: .connectionError(underlyingError: NIOHTTP2Errors.IOOnClosedConnection(), type: .protocolError), effect: nil)

        case .modifying:
            preconditionFailure("Must not be left in modifying state")
        }
    }

    /// Validates a single HTTP/2 settings block.
    ///
    /// - parameters:
    ///     - settings: The HTTP/2 settings block to validate.
    /// - returns: The result of the validation.
    private func validateSettings(_ settings: HTTP2Settings) -> StateMachineResult {
        for setting in settings {
            switch setting.parameter {
            case .enablePush:
                guard setting._value == 0 || setting._value == 1 else {
                    return .connectionError(underlyingError: NIOHTTP2Errors.InvalidSetting(setting: setting), type: .protocolError)
                }
            case .initialWindowSize:
                guard setting._value <= HTTP2FlowControlWindow.maxSize else {
                    return .connectionError(underlyingError: NIOHTTP2Errors.InvalidSetting(setting: setting), type: .flowControlError)
                }
            case .maxFrameSize:
                guard setting._value >= (1 << 14) && setting._value <= ((1 << 24) - 1) else {
                    return .connectionError(underlyingError: NIOHTTP2Errors.InvalidSetting(setting: setting), type: .protocolError)
                }
            default:
                // All other settings have unrestricted ranges.
                break
            }
        }

        return .succeed
    }
}

extension HTTP2ConnectionStateMachine.State {
    // Sets the connection state to fullyQuiesced if necessary.
    //
    // We should only call this when a server has quiesced the connection. As long as only the client has quiesced the
    // connection more work can always be done.
    mutating func closeIfNeeded<CurrentState: QuiescingState & LocallyQuiescingState & RemotelyQuiescingState & SendAndReceiveGoawayState & ConnectionStateWithRole & ConnectionStateWithConfiguration>(_ state: CurrentState) {
        if state.quiescedByServer && state.streamState.openStreams == 0 {
            self = .fullyQuiesced(.init(previousState: state))
        }
    }

    // Sets the connection state to fullyQuiesced if necessary.
    //
    // We should only call this when a server has quiesced the connection. As long as only the client has quiesced the
    // connection more work can always be done.
    mutating func closeIfNeeded<CurrentState: QuiescingState & LocallyQuiescingState & SendAndReceiveGoawayState & ConnectionStateWithRole & ConnectionStateWithConfiguration>(_ state: CurrentState) {
        if state.quiescedByServer && state.streamState.openStreams == 0 {
            self = .fullyQuiesced(.init(previousState: state))
        }
    }

    // Sets the connection state to fullyQuiesced if necessary.
    //
    // We should only call this when a server has quiesced the connection. As long as only the client has quiesced the
    // connection more work can always be done.
    mutating func closeIfNeeded<CurrentState: QuiescingState & RemotelyQuiescingState & SendAndReceiveGoawayState & ConnectionStateWithRole & ConnectionStateWithConfiguration>(_ state: CurrentState) {
        if state.quiescedByServer && state.streamState.openStreams == 0 {
            self = .fullyQuiesced(.init(previousState: state))
        }
    }
}

// MARK: CoW helpers
extension HTTP2ConnectionStateMachine {
    /// So, uh...this function needs some explaining.
    ///
    /// While the state machine logic above is great, there is a downside to having all of the state machine data in
    /// associated data on enumerations: any modification of that data will trigger copy on write for heap-allocated
    /// data. That means that for _every operation on the state machine_ we will CoW our underlying state, which is
    /// not good.
    ///
    /// The way we can avoid this is by using this helper function. It will temporarily set state to a value with no
    /// associated data, before attempting the body of the function. It will also verify that the state machine never
    /// remains in this bad state.
    ///
    /// A key note here is that all callers must ensure that they return to a good state before they exit.
    ///
    /// Sadly, because it's generic and has a closure, we need to force it to be inlined at all call sites, which is
    /// not ideal.
    @inline(__always)
    private mutating func avoidingStateMachineCoW<ReturnType>(_ body: (inout State) -> ReturnType) -> ReturnType {
        self.state = .modifying
        defer {
            assert(!self.isModifying)
        }

        return body(&self.state)
    }

    private var isModifying: Bool {
        if case .modifying = self.state {
            return true
        } else {
            return false
        }
    }
}


extension HTTP2StreamID {
    /// Confirms that this kind of stream ID may be initiated by a peer in the specific role.
    ///
    /// RFC 7540 limits odd stream IDs to being initiated by clients, and even stream IDs to
    /// being initiated by servers. This method confirms this.
    func mayBeInitiatedBy(_ role: HTTP2ConnectionStateMachine.ConnectionRole) -> Bool {
        switch role {
        case .client:
            return self.networkStreamID % 2 == 1
        case .server:
            // Noone may initiate the root stream.
            return self.networkStreamID % 2 == 0 && self != .rootStream
        }
    }
}


/// A simple protocol that provides helpers that apply to all connection states that keep track of a role.
private protocol ConnectionStateWithRole {
    var role: HTTP2ConnectionStateMachine.ConnectionRole { get }
}

extension ConnectionStateWithRole {
    var peerRole: HTTP2ConnectionStateMachine.ConnectionRole {
        switch self.role {
        case .client:
            return .server
        case .server:
            return .client
        }
    }
}

/// A simple protocol that provides helpers that apply to all connection states that have configuration.
private protocol ConnectionStateWithConfiguration {
    var headerBlockValidation: HTTP2ConnectionStateMachine.ValidationState { get }

    var contentLengthValidation: HTTP2ConnectionStateMachine.ValidationState { get}
}
