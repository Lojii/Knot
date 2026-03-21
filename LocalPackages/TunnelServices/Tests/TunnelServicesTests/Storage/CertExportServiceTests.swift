//
//  CertExportServiceTests.swift
//  TunnelServicesTests
//

import XCTest
@testable import TunnelServices

final class CertExportServiceTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testSavePEMCreatesFile() throws {
        let service = CertExportService(fileFolder: tempDir.path)
        let testPEM = "-----BEGIN CERTIFICATE-----\nTESTDATA\n-----END CERTIFICATE-----\n"
        let ref = try service.savePEMString(flowId: "test-1", pemContent: testPEM)

        XCTAssertEqual(ref, "certs/test-1.pem")
        let fullPath = tempDir.appendingPathComponent(ref).path
        XCTAssertTrue(FileManager.default.fileExists(atPath: fullPath))
        let content = try String(contentsOfFile: fullPath)
        XCTAssertEqual(content, testPEM)
    }

    func testExportReturnsFileContent() throws {
        let service = CertExportService(fileFolder: tempDir.path)
        let testPEM = "-----BEGIN CERTIFICATE-----\nDATA\n-----END CERTIFICATE-----\n"
        let ref = try service.savePEMString(flowId: "exp-1", pemContent: testPEM)

        let result = service.exportCertChain(certChainRef: ref)
        switch result {
        case .success(let export):
            XCTAssertEqual(export.pemText, testPEM)
        case .failure(let error):
            XCTFail("Export failed: \(error)")
        }
    }

    func testExportMissingFileReturnsError() {
        let service = CertExportService(fileFolder: tempDir.path)
        let result = service.exportCertChain(certChainRef: "certs/nonexistent.pem")
        if case .failure(let error) = result {
            if case .fileNotFound = error { /* expected */ }
            else { XCTFail("Wrong error type: \(error)") }
        } else {
            XCTFail("Should have failed")
        }
    }
}
