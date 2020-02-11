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

import Foundation
import XCTest
import NIO
@testable import NIOSSL

class SSLPrivateKeyTest: XCTestCase {
    static var pemKeyFilePath: String! = nil
    static var derKeyFilePath: String! = nil
    static var passwordPemKeyFilePath: String! = nil
    static var passwordPKCS8PemKeyFilePath: String! = nil
    static var dynamicallyGeneratedKey: NIOSSLPrivateKey! = nil

    override class func setUp() {
        SSLPrivateKeyTest.pemKeyFilePath = try! dumpToFile(text: samplePemKey)
        SSLPrivateKeyTest.derKeyFilePath = try! dumpToFile(data: sampleDerKey)
        SSLPrivateKeyTest.passwordPemKeyFilePath = try! dumpToFile(text: samplePemRSAEncryptedKey)
        SSLPrivateKeyTest.passwordPKCS8PemKeyFilePath = try! dumpToFile(text: samplePKCS8PemPrivateKey)

        let (_, key) = generateSelfSignedCert()
        SSLPrivateKeyTest.dynamicallyGeneratedKey = key
    }

    override class func tearDown() {
        _ = SSLPrivateKeyTest.pemKeyFilePath.withCString {
            unlink($0)
        }
        _ = SSLPrivateKeyTest.derKeyFilePath.withCString {
            unlink($0)
        }
        _ = SSLPrivateKeyTest.passwordPemKeyFilePath.withCString {
            unlink($0)
        }
        _ = SSLPrivateKeyTest.passwordPKCS8PemKeyFilePath.withCString {
            unlink($0)
        }
    }

    func testLoadingPemKeyFromFile() throws {
        let key1 = try NIOSSLPrivateKey(file: SSLPrivateKeyTest.pemKeyFilePath, format: .pem)
        let key2 = try NIOSSLPrivateKey(file: SSLPrivateKeyTest.pemKeyFilePath, format: .pem)

        XCTAssertEqual(key1, key2)
        XCTAssertNotEqual(key1, SSLPrivateKeyTest.dynamicallyGeneratedKey)
    }

    func testLoadingDerKeyFromFile() throws {
        let key1 = try NIOSSLPrivateKey(file: SSLPrivateKeyTest.derKeyFilePath, format: .der)
        let key2 = try NIOSSLPrivateKey(file: SSLPrivateKeyTest.derKeyFilePath, format: .der)

        XCTAssertEqual(key1, key2)
        XCTAssertNotEqual(key1, SSLPrivateKeyTest.dynamicallyGeneratedKey)
    }

    func testDerAndPemAreIdentical() throws {
        let key1 = try NIOSSLPrivateKey(file: SSLPrivateKeyTest.pemKeyFilePath, format: .pem)
        let key2 = try NIOSSLPrivateKey(file: SSLPrivateKeyTest.derKeyFilePath, format: .der)

        XCTAssertEqual(key1, key2)
    }

    func testLoadingPemKeyFromMemory() throws {
        let key1 = try NIOSSLPrivateKey(buffer: [Int8](samplePemKey.utf8CString), format: .pem)
        let key2 = try NIOSSLPrivateKey(buffer: [Int8](samplePemKey.utf8CString), format: .pem)

        XCTAssertEqual(key1, key2)
    }

    func testLoadingDerKeyFromMemory() throws {
        let keyBuffer = sampleDerKey.asArray()
        let key1 = try NIOSSLPrivateKey(buffer: keyBuffer, format: .der)
        let key2 = try NIOSSLPrivateKey(buffer: keyBuffer, format: .der)

        XCTAssertEqual(key1, key2)
    }

    func testLoadingGibberishFromMemoryAsPemFails() throws {
        let keyBuffer: [Int8] = [1, 2, 3]

        do {
            _ = try NIOSSLPrivateKey(buffer: keyBuffer, format: .pem)
            XCTFail("Gibberish successfully loaded")
        } catch NIOSSLError.failedToLoadPrivateKey {
            // Do nothing.
        }
    }

    func testLoadingGibberishFromMemoryAsDerFails() throws {
        let keyBuffer: [Int8] = [1, 2, 3]

        do {
            _ = try NIOSSLPrivateKey(buffer: keyBuffer, format: .der)
            XCTFail("Gibberish successfully loaded")
        } catch NIOSSLError.failedToLoadPrivateKey {
            // Do nothing.
        }
    }

    func testLoadingGibberishFromFileAsPemFails() throws {
        let tempFile = try dumpToFile(text: "hello")
        defer {
            _ = tempFile.withCString { unlink($0) }
        }

        do {
            _ = try NIOSSLPrivateKey(file: tempFile, format: .pem)
            XCTFail("Gibberish successfully loaded")
        } catch NIOSSLError.failedToLoadPrivateKey {
            // Do nothing.
        }
    }

    func testLoadingGibberishFromFileAsDerFails() throws {
        let tempFile = try dumpToFile(text: "hello")
        defer {
            _ = tempFile.withCString { unlink($0) }
        }

        do {
            _ = try NIOSSLPrivateKey(file: tempFile, format: .der)
            XCTFail("Gibberish successfully loaded")
        } catch NIOSSLError.failedToLoadPrivateKey {
            // Do nothing.
        }
    }

    func testLoadingNonexistentFileAsPem() throws {
        do {
            _ = try NIOSSLPrivateKey(file: "/nonexistent/path", format: .pem)
            XCTFail("Did not throw")
        } catch let error as IOError {
            XCTAssertEqual(error.errnoCode, ENOENT)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLoadingNonexistentFileAsDer() throws {
        do {
            _ = try NIOSSLPrivateKey(file: "/nonexistent/path", format: .der)
            XCTFail("Did not throw")
        } catch let error as IOError {
            XCTAssertEqual(error.errnoCode, ENOENT)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLoadingNonexistentFileAsPemWithPassphrase() throws {
        do {
            _ = try NIOSSLPrivateKey(file: "/nonexistent/path", format: .pem) { (_: NIOSSLPassphraseSetter<Array<UInt8>>) in
                XCTFail("Should not be called")
            }
            XCTFail("Did not throw")
        } catch let error as IOError {
            XCTAssertEqual(error.errnoCode, ENOENT)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLoadingNonexistentFileAsDerWithPassphrase() throws {
        do {
            _ = try NIOSSLPrivateKey(file: "/nonexistent/path", format: .der) { (_: NIOSSLPassphraseSetter<Array<UInt8>>) in
                XCTFail("Should not be called")
            }
            XCTFail("Did not throw")
        } catch let error as IOError {
            XCTAssertEqual(error.errnoCode, ENOENT)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLoadingEncryptedRSAKeyFromMemory() throws {
        let key1 = try NIOSSLPrivateKey(buffer: [Int8](samplePemRSAEncryptedKey.utf8CString), format: .pem) { closure in closure("thisisagreatpassword".utf8) }
        let key2 = try NIOSSLPrivateKey(buffer: [Int8](samplePemRSAEncryptedKey.utf8CString), format: .pem) { closure in closure("thisisagreatpassword".utf8) }

        XCTAssertEqual(key1, key2)
    }

    func testLoadingEncryptedRSAPKCS8KeyFromMemory() throws {
        let key1 = try NIOSSLPrivateKey(buffer: [Int8](samplePKCS8PemPrivateKey.utf8CString), format: .pem) { closure in closure("thisisagreatpassword".utf8) }
        let key2 = try NIOSSLPrivateKey(buffer: [Int8](samplePKCS8PemPrivateKey.utf8CString), format: .pem) { closure in closure("thisisagreatpassword".utf8) }

        XCTAssertEqual(key1, key2)
    }

    func testLoadingEncryptedRSAKeyFromFile() throws {
        let key1 = try NIOSSLPrivateKey(file: SSLPrivateKeyTest.passwordPemKeyFilePath, format: .pem) { closure in closure("thisisagreatpassword".utf8) }
        let key2 = try NIOSSLPrivateKey(file: SSLPrivateKeyTest.passwordPemKeyFilePath, format: .pem) { closure in closure("thisisagreatpassword".utf8) }

        XCTAssertEqual(key1, key2)
    }

    func testLoadingEncryptedRSAPKCS8KeyFromFile() throws {
        let key1 = try NIOSSLPrivateKey(file: SSLPrivateKeyTest.passwordPKCS8PemKeyFilePath, format: .pem) { closure in closure("thisisagreatpassword".utf8) }
        let key2 = try NIOSSLPrivateKey(file: SSLPrivateKeyTest.passwordPKCS8PemKeyFilePath, format: .pem) { closure in closure("thisisagreatpassword".utf8) }

        XCTAssertEqual(key1, key2)
    }

    func testWildlyOverlongPassphraseRSAFromMemory() throws {
        do {
            _ = try NIOSSLPrivateKey(buffer: [Int8](samplePemRSAEncryptedKey.utf8CString), format: .pem) { closure in closure(Array(repeating: UInt8(8), count: 1 << 16)) }
            XCTFail("Should not have created the key")
        } catch NIOSSLError.failedToLoadPrivateKey {
            // ok
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testWildlyOverlongPassphrasePKCS8FromMemory() throws {
        do {
            _ = try NIOSSLPrivateKey(buffer: [Int8](samplePKCS8PemPrivateKey.utf8CString), format: .pem) { closure in closure(Array(repeating: UInt8(8), count: 1 << 16)) }
            XCTFail("Should not have created the key")
        } catch NIOSSLError.failedToLoadPrivateKey {
            // ok
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testWildlyOverlongPassphraseRSAFromFile() throws {
        do {
            _ = try NIOSSLPrivateKey(buffer: [Int8](samplePemRSAEncryptedKey.utf8CString), format: .pem) { closure in closure(Array(repeating: UInt8(8), count: 1 << 16)) }
            XCTFail("Should not have created the key")
        } catch NIOSSLError.failedToLoadPrivateKey {
            // ok
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testWildlyOverlongPassphrasePKCS8FromFile() throws {
        do {
            _ = try NIOSSLPrivateKey(buffer: [Int8](samplePKCS8PemPrivateKey.utf8CString), format: .pem) { closure in closure(Array(repeating: UInt8(8), count: 1 << 16)) }
            XCTFail("Should not have created the key")
        } catch NIOSSLError.failedToLoadPrivateKey {
            // ok
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testThrowingPassphraseCallback() throws {
        enum MyError: Error {
            case error
        }

        do {
            _ = try NIOSSLPrivateKey(buffer: [Int8](samplePemRSAEncryptedKey.utf8CString), format: .pem) { (_: NIOSSLPassphraseSetter<Array<UInt8>>) in
                throw MyError.error
            }
            XCTFail("Should not have created the key")
        } catch NIOSSLError.failedToLoadPrivateKey {
            // ok
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
