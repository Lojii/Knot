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

// FIXME(jim): Need to improve the buffering behavior so we're not manually copying every byte we see.
fileprivate protocol BytesAccumulating {
    mutating func accumulate(bytes: inout ByteBuffer)
}

/// Ingests HTTP/2 data and produces frames. You feed data in, and sometimes you'll get a complete frame out.
struct HTTP2FrameDecoder {

    private static let clientMagicBytes = Array("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n".utf8)

    /// The result of a pass through the decoder state machine.
    private enum ParseResult {
        case needMoreData
        case `continue`
        case frame(HTTP2Frame, flowControlledLength: Int)
    }

    private struct IgnoredFrame: Error {}

    /// The state for a parser that is waiting for the client magic.
    private struct ClientMagicState: BytesAccumulating {
        var pendingBytes: ByteBuffer! = nil

        mutating func accumulate(bytes: inout ByteBuffer) {
            guard var pendingBytes = self.pendingBytes else {
                // Take a copy of the pending bytes, consume them.
                self.pendingBytes = bytes
                bytes.moveReaderIndex(to: bytes.writerIndex)
                return
            }
            _ = pendingBytes.writeBuffer(&bytes)
            self.pendingBytes = pendingBytes
        }
    }

    /// The state for a parser that is currently accumulating the bytes of a frame header.
    private struct AccumulatingFrameHeaderParserState: BytesAccumulating {
        var unusedBytes: ByteBuffer

        init(unusedBytes: ByteBuffer) {
            self.unusedBytes = unusedBytes
            if self.unusedBytes.readableBytes == 0 {
                // if it's an empty buffer, reset the read/write indices so the read/write indices
                // don't just race each other & cause many many reallocations and larger allocations
                self.unusedBytes.quietlyReset()
            }
        }

        mutating func accumulate(bytes: inout ByteBuffer) {
            _ = self.unusedBytes.writeBuffer(&bytes)
        }
    }

    /// The state for a parser that is currently accumulating payload data associated with
    /// a successfully decoded frame header.
    private struct AccumulatingPayloadParserState: BytesAccumulating {
        var header: FrameHeader
        var accumulatedBytes: ByteBuffer

        init(fromIdle state: AccumulatingFrameHeaderParserState, header: FrameHeader) {
            self.header = header
            self.accumulatedBytes = state.unusedBytes
        }

        mutating func accumulate(bytes: inout ByteBuffer) {
            self.accumulatedBytes.writeBuffer(&bytes)
        }
    }

    /// The state for a parser that is currently emitting simulated DATA frames.
    ///
    /// In this state we are receiving bytes associated with a DATA frame. We have
    /// read the header successfully and, instead of accumulating all the payload bytes
    /// and emitting the single monolithic DATA frame sent by our peer, we instead emit
    /// one DATA frame for each payload chunk we receive from the networking stack. This
    /// allows us to make use of the existing `ByteBuffer`s allocated by the stack,
    /// and lets us avoid compiling a large buffer in our own memory. Note that it's
    /// entirely plausible for a 20MB payload to be split into four 5MB DATA frames,
    /// such that the client of this library will already be accumulating them into
    /// some form of buffer or file. Our breaking this into (say) twenty 1MB DATA
    /// frames will not affect that, and will avoid additional allocations and copies
    /// in the meantime.
    ///
    /// This object is also responsible for ensuring we correctly manage flow control
    /// for DATA frames. It does this by notifying the state machine up front of the
    /// total flow controlled size of the underlying frame, even if it is synthesising
    /// partial frames. All subsequent partial frames have a flow controlled length of
    /// zero. This ensures that the upper layer can correctly enforce flow control
    /// windows.
    private struct SimulatingDataFramesParserState: BytesAccumulating {
        var header: FrameHeader
        var payload: ByteBuffer
        let expectedPadding: UInt8
        var remainingByteCount: Int
        private var _flowControlledLength: Int

        init(fromIdle state: AccumulatingFrameHeaderParserState, header: FrameHeader, expectedPadding: UInt8, remainingBytes: Int) {
            self.header = header
            self.payload = state.unusedBytes
            self.expectedPadding = expectedPadding
            self.remainingByteCount = remainingBytes
            self._flowControlledLength = header.length
        }

        init(fromAccumulatingPayload state: AccumulatingPayloadParserState, expectedPadding: UInt8, remainingBytes: Int) {
            self.header = state.header
            self.payload = state.accumulatedBytes
            self.expectedPadding = expectedPadding
            self.remainingByteCount = remainingBytes
            self._flowControlledLength = state.header.length
        }

        mutating func accumulate(bytes: inout ByteBuffer) {
            self.payload.writeBuffer(&bytes)
        }

        /// Obtains the flow controlled length, and sets it to zero for the rest of this DATA
        /// frame.
        mutating func flowControlledLength() -> Int {
            defer {
                self._flowControlledLength = 0
            }
            return self._flowControlledLength
        }
    }

    /// The state for a parser that is accumulating the payload of a CONTINUATION frame.
    ///
    /// The CONTINUATION frame must follow from an existing HEADERS or PUSH_PROMISE frame,
    /// whose details are kept in this state.
    private struct AccumulatingContinuationPayloadParserState: BytesAccumulating {
//        var headerBlockState: AccumulatingHeaderBlockFragmentsParserState
        let initialHeader: FrameHeader
        let continuationHeader: FrameHeader
        let currentFrameBytes: ByteBuffer

        var continuationPayload: ByteBuffer

        init(fromAccumulatingHeaderBlockFragments acc: AccumulatingHeaderBlockFragmentsParserState,
             continuationHeader: FrameHeader) {
            self.initialHeader = acc.header
            self.continuationHeader = continuationHeader
            self.currentFrameBytes = acc.accumulatedPayload
            self.continuationPayload = acc.incomingPayload
        }

        mutating func accumulate(bytes: inout ByteBuffer) {
            self.continuationPayload.writeBuffer(&bytes)
        }
    }

    /// This state is accumulating the various CONTINUATION frames into a single HEADERS or
    /// PUSH_PROMISE frame.
    ///
    /// The `incomingPayload` member holds any bytes from a following frame that haven't yet
    /// accumulated enough to parse the next frame and move to the next state.
    private struct AccumulatingHeaderBlockFragmentsParserState: BytesAccumulating {
        var header: FrameHeader
        var accumulatedPayload: ByteBuffer
        var incomingPayload: ByteBuffer

        init(fromAccumulatingPayload acc: AccumulatingPayloadParserState, initialPayload: ByteBuffer) {
            self.header = acc.header
            self.accumulatedPayload = initialPayload
            self.incomingPayload = acc.accumulatedBytes
        }

        init(fromAccumulatingContinuation acc: AccumulatingContinuationPayloadParserState) {
            precondition(acc.continuationPayload.readableBytes >= acc.continuationHeader.length)

            self.header = acc.initialHeader
            self.header.length += acc.continuationHeader.length
            self.accumulatedPayload = acc.currentFrameBytes
            self.incomingPayload = acc.continuationPayload

            // strip off the continuation payload from the incoming payload
            var slice = self.incomingPayload.readSlice(length: acc.continuationHeader.length)!
            self.accumulatedPayload.writeBuffer(&slice)
        }

        mutating func accumulate(bytes: inout ByteBuffer) {
            self.incomingPayload.writeBuffer(&bytes)
        }
    }

    private enum ParserState {
        /// We are waiting for the initial client magic string.
        case awaitingClientMagic(ClientMagicState)

        /// This parser has been freshly allocated and has never seen any bytes.
        case initialized

        /// We are not in the middle of parsing any frames, we're waiting for a full frame header to arrive.
        case accumulatingFrameHeader(AccumulatingFrameHeaderParserState)

        /// We are accumulating payload bytes for a single frame.
        case accumulatingData(AccumulatingPayloadParserState)

        /// We are receiving bytes from a DATA frame payload, and are emitting multiple DATA frames,
        /// one for each chunk of bytes we see here.
        case simulatingDataFrames(SimulatingDataFramesParserState)

        /// We are accumulating a CONTINUATION frame.
        case accumulatingContinuationPayload(AccumulatingContinuationPayloadParserState)

        /// We are waiting for a new CONTINUATION frame to arrive.
        case accumulatingHeaderBlockFragments(AccumulatingHeaderBlockFragmentsParserState)

        /// A temporary state where we are appending data to a buffer. Must always be exited after the append operation.
        case appending
    }

    internal var headerDecoder: HPACKDecoder
    private var state: ParserState
    private var allocator: ByteBufferAllocator

    // RFC 7540 § 6.5.2 puts the initial value of SETTINGS_MAX_FRAME_SIZE at 2**14 octets
    internal var maxFrameSize: UInt32 = 1<<14

    /// Creates a new HTTP2 frame decoder.
    ///
    /// - parameter allocator: A `ByteBufferAllocator` used when accumulating blocks of data
    ///                        and decoding headers.
    /// - parameter expectClientMagic: Whether the parser should expect to receive the bytes of
    ///                                client magic string before frame parsing begins.
    init(allocator: ByteBufferAllocator, expectClientMagic: Bool) {
        self.allocator = allocator
        self.headerDecoder = HPACKDecoder(allocator: allocator)

        if expectClientMagic {
            self.state = .awaitingClientMagic(ClientMagicState(pendingBytes: nil))
        } else {
            self.state = .initialized
        }
    }

    /// Used to pass bytes to the decoder.
    ///
    /// Once you've added bytes, call `nextFrame()` repeatedly to obtain any frames that can
    /// be decoded from the bytes previously accumulated.
    ///
    /// - Parameter bytes: Raw bytes received, ready to decode.
    mutating func append(bytes: inout ByteBuffer) {
        switch self.state {
        case .awaitingClientMagic(var state):
            self.avoidingParserCoW { newState in
                state.accumulate(bytes: &bytes)
                newState = .awaitingClientMagic(state)
            }
        case .initialized:
            // No need for the CoW helper here, as moveReaderIndex does not CoW.
            self.state = .accumulatingFrameHeader(AccumulatingFrameHeaderParserState(unusedBytes: bytes))
            bytes.moveReaderIndex(to: bytes.writerIndex)        // we ate all the bytes
        case .accumulatingFrameHeader(var state):
            self.avoidingParserCoW { newState in
                state.accumulate(bytes: &bytes)
                newState = .accumulatingFrameHeader(state)
            }
        case .accumulatingData(var state):
            self.avoidingParserCoW { newState in
                state.accumulate(bytes: &bytes)
                newState = .accumulatingData(state)
            }
        case .simulatingDataFrames(var state):
            self.avoidingParserCoW { newState in
                state.accumulate(bytes: &bytes)
                newState = .simulatingDataFrames(state)
            }
        case .accumulatingContinuationPayload(var state):
            self.avoidingParserCoW { newState in
                state.accumulate(bytes: &bytes)
                newState = .accumulatingContinuationPayload(state)
            }
        case .accumulatingHeaderBlockFragments(var state):
            self.avoidingParserCoW { newState in
                state.accumulate(bytes: &bytes)
                newState = .accumulatingHeaderBlockFragments(state)
            }
        case .appending:
            preconditionFailure("Cannot recursively append in appending state")
        }
    }

    /// Attempts to decode a frame from the accumulated bytes passed to
    /// `append(bytes:)`.
    ///
    /// - returns: A decoded frame, or `nil` if no frame could be decoded.
    /// - throws: An error if a decoded frame violated the HTTP/2 protocol
    ///           rules.
    mutating func nextFrame() throws -> (HTTP2Frame, flowControlledLength: Int)? {
        // Start running through our state machine until we run out of bytes or we emit a frame.
        switch (try self.processNextState()) {
        case .needMoreData:
            return nil
        case .frame(let frame):
            return frame
        case .continue:
            // tail-call ourselves
            return try nextFrame()
        }
    }

    private mutating func processNextState() throws -> ParseResult {
        switch self.state {
        case .awaitingClientMagic(var state):
            // The client magic is 24 octets long: If we don't have it, keep waiting.
            guard let clientMagic = state.pendingBytes.readBytes(length: 24) else {
                return .needMoreData
            }

            guard clientMagic == HTTP2FrameDecoder.clientMagicBytes else {
                throw NIOHTTP2Errors.BadClientMagic()
            }

            self.state = .accumulatingFrameHeader(.init(unusedBytes: state.pendingBytes))

        case .initialized:
            // no bytes, no frame
            return .needMoreData

        case .accumulatingFrameHeader(var state):
            guard let header = state.unusedBytes.readFrameHeader() else {
                return .needMoreData
            }

            // Confirm that SETTINGS_MAX_FRAME_SIZE is respected.
            guard header.length <= self.maxFrameSize else {
                throw InternalError.codecError(code: .frameSizeError)
            }

            if header.type != 0 {
                // Not a DATA frame. Before we move on, do a quick preflight: if this frame header is for a frame that will
                // definitely violate SETTINGS_MAX_HEADER_LIST_SIZE, quit now.
                if header.type == 1 && header.length > self.headerDecoder.maxHeaderListSize {
                    throw NIOHTTP2Errors.ExcessivelyLargeHeaderBlock()

                }
                self.state = .accumulatingData(AccumulatingPayloadParserState(fromIdle: state, header: header))
            } else if header.flags.contains(.padded) {
                // DATA frame with padding
                guard let expectedPadding: UInt8 = state.unusedBytes.readInteger() else {
                    // Wait for the padding byte to come in
                    self.state = .accumulatingData(AccumulatingPayloadParserState(fromIdle: state, header: header))
                    return .needMoreData
                }

                let remainingBytes = header.length - 1
                guard remainingBytes >= Int(expectedPadding) else {
                    // There may not be more padding bytes than the length of the frame allows
                    throw InternalError.codecError(code: .protocolError)
                }

                self.state = .simulatingDataFrames(SimulatingDataFramesParserState(fromIdle: state, header: header, expectedPadding: expectedPadding, remainingBytes: remainingBytes))

                // Emit an empty frame if we only have padding; .simulatingDataFrames will handle eating the padding.
                if expectedPadding == remainingBytes {
                    let streamID = HTTP2StreamID(networkID: header.rawStreamID)
                    let dataPayload = HTTP2Frame.FramePayload.Data(data: .byteBuffer(self.allocator.buffer(capacity: 0)), endStream: header.flags.contains(.endStream), paddingBytes: nil)
                    let outputFrame = HTTP2Frame(streamID: streamID, payload: .data(dataPayload))
                    return .frame(outputFrame, flowControlledLength: header.length)
                }
            }
            else {
                // Un-padded DATA frame.
                // ensure we're on a valid stream
                guard header.rawStreamID != 0 else {
                    // DATA frames cannot appear on the root stream
                    throw InternalError.codecError(code: .protocolError)
                }

                // No padding and zero length so we can just emit an empty frame.
                guard header.length > 0 else {
                    let streamID = HTTP2StreamID(networkID: header.rawStreamID)
                    let dataPayload = HTTP2Frame.FramePayload.Data(data: .byteBuffer(self.allocator.buffer(capacity: 0)), endStream: header.flags.contains(.endStream), paddingBytes: nil)
                    let outputFrame = HTTP2Frame(streamID: streamID, payload: .data(dataPayload))
                    self.state = .accumulatingFrameHeader(.init(unusedBytes: state.unusedBytes))
                    return .frame(outputFrame, flowControlledLength: 0)
                }

                self.state = .simulatingDataFrames(SimulatingDataFramesParserState(fromIdle: state, header: header, expectedPadding: 0, remainingBytes: header.length))
            }

        case .accumulatingData(var state):
            if state.header.type == 0 && state.accumulatedBytes.readableBytes > 0 {
                // We now have enough bytes to read the expected padding
                // We should only be here if it's a DATA frame with padding and we couldn't read
                // the padding before:
                precondition(state.header.flags.contains(.padded))
                // force unwrap must succeed since we checked value of readableBytes
                let expectedPadding: UInt8 = state.accumulatedBytes.readInteger()!
                let remainingBytes = state.header.length - 1

                self.state = .simulatingDataFrames(SimulatingDataFramesParserState(fromAccumulatingPayload: state, expectedPadding: expectedPadding, remainingBytes: state.header.length - 1))

                // Emit an empty frame if we only have padding; .simulatingDataFrames will handle eating the padding.
                if expectedPadding == remainingBytes {
                    let streamID = HTTP2StreamID(networkID: state.header.rawStreamID)
                    let dataPayload = HTTP2Frame.FramePayload.Data(data: .byteBuffer(self.allocator.buffer(capacity: 0)), endStream: state.header.flags.contains(.endStream), paddingBytes: nil)
                    let outputFrame = HTTP2Frame(streamID: streamID, payload: .data(dataPayload))
                    return .frame(outputFrame, flowControlledLength: state.header.length)
                }

                return .continue
            }
            guard state.header.type != 9 else {
                // we shouldn't see any CONTINUATION frames in this state
                throw InternalError.codecError(code: .protocolError)
            }
            guard state.accumulatedBytes.readableBytes >= state.header.length else {
                return .needMoreData
            }

            // entire frame is available -- handle special cases (HEADERS/PUSH_PROMISE) first
            if (state.header.type == 1 || state.header.type == 5) && !state.header.flags.contains(.endHeaders) {
                // don't emit these, coalesce them with following CONTINUATION frames
                // strip out the frame payload bytes
                var payloadBytes = state.accumulatedBytes.readSlice(length: state.header.length)!

                // handle padding bytes, if any
                if state.header.flags.contains(.padded) {
                    // read the padding byte
                    // we've already ascertained that there's at least one byte in the buffer
                    let padding: UInt8 = payloadBytes.readInteger()!
                    // remove that many bytes from the end of the payload buffer
                    payloadBytes.moveWriterIndex(to: payloadBytes.writerIndex - Int(padding))
                    state.header.flags.subtract(.padded)     // we ate the padding
                    state.header.length -= Int(padding)      // shave the padding from the frame's length
                }

                self.state = .accumulatingHeaderBlockFragments(AccumulatingHeaderBlockFragmentsParserState(fromAccumulatingPayload: state,
                                                                                                           initialPayload: payloadBytes))
                return .continue
            }

            // an entire frame's data, including HEADERS/PUSH_PROMISE with the END_HEADERS flag set
            // this may legitimately return nil if we ignore the frame
            let result = try self.readFrame(withHeader: state.header, from: &state.accumulatedBytes)
            self.state = .accumulatingFrameHeader(AccumulatingFrameHeaderParserState(unusedBytes: state.accumulatedBytes))

            // if we got a frame, return it. If not that means we consumed and ignored a frame, so we
            // should go round again.
            // We cannot emit DATA frames from here, so the flow controlled length is always 0.
            if let frame = result {
                assert(state.header.type != 0, "Emitted invalid data frame")
                return .frame(frame, flowControlledLength: 0)
            }

        case .simulatingDataFrames(var state):
            // NB: already checked for root stream before entering this state
            if state.payload.readableBytes == 0 && (state.remainingByteCount - Int(state.expectedPadding)) > 0 {
                // need more bytes!
                return .needMoreData
            }

            if state.remainingByteCount <= Int(state.expectedPadding) {
                // we're just eating pad bytes now, maintaining state and emitting nothing
                if state.payload.readableBytes >= state.remainingByteCount {
                    // we've got them all, move to idle state with any following bytes
                    state.payload.moveReaderIndex(forwardBy: state.remainingByteCount)
                    self.state = .accumulatingFrameHeader(AccumulatingFrameHeaderParserState(unusedBytes: state.payload))
                    return .continue
                } else {
                    // stay in state and wait for more bytes
                    return .needMoreData
                }
            }

            // create a frame using these bytes, or a subset thereof
            var frameBytes: ByteBuffer
            var nextState: ParserState
            var flags: FrameFlags = state.header.flags

            // We extract the flow controlled length early because we only ever emit it once for a given frame.
            // This operation mutates the flow controlled length and sets it to zero, so it will always give an appropriate result.
            let flowControlledLength = state.flowControlledLength()

            if state.payload.readableBytes >= state.remainingByteCount {
                // read all the bytes for this last frame
                frameBytes = state.payload.readSlice(length: state.remainingByteCount - Int(state.expectedPadding))!
                state.payload.moveReaderIndex(forwardBy: Int(state.expectedPadding))
                if state.payload.readableBytes == 0 {
                    state.payload.quietlyReset()
                }

                nextState = .accumulatingFrameHeader(AccumulatingFrameHeaderParserState(unusedBytes: state.payload))
            } else if state.payload.readableBytes >= state.remainingByteCount - Int(state.expectedPadding) {
                // Here we have the last actual bytes of the payload, but haven't yet received all the
                // padding bytes that follow to complete the frame.
                frameBytes = state.payload.readSlice(length: state.remainingByteCount - Int(state.expectedPadding))!
                state.remainingByteCount -= frameBytes.readableBytes
                nextState = .simulatingDataFrames(state)        // we still need to consume the remaining padding bytes
            } else {
                frameBytes = state.payload      // entire thing
                state.remainingByteCount -= frameBytes.readableBytes
                state.payload.quietlyReset()
                nextState = .simulatingDataFrames(state)
                flags.remove(.endStream)  // Still simulating frames, this can't have END_STREAM on it.
            }

            let streamID = HTTP2StreamID(networkID: state.header.rawStreamID)

            // TODO(cory): report padding length.
            let dataPayload = HTTP2Frame.FramePayload.Data(data: .byteBuffer(frameBytes), endStream: flags.contains(.endStream), paddingBytes: nil)
            let outputFrame = HTTP2Frame(streamID: streamID, payload: .data(dataPayload))
            self.state = nextState
            return .frame(outputFrame, flowControlledLength: flowControlledLength)

        case .accumulatingContinuationPayload(var state):
            guard state.continuationHeader.length <= state.continuationPayload.readableBytes else {
                return .needMoreData
            }

            // we have collected enough bytes: is this the last CONTINUATION frame?
            guard state.continuationHeader.flags.contains(.endHeaders) else {
                // nope, switch back to accumulating fragments
                self.state = .accumulatingHeaderBlockFragments(AccumulatingHeaderBlockFragmentsParserState(fromAccumulatingContinuation: state))
                return .continue
            }

            // it is, yay! Output a frame
            var payload = state.currentFrameBytes
            var continuationSlice = state.continuationPayload.readSlice(length: state.continuationHeader.length)!
            payload.writeBuffer(&continuationSlice)

            // we have something that looks just like a HEADERS or PUSH_PROMISE frame now
            var header = state.initialHeader
            header.length += state.continuationHeader.length
            header.flags.formUnion(.endHeaders)
            let frame = try self.readFrame(withHeader: header, from: &payload)
            precondition(frame != nil)

            // move to idle, passing in whatever was left after we consumed the CONTINUATION payload
            self.state = .accumulatingFrameHeader(AccumulatingFrameHeaderParserState(unusedBytes: state.continuationPayload))

            // Emit the frame. This can't be a DATA frame, so there is no flow controlled length here.
            return .frame(frame!, flowControlledLength: 0)

        case .accumulatingHeaderBlockFragments(var state):
            // we have an entire HEADERS/PUSH_PROMISE frame, but one or more CONTINUATION frames
            // are arriving. Wait for them.
            guard let header = state.incomingPayload.readFrameHeader() else {
                return .needMoreData
            }

            // incoming frame: should be CONTINUATION
            guard header.type == 9 else {
                throw InternalError.codecError(code: .protocolError)
            }

            // This must be for the stream we're buffering header block fragments for, or this is an error.
            guard header.rawStreamID == state.header.rawStreamID else {
                throw InternalError.codecError(code: .protocolError)
            }

            // Check whether there is any possibility of this payload decompressing and fitting in max header list size.
            // If there isn't, kill it.
            guard state.accumulatedPayload.readableBytes + header.length <= self.headerDecoder.maxHeaderListSize else {
                throw NIOHTTP2Errors.ExcessivelyLargeHeaderBlock()
            }

            self.state = .accumulatingContinuationPayload(AccumulatingContinuationPayloadParserState(fromAccumulatingHeaderBlockFragments: state, continuationHeader: header))

        case .appending:
            preconditionFailure("Attempting to process in appending state")
        }

        return .continue
    }

    private mutating func readFrame(withHeader header: FrameHeader, from bytes: inout ByteBuffer) throws -> HTTP2Frame? {
        assert(bytes.readableBytes >= header.length, "Buffer should contain at least \(header.length) bytes.")

        let flags = header.flags
        let streamID = HTTP2StreamID(networkID: header.rawStreamID)
        let frameEndIndex = bytes.readerIndex + header.length

        let payload: HTTP2Frame.FramePayload
        do {
            switch header.type {
            case 0:
                payload = try self.parseDataFramePayload(length: header.length, streamID: streamID, flags: flags, bytes: &bytes)
            case 1:
                precondition(flags.contains(.endHeaders))
                payload = try self.parseHeadersFramePayload(length: header.length, streamID: streamID, flags: flags, bytes: &bytes)
            case 2:
                payload = try self.parsePriorityFramePayload(length: header.length, streamID: streamID, bytes: &bytes)
            case 3:
                payload = try self.parseRstStreamFramePayload(length: header.length, streamID: streamID, bytes: &bytes)
            case 4:
                payload = try self.parseSettingsFramePayload(length: header.length, streamID: streamID, flags: flags, bytes: &bytes)
            case 5:
                precondition(flags.contains(.endHeaders))
                payload = try self.parsePushPromiseFramePayload(length: header.length, streamID: streamID, flags: flags, bytes: &bytes)
            case 6:
                payload = try self.parsePingFramePayload(length: header.length, streamID: streamID, flags: flags, bytes: &bytes)
            case 7:
                payload = try self.parseGoAwayFramePayload(length: header.length, streamID: streamID, bytes: &bytes)
            case 8:
                payload = try self.parseWindowUpdateFramePayload(length: header.length, bytes: &bytes)
            case 9:
                // CONTINUATION frame should never be found here -- we should have handled them elsewhere
                preconditionFailure("Unexpected continuation frame")
            case 10:
                payload = try self.parseAltSvcFramePayload(length: header.length, streamID: streamID, bytes: &bytes)
            case 12:
                payload = try self.parseOriginFramePayload(length: header.length, streamID: streamID, bytes: &bytes)
            default:
                // RFC 7540 § 4.1 https://httpwg.org/specs/rfc7540.html#FrameHeader
                //    "Implementations MUST ignore and discard any frame that has a type that is unknown."
                bytes.moveReaderIndex(to: frameEndIndex)
                self.state = .accumulatingFrameHeader(AccumulatingFrameHeaderParserState(unusedBytes: bytes))
                return nil
            }
        } catch is IgnoredFrame {
            bytes.moveReaderIndex(to: frameEndIndex)
            self.state = .accumulatingFrameHeader(AccumulatingFrameHeaderParserState(unusedBytes: bytes))
            return nil
        } catch _ as NIOHPACKError {
            // convert into a connection error of type COMPRESSION_ERROR
            bytes.moveReaderIndex(to: frameEndIndex)
            self.state = .accumulatingFrameHeader(AccumulatingFrameHeaderParserState(unusedBytes: bytes))
            throw InternalError.codecError(code: .compressionError)
        } catch {
            bytes.moveReaderIndex(to: frameEndIndex)
            self.state = .accumulatingFrameHeader(AccumulatingFrameHeaderParserState(unusedBytes: bytes))
            throw error
        }

        // ensure we've consumed all the input bytes
        bytes.moveReaderIndex(to: frameEndIndex)
        self.state = .accumulatingFrameHeader(AccumulatingFrameHeaderParserState(unusedBytes: bytes))
        return HTTP2Frame(streamID: streamID, payload: payload)
    }

    private func parseDataFramePayload(length: Int, streamID: HTTP2StreamID, flags: FrameFlags, bytes: inout ByteBuffer) throws -> HTTP2Frame.FramePayload {
        // DATA frame : RFC 7540 § 6.1
        guard streamID != .rootStream else {
            // DATA frames MUST be associated with a stream. If a DATA frame is received whose
            // stream identifier field is 0x0, the recipient MUST respond with a connection error
            // (Section 5.4.1) of type PROTOCOL_ERROR.
            throw InternalError.codecError(code: .protocolError)
        }

        var dataLen = length
        let padding = try self.validatePadding(of: &bytes, against: &dataLen, flags: flags)

        let buf = bytes.readSlice(length: dataLen)!
        if padding > 0 {
            // don't forget to consume any padding bytes
            bytes.moveReaderIndex(forwardBy: padding)
        }

        // TODO(cory): For consistency we don't report padding bytes here either. We should report them both here and when synthesising frames, though.
        let dataPayload = HTTP2Frame.FramePayload.Data(data: .byteBuffer(buf), endStream: flags.contains(.endStream), paddingBytes: nil)
        return .data(dataPayload)
    }

    private mutating func parseHeadersFramePayload(length: Int, streamID: HTTP2StreamID, flags: FrameFlags, bytes: inout ByteBuffer) throws -> HTTP2Frame.FramePayload {
        // HEADERS frame : RFC 7540 § 6.2
        guard streamID != .rootStream else {
            // HEADERS frames MUST be associated with a stream. If a HEADERS frame is received whose
            // stream identifier field is 0x0, the recipient MUST respond with a connection error
            // (Section 5.4.1) of type PROTOCOL_ERROR.
            throw InternalError.codecError(code: .protocolError)
        }

        var bytesToRead = length
        let padding = try self.validatePadding(of: &bytes, against: &bytesToRead, flags: flags)

        let priorityData: HTTP2Frame.StreamPriorityData?
        if flags.contains(.priority) {
            let raw: UInt32 = bytes.readInteger()!
            priorityData = HTTP2Frame.StreamPriorityData(exclusive: (raw & 0x8000_0000 != 0),
                                                         dependency: HTTP2StreamID(networkID: raw),
                                                         weight: bytes.readInteger()!)
            bytesToRead -= 5
        } else {
            priorityData = nil
        }

        // slice out the relevant chunk of data (ignoring padding)
        let headerByteSize = bytesToRead - padding
        var slice = bytes.readSlice(length: headerByteSize)!
        let headers = try self.headerDecoder.decodeHeaders(from: &slice)

        let headersPayload = HTTP2Frame.FramePayload.Headers(headers: headers,
                                                             priorityData: priorityData,
                                                             endStream: flags.contains(.endStream),
                                                             paddingBytes: flags.contains(.padded) ? padding : nil)

        return .headers(headersPayload)
    }

    private func parsePriorityFramePayload(length: Int, streamID: HTTP2StreamID, bytes: inout ByteBuffer) throws -> HTTP2Frame.FramePayload {
        // PRIORITY frame : RFC 7540 § 6.3
        guard streamID != .rootStream else {
            // The PRIORITY frame always identifies a stream. If a PRIORITY frame is received
            // with a stream identifier of 0x0, the recipient MUST respond with a connection error
            // (Section 5.4.1) of type PROTOCOL_ERROR.
            throw InternalError.codecError(code: .protocolError)
        }
        guard length == 5 else {
            // A PRIORITY frame with a length other than 5 octets MUST be treated as a stream
            // error (Section 5.4.2) of type FRAME_SIZE_ERROR.
            throw InternalError.codecError(code: .frameSizeError)
        }

        let raw: UInt32 = bytes.readInteger()!
        let priorityData = HTTP2Frame.StreamPriorityData(exclusive: raw & 0x8000_0000 != 0,
                                                         dependency: HTTP2StreamID(networkID: raw),
                                                         weight: bytes.readInteger()!)
        return .priority(priorityData)
    }

    private func parseRstStreamFramePayload(length: Int, streamID: HTTP2StreamID, bytes: inout ByteBuffer) throws -> HTTP2Frame.FramePayload {
        // RST_STREAM frame : RFC 7540 § 6.4
        guard streamID != .rootStream else {
            // RST_STREAM frames MUST be associated with a stream. If a RST_STREAM frame is
            // received with a stream identifier of 0x0, the recipient MUST treat this as a
            // connection error (Section 5.4.1) of type PROTOCOL_ERROR.
            throw InternalError.codecError(code: .protocolError)
        }
        guard length == 4 else {
            // A RST_STREAM frame with a length other than 4 octets MUST be treated as a
            // connection error (Section 5.4.1) of type FRAME_SIZE_ERROR.
            throw InternalError.codecError(code: .frameSizeError)
        }

        let errcode: UInt32 = bytes.readInteger()!
        return .rstStream(HTTP2ErrorCode(errcode))
    }

    private func parseSettingsFramePayload(length: Int, streamID: HTTP2StreamID, flags: FrameFlags, bytes: inout ByteBuffer) throws -> HTTP2Frame.FramePayload {
        // SETTINGS frame : RFC 7540 § 6.5
        guard streamID == .rootStream else {
            // SETTINGS frames always apply to a connection, never a single stream. The stream
            // identifier for a SETTINGS frame MUST be zero (0x0). If an endpoint receives a
            // SETTINGS frame whose stream identifier field is anything other than 0x0, the
            // endpoint MUST respond with a connection error (Section 5.4.1) of type
            // PROTOCOL_ERROR.
            throw InternalError.codecError(code: .protocolError)
        }
        if flags.contains(.ack) {
            guard length == 0 else {
                // When [the ACK flag] is set, the payload of the SETTINGS frame MUST be empty.
                // Receipt of a SETTINGS frame with the ACK flag set and a length field value
                // other than 0 MUST be treated as a connection error (Section 5.4.1) of type
                // FRAME_SIZE_ERROR.
                throw InternalError.codecError(code: .frameSizeError)
            }

            return .settings(.ack)
        } else if length % 6 != 0 {
            // A SETTINGS frame with a length other than a multiple of 6 octets MUST be treated
            // as a connection error (Section 5.4.1) of type FRAME_SIZE_ERROR.
            throw InternalError.codecError(code: .frameSizeError)
        }

        var settings: [HTTP2Setting] = []
        settings.reserveCapacity(length / 6)

        var consumed = 0
        while consumed < length {
            // TODO: name here should be HTTP2SettingsParameter(fromNetwork:), but that's currently defined for NGHTTP2's Int32 value
            let identifier = HTTP2SettingsParameter(fromPayload: bytes.readInteger()!)
            let value: UInt32 = bytes.readInteger()!

            settings.append(HTTP2Setting(parameter: identifier, value: Int(value)))
            consumed += 6
        }

        return .settings(.settings(settings))
    }

    private mutating func parsePushPromiseFramePayload(length: Int, streamID: HTTP2StreamID, flags: FrameFlags, bytes: inout ByteBuffer) throws -> HTTP2Frame.FramePayload {
        // PUSH_PROMISE frame : RFC 7540 § 6.6
        guard streamID != .rootStream else {
            // The stream identifier of a PUSH_PROMISE frame indicates the stream it is associated with.
            // If the stream identifier field specifies the value 0x0, a recipient MUST respond with a
            // connection error (Section 5.4.1) of type PROTOCOL_ERROR.
            throw InternalError.codecError(code: .protocolError)
        }

        var bytesToRead = length
        let padding = try self.validatePadding(of: &bytes, against: &bytesToRead, flags: flags)

        let promisedStreamID = HTTP2StreamID(networkID: bytes.readInteger()!)
        bytesToRead -= 4

        guard promisedStreamID != .rootStream else {
            throw InternalError.codecError(code: .protocolError)
        }

        let headerByteLen = bytesToRead - padding
        var slice = bytes.readSlice(length: headerByteLen)!
        let headers = try self.headerDecoder.decodeHeaders(from: &slice)

        let pushPromiseContent = HTTP2Frame.FramePayload.PushPromise(pushedStreamID: promisedStreamID, headers: headers, paddingBytes: flags.contains(.padded) ? padding : nil)
        return .pushPromise(pushPromiseContent)
    }

    private func parsePingFramePayload(length: Int, streamID: HTTP2StreamID, flags: FrameFlags, bytes: inout ByteBuffer) throws -> HTTP2Frame.FramePayload {
        // PING frame : RFC 7540 § 6.7
        guard length == 8 else {
            // Receipt of a PING frame with a length field value other than 8 MUST be treated
            // as a connection error (Section 5.4.1) of type FRAME_SIZE_ERROR.
            throw InternalError.codecError(code: .frameSizeError)
        }
        guard streamID == .rootStream else {
            // PING frames are not associated with any individual stream. If a PING frame is
            // received with a stream identifier field value other than 0x0, the recipient MUST
            // respond with a connection error (Section 5.4.1) of type PROTOCOL_ERROR.
            throw InternalError.codecError(code: .protocolError)
        }

        var tuple: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0,0,0,0,0,0,0,0)
        withUnsafeMutableBytes(of: &tuple) { ptr -> Void in
            bytes.readWithUnsafeReadableBytes { bytesPtr -> Int in
                ptr.copyBytes(from: bytesPtr[0..<8])
                return 8
            }
        }

        return .ping(HTTP2PingData(withTuple: tuple), ack: flags.contains(.ack))
    }

    private func parseGoAwayFramePayload(length: Int, streamID: HTTP2StreamID, bytes: inout ByteBuffer) throws -> HTTP2Frame.FramePayload {
        // GOAWAY frame : RFC 7540 § 6.8
        guard streamID == .rootStream else {
            // The GOAWAY frame applies to the connection, not a specific stream. An endpoint
            // MUST treat a GOAWAY frame with a stream identifier other than 0x0 as a connection
            // error (Section 5.4.1) of type PROTOCOL_ERROR.
            throw InternalError.codecError(code: .protocolError)
        }

        guard length >= 8 else {
            // Must have at least 8 bytes of data (last-stream-id plus error-code).
            throw InternalError.codecError(code: .frameSizeError)
        }

        let raw: UInt32 = bytes.readInteger()!
        let errcode: UInt32 = bytes.readInteger()!

        let debugData: ByteBuffer?
        let extraLen = length - 8
        if extraLen > 0 {
            debugData = bytes.readSlice(length: extraLen)
        } else {
            debugData = nil
        }

        return .goAway(lastStreamID: HTTP2StreamID(networkID: raw),
                       errorCode: HTTP2ErrorCode(errcode), opaqueData: debugData)
    }

    private func parseWindowUpdateFramePayload(length: Int, bytes: inout ByteBuffer) throws -> HTTP2Frame.FramePayload {
        // WINDOW_UPDATE frame : RFC 7540 § 6.9
        guard length == 4 else {
            // A WINDOW_UPDATE frame with a length other than 4 octets MUST be treated as a
            // connection error (Section 5.4.1) of type FRAME_SIZE_ERROR.
            throw InternalError.codecError(code: .frameSizeError)
        }

        let raw: UInt32 = bytes.readInteger()!
        return .windowUpdate(windowSizeIncrement: Int(raw & ~0x8000_0000))
    }

    private func parseAltSvcFramePayload(length: Int, streamID: HTTP2StreamID, bytes: inout ByteBuffer) throws -> HTTP2Frame.FramePayload {
        // ALTSVC frame : RFC 7838 § 4
        guard length >= 2 else {
            // Must be at least two bytes, to contain the length of the optional 'Origin' field.
            throw InternalError.codecError(code: .frameSizeError)
        }

        let originLen: UInt16 = bytes.readInteger()!
        let origin: String?
        if originLen > 0 {
            origin = bytes.readString(length: Int(originLen))!
        } else {
            origin = nil
        }

        if streamID == .rootStream && originLen == 0 {
            // MUST have origin on root stream
            throw IgnoredFrame()
        }
        if streamID != .rootStream && originLen != 0 {
            // MUST NOT have origin on non-root stream
            throw IgnoredFrame()
        }

        let fieldLen = length - 2 - Int(originLen)
        let value: ByteBuffer?
        if fieldLen != 0 {
            value = bytes.readSlice(length: fieldLen)!
        } else {
            value = nil
        }

        return .alternativeService(origin: origin, field: value)
    }

    private func parseOriginFramePayload(length: Int, streamID: HTTP2StreamID, bytes: inout ByteBuffer) throws -> HTTP2Frame.FramePayload {
        // ORIGIN frame : RFC 8336 § 2
        guard streamID == .rootStream else {
            // The ORIGIN frame MUST be sent on stream 0; an ORIGIN frame on any
            // other stream is invalid and MUST be ignored.
            throw IgnoredFrame()
        }

        var origins: [String] = []
        var remaining = length
        while remaining > 0 {
            guard remaining >= 2 else {
                // If less than two bytes remain, this is a malformed frame.
                throw InternalError.codecError(code: .protocolError)
            }
            let originLen: UInt16 = bytes.readInteger()!
            remaining -= 2

            guard remaining >= Int(originLen) else {
                // Malformed frame.
                throw InternalError.codecError(code: .frameSizeError)
            }
            let origin = bytes.readString(length: Int(originLen))!
            remaining -= Int(originLen)

            origins.append(origin)
        }

        return .origin(origins)
    }

    private func validatePadding(of bytes: inout ByteBuffer, against length: inout Int, flags: FrameFlags) throws -> Int {
        guard flags.contains(.padded) else {
            return 0
        }

        let padding: UInt8 = bytes.readInteger()!
        length -= 1

        if length <= Int(padding) {
            // Padding that exceeds the remaining payload size MUST be treated as a PROTOCOL_ERROR.
            throw InternalError.codecError(code: .protocolError)
        }

        return Int(padding)
    }
}

struct HTTP2FrameEncoder {
    private let allocator: ByteBufferAllocator
    var headerEncoder: HPACKEncoder

    // RFC 7540 § 6.5.2 puts the initial value of SETTINGS_MAX_FRAME_SIZE at 2**14 octets
    var maxFrameSize: UInt32 = 1<<14

    init(allocator: ByteBufferAllocator) {
        self.allocator = allocator
        self.headerEncoder = HPACKEncoder(allocator: allocator)
    }

    /// Encodes the frame and optionally returns one or more blobs of data
    /// ready for the system.
    ///
    /// Returned data blobs would include anything of potentially flexible
    /// length, such as DATA payloads, header fragments in HEADERS or PUSH_PROMISE
    /// frames, and so on. This is to avoid manually copying chunks of data which
    /// we could just enqueue separately in sequence on the channel. Generally, if
    /// we have a byte buffer somewhere, we will return that separately rather than
    /// copy it into another buffer, with the corresponding allocation overhead.
    ///
    /// - Parameters:
    ///   - frame: The frame to encode.
    ///   - buf: Destination buffer for the encoded frame.
    /// - Returns: An array containing zero or more additional buffers to send, in
    ///            order. These may contain data frames' payload bytes, encoded
    ///            header fragments, etc.
    /// - Throws: Errors returned from HPACK encoder.
    mutating func encode(frame: HTTP2Frame, to buf: inout ByteBuffer) throws -> IOData? {
        // note our starting point
        let start = buf.writerIndex

//      +-----------------------------------------------+
//      |                 Length (24)                   |
//      +---------------+---------------+---------------+
//      |   Type (8)    |   Flags (8)   |
//      +-+-------------+---------------+-------------------------------+
//      |R|                 Stream Identifier (31)                      |
//      +=+=============================================================+
//      |                   Frame Payload (0...)                      ...
//      +---------------------------------------------------------------+

        // skip 24-bit length for now, we'll fill that in later
        buf.moveWriterIndex(forwardBy: 3)

        // 8-bit type
        buf.writeInteger(frame.payload.code)

        // skip the 8 bit flags for now, we'll fill it in later as well.
        let flagsIndex = buf.writerIndex
        var flags = FrameFlags()
        buf.moveWriterIndex(forwardBy: 1)

        // 32-bit stream identifier -- ensuring the top bit is empty
        buf.writeInteger(Int32(frame.streamID))

        // frame payload follows, which depends on the frame type itself
        let payloadStart = buf.writerIndex
        let extraFrameData: IOData?
        let payloadSize: Int

        switch frame.payload {
        case .data(let dataContent):
            if dataContent.paddingBytes != nil {
                // we don't support sending padded frames just now
                throw NIOHTTP2Errors.Unsupported(info: "Padding is not supported on sent frames at this time")
            }

            if dataContent.endStream {
                flags.insert(.endStream)
            }
            extraFrameData = dataContent.data
            payloadSize = dataContent.data.readableBytes

        case .headers(let headerData):
            if headerData.paddingBytes != nil {
                // we don't support sending padded frames just now
                throw NIOHTTP2Errors.Unsupported(info: "Padding is not supported on sent frames at this time")
            }

            flags.insert(.endHeaders)
            if headerData.endStream {
                flags.insert(.endStream)
            }

            if let priority = headerData.priorityData {
                flags.insert(.priority)
                var dependencyRaw = UInt32(priority.dependency)
                if priority.exclusive {
                    dependencyRaw |= 0x8000_0000
                }
                buf.writeInteger(dependencyRaw)
                buf.writeInteger(priority.weight)
            }

            try self.headerEncoder.encode(headers: headerData.headers, to: &buf)
            payloadSize = buf.writerIndex - payloadStart
            extraFrameData = nil

        case .priority(let priorityData):
            var raw = UInt32(priorityData.dependency)
            if priorityData.exclusive {
                raw |= 0x8000_0000
            }
            buf.writeInteger(raw)
            buf.writeInteger(priorityData.weight)

            extraFrameData = nil
            payloadSize = 5

        case .rstStream(let errcode):
            buf.writeInteger(UInt32(errcode.networkCode))

            payloadSize = 4
            extraFrameData = nil

        case .settings(.settings(let settings)):
            for setting in settings {
                buf.writeInteger(setting.parameter.networkRepresentation)
                buf.writeInteger(setting._value)
            }

            payloadSize = settings.count * 6
            extraFrameData = nil

        case .settings(.ack):
            payloadSize = 0
            extraFrameData = nil
            flags.insert(.ack)

        case .pushPromise(let pushPromiseData):
            if pushPromiseData.paddingBytes != nil {
                // we don't support sending padded frames just now
                throw NIOHTTP2Errors.Unsupported(info: "Padding is not supported on sent frames at this time")
            }

            let streamVal: UInt32 = UInt32(pushPromiseData.pushedStreamID)
            buf.writeInteger(streamVal)

            try self.headerEncoder.encode(headers: pushPromiseData.headers, to: &buf)

            payloadSize = buf.writerIndex - payloadStart
            extraFrameData = nil
            flags.insert(.endHeaders)

        case .ping(let pingData, let ack):
            withUnsafeBytes(of: pingData.bytes) { ptr -> Void in
                _ = buf.writeBytes(ptr)
            }

            if ack {
                flags.insert(.ack)
            }

            payloadSize = 8
            extraFrameData = nil

        case .goAway(let lastStreamID, let errorCode, let opaqueData):
            let streamVal: UInt32 = UInt32(lastStreamID) & ~0x8000_0000
            buf.writeInteger(streamVal)
            buf.writeInteger(UInt32(errorCode.networkCode))

            if let data = opaqueData {
                payloadSize = data.readableBytes + 8
                extraFrameData = .byteBuffer(data)
            } else {
                payloadSize = 8
                extraFrameData = nil
            }

        case .windowUpdate(let size):
            buf.writeInteger(UInt32(size) & ~0x8000_0000)
            payloadSize = 4
            extraFrameData = nil

        case .alternativeService(let origin, let field):
            if let org = origin {
                buf.moveWriterIndex(forwardBy: 2)
                let start = buf.writerIndex
                buf.writeString(org)
                buf.setInteger(UInt16(buf.writerIndex - start), at: payloadStart)
            } else {
                buf.writeInteger(UInt16(0))
            }

            if let value = field {
                payloadSize = buf.writerIndex - payloadStart + value.readableBytes
                extraFrameData = .byteBuffer(value)
            } else {
                payloadSize = buf.writerIndex - payloadStart
                extraFrameData = nil
            }

        case .origin(let origins):
            for origin in origins {
                let sizeLoc = buf.writerIndex
                buf.moveWriterIndex(forwardBy: 2)

                let start = buf.writerIndex
                buf.writeString(origin)
                buf.setInteger(UInt16(buf.writerIndex - start), at: sizeLoc)
            }

            payloadSize = buf.writerIndex - payloadStart
            extraFrameData = nil
        }

        // Confirm we're not about to violate SETTINGS_MAX_FRAME_SIZE.
        guard payloadSize <= Int(self.maxFrameSize) else {
            throw InternalError.codecError(code: .frameSizeError)
        }

        // Write the frame data. This is the payload size and the flags byte.
        buf.writePayloadSize(payloadSize, at: start)
        buf.setInteger(flags.rawValue, at: flagsIndex)

        // all bytes to write are in the provided buffer now
        return extraFrameData
    }
}

fileprivate struct FrameHeader {
    var length: Int     // actually 24-bits
    var type: UInt8
    var flags: FrameFlags
    var rawStreamID: UInt32 // including reserved bit
}

fileprivate extension ByteBuffer {
    mutating func readFrameHeader() -> FrameHeader? {
        let saveSelf = self
        guard let lenHigh = self.readInteger(as: UInt16.self),
            let lenLow = self.readInteger(as: UInt8.self),
            let type = self.readInteger(as: UInt8.self),
            let flags = self.readInteger(as: UInt8.self),
            let rawStreamID = self.readInteger(as: UInt32.self) else {
                self = saveSelf
                return nil
        }

        return FrameHeader(length: Int(lenHigh) << 8 | Int(lenLow), type: type, flags: FrameFlags(rawValue: flags), rawStreamID: rawStreamID)
    }

    mutating func writePayloadSize(_ size: Int, at location: Int) {
        // Yes, this performs better than running a UInt8 through the generic write(integer:) three times.
        var bytes: (UInt8, UInt8, UInt8)
        bytes.0 = UInt8((size & 0xff_00_00) >> 16)
        bytes.1 = UInt8((size & 0x00_ff_00) >>  8)
        bytes.2 = UInt8( size & 0x00_00_ff)
        withUnsafeBytes(of: bytes) { ptr in
            _ = self.setBytes(ptr, at: location)
        }
    }

    mutating func quietlyReset() {
        self.moveReaderIndex(to: 0)
        self.moveWriterIndex(to: 0)
    }
}


/// The flags supported by the frame types understood by this protocol.
private struct FrameFlags: OptionSet, CustomStringConvertible {
    internal typealias RawValue = UInt8

    internal private(set) var rawValue: UInt8

    internal init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// END_STREAM flag. Valid on DATA and HEADERS frames.
    internal static let endStream     = FrameFlags(rawValue: 0x01)

    /// ACK flag. Valid on SETTINGS and PING frames.
    internal static let ack           = FrameFlags(rawValue: 0x01)

    /// END_HEADERS flag. Valid on HEADERS, CONTINUATION, and PUSH_PROMISE frames.
    internal static let endHeaders    = FrameFlags(rawValue: 0x04)

    /// PADDED flag. Valid on DATA, HEADERS, CONTINUATION, and PUSH_PROMISE frames.
    ///
    /// NB: swift-nio-http2 does not automatically pad outgoing frames.
    internal static let padded        = FrameFlags(rawValue: 0x08)

    /// PRIORITY flag. Valid on HEADERS frames, specifically as the first frame sent
    /// on a new stream.
    internal static let priority      = FrameFlags(rawValue: 0x20)

    // useful for test cases
    internal static var allFlags: FrameFlags = [.endStream, .endHeaders, .padded, .priority]

    internal var description: String {
        var strings: [String] = []
        for i in 0..<8 {
            let flagBit: UInt8 = 1 << i
            if (self.rawValue & flagBit) != 0 {
                strings.append(String(flagBit, radix: 16, uppercase: true))
            }
        }
        return "[\(strings.joined(separator: ", "))]"
    }
}


// MARK: CoW helpers
extension HTTP2FrameDecoder {
    /// So, uh...this function needs some explaining.
    ///
    /// There is a downside to having all of the parser data in associated data on enumerations: any modification of
    /// that data will trigger copy on write for heap-allocated data. That means that when we append data to the underlying
    /// ByteBuffer we will CoW it, which is not good.
    ///
    /// The way we can avoid this is by using this helper function. It will temporarily set state to a value with no
    /// associated data, before attempting the body of the function. It will also verify that the parser never
    /// remains in this bad state.
    ///
    /// A key note here is that all callers must ensure that they return to a good state before they exit.
    ///
    /// Sadly, because it's generic and has a closure, we need to force it to be inlined at all call sites, which is
    /// not ideal.
    @inline(__always)
    private mutating func avoidingParserCoW<ReturnType>(_ body: (inout ParserState) -> ReturnType) -> ReturnType {
        self.state = .appending
        defer {
            assert(!self.isAppending)
        }

        return body(&self.state)
    }

    private var isAppending: Bool {
        if case .appending = self.state {
            return true
        } else {
            return false
        }
    }
}
