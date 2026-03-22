import XCTest
import KnotStorage
@testable import TunnelServices

final class TextAccumulatorTests: XCTestCase {
    func testAccumulatesText() {
        let acc = TextAccumulator(maxSize: 1024)
        acc.append(Data("Hello ".utf8))
        acc.append(Data("World".utf8))
        XCTAssertEqual(acc.text, "Hello World")
    }

    func testRespectsMaxSize() {
        let acc = TextAccumulator(maxSize: 10)
        acc.append(Data("12345".utf8))
        acc.append(Data("67890EXTRA".utf8))
        // Should only keep first 10 bytes
        XCTAssertEqual(acc.text, "1234567890")
    }

    func testStopsAccumulatingAfterMax() {
        let acc = TextAccumulator(maxSize: 5)
        acc.append(Data("ABCDE".utf8))  // fills to max
        acc.append(Data("FGH".utf8))    // should be ignored
        XCTAssertEqual(acc.text, "ABCDE")
    }

    func testReturnsNilForBinaryData() {
        let acc = TextAccumulator(maxSize: 1024)
        acc.append(Data([0xFF, 0xFE, 0x00, 0x80, 0xC0]))
        XCTAssertNil(acc.text)
    }

    func testEmptyAccumulator() {
        let acc = TextAccumulator(maxSize: 1024)
        XCTAssertNil(acc.text) // no data appended → nil (not empty string)
    }

    func testMixedValidAndInvalidUTF8() {
        let acc = TextAccumulator(maxSize: 1024)
        acc.append(Data("Hello".utf8))
        acc.append(Data([0xFF, 0xFE]))  // invalid UTF-8
        XCTAssertNil(acc.text) // entire buffer is not valid UTF-8
    }
}
