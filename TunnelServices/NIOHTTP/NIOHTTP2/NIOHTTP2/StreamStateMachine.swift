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
import NIOHPACK

/// A HTTP/2 protocol implementation is fundamentally built on top of two interlocking finite
/// state machines. The full description of this is in ConnectionStateMachine.swift.
///
/// This file contains the implementation of the per-stream state machine. A HTTP/2 stream goes
/// through a number of states in its lifecycle, and the specific states it passes through depend
/// on how the stream is created and what it is for. RFC 7540 claims to have a state machine
/// diagram for a HTTP/2 stream, which I have reproduced below:
///
///                                +--------+
///                        send PP |        | recv PP
///                       ,--------|  idle  |--------.
///                      /         |        |         \
///                     v          +--------+          v
///              +----------+          |           +----------+
///              |          |          | send H /  |          |
///       ,------| reserved |          | recv H    | reserved |------.
///       |      | (local)  |          |           | (remote) |      |
///       |      +----------+          v           +----------+      |
///       |          |             +--------+             |          |
///       |          |     recv ES |        | send ES     |          |
///       |   send H |     ,-------|  open  |-------.     | recv H   |
///       |          |    /        |        |        \    |          |
///       |          v   v         +--------+         v   v          |
///       |      +----------+          |           +----------+      |
///       |      |   half   |          |           |   half   |      |
///       |      |  closed  |          | send R /  |  closed  |      |
///       |      | (remote) |          | recv R    | (local)  |      |
///       |      +----------+          |           +----------+      |
///       |           |                |                 |           |
///       |           | send ES /      |       recv ES / |           |
///       |           | send R /       v        send R / |           |
///       |           | recv R     +--------+   recv R   |           |
///       | send R /  `----------->|        |<-----------'  send R / |
///       | recv R                 | closed |               recv R   |
///       `----------------------->|        |<----------------------'
///                                +--------+
///
///          send:   endpoint sends this frame
///          recv:   endpoint receives this frame
///
///          H:  HEADERS frame (with implied CONTINUATIONs)
///          PP: PUSH_PROMISE frame (with implied CONTINUATIONs)
///          ES: END_STREAM flag
///          R:  RST_STREAM frame
///
/// Unfortunately, this state machine diagram is not really entirely sufficient, as it
/// underspecifies many aspects of the system. One particular note is that it does not
/// encode the validity of some of these transitions: for example, send PP or recv PP
/// are only valid for certain kinds of peers.
///
/// Ultimately, however, this diagram provides the basis for our state machine
/// implementation in this file. The state machine aims to enforce the correctness of
/// the protocol.
///
/// Remote peers that violate the protocol requirements should be notified early.
/// HTTP/2 is unusual in that the vast majority of implementations are strict about
/// RFC violations, and we should be as well. Therefore, the state machine exists to
/// constrain the remote peer's actions: if they take an action that leads to an invalid
/// state transition, we will report this to the remote peer (and to our user).
///
/// Additionally, we want to enforce that our users do not violate the correctness of the
/// protocol. In this early implementation if the user violates protocol correctness, no
/// action is taken: the stream remains in its prior state, and no frame is emitted.
/// In future it may become configurable such that if the user violates the correctness of
/// the protocol, NIO will proactively close the stream to avoid consuming resources.
///
/// ### Implementation
///
/// The core of the state machine implementation is a `State` enum. This enum demarcates all
/// valid states of the stream, and enforces only valid transitions between those states.
/// Attempts to make invalid transitions between those states will be rejected by this enum.
///
/// Additionally, this enum stores all relevant data about the stream that is associated with
/// its stream state as associated data. This ensures that it is not possible to store a stream
/// state that requires associated data without providing it.
///
/// To prevent future maintainers from being tempted to circumvent the rules in this state machine,
/// the `State` enum is wrapped in a `struct` (this `struct`, in fact) that prevents programmers
/// from directly setting the state of a stream.
///
/// Operations on the state machine are performed by calling specific functions corresponding to
/// the operation that is about to occur.
struct HTTP2StreamStateMachine {
    private enum State {
        // TODO(cory): Can we remove the idle state? Streams shouldn't sit in idle for long periods
        // of time, they should immediately transition out, so can we avoid it entirely?
        /// In the idle state, the stream has not been opened by either peer.
        /// This is usually a temporary state, and we expect rapid transitions out of this state.
        /// In this state we keep track of whether we are in a client or server connection, as it
        /// limits the transitions we can make. In all other states, being either a client or server
        /// is either not relevant, or encoded in the state itself implicitly.
        case idle(localRole: StreamRole, localWindow: HTTP2FlowControlWindow, remoteWindow: HTTP2FlowControlWindow)

        /// In the reservedRemote state, the stream has been opened by the remote peer emitting a
        /// PUSH_PROMISE frame. We are expecting to receive a HEADERS frame for the pushed response. In this
        /// state we are definitionally a client.
        case reservedRemote(remoteWindow: HTTP2FlowControlWindow)

        /// In the reservedLocal state, the stream has been opened by the local user sending a PUSH_PROMISE
        /// frame. We now need to send a HEADERS frame for the pushed response. In this state we are definitionally
        /// a server.
        case reservedLocal(localWindow: HTTP2FlowControlWindow)

        /// This state does not exist on the diagram above. It encodes the notion that this stream has
        /// been opened by the local user sending a HEADERS frame, but we have not yet received the remote
        /// peer's final HEADERS frame in response. It is possible we have received non-final HEADERS frames
        /// from the remote peer in this state, however. If we are in this state, we must be a client: servers
        /// initiating streams put them into reservedLocal, and then sending HEADERS transfers them directly to
        /// halfClosedRemoteLocalActive.
        case halfOpenLocalPeerIdle(localWindow: HTTP2FlowControlWindow, localContentLength: ContentLengthVerifier, remoteWindow: HTTP2FlowControlWindow)

        /// This state does not exist on the diagram above. It encodes the notion that this stream has
        /// been opened by the remote user sending a HEADERS frame, but we have not yet sent our HEADERS frame
        /// in response. If we are in this state, we must be a server: clients receiving streams that were opened
        /// by servers put them into reservedRemote, and then receiving the response HEADERS transitions them directly
        /// to halfClosedLocalPeerActive.
        case halfOpenRemoteLocalIdle(localWindow: HTTP2FlowControlWindow, remoteContentLength: ContentLengthVerifier, remoteWindow: HTTP2FlowControlWindow)

        /// This state is when both peers have sent a HEADERS frame, but neither has sent a frame with END_STREAM
        /// set. Both peers may exchange data fully. In this state we keep track of whether we are a client or a
        /// server, as only servers may push new streams.
        case fullyOpen(localRole: StreamRole, localContentLength: ContentLengthVerifier, remoteContentLength: ContentLengthVerifier, localWindow: HTTP2FlowControlWindow, remoteWindow: HTTP2FlowControlWindow)

        /// In the halfClosedLocalPeerIdle state, the local user has sent END_STREAM, but the remote peer has not
        /// yet sent its HEADERS frame. This mostly happens on GET requests, when END_HEADERS and END_STREAM are
        /// present on the same frame, and so the stream transitions directly from idle to this state.
        /// This peer can no longer send data. We are expecting a headers frame from the remote peer.
        ///
        /// In this state we must be a client, as this state can only be entered by the local peer sending
        /// END_STREAM before we receive HEADERS. This cannot happen to a server, as we must have initiated
        /// this stream to have half closed it before we receive HEADERS, and if we had initiated the stream via
        /// PUSH_PROMISE (as a server must), the stream would be halfClosedRemote, not halfClosedLocal.
        case halfClosedLocalPeerIdle(remoteWindow: HTTP2FlowControlWindow)

        /// In the halfClosedLocalPeerActive state, the local user has sent END_STREAM, and the remote peer has
        /// sent its HEADERS frame. This happens when we send END_STREAM from the fullyOpen state, or when we
        /// receive a HEADERS in reservedRemote. This peer can no longer send data. The remote peer may continue
        /// to do so. We are not expecting a HEADERS frame from the remote peer.
        ///
        /// Both servers and clients can be in this state.
        ///
        /// We keep track of whether this stream was initiated by us or by the peer, which can be determined based
        /// on how we entered this state. If we came from fullyOpen and we're a client, then this peer was initiated
        /// by us: if we're a server, it was initiated by the peer. This is because server-initiated streams never
        /// enter fullyOpen, as the client is never actually open on those streams. If we came here from
        /// reservedRemote, this stream must be peer initiated, as this is the client side of a pushed stream.
        case halfClosedLocalPeerActive(localRole: StreamRole, initiatedBy: StreamRole, remoteContentLength: ContentLengthVerifier, remoteWindow: HTTP2FlowControlWindow)

        /// In the halfClosedRemoteLocalIdle state, the remote peer has sent END_STREAM, but the local user has not
        /// yet sent its HEADERS frame. This mostly happens on GET requests, when END_HEADERS and END_STREAM are
        /// present on the same frame, and so the stream transitions directly from idle to this state.
        /// This peer is expected to send a HEADERS frame. The remote peer may no longer send data.
        ///
        /// In this state we must be a server, as this state can only be entered by the remote peer sending
        /// END_STREAM before we send HEADERS. This cannot happen to a client, as the remote peer must have initiated
        /// this stream to have half closed it before we send HEADERS, and that will cause a client to enter halfClosedLocal,
        /// not halfClosedRemote.
        case halfClosedRemoteLocalIdle(localWindow: HTTP2FlowControlWindow)

        /// In the halfClosedRemoteLocalActive state, the remote peer has sent END_STREAM, and the local user has
        /// sent its HEADERS frame. This happens when we receive END_STREAM in the fullyOpen state, or when we
        /// send a HEADERS frame in reservedLocal. This peer is not expected to send a HEADERS frame.
        /// The remote peer may no longer send data.
        ///
        /// Both servers and clients can be in this state.
        ///
        /// We keep track of whether this stream was initiated by us or by the peer, which can be determined based
        /// on how we entered this state. If we came from fullyOpen and we're a client, then this stream was initiated
        /// by us: if we're a server, it was initiated by the peer. This is because server-initiated streams never
        /// enter fullyOpen, as the client is never actually open on those streams. If we came here from
        /// reservedLocal, this stream must be initiated by us, as this is the server side of a pushed stream.
        case halfClosedRemoteLocalActive(localRole: StreamRole, initiatedBy: StreamRole, localContentLength: ContentLengthVerifier, localWindow: HTTP2FlowControlWindow)

        /// Both peers have sent their END_STREAM flags, and the stream is closed. In this stage no further data
        /// may be exchanged.
        case closed(reason: HTTP2ErrorCode?)
    }


    /// The possible roles an endpoint may play in a given stream.
    enum StreamRole {
        /// A server. Servers initiate streams by pushing them.
        case server

        /// A client. Clients initiate streams by sending requests.
        case client
    }

    /// Whether the stream has been closed.
    internal enum StreamClosureState: Hashable {
        case closed(HTTP2ErrorCode?)

        case notClosed
    }

    /// Whether this stream has been closed.
    ///
    /// This property should be used only for asserting correct state.
    internal var closed: StreamClosureState {
        switch self.state {
        case .closed(let reason):
            return .closed(reason)
        default:
            return .notClosed
        }
    }

    /// The current state of this stream.
    private var state: State

    /// The ID of this stream.
    internal let streamID: HTTP2StreamID

    /// Creates a new, idle, HTTP/2 stream.
    init(streamID: HTTP2StreamID, localRole: StreamRole, localInitialWindowSize: UInt32, remoteInitialWindowSize: UInt32) {
        let localWindow = HTTP2FlowControlWindow(initialValue: localInitialWindowSize)
        let remoteWindow = HTTP2FlowControlWindow(initialValue: remoteInitialWindowSize)

        self.streamID = streamID
        self.state = .idle(localRole: localRole, localWindow: localWindow, remoteWindow: remoteWindow)
    }

    /// Creates a new HTTP/2 stream for a stream that was created by receiving a PUSH_PROMISE frame
    /// on another stream.
    init(receivedPushPromiseCreatingStreamID streamID: HTTP2StreamID, remoteInitialWindowSize: UInt32) {
        self.streamID = streamID
        self.state = .reservedRemote(remoteWindow: HTTP2FlowControlWindow(initialValue: remoteInitialWindowSize))
    }

    /// Creates a new HTTP/2 stream for a stream that was created by sending a PUSH_PROMISE frame on
    /// another stream.
    init(sentPushPromiseCreatingStreamID streamID: HTTP2StreamID, localInitialWindowSize: UInt32) {
        self.streamID = streamID
        self.state = .reservedLocal(localWindow: HTTP2FlowControlWindow(initialValue: localInitialWindowSize))
    }
}

// MARK:- State transition functions
//
// The events that may cause the state machine to change state.
//
// This enumeration contains entries for sending and receiving all per-stream frames except for PRIORITY.
// The per-connection frames (GOAWAY, PING, some WINDOW_UPDATE) are managed by the connection state machine
// instead of the stream one, and so are not covered here. This enumeration excludes PRIORITY frames, because
// while PRIORITY frames are technically per-stream they can be sent at any time on an active connection,
// regardless of the state of the affected stream. For this reason, they are not so much per-stream frames
// as per-connection frames that happen to have a stream ID.
extension HTTP2StreamStateMachine {
    /// Called when a HEADERS frame is being sent. Validates that the frame may be sent in this state, that
    /// it meets the requirements of RFC 7540 for containing a well-formed header block, and additionally
    /// checks whether the value of the end stream bit is acceptable. If all checks pass, transitions the
    /// state to the appropriate next entry.
    mutating func sendHeaders(headers: HPACKHeaders, validateHeaderBlock: Bool, validateContentLength: Bool, isEndStreamSet endStream: Bool) -> StateMachineResultWithStreamEffect {
        do {
            // We can send headers in the following states:
            //
            // - idle, when we are a client, in which case we are sending our request headers
            // - halfOpenRemoteLocalIdle, in which case we are a server sending either informational or final headers
            // - halfOpenLocalPeerIdle, in which case we are a client sending trailers
            // - reservedLocal, in which case we are a server sending either informational or final headers
            // - fullyOpen, in which case we are sending trailers
            // - halfClosedRemoteLocalIdle, in which case we area server  sending either informational or final headers
            //     (see the comment on halfClosedRemoteLocalIdle for more)
            // - halfClosedRemoteLocalActive, in which case we are sending trailers
            //
            // In idle or reservedLocal we are opening the stream. In reservedLocal, halfClosedRemoteLocalIdle, or halfClosedremoteLocalActive
            // we may be closing the stream. The keen-eyed may notice that reservedLocal may both open *and* close a stream. This is a bit awkward
            // for us, and requires a separate event.
            switch self.state {
            case .idle(.client, localWindow: let localWindow, remoteWindow: let remoteWindow):
                let targetState: State
                let localContentLength = validateContentLength ? ContentLengthVerifier(headers) : .disabled

                if endStream {
                    try localContentLength.endOfStream()
                    targetState = .halfClosedLocalPeerIdle(remoteWindow: remoteWindow)
                } else {
                    targetState = .halfOpenLocalPeerIdle(localWindow: localWindow, localContentLength: localContentLength, remoteWindow: remoteWindow)
                }

                let targetEffect: StreamStateChange = .streamCreated(.init(streamID: self.streamID, localStreamWindowSize: Int(localWindow), remoteStreamWindowSize: Int(remoteWindow)))
                return self.processRequestHeaders(headers,
                                                  validateHeaderBlock: validateHeaderBlock,
                                                  targetState: targetState,
                                                  targetEffect: targetEffect)

            case .halfOpenRemoteLocalIdle(localWindow: let localWindow, remoteContentLength: let remoteContentLength, remoteWindow: let remoteWindow):
                let targetState: State
                let localContentLength = validateContentLength ? ContentLengthVerifier(headers) : .disabled

                if endStream {
                    try localContentLength.endOfStream()
                    targetState = .halfClosedLocalPeerActive(localRole: .server, initiatedBy: .client, remoteContentLength: remoteContentLength, remoteWindow: remoteWindow)
                } else {
                    targetState = .fullyOpen(localRole: .server, localContentLength: localContentLength, remoteContentLength: remoteContentLength, localWindow: localWindow, remoteWindow: remoteWindow)
                }

                return self.processResponseHeaders(headers,
                                                   validateHeaderBlock: validateHeaderBlock,
                                                   targetStateIfFinal: targetState,
                                                   targetEffectIfFinal: nil)

            case .halfOpenLocalPeerIdle(localWindow: _, localContentLength: let localContentLength, remoteWindow: let remoteWindow):
                try localContentLength.endOfStream()
                return self.processTrailers(headers,
                                            validateHeaderBlock: validateHeaderBlock,
                                            isEndStreamSet: endStream,
                                            targetState: .halfClosedLocalPeerIdle(remoteWindow: remoteWindow),
                                            targetEffect: nil)

            case .reservedLocal(let localWindow):
                let targetState: State
                let targetEffect: StreamStateChange
                let localContentLength = validateContentLength ? ContentLengthVerifier(headers) : .disabled

                if endStream {
                    try localContentLength.endOfStream()
                    targetState = .closed(reason: nil)
                    targetEffect = .streamCreatedAndClosed(.init(streamID: self.streamID))
                } else {
                    targetState = .halfClosedRemoteLocalActive(localRole: .server, initiatedBy: .server, localContentLength: localContentLength, localWindow: localWindow)
                    targetEffect = .streamCreated(.init(streamID: self.streamID, localStreamWindowSize: Int(localWindow), remoteStreamWindowSize: nil))
                }

                return self.processResponseHeaders(headers,
                                                   validateHeaderBlock: validateHeaderBlock,
                                                   targetStateIfFinal: targetState,
                                                   targetEffectIfFinal: targetEffect)

            case .fullyOpen(let localRole, localContentLength: let localContentLength, remoteContentLength: let remoteContentLength, localWindow: _, remoteWindow: let remoteWindow):
                try localContentLength.endOfStream()
                return self.processTrailers(headers,
                                            validateHeaderBlock: validateHeaderBlock,
                                            isEndStreamSet: endStream,
                                            targetState: .halfClosedLocalPeerActive(localRole: localRole, initiatedBy: .client, remoteContentLength: remoteContentLength, remoteWindow: remoteWindow),
                                            targetEffect: nil)

            case .halfClosedRemoteLocalIdle(let localWindow):
                let targetState: State
                let targetEffect: StreamStateChange?
                let localContentLength = validateContentLength ? ContentLengthVerifier(headers) : .disabled

                if endStream {
                    try localContentLength.endOfStream()
                    targetState = .closed(reason: nil)
                    targetEffect = .streamClosed(.init(streamID: self.streamID, reason: nil))
                } else {
                    targetState = .halfClosedRemoteLocalActive(localRole: .server, initiatedBy: .client, localContentLength: localContentLength, localWindow: localWindow)
                    targetEffect = nil
                }
                return self.processResponseHeaders(headers,
                                                   validateHeaderBlock: validateHeaderBlock,
                                                   targetStateIfFinal: targetState,
                                                   targetEffectIfFinal: targetEffect)

            case .halfClosedRemoteLocalActive(localRole: _, initiatedBy: _, localContentLength: let localContentLength, localWindow: _):
                try localContentLength.endOfStream()
                return self.processTrailers(headers,
                                            validateHeaderBlock: validateHeaderBlock,
                                            isEndStreamSet: endStream,
                                            targetState: .closed(reason: nil),
                                            targetEffect: .streamClosed(.init(streamID: self.streamID, reason: nil)))

            // Sending a HEADERS frame as an idle server, or on a closed stream, is a connection error
            // of type PROTOCOL_ERROR. In any other state, sending a HEADERS frame is a stream error of
            // type PROTOCOL_ERROR.
            // (Authors note: I can find nothing in the RFC that actually states what kind of error is
            // triggered for HEADERS frames outside the valid states. So I just guessed here based on what
            // seems reasonable to me: specifically, if we have a stream to fail, fail it, otherwise treat
            // the error as connection scoped.)
            case .idle(.server, _, _), .closed:
                return .init(result: .connectionError(underlyingError: NIOHTTP2Errors.BadStreamStateTransition(), type: .protocolError), effect: nil)
            case .reservedRemote, .halfClosedLocalPeerIdle, .halfClosedLocalPeerActive:
                return .init(result: .streamError(streamID: self.streamID, underlyingError: NIOHTTP2Errors.BadStreamStateTransition(), type: .protocolError), effect: nil)
            }
        } catch let error where error is NIOHTTP2Errors.ContentLengthViolated {
            return .init(result: .streamError(streamID: self.streamID, underlyingError: error, type: .protocolError), effect: nil)
        } catch {
            preconditionFailure("Unexpected error: \(error)")
        }
    }

    mutating func receiveHeaders(headers: HPACKHeaders, validateHeaderBlock: Bool, validateContentLength: Bool, isEndStreamSet endStream: Bool) -> StateMachineResultWithStreamEffect {
        do {
            // We can receive headers in the following states:
            //
            // - idle, when we are a server, in which case we are receiving request headers
            // - halfOpenLocalPeerIdle, in which case we are receiving either informational or final response headers
            // - halfOpenRemoteLocalIdle, in which case we are receiving trailers
            // - reservedRemote, in which case we are a client receiving either informational or final response headers
            // - fullyOpen, in which case we are receiving trailers
            // - halfClosedLocalPeerIdle, in which case we are receiving either informational or final headers
            //     (see the comment on halfClosedLocalPeerIdle for more)
            // - halfClosedLocalPeerActive, in which case we are receiving trailers
            //
            // In idle or reservedRemote we are opening the stream. In reservedRemote, halfClosedLocalPeerIdle, or halfClosedLocalPeerActive
            // we may be closing the stream. The keen-eyed may notice that reservedLocal may both open *and* close a stream. This is a bit awkward
            // for us, and requires a separate event.
            switch self.state {
            case .idle(.server, localWindow: let localWindow, remoteWindow: let remoteWindow):
                let targetState: State
                let remoteContentLength = validateContentLength ? ContentLengthVerifier(headers) : .disabled

                if endStream {
                    try remoteContentLength.endOfStream()
                    targetState = .halfClosedRemoteLocalIdle(localWindow: localWindow)
                } else {
                    targetState = .halfOpenRemoteLocalIdle(localWindow: localWindow, remoteContentLength: remoteContentLength, remoteWindow: remoteWindow)
                }

                let targetEffect: StreamStateChange = .streamCreated(.init(streamID: self.streamID, localStreamWindowSize: Int(localWindow), remoteStreamWindowSize: Int(remoteWindow)))
                return self.processRequestHeaders(headers,
                                                  validateHeaderBlock: validateHeaderBlock,
                                                  targetState: targetState,
                                                  targetEffect: targetEffect)

            case .halfOpenLocalPeerIdle(localWindow: let localWindow, localContentLength: let localContentLength, remoteWindow: let remoteWindow):
                let targetState: State
                let remoteContentLength = validateContentLength ? ContentLengthVerifier(headers) : .disabled

                if endStream {
                    try remoteContentLength.endOfStream()
                    targetState = .halfClosedRemoteLocalActive(localRole: .client, initiatedBy: .client, localContentLength: localContentLength, localWindow: localWindow)
                } else {
                    targetState = .fullyOpen(localRole: .client, localContentLength: localContentLength, remoteContentLength: remoteContentLength, localWindow: localWindow, remoteWindow: remoteWindow)
                }

                return self.processResponseHeaders(headers,
                                                   validateHeaderBlock: validateHeaderBlock,
                                                   targetStateIfFinal: targetState,
                                                   targetEffectIfFinal: nil)

            case .halfOpenRemoteLocalIdle(localWindow: let localWindow, remoteContentLength: let remoteContentLength, remoteWindow: _):
                try remoteContentLength.endOfStream()
                return self.processTrailers(headers,
                                            validateHeaderBlock: validateHeaderBlock,
                                            isEndStreamSet: endStream,
                                            targetState: .halfClosedRemoteLocalIdle(localWindow: localWindow),
                                            targetEffect: nil)

            case .reservedRemote(let remoteWindow):
                let targetState: State
                let targetEffect: StreamStateChange
                let remoteContentLength = validateContentLength ? ContentLengthVerifier(headers) : .disabled

                if endStream {
                    try remoteContentLength.endOfStream()
                    targetState = .closed(reason: nil)
                    targetEffect = .streamCreatedAndClosed(.init(streamID: self.streamID))
                } else {
                    targetState = .halfClosedLocalPeerActive(localRole: .client, initiatedBy: .server, remoteContentLength: remoteContentLength, remoteWindow: remoteWindow)
                    targetEffect = .streamCreated(.init(streamID: self.streamID, localStreamWindowSize: nil, remoteStreamWindowSize: Int(remoteWindow)))
                }

                return self.processResponseHeaders(headers,
                                                   validateHeaderBlock: validateHeaderBlock,
                                                   targetStateIfFinal: targetState,
                                                   targetEffectIfFinal: targetEffect)

            case .fullyOpen(let localRole, localContentLength: let localContentLength, remoteContentLength: let remoteContentLength, localWindow: let localWindow, remoteWindow: _):
                try remoteContentLength.endOfStream()
                return self.processTrailers(headers,
                                            validateHeaderBlock: validateHeaderBlock,
                                            isEndStreamSet: endStream,
                                            targetState: .halfClosedRemoteLocalActive(localRole: localRole, initiatedBy: .client, localContentLength: localContentLength, localWindow: localWindow),
                                            targetEffect: nil)

            case .halfClosedLocalPeerIdle(let remoteWindow):
                let targetState: State
                let targetEffect: StreamStateChange?
                let remoteContentLength = validateContentLength ? ContentLengthVerifier(headers) : .disabled

                if endStream {
                    try remoteContentLength.endOfStream()
                    targetState = .closed(reason: nil)
                    targetEffect = .streamClosed(.init(streamID: self.streamID, reason: nil))
                } else {
                    targetState = .halfClosedLocalPeerActive(localRole: .client, initiatedBy: .client, remoteContentLength: remoteContentLength, remoteWindow: remoteWindow)
                    targetEffect = nil
                }

                return self.processResponseHeaders(headers,
                                                   validateHeaderBlock: validateHeaderBlock,
                                                   targetStateIfFinal: targetState,
                                                   targetEffectIfFinal: targetEffect)

            case .halfClosedLocalPeerActive(localRole: _, initiatedBy: _, remoteContentLength: let remoteContentLength, remoteWindow: _):
                try remoteContentLength.endOfStream()
                return self.processTrailers(headers,
                                            validateHeaderBlock: validateHeaderBlock,
                                            isEndStreamSet: endStream,
                                            targetState: .closed(reason: nil),
                                            targetEffect: .streamClosed(.init(streamID: self.streamID, reason: nil)))

            // Receiving a HEADERS frame as an idle client, or on a closed stream, is a connection error
            // of type PROTOCOL_ERROR. In any other state, receiving a HEADERS frame is a stream error of
            // type PROTOCOL_ERROR.
            // (Authors note: I can find nothing in the RFC that actually states what kind of error is
            // triggered for HEADERS frames outside the valid states. So I just guessed here based on what
            // seems reasonable to me: specifically, if we have a stream to fail, fail it, otherwise treat
            // the error as connection scoped.)
            case .idle(.client, _, _), .closed:
                return .init(result: .connectionError(underlyingError: NIOHTTP2Errors.BadStreamStateTransition(), type: .protocolError), effect: nil)
            case .reservedLocal, .halfClosedRemoteLocalIdle, .halfClosedRemoteLocalActive:
                return .init(result: .streamError(streamID: self.streamID, underlyingError: NIOHTTP2Errors.BadStreamStateTransition(), type: .protocolError), effect: nil)
            }
        } catch let error where error is NIOHTTP2Errors.ContentLengthViolated {
            return .init(result: .streamError(streamID: self.streamID, underlyingError: error, type: .protocolError), effect: nil)
        } catch {
            preconditionFailure("Unexpected error: \(error)")
        }
    }

    mutating func sendData(contentLength: Int, flowControlledBytes: Int, isEndStreamSet endStream: Bool) -> StateMachineResultWithStreamEffect {
        do {
            // We can send DATA frames in the following states:
            //
            // - halfOpenLocalPeerIdle, in which case we are a client sending request data before the server
            //     has sent its final response headers.
            // - fullyOpen, where we could be either a client or a server using a fully bi-directional stream.
            // - halfClosedRemoteLocalActive, where the remote peer has completed its data, but we have more to send.
            //
            // Valid data frames always have a stream effect, because they consume flow control windows.
            switch self.state {
            case .halfOpenLocalPeerIdle(localWindow: var localWindow, localContentLength: var localContentLength, remoteWindow: let remoteWindow):
                try localWindow.consume(flowControlledBytes: flowControlledBytes)
                try localContentLength.receivedDataChunk(length: contentLength)

                let effect: StreamStateChange
                if endStream {
                    try localContentLength.endOfStream()
                    self.state = .halfClosedLocalPeerIdle(remoteWindow: remoteWindow)
                    effect = .windowSizeChange(.init(streamID: self.streamID, localStreamWindowSize: nil, remoteStreamWindowSize: Int(remoteWindow)))
                } else {
                    self.state = .halfOpenLocalPeerIdle(localWindow: localWindow, localContentLength: localContentLength, remoteWindow: remoteWindow)
                    effect = .windowSizeChange(.init(streamID: self.streamID, localStreamWindowSize: Int(localWindow), remoteStreamWindowSize: Int(remoteWindow)))
                }

                return .init(result: .succeed, effect: effect)

            case .fullyOpen(let localRole, localContentLength: var localContentLength, remoteContentLength: let remoteContentLength, localWindow: var localWindow, remoteWindow: let remoteWindow):
                try localWindow.consume(flowControlledBytes: flowControlledBytes)
                try localContentLength.receivedDataChunk(length: contentLength)

                let effect: StreamStateChange = .windowSizeChange(.init(streamID: self.streamID, localStreamWindowSize: Int(localWindow), remoteStreamWindowSize: Int(remoteWindow)))

                if endStream {
                    try localContentLength.endOfStream()
                    self.state = .halfClosedLocalPeerActive(localRole: localRole, initiatedBy: .client, remoteContentLength: remoteContentLength, remoteWindow: remoteWindow)
                } else {
                    self.state = .fullyOpen(localRole: localRole, localContentLength: localContentLength, remoteContentLength: remoteContentLength, localWindow: localWindow, remoteWindow: remoteWindow)
                }

                return .init(result: .succeed, effect: effect)

            case .halfClosedRemoteLocalActive(let localRole, let initiatedBy, var localContentLength, var localWindow):
                try localWindow.consume(flowControlledBytes: flowControlledBytes)
                try localContentLength.receivedDataChunk(length: contentLength)

                let effect: StreamStateChange
                if endStream {
                    try localContentLength.endOfStream()
                    self.state = .closed(reason: nil)
                    effect = .streamClosed(.init(streamID: self.streamID, reason: nil))
                } else {
                    self.state = .halfClosedRemoteLocalActive(localRole: localRole, initiatedBy: initiatedBy, localContentLength: localContentLength, localWindow: localWindow)
                    effect = .windowSizeChange(.init(streamID: self.streamID, localStreamWindowSize: Int(localWindow), remoteStreamWindowSize: nil))
                }

                return .init(result: .succeed, effect: effect)

            // Sending a DATA frame outside any of these states is a stream error of type STREAM_CLOSED (RFC7540 § 6.1)
            case .idle, .halfOpenRemoteLocalIdle, .reservedLocal, .reservedRemote, .halfClosedLocalPeerIdle,
                 .halfClosedLocalPeerActive, .halfClosedRemoteLocalIdle, .closed:
                return .init(result: .streamError(streamID: self.streamID, underlyingError: NIOHTTP2Errors.BadStreamStateTransition(), type: .streamClosed), effect: nil)
            }
        } catch let error where error is NIOHTTP2Errors.FlowControlViolation {
            return .init(result: .streamError(streamID: self.streamID, underlyingError: error, type: .flowControlError), effect: nil)
        } catch let error where error is NIOHTTP2Errors.ContentLengthViolated {
            return .init(result: .streamError(streamID: self.streamID, underlyingError: error, type: .protocolError), effect: nil)
        } catch {
            preconditionFailure("Unexpected error: \(error)")
        }
    }

    mutating func receiveData(contentLength: Int, flowControlledBytes: Int, isEndStreamSet endStream: Bool) -> StateMachineResultWithStreamEffect {
        do {
            // We can receive DATA frames in the following states:
            //
            // - halfOpenRemoteLocalIdle, in which case we are a server receiving request data before we have
            //     sent our final response headers.
            // - fullyOpen, where we could be either a client or a server using a fully bi-directional stream.
            // - halfClosedLocalPeerActive, whe have completed our data, but the remote peer has more to send.
            switch self.state {
            case .halfOpenRemoteLocalIdle(localWindow: let localWindow, remoteContentLength: var remoteContentLength, remoteWindow: var remoteWindow):
                try remoteWindow.consume(flowControlledBytes: flowControlledBytes)
                try remoteContentLength.receivedDataChunk(length: contentLength)

                let effect: StreamStateChange
                if endStream {
                    try remoteContentLength.endOfStream()
                    self.state = .halfClosedRemoteLocalIdle(localWindow: localWindow)
                    effect = .windowSizeChange(.init(streamID: self.streamID, localStreamWindowSize: Int(localWindow), remoteStreamWindowSize: nil))
                } else {
                    self.state = .halfOpenRemoteLocalIdle(localWindow: localWindow, remoteContentLength: remoteContentLength, remoteWindow: remoteWindow)
                    effect = .windowSizeChange(.init(streamID: self.streamID, localStreamWindowSize: Int(localWindow), remoteStreamWindowSize: Int(remoteWindow)))
                }

                return .init(result: .succeed, effect: effect)

            case .fullyOpen(let localRole, localContentLength: let localContentLength, remoteContentLength: var remoteContentLength, localWindow: let localWindow, remoteWindow: var remoteWindow):
                try remoteWindow.consume(flowControlledBytes: flowControlledBytes)
                try remoteContentLength.receivedDataChunk(length: contentLength)

                let effect: StreamStateChange
                if endStream {
                    try remoteContentLength.endOfStream()
                    self.state = .halfClosedRemoteLocalActive(localRole: localRole, initiatedBy: .client, localContentLength: localContentLength, localWindow: localWindow)
                    effect = .windowSizeChange(.init(streamID: self.streamID, localStreamWindowSize: Int(localWindow), remoteStreamWindowSize: nil))
                } else {
                    self.state = .fullyOpen(localRole: localRole, localContentLength: localContentLength, remoteContentLength: remoteContentLength, localWindow: localWindow, remoteWindow: remoteWindow)
                    effect = .windowSizeChange(.init(streamID: self.streamID, localStreamWindowSize: Int(localWindow), remoteStreamWindowSize: Int(remoteWindow)))
                }

                return .init(result: .succeed, effect: effect)

            case .halfClosedLocalPeerActive(let localRole, let initiatedBy, var remoteContentLength, var remoteWindow):
                try remoteWindow.consume(flowControlledBytes: flowControlledBytes)
                try remoteContentLength.receivedDataChunk(length: contentLength)

                let effect: StreamStateChange
                if endStream {
                    try remoteContentLength.endOfStream()
                    self.state = .closed(reason: nil)
                    effect = .streamClosed(.init(streamID: self.streamID, reason: nil))
                } else {
                    self.state = .halfClosedLocalPeerActive(localRole: localRole, initiatedBy: initiatedBy, remoteContentLength: remoteContentLength, remoteWindow: remoteWindow)
                    effect = .windowSizeChange(.init(streamID: self.streamID, localStreamWindowSize: nil, remoteStreamWindowSize: Int(remoteWindow)))
                }

                return .init(result: .succeed, effect: effect)

            // Receiving a DATA frame outside any of these states is a stream error of type STREAM_CLOSED (RFC7540 § 6.1)
            case .idle, .halfOpenLocalPeerIdle, .reservedLocal, .reservedRemote, .halfClosedLocalPeerIdle,
                 .halfClosedRemoteLocalActive, .halfClosedRemoteLocalIdle, .closed:
                return .init(result: .streamError(streamID: self.streamID, underlyingError: NIOHTTP2Errors.BadStreamStateTransition(), type: .streamClosed), effect: nil)
            }
        } catch let error where error is NIOHTTP2Errors.FlowControlViolation {
            return .init(result: .streamError(streamID: self.streamID, underlyingError: error, type: .flowControlError), effect: nil)
        } catch let error where error is NIOHTTP2Errors.ContentLengthViolated {
            return .init(result: .streamError(streamID: self.streamID, underlyingError: error, type: .protocolError), effect: nil)
        } catch {
            preconditionFailure("Unexpected error: \(error)")
        }
    }

    mutating func sendPushPromise(headers: HPACKHeaders, validateHeaderBlock: Bool) -> StateMachineResultWithStreamEffect {
        // We can send PUSH_PROMISE frames in the following states:
        //
        // - fullyOpen when we are a server. In this case we assert that the stream was initiated by the client.
        // - halfOpenRemoteLocalIdle, which only servers can enter on streams initiated by clients.
        // - halfClosedRemoteLocalIdle, which only servers can enter on streams initiated by clients.
        // - halfClosedRemoteLocalActive, when we are a server, and when the stream was initiated by the client.
        //
        // RFC 7540 § 6.6 forbids sending PUSH_PROMISE frames on locally-initiated streams.
        //
        // PUSH_PROMISE frames never have stream effects: they cannot create or close streams, or affect flow control state.
        switch self.state {
        case .fullyOpen(localRole: .server, localContentLength: _, remoteContentLength: _, localWindow: _, remoteWindow: _),
             .halfOpenRemoteLocalIdle(localWindow: _, remoteContentLength: _, remoteWindow: _),
             .halfClosedRemoteLocalIdle(localWindow: _),
             .halfClosedRemoteLocalActive(localRole: .server, initiatedBy: .client, localContentLength: _, localWindow: _):
            return self.processRequestHeaders(headers, validateHeaderBlock: validateHeaderBlock, targetState: self.state, targetEffect: nil)

        // Sending a PUSH_PROMISE frame outside any of these states is a stream error of type PROTOCOL_ERROR.
        // Authors note: I cannot find a citation for this in RFC 7540, but this seems a sensible choice.
        case .idle, .reservedLocal, .reservedRemote, .halfClosedLocalPeerIdle, .halfClosedLocalPeerActive,
             .halfOpenLocalPeerIdle, .closed,
             .fullyOpen(localRole: .client, localContentLength: _, remoteContentLength: _, localWindow: _, remoteWindow: _),
             .halfClosedRemoteLocalActive(localRole: .client, initiatedBy: _, localContentLength: _, localWindow: _),
             .halfClosedRemoteLocalActive(localRole: .server, initiatedBy: .server, localContentLength: _, localWindow: _):
            return .init(result: .streamError(streamID: self.streamID, underlyingError: NIOHTTP2Errors.BadStreamStateTransition(), type: .protocolError), effect: nil)
        }
    }

    mutating func receivePushPromise(headers: HPACKHeaders, validateHeaderBlock: Bool) -> StateMachineResultWithStreamEffect {
        // We can receive PUSH_PROMISE frames in the following states:
        //
        // - fullyOpen when we are a client. In this case we assert that the stream was initiated by us.
        // - halfOpenLocalPeerIdle, which only clients can enter on streams they initiated.
        // - halfClosedLocalPeerIdle, which only clients can enter on streams they initiated.
        // - halfClosedLocalPeerActive, when we are a client, and when the stream was initiated by us.
        //
        // RFC 7540 § 6.6 forbids receiving PUSH_PROMISE frames on remotely-initiated streams.
        switch self.state {
        case .fullyOpen(localRole: .client, localContentLength: _, remoteContentLength: _, localWindow: _, remoteWindow: _),
             .halfOpenLocalPeerIdle(localWindow: _, localContentLength: _, remoteWindow: _),
             .halfClosedLocalPeerIdle(remoteWindow: _),
             .halfClosedLocalPeerActive(localRole: .client, initiatedBy: .client, remoteContentLength: _, remoteWindow: _):
            return self.processRequestHeaders(headers, validateHeaderBlock: validateHeaderBlock, targetState: self.state, targetEffect: nil)

        // Receiving a PUSH_PROMISE frame outside any of these states is a stream error of type PROTOCOL_ERROR.
        // Authors note: I cannot find a citation for this in RFC 7540, but this seems a sensible choice.
        case .idle, .reservedLocal, .reservedRemote, .halfClosedRemoteLocalIdle,
             .halfClosedRemoteLocalActive, .halfOpenRemoteLocalIdle, .closed,
             .fullyOpen(localRole: .server, localContentLength: _, remoteContentLength: _, localWindow: _, remoteWindow: _),
             .halfClosedLocalPeerActive(localRole: .server, initiatedBy: _, remoteContentLength: _, remoteWindow: _),
             .halfClosedLocalPeerActive(localRole: .client, initiatedBy: .server, remoteContentLength: _, remoteWindow: _):
            return .init(result: .streamError(streamID: self.streamID, underlyingError: NIOHTTP2Errors.BadStreamStateTransition(), type: .protocolError), effect: nil)
        }
    }

    mutating func sendWindowUpdate(windowIncrement: UInt32) -> StateMachineResultWithStreamEffect {
        let windowEffect: StreamStateChange

        do {
            // RFC 7540 does not limit the states in which WINDOW_UDPATE frames can be sent. For this reason we need to be
            // fairly conservative about applying limits. In essence, we allow sending WINDOW_UPDATE frames in all but the
            // following states:
            //
            // - idle, because the stream hasn't been created yet so the stream ID is invalid
            // - reservedLocal, because the remote peer will never be able to send data
            // - halfClosedRemoteLocalIdle and halfClosedRemoteLocalActive, because the remote peer has sent END_STREAM and
            //     can send no further data
            // - closed, because the entire stream is closed now
            switch self.state {
            case .reservedRemote(remoteWindow: var remoteWindow):
                try remoteWindow.windowUpdate(by: windowIncrement)
                self.state = .reservedRemote(remoteWindow: remoteWindow)
                windowEffect = .windowSizeChange(.init(streamID: self.streamID, localStreamWindowSize: nil, remoteStreamWindowSize: Int(remoteWindow)))

            case .halfOpenLocalPeerIdle(localWindow: let localWindow, localContentLength: let localContentLength, remoteWindow: var remoteWindow):
                try remoteWindow.windowUpdate(by: windowIncrement)
                self.state = .halfOpenLocalPeerIdle(localWindow: localWindow, localContentLength: localContentLength, remoteWindow: remoteWindow)
                windowEffect = .windowSizeChange(.init(streamID: self.streamID, localStreamWindowSize: Int(localWindow), remoteStreamWindowSize: Int(remoteWindow)))

            case .halfOpenRemoteLocalIdle(localWindow: let localWindow, remoteContentLength: let remoteContentLength, remoteWindow: var remoteWindow):
                try remoteWindow.windowUpdate(by: windowIncrement)
                self.state = .halfOpenRemoteLocalIdle(localWindow: localWindow, remoteContentLength: remoteContentLength, remoteWindow: remoteWindow)
                windowEffect = .windowSizeChange(.init(streamID: self.streamID, localStreamWindowSize: Int(localWindow), remoteStreamWindowSize: Int(remoteWindow)))

            case .fullyOpen(localRole: let localRole, localContentLength: let localContentLength, remoteContentLength: let remoteContentLength, localWindow: let localWindow, remoteWindow: var remoteWindow):
                try remoteWindow.windowUpdate(by: windowIncrement)
                self.state = .fullyOpen(localRole: localRole, localContentLength: localContentLength, remoteContentLength: remoteContentLength, localWindow: localWindow, remoteWindow: remoteWindow)
                windowEffect = .windowSizeChange(.init(streamID: self.streamID, localStreamWindowSize: Int(localWindow), remoteStreamWindowSize: Int(remoteWindow)))

            case .halfClosedLocalPeerIdle(remoteWindow: var remoteWindow):
                try remoteWindow.windowUpdate(by: windowIncrement)
                self.state = .halfClosedLocalPeerIdle(remoteWindow: remoteWindow)
                windowEffect = .windowSizeChange(.init(streamID: self.streamID, localStreamWindowSize: nil, remoteStreamWindowSize: Int(remoteWindow)))

            case .halfClosedLocalPeerActive(localRole: let localRole, initiatedBy: let initiatedBy, remoteContentLength: let remoteContentLength, remoteWindow: var remoteWindow):
                try remoteWindow.windowUpdate(by: windowIncrement)
                self.state = .halfClosedLocalPeerActive(localRole: localRole, initiatedBy: initiatedBy, remoteContentLength: remoteContentLength, remoteWindow: remoteWindow)
                windowEffect = .windowSizeChange(.init(streamID: self.streamID, localStreamWindowSize: nil, remoteStreamWindowSize: Int(remoteWindow)))

            case .idle, .reservedLocal, .halfClosedRemoteLocalIdle, .halfClosedRemoteLocalActive, .closed:
                return .init(result: .streamError(streamID: self.streamID, underlyingError: NIOHTTP2Errors.BadStreamStateTransition(), type: .protocolError), effect: nil)
            }
        } catch let error where error is NIOHTTP2Errors.InvalidFlowControlWindowSize {
            return .init(result: .streamError(streamID: self.streamID, underlyingError: error, type: .flowControlError), effect: nil)
        } catch let error where error is NIOHTTP2Errors.InvalidWindowIncrementSize {
            return .init(result: .streamError(streamID: self.streamID, underlyingError: error, type: .protocolError), effect: nil)
        } catch {
            preconditionFailure("Unexpected error: \(error)")
        }

        return .init(result: .succeed, effect: windowEffect)
    }

    mutating func receiveWindowUpdate(windowIncrement: UInt32) -> StateMachineResultWithStreamEffect {
        let windowEffect: StreamStateChange?

        do {
            // RFC 7540 does not limit the states in which WINDOW_UDPATE frames can be received. For this reason we need to be
            // fairly conservative about applying limits. In essence, we allow receiving WINDOW_UPDATE frames in all but the
            // following states:
            //
            // - idle, because the stream hasn't been created yet so the stream ID is invalid
            // - reservedRemote, because we will never be able to send data so it's silly to manipulate our flow control window
            // - closed, because the entire stream is closed now
            //
            // Note that, unlike with sending, we allow receiving window update frames when we are half-closed. This is because
            // it is possible that those frames may have been in flight when we were closing the stream, and so we shouldn't cause
            // the stream to explode simply for that reason. In this case, we just ignore the data.
            switch self.state {
            case .reservedLocal(localWindow: var localWindow):
                try localWindow.windowUpdate(by: windowIncrement)
                self.state = .reservedLocal(localWindow: localWindow)
                windowEffect = .windowSizeChange(.init(streamID: self.streamID, localStreamWindowSize: Int(localWindow), remoteStreamWindowSize: nil))

            case .halfOpenLocalPeerIdle(localWindow: var localWindow, localContentLength: let localContentLength, remoteWindow: let remoteWindow):
                try localWindow.windowUpdate(by: windowIncrement)
                self.state = .halfOpenLocalPeerIdle(localWindow: localWindow, localContentLength: localContentLength, remoteWindow: remoteWindow)
                windowEffect = .windowSizeChange(.init(streamID: self.streamID, localStreamWindowSize: Int(localWindow), remoteStreamWindowSize: Int(remoteWindow)))

            case .halfOpenRemoteLocalIdle(localWindow: var localWindow, remoteContentLength: let remoteContentLength, remoteWindow: let remoteWindow):
                try localWindow.windowUpdate(by: windowIncrement)
                self.state = .halfOpenRemoteLocalIdle(localWindow: localWindow, remoteContentLength: remoteContentLength, remoteWindow: remoteWindow)
                windowEffect = .windowSizeChange(.init(streamID: self.streamID, localStreamWindowSize: Int(localWindow), remoteStreamWindowSize: Int(remoteWindow)))

            case .fullyOpen(localRole: let localRole, localContentLength: let localContentLength, remoteContentLength: let remoteContentLength, localWindow: var localWindow, remoteWindow: let remoteWindow):
                try localWindow.windowUpdate(by: windowIncrement)
                self.state = .fullyOpen(localRole: localRole, localContentLength: localContentLength, remoteContentLength: remoteContentLength, localWindow: localWindow, remoteWindow: remoteWindow)
                windowEffect = .windowSizeChange(.init(streamID: self.streamID, localStreamWindowSize: Int(localWindow), remoteStreamWindowSize: Int(remoteWindow)))

            case .halfClosedRemoteLocalIdle(localWindow: var localWindow):
                try localWindow.windowUpdate(by: windowIncrement)
                self.state = .halfClosedRemoteLocalIdle(localWindow: localWindow)
                windowEffect = .windowSizeChange(.init(streamID: self.streamID, localStreamWindowSize: Int(localWindow), remoteStreamWindowSize: nil))

            case .halfClosedRemoteLocalActive(localRole: let localRole, initiatedBy: let initiatedBy, localContentLength: let localContentLength, localWindow: var localWindow):
                try localWindow.windowUpdate(by: windowIncrement)
                self.state = .halfClosedRemoteLocalActive(localRole: localRole, initiatedBy: initiatedBy, localContentLength: localContentLength, localWindow: localWindow)
                windowEffect = .windowSizeChange(.init(streamID: self.streamID, localStreamWindowSize: Int(localWindow), remoteStreamWindowSize: nil))

            case .halfClosedLocalPeerIdle, .halfClosedLocalPeerActive:
                // No-op, see above
                windowEffect = nil

            case .idle, .reservedRemote, .closed:
                return .init(result: .streamError(streamID: self.streamID, underlyingError: NIOHTTP2Errors.BadStreamStateTransition(), type: .protocolError), effect: nil)
            }
        } catch let error where error is NIOHTTP2Errors.InvalidFlowControlWindowSize {
            return .init(result: .streamError(streamID: self.streamID, underlyingError: error, type: .flowControlError), effect: nil)
        } catch let error where error is NIOHTTP2Errors.InvalidWindowIncrementSize {
            return .init(result: .streamError(streamID: self.streamID, underlyingError: error, type: .protocolError), effect: nil)
        } catch {
            preconditionFailure("Unexpected error: \(error)")
        }

        return .init(result: .succeed, effect: windowEffect)
    }

    mutating func sendRstStream(reason: HTTP2ErrorCode) -> StateMachineResultWithStreamEffect {
        // We can send RST_STREAM frames in all states, including idle. We allow it in idle because errors may be occurred when receiving a stream opening
        // frame e.g. request headers.
        self.state = .closed(reason: reason)
        return .init(result: .succeed, effect: .streamClosed(.init(streamID: self.streamID, reason: reason)))
    }

    mutating func receiveRstStream(reason: HTTP2ErrorCode) -> StateMachineResultWithStreamEffect {
        // We can receive RST_STREAM frames in any state but idle.
        if case .idle = self.state {
            return .init(result: .connectionError(underlyingError: NIOHTTP2Errors.BadStreamStateTransition(), type: .protocolError), effect: nil)
        }

        self.state = .closed(reason: reason)
        return .init(result: .succeed, effect: .streamClosed(.init(streamID: self.streamID, reason: reason)))
    }

    /// The local value of SETTINGS_INITIAL_WINDOW_SIZE has been changed, and the change has been ACKed.
    ///
    /// This change causes the remote flow control window to be resized.
    mutating func localInitialWindowSizeChanged(by change: Int32) throws {
        switch self.state {
        case .idle(localRole: let role, localWindow: let localWindow, remoteWindow: var remoteWindow):
            try remoteWindow.initialSizeChanged(by: change)
            self.state = .idle(localRole: role, localWindow: localWindow, remoteWindow: remoteWindow)

        case .reservedRemote(remoteWindow: var remoteWindow):
            try remoteWindow.initialSizeChanged(by: change)
            self.state = .reservedRemote(remoteWindow: remoteWindow)

        case .halfOpenLocalPeerIdle(localWindow: let localWindow, localContentLength: let localContentLength, remoteWindow: var remoteWindow):
            try remoteWindow.initialSizeChanged(by: change)
            self.state = .halfOpenLocalPeerIdle(localWindow: localWindow, localContentLength: localContentLength, remoteWindow: remoteWindow)

        case .halfOpenRemoteLocalIdle(localWindow: let localWindow, remoteContentLength: let remoteContentLength, remoteWindow: var remoteWindow):
            try remoteWindow.initialSizeChanged(by: change)
            self.state = .halfOpenRemoteLocalIdle(localWindow: localWindow, remoteContentLength: remoteContentLength, remoteWindow: remoteWindow)

        case .fullyOpen(localRole: let localRole, localContentLength: let localContentLength, remoteContentLength: let remoteContentLength, localWindow: let localWindow, remoteWindow: var remoteWindow):
            try remoteWindow.initialSizeChanged(by: change)
            self.state = .fullyOpen(localRole: localRole, localContentLength: localContentLength, remoteContentLength: remoteContentLength, localWindow: localWindow, remoteWindow: remoteWindow)

        case .halfClosedLocalPeerIdle(remoteWindow: var remoteWindow):
            try remoteWindow.initialSizeChanged(by: change)
            self.state = .halfClosedLocalPeerIdle(remoteWindow: remoteWindow)

        case .halfClosedLocalPeerActive(localRole: let localRole, initiatedBy: let initiatedBy, remoteContentLength: let remoteContentLength, remoteWindow: var remoteWindow):
            try remoteWindow.initialSizeChanged(by: change)
            self.state = .halfClosedLocalPeerActive(localRole: localRole, initiatedBy: initiatedBy, remoteContentLength: remoteContentLength, remoteWindow: remoteWindow)

        case .reservedLocal, .halfClosedRemoteLocalIdle, .halfClosedRemoteLocalActive:
            // In these states the remote side of this stream is closed and will never be open, so its flow control window is not relevant.
            // This is a no-op.
            break

        case .closed:
            // This should never occur.
            preconditionFailure("Updated window of a closed stream.")
        }
    }

    /// The remote value of SETTINGS_INITIAL_WINDOW_SIZE has been changed.
    ///
    /// This change causes the local flow control window to be resized.
    mutating func remoteInitialWindowSizeChanged(by change: Int32) throws {
        switch self.state {
        case .idle(localRole: let role, localWindow: var localWindow, remoteWindow: let remoteWindow):
            try localWindow.initialSizeChanged(by: change)
            self.state = .idle(localRole: role, localWindow: localWindow, remoteWindow: remoteWindow)

        case .reservedLocal(localWindow: var localWindow):
            try localWindow.initialSizeChanged(by: change)
            self.state = .reservedLocal(localWindow: localWindow)

        case .halfOpenLocalPeerIdle(localWindow: var localWindow, localContentLength: let localContentLength, remoteWindow: let remoteWindow):
            try localWindow.initialSizeChanged(by: change)
            self.state = .halfOpenLocalPeerIdle(localWindow: localWindow, localContentLength: localContentLength, remoteWindow: remoteWindow)

        case .halfOpenRemoteLocalIdle(localWindow: var localWindow, remoteContentLength: let remoteContentLength, remoteWindow: let remoteWindow):
            try localWindow.initialSizeChanged(by: change)
            self.state = .halfOpenRemoteLocalIdle(localWindow: localWindow, remoteContentLength: remoteContentLength, remoteWindow: remoteWindow)

        case .fullyOpen(localRole: let localRole, localContentLength: let localContentLength, remoteContentLength: let remoteContentLength, localWindow: var localWindow, remoteWindow: let remoteWindow):
            try localWindow.initialSizeChanged(by: change)
            self.state = .fullyOpen(localRole: localRole, localContentLength: localContentLength, remoteContentLength: remoteContentLength, localWindow: localWindow, remoteWindow: remoteWindow)

        case .halfClosedRemoteLocalIdle(localWindow: var localWindow):
            try localWindow.initialSizeChanged(by: change)
            self.state = .halfClosedRemoteLocalIdle(localWindow: localWindow)

        case .halfClosedRemoteLocalActive(localRole: let localRole, initiatedBy: let initiatedBy, localContentLength: let localContentLength, localWindow: var localWindow):
            try localWindow.initialSizeChanged(by: change)
            self.state = .halfClosedRemoteLocalActive(localRole: localRole, initiatedBy: initiatedBy, localContentLength: localContentLength, localWindow: localWindow)

        case .reservedRemote, .halfClosedLocalPeerIdle, .halfClosedLocalPeerActive:
            // In these states the local side of this stream is closed and will never be open, so its flow control window is not relevant.
            // This is a no-op.
            break

        case .closed:
            // This should never occur.
            preconditionFailure("Updated window of a closed stream.")
        }
    }
}

// MARK:- Functions for handling headers frames.
extension HTTP2StreamStateMachine {
    /// Validate that the request headers meet the requirements of RFC 7540. If they do,
    /// transitions to the target state.
    private mutating func processRequestHeaders(_ headers: HPACKHeaders, validateHeaderBlock: Bool, targetState target: State, targetEffect effect: StreamStateChange?) -> StateMachineResultWithStreamEffect {
        if validateHeaderBlock {
            do {
                try headers.validateRequestBlock()
            } catch {
                return StateMachineResultWithStreamEffect(result: .streamError(streamID: self.streamID, underlyingError: error, type: .protocolError), effect: nil)
            }
        }

        self.state = target
        return StateMachineResultWithStreamEffect(result: .succeed, effect: effect)
    }

    /// Validate that the response headers meet the requirements of RFC 7540. Also characterises
    /// them to check whether the headers are informational or final, and if the headers are
    /// valid and correspond to a final response, transitions to the appropriate target state.
    private mutating func processResponseHeaders(_ headers: HPACKHeaders, validateHeaderBlock: Bool, targetStateIfFinal finalState: State, targetEffectIfFinal finalEffect: StreamStateChange?) -> StateMachineResultWithStreamEffect {
        if validateHeaderBlock {
            do {
                try headers.validateResponseBlock()
            } catch {
                return StateMachineResultWithStreamEffect(result: .streamError(streamID: self.streamID, underlyingError: error, type: .protocolError), effect: nil)
            }
        }

        // The barest minimum of functionality is to distinguish final and non-final headers, so we do that for now.
        if !headers.isInformationalResponse {
            // Non-informational responses cause state transitions.
            self.state = finalState
            return StateMachineResultWithStreamEffect(result: .succeed, effect: finalEffect)
        } else {
            return StateMachineResultWithStreamEffect(result: .succeed, effect: nil)
        }
    }

    /// Validates that the trailers meet the requirements of RFC 7540. If they do, transitions to the
    /// target final state.
    private mutating func processTrailers(_ headers: HPACKHeaders, validateHeaderBlock: Bool, isEndStreamSet endStream: Bool, targetState target: State, targetEffect effect: StreamStateChange?) -> StateMachineResultWithStreamEffect {
        if validateHeaderBlock {
            do {
                try headers.validateTrailersBlock()
            } catch {
                return StateMachineResultWithStreamEffect(result: .streamError(streamID: self.streamID, underlyingError: error, type: .protocolError), effect: nil)
            }
        }

        // End stream must be set on trailers.
        guard endStream else {
            return StateMachineResultWithStreamEffect(result: .streamError(streamID: self.streamID, underlyingError: NIOHTTP2Errors.TrailersWithoutEndStream(streamID: self.streamID), type: .protocolError), effect: nil)
        }

        self.state = target
        return StateMachineResultWithStreamEffect(result: .succeed, effect: effect)
    }
}


private extension HPACKHeaders {
    /// Whether this `HPACKHeaders` corresponds to a final response or not.
    ///
    /// This property is only valid if called on a response header block. If the :status header
    /// is not present, this will return "false"
    var isInformationalResponse: Bool {
        return self.first { $0.name == ":status" }?.value.first == "1"
    }
}
