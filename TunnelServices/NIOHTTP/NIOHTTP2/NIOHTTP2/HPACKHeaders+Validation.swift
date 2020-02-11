//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2019 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
import NIOHPACK

extension HPACKHeaders {
    /// Checks that a given HPACKHeaders block is a valid request header block, meeting all of the constraints of RFC 7540.
    ///
    /// If the header block is not valid, throws an error.
    internal func validateRequestBlock() throws {
        return try RequestBlockValidator.validateBlock(self)
    }

    /// Checks that a given HPACKHeaders block is a valid response header block, meeting all of the constraints of RFC 7540.
    ///
    /// If the header block is not valid, throws an error.
    internal func validateResponseBlock() throws {
        return try ResponseBlockValidator.validateBlock(self)
    }

    /// Checks that a given HPACKHeaders block is a valid trailer block, meeting all of the constraints of RFC 7540.
    ///
    /// If the header block is not valid, throws an error.
    internal func validateTrailersBlock() throws {
        return try TrailersValidator.validateBlock(self)
    }
}


/// A HTTP/2 header block is divided into two sections: the leading section, containing pseudo-headers, and
/// the regular header section. Once the first regular header has been seen and we have transitioned into the
/// header section, it is an error to see a pseudo-header again in this block.
fileprivate enum BlockSection {
    case pseudoHeaders
    case headers

    fileprivate mutating func validField(_ field: HeaderFieldName) throws {
        switch (self, field.fieldType) {
        case (.pseudoHeaders, .pseudoHeaderField),
             (.headers, .regularHeaderField):
            // Another header of the same type we're expecting. Do nothing.
            break

        case (.pseudoHeaders, .regularHeaderField):
            // The regular header fields have begun.
            self = .headers

        case (.headers, .pseudoHeaderField):
            // This is an error: it's not allowed to send a pseudo-header field once a regular
            // header field has been sent.
            throw NIOHTTP2Errors.PseudoHeaderAfterRegularHeader(":\(field.baseName)")
        }
    }
}


/// A `HeaderBlockValidator` is an object that can confirm that a HPACK block meets certain constraints.
fileprivate protocol HeaderBlockValidator {
    init()

    var allowedPseudoHeaderFields: PseudoHeaders { get }

    var mandatoryPseudoHeaderFields: PseudoHeaders { get }

    mutating func validateNextField(name: HeaderFieldName, value: String, pseudoHeaderType: PseudoHeaders?) throws
}


extension HeaderBlockValidator {
    /// Validates that a header block meets the requirements of this `HeaderBlockValidator`.
    fileprivate static func validateBlock(_ block: HPACKHeaders) throws {
        var validator = Self()
        var blockSection = BlockSection.pseudoHeaders
        var seenPseudoHeaders = PseudoHeaders(rawValue: 0)

        for (name, value, _) in block {
            let fieldName = try HeaderFieldName(name)
            try blockSection.validField(fieldName)
            try fieldName.legalHeaderField(value: value)

            let thisPseudoHeaderFieldType = try seenPseudoHeaders.seenNewHeaderField(fieldName)

            try validator.validateNextField(name: fieldName, value: value, pseudoHeaderType: thisPseudoHeaderFieldType)
        }

        // We must only have seen pseudo-header fields allowed on this type of header block,
        // and at least the mandatory set.
        guard validator.allowedPseudoHeaderFields.isSuperset(of: seenPseudoHeaders) &&
              validator.mandatoryPseudoHeaderFields.isSubset(of: seenPseudoHeaders) else {
            throw NIOHTTP2Errors.InvalidPseudoHeaders(block)
        }
    }
}


/// An object that can be used to validate if a given header block is a valid request header block.
fileprivate struct RequestBlockValidator {
    private var isConnectRequest: Bool = false
}

extension RequestBlockValidator: HeaderBlockValidator {
    fileprivate mutating func validateNextField(name: HeaderFieldName, value: String, pseudoHeaderType: PseudoHeaders?) throws {
        // We have a wrinkle here: the set of allowed and mandatory pseudo headers for requests depends on whether this request is a CONNECT request.
        // If it isn't, RFC 7540 § 8.1.2.3 rules, and says that:
        //
        // > All HTTP/2 requests MUST include exactly one valid value for the ":method", ":scheme", and ":path" pseudo-header fields
        //
        // Unfortunately, it also has an extra clause that says "unless it is a CONNECT request". That clause makes RFC 7540 § 8.3 relevant, which
        // says:
        //
        // > The ":scheme" and ":path" pseudo-header fields MUST be omitted.
        //
        // Implicitly, the :authority pseudo-header field must be present here as well, as § 8.3 imposes a specific form on that header field which
        // cannot make much sense if the field is optional.
        //
        // This is further complicated by RFC 8441 (Bootstrapping WebSockets with HTTP/2) which defines the "extended" CONNECT method. RFC 8441 § 4
        // says:
        //
        // > A new pseudo-header field :protocol MAY be included on request HEADERS indicating the desired protocol to be spoken on the tunnel
        // > created by CONNECT.
        //
        // > On requests that contain the :protocol pseudo-header field, the :scheme and :path pseudo-header fields of the target URI
        // > MUST also be included.
        //
        // > On requests bearing the :protocol pseudo-header field, the :authority pseudo-header field is interpreted according to
        // > Section 8.1.2.3 of [RFC7540] instead of Section 8.3 of that document.
        //
        // We can summarise these rules loosely by saying that:
        //
        // - On non-CONNECT requests or CONNECT requests with the :protocol pseudo-header, :method, :scheme, and :path are mandatory, :authority is allowed.
        // - On CONNECT requests without the :protocol pseudo-header, :method and :authority are mandatory, no others are allowed.
        //
        // This is a bit awkward.
        //
        // For now we don't support extended-CONNECT, but when we do we'll need to update the logic here.
        if let pseudoHeaderType = pseudoHeaderType {
            assert(name.fieldType == .pseudoHeaderField)

            switch pseudoHeaderType {
            case .method:
                // This is a method pseudo-header. Check if the value is CONNECT.
                self.isConnectRequest = value == "CONNECT"
            case .path:
                // This is a path pseudo-header. It must not be empty.
                if value.utf8.count == 0 {
                    throw NIOHTTP2Errors.EmptyPathHeader()
                }
            default:
                break
            }
        } else {
            assert(name.fieldType == .regularHeaderField)

            // We want to check that if the TE header field is present, it only contains "trailers".
            if name.baseName == "te" && value != "trailers" {
                throw NIOHTTP2Errors.ForbiddenHeaderField(name: String(name.baseName), value: value)
            }
        }
    }

    var allowedPseudoHeaderFields: PseudoHeaders {
        // For the logic behind this if statement, see the comment in validateNextField.
        if self.isConnectRequest {
            return .allowedConnectRequestHeaders
        } else {
            return .allowedRequestHeaders
        }
    }

    var mandatoryPseudoHeaderFields: PseudoHeaders {
        // For the logic behind this if statement, see the comment in validateNextField.
        if self.isConnectRequest {
            return .mandatoryConnectRequestHeaders
        } else {
            return .mandatoryRequestHeaders
        }
    }
}


/// An object that can be used to validate if a given header block is a valid response header block.
fileprivate struct ResponseBlockValidator {
    let allowedPseudoHeaderFields: PseudoHeaders = .allowedResponseHeaders

    let mandatoryPseudoHeaderFields: PseudoHeaders = .mandatoryResponseHeaders
}

extension ResponseBlockValidator: HeaderBlockValidator {
    fileprivate mutating func validateNextField(name: HeaderFieldName, value: String, pseudoHeaderType: PseudoHeaders?) throws {
        return
    }
}


/// An object that can be used to validate if a given header block is a valid trailer block.
fileprivate struct TrailersValidator {
    let allowedPseudoHeaderFields: PseudoHeaders = []

    let mandatoryPseudoHeaderFields: PseudoHeaders = []
}

extension TrailersValidator: HeaderBlockValidator {
    fileprivate mutating func validateNextField(name: HeaderFieldName, value: String, pseudoHeaderType: PseudoHeaders?) throws {
        return
    }
}


/// A structure that carries the details of a specific header field name.
///
/// Used to validate the correctness of a specific header field name at a given
/// point in a header block.
fileprivate struct HeaderFieldName {
    /// The type of this header-field: pseudo-header or regular.
    fileprivate var fieldType: FieldType

    /// The base name of this header field, which is the name with any leading colon stripped off.
    fileprivate var baseName: Substring
}

extension HeaderFieldName {
    /// The types of header fields in HTTP/2.
    enum FieldType {
        case pseudoHeaderField
        case regularHeaderField
    }
}

extension HeaderFieldName {
    fileprivate init(_ fieldName: String) throws {
        let fieldSubstring = Substring(fieldName)
        let fieldBytes = fieldSubstring.utf8

        let baseNameBytes: Substring.UTF8View
        if fieldBytes.first == UInt8(ascii: ":") {
            baseNameBytes = fieldBytes.dropFirst()
            self.fieldType = .pseudoHeaderField
            self.baseName = fieldSubstring.dropFirst()
        } else {
            baseNameBytes = fieldBytes
            self.fieldType = .regularHeaderField
            self.baseName = fieldSubstring
        }

        guard baseNameBytes.isValidFieldName else {
            throw NIOHTTP2Errors.InvalidHTTP2HeaderFieldName(fieldName)
        }
    }

    func legalHeaderField(value: String) throws {
        // RFC 7540 § 8.1.2.2 forbids all connection-specific header fields. A connection-specific header field technically
        // is one that is listed in the Connection header, but could also be proxy-connection & transfer-encoding, even though
        // those are not usually listed in the Connection header. For defensiveness sake, we forbid those too.
        //
        // There is one more wrinkle, which is that the client is allowed to send TE: trailers, and forbidden from sending TE
        // with anything else. We police that separately, as TE is only defined on requests, so we can avoid checking for it
        // on responses and trailers.
        guard self.fieldType == .regularHeaderField else {
            // Pseudo-headers are never connection-specific.
            return
        }

        switch self.baseName {
        case "connection", "transfer-encoding", "proxy-connection":
            throw NIOHTTP2Errors.ForbiddenHeaderField(name: String(self.baseName), value: value)
        default:
            return
        }
    }
}


extension Substring.UTF8View {
    /// Whether this is a valid HTTP/2 header field name.
    fileprivate var isValidFieldName: Bool {
        /// RFC 7230 defines header field names as matching the `token` ABNF, which is:
        ///
        ///     token          = 1*tchar
        ///
        ///     tchar          = "!" / "#" / "$" / "%" / "&" / "'" / "*"
        ///                    / "+" / "-" / "." / "^" / "_" / "`" / "|" / "~"
        ///                    / DIGIT / ALPHA
        ///                    ; any VCHAR, except delimiters
        ///
        ///     DIGIT          =  %x30-39
        ///                    ; 0-9
        ///
        ///     ALPHA          =  %x41-5A / %x61-7A   ; A-Z / a-z
        ///
        /// RFC 7540 subsequently clarifies that HTTP/2 headers must be converted to lowercase before
        /// sending. This therefore excludes the range A-Z in ALPHA. If we convert tchar to the range syntax
        /// used in DIGIT and ALPHA, and then collapse the ranges that are more than two elements long, we get:
        ///
        ///     tchar          = %x21 / %x23-27 / %x2A / %x2B / %x2D / %x2E / %x5E-60 / %x7C / %x7E / %x30-39 /
        ///                    / %x41-5A / %x61-7A
        ///
        /// Now we can strip out the uppercase characters, and shuffle these so they're in ascending order:
        ///
        ///     tchar          = %x21 / %x23-27 / %x2A / %x2B / %x2D / %x2E / %x30-39 / %x5E-60 / %x61-7A
        ///                    / %x7C / %x7E
        ///
        /// Then we can also spot that we have a pair of ranges that bump into each other and do one further level
        /// of collapsing.
        ///
        ///     tchar          = %x21 / %x23-27 / %x2A / %x2B / %x2D / %x2E / %x30-39 / %x5E-7A
        ///                    / %x7C / %x7E
        ///
        /// We can then translate this into a straightforward switch statement to check whether the code
        /// units are valid.
        return self.allSatisfy { codeUnit in
            switch codeUnit {
            case 0x21, 0x23...0x27, 0x2a, 0x2b, 0x2d, 0x2e, 0x30...0x39,
                 0x5e...0x7a, 0x7c, 0x7e:
                return true
            default:
                return false
            }
        }
    }
}


/// A set of all pseudo-headers defined in HTTP/2.
fileprivate struct PseudoHeaders: OptionSet {
    var rawValue: UInt8

    static let path = PseudoHeaders(rawValue: 1 << 0)
    static let method = PseudoHeaders(rawValue: 1 << 1)
    static let scheme = PseudoHeaders(rawValue: 1 << 2)
    static let authority = PseudoHeaders(rawValue: 1 << 3)
    static let status = PseudoHeaders(rawValue: 1 << 4)

    static let mandatoryRequestHeaders: PseudoHeaders = [.path, .method, .scheme]
    static let allowedRequestHeaders: PseudoHeaders = [.path, .method, .scheme, .authority]
    static let mandatoryConnectRequestHeaders: PseudoHeaders = [.method, .authority]
    static let allowedConnectRequestHeaders: PseudoHeaders = [.method, .authority]
    static let mandatoryResponseHeaders: PseudoHeaders = [.status]
    static let allowedResponseHeaders: PseudoHeaders = [.status]
}

extension PseudoHeaders {
    /// Obtain a PseudoHeaders optionset containing the bit for a known pseudo header. Fails if this is an unknown pseudoheader.
    /// Traps if this is not a pseudo-header at all.
    init?(headerFieldName name: HeaderFieldName) {
        precondition(name.fieldType == .pseudoHeaderField)

        switch name.baseName {
        case "path":
            self = .path
        case "method":
            self = .method
        case "scheme":
            self = .scheme
        case "authority":
            self = .authority
        case "status":
            self = .status
        default:
            return nil
        }
    }
}

extension PseudoHeaders {
    /// Updates this set of PseudoHeaders with any new pseudo headers we've seen. Also returns a PseudoHeaders that marks
    /// the type of this specific header field.
    mutating func seenNewHeaderField(_ name: HeaderFieldName) throws -> PseudoHeaders? {
        // We need to check if this is a pseudo-header field we've seen before and one we recognise.
        // We only want to see a pseudo-header field once.
        guard name.fieldType == .pseudoHeaderField else {
            return nil
        }

        guard let pseudoHeaderType = PseudoHeaders(headerFieldName: name) else {
            throw NIOHTTP2Errors.UnknownPseudoHeader(":\(name.baseName)")
        }

        if self.contains(pseudoHeaderType) {
            throw NIOHTTP2Errors.DuplicatePseudoHeader(":\(name.baseName)")
        }

        self.formUnion(pseudoHeaderType)

        return pseudoHeaderType
    }
}
