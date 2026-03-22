//
//  XMLFormatter.swift
//  TunnelServices
//
//  XML/SOAP content detection and pretty-printing.
//  Netty reference: codec-xml/XmlFrameDecoder.java
//

import Foundation

public class XMLFormatter {

    /// Detect XML/SOAP content type.
    public static func isXML(contentType: String?) -> Bool {
        guard let ct = contentType?.lowercased() else { return false }
        return ct.contains("xml") || ct.contains("soap")
    }

    /// Pretty-print XML with indentation.
    public static func prettyPrint(_ xmlString: String, indent: Int = 2) -> String? {
        guard let data = xmlString.data(using: .utf8) else { return nil }

        let parser = PrettyXMLParser(indent: indent)
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        guard xmlParser.parse() else { return nil }
        return parser.result
    }

    /// Extract SOAP action from headers or body.
    public static func soapAction(headers: [(String, String)]) -> String? {
        // SOAPAction header
        if let action = headers.first(where: { $0.0.lowercased() == "soapaction" })?.1 {
            return action.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return nil
    }

    /// Format XML content for session display.
    public static func formatForDisplay(_ data: Data, maxLength: Int = 4096) -> String {
        guard let str = String(data: data.prefix(maxLength), encoding: .utf8) else {
            return "[\(data.count) bytes binary XML]"
        }

        // Try pretty printing
        if let pretty = prettyPrint(str) {
            return pretty
        }

        // Fallback: return raw
        return str
    }
}

// MARK: - Pretty Printer

private class PrettyXMLParser: NSObject, XMLParserDelegate {
    private let indentStr: String
    private var depth = 0
    private var output = ""
    private var currentText = ""

    var result: String { output }

    init(indent: Int) {
        self.indentStr = String(repeating: " ", count: indent)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        flushText()
        output += "\(prefix)<\(elementName)"
        for (key, value) in attributes {
            output += " \(key)=\"\(value)\""
        }
        output += ">\n"
        depth += 1
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        depth -= 1
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            output += "\(prefix)  \(text)\n"
        }
        currentText = ""
        output += "\(prefix)</\(elementName)>\n"
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    private func flushText() {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            output += "\(prefix)\(text)\n"
        }
        currentText = ""
    }

    private var prefix: String {
        String(repeating: indentStr, count: depth)
    }
}
