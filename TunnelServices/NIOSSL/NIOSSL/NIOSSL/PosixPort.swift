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

// This file contains a version of the SwiftNIO Posix enum. This is necessary
// because SwiftNIO's version is internal. Our version exists for the same reason:
// to ensure errno is captured correctly when doing syscalls, and that no ARC traffic
// can happen inbetween that *could* change the errno value before we were able to
// read it.
//
// The code is an exact port from SwiftNIO, so if that version ever becomes public we
// can lift anything missing from there and move it over without change.
import NIO

private let sysFopen: @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> UnsafeMutablePointer<FILE>? = fopen
private let sysMlock: @convention(c) (UnsafeRawPointer?, size_t) -> CInt = mlock
private let sysMunlock: @convention(c) (UnsafeRawPointer?, size_t) -> CInt = munlock
private let sysFclose: @convention(c) (UnsafeMutablePointer<FILE>?) -> CInt = fclose

// Sadly, stat has different signatures with glibc and macOS libc.
#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS) || os(Android)
private let sysStat: @convention(c) (UnsafePointer<CChar>?, UnsafeMutablePointer<stat>?) -> CInt = stat(_:_:)
#elseif os(Linux) || os(FreeBSD)
private let sysStat: @convention(c) (UnsafePointer<CChar>, UnsafeMutablePointer<stat>) -> CInt = stat(_:_:)
#endif


// MARK:- Copied code from SwiftNIO
private func isBlacklistedErrno(_ code: CInt) -> Bool {
    switch code {
    case EFAULT, EBADF:
        return true
    default:
        return false
    }
}

/* Sorry, we really try hard to not use underscored attributes. In this case however we seem to break the inlining threshold which makes a system call take twice the time, ie. we need this exception. */
@inline(__always)
internal func wrapSyscall<T: FixedWidthInteger>(where function: StaticString = #function, _ body: () throws -> T) throws -> T {
    while true {
        let res = try body()
        if res == -1 {
            let err = errno
            if err == EINTR {
                continue
            }
            assert(!isBlacklistedErrno(err), "blacklisted errno \(err) \(strerror(err)!)")
            throw IOError(errnoCode: err, function: function)
        }
        return res
    }
}

/* Sorry, we really try hard to not use underscored attributes. In this case however we seem to break the inlining threshold which makes a system call take twice the time, ie. we need this exception. */
@inline(__always)
internal func wrapErrorIsNullReturnCall<T>(where function: StaticString = #function, _ body: () throws -> T?) throws -> T {
    while true {
        guard let res = try body() else {
            let err = errno
            if err == EINTR {
                continue
            }
            assert(!isBlacklistedErrno(err), "blacklisted errno \(err) \(strerror(err)!)")
            throw IOError(errnoCode: err, function: function)
        }
        return res
    }
}

// MARK:- Our functions
internal enum Posix {
    @inline(never)
    internal static func fopen(file: UnsafePointer<CChar>, mode: UnsafePointer<CChar>) throws -> UnsafeMutablePointer<FILE> {
        return try wrapErrorIsNullReturnCall {
            sysFopen(file, mode)
        }
    }

    @inline(never)
    internal static func fclose(file: UnsafeMutablePointer<FILE>) throws -> CInt {
        return try wrapSyscall {
            sysFclose(file)
        }
    }

    @inline(never)
    @discardableResult
    internal static func stat(path: UnsafePointer<CChar>, buf: UnsafeMutablePointer<stat>) throws -> CInt {
        return try wrapSyscall {
            sysStat(path, buf)
        }
    }

    @inline(never)
    @discardableResult
    internal static func mlock(addr: UnsafeRawPointer, len: size_t) throws -> CInt {
        return try wrapSyscall {
            sysMlock(addr, len)
        }
    }

    @inline(never)
    @discardableResult
    internal static func munlock(addr: UnsafeRawPointer, len: size_t) throws -> CInt {
        return try wrapSyscall {
            sysMunlock(addr, len)
        }
    }
}
