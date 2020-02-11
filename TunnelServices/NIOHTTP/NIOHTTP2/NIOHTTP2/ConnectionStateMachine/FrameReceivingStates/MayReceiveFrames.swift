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

/// A protocol that provides implementation for receiving frames, for those states that
/// can validly receive any frames.
///
/// This protocol should only be conformed to by states for the HTTP/2 connection state machine.
protocol MayReceiveFrames:
    ReceivingHeadersState,
    ReceivingDataState,
    ReceivingPushPromiseState,
    ReceivingWindowUpdateState,
    ReceivingRstStreamState,
    ReceivingGoawayState { }
