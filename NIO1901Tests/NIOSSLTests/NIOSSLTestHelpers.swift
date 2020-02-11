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
import CNIOBoringSSL
@testable import NIOSSL

let samplePemCert = """
-----BEGIN CERTIFICATE-----
MIIGGzCCBAOgAwIBAgIJAJ/X0Fo0ynmEMA0GCSqGSIb3DQEBCwUAMIGjMQswCQYD
VQQGEwJVUzETMBEGA1UECAwKQ2FsaWZvcm5pYTEWMBQGA1UEBwwNU2FuIEZyYW5z
b2t5bzEuMCwGA1UECgwlU2FuIEZyYW5zb2t5byBJbnN0aXR1dGUgb2YgVGVjaG5v
bG9neTEVMBMGA1UECwwMUm9ib3RpY3MgTGFiMSAwHgYDVQQDDBdyb2JvdHMuc2Fu
ZnJhbnNva3lvLmVkdTAeFw0xNzEwMTYyMTAxMDJaFw00NzEwMDkyMTAxMDJaMIGj
MQswCQYDVQQGEwJVUzETMBEGA1UECAwKQ2FsaWZvcm5pYTEWMBQGA1UEBwwNU2Fu
IEZyYW5zb2t5bzEuMCwGA1UECgwlU2FuIEZyYW5zb2t5byBJbnN0aXR1dGUgb2Yg
VGVjaG5vbG9neTEVMBMGA1UECwwMUm9ib3RpY3MgTGFiMSAwHgYDVQQDDBdyb2Jv
dHMuc2FuZnJhbnNva3lvLmVkdTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoC
ggIBAO9rzJOOE8cmsIqAJMCrHDxkBAMgZhMsJ863MnWtVz5JIJK6CKI/Nu26tEzo
kHy3EI9565RwikvauheMsWaTFA4PD/P+s1DtxRCGIcK5x+SoTN7Drn5ZueoJNZRf
TYuN+gwyhprzrZrYjXpvEVPYuSIeUqK5XGrTyFA2uGj9wY3f9IF4rd7JT0ewRb1U
8OcR7xQbXKGjkY4iJE1TyfmIsBZboKaG/aYa9KbnWyTkDssaELWUIKrjwwuPgVgS
vlAYmo12MlsGEzkO9z78jvFmhUOsaEldM8Ua2AhOKW0oSYgauVuro/Ap/o5zn8PD
IDapl9g+5vjN2LucqX2a9utoFvxSKXT4NvfpL9fJvzdBNMM4xpqtHIkV0fkiMbWk
EW2FFlOXKnIJV8wT4a9iduuIDMg8O7oc+gt9pG9MHTWthXm4S29DARTqfZ48bW77
z8RrEURV03o05b/twuAJSRyyOCUi61yMo3YNytebjY2W3Pxqpq+YmT5qhqBZDLlT
LMptuFdISv6SQgg7JoFHGMWRXUavMj/sn5qZD4pQyZToHJ2Vtg5W/MI1pKwc3oKD
6M3/7Gf35r92V/ox6XT7+fnEsAH8AtQiZJkEbvzJ5lpUihSIaV3a/S+jnk7Lw8Tp
vjtpfjOg+wBblc38Oa9tk2WdXwYDbnvbeL26WmyHwQTUBi1jAgMBAAGjUDBOMB0G
A1UdDgQWBBToPRmTBQEF5F5LcPiUI5qBNPBU+DAfBgNVHSMEGDAWgBToPRmTBQEF
5F5LcPiUI5qBNPBU+DAMBgNVHRMEBTADAQH/MA0GCSqGSIb3DQEBCwUAA4ICAQCY
gxM5lufF2lTB9sH0s1E1VTERv37qoapNP+aw06oZkAD67QOTXFzbsM3JU1diY6rV
Y0g9CLzRO7gZY+kmi1WWnsYiMMSIGjIfsB8S+ot43LME+AJXPVeDZQnoZ6KQ/9r+
71Umi4AKLoZ9dInyUIM3EHg9pg5B0eEINrh4J+OPGtlC3NMiWxdmIkZwzfXa+64Z
8k5aX5piMTI+9BQSMWw5l7tFT/PISuI8b/Ln4IUBXKA0xkONXVnjPOmS0h7MBoc2
EipChDKnK+Mtm9GQewOCKdS2nsrCndGkIBnUix4ConUYIoywVzWGMD+9OzKNg76d
O6A7MxdjEdKhf1JDvklxInntDUDTlSFL4iEFELwyRseoTzj8vJE+cL6h6ClasYQ6
p0EeL3UpICYerfIvPhohftCivCH3k7Q1BSf0fq73cQ55nrFAHrqqYjD7HBeBS9hn
3L6bz9Eo6U9cuxX42k3l1N44BmgcDPin0+CRTirEmahUMb3gmvoSZqQ3Cz86GkIg
7cNJosc9NyevQlU9SX3ptEbv33tZtlB5GwgZ2hiGBTY0C3HaVFjLpQiSS5ygZLgI
/+AKtah7sTHIAtpUH1ZZEgKPl1Hg6J4x/dBkuk3wxPommNHaYaHREXF+fHMhBrSi
yH8agBmmECpa21SVnr7vrL+KSqfuF+GxwjSNsSR4SA==
-----END CERTIFICATE-----
"""

let samplePemKey = """
-----BEGIN RSA PRIVATE KEY-----
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
-----END RSA PRIVATE KEY-----
"""

let samplePemRSAEncryptedKey = """
-----BEGIN RSA PRIVATE KEY-----
Proc-Type: 4,ENCRYPTED
DEK-Info: AES-256-CBC,701BA8806DAD9F13E63F41109F51B2AD

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
-----END RSA PRIVATE KEY-----
"""

let samplePKCS8PemPrivateKey = """
-----BEGIN ENCRYPTED PRIVATE KEY-----
MIIFDjBABgkqhkiG9w0BBQ0wMzAbBgkqhkiG9w0BBQwwDgQIShGta1Mpj/QCAggA
MBQGCCqGSIb3DQMHBAjQbLTPjvMqpwSCBMh8omeDIM0ceuoiEhaepFqbst/jUwYh
m1pzLokTph0GS/81vmTDr9U7uI9rHiFbACRRMQBH/cCkZFUN2Jo3pJXA4q3RvGsh
4UIaWiP+SNkzKR54QcuWRzYoQs/YH8VickNp2per3zQ9R0Regx1ZaHSCk3cFRFy3
4sJtgoquwJYD2vUdQvhwcuF2Syl/VCpaQ0+KtfBqJ+4YLJPQcsL+OKLlaWFY0ivO
2oSVCg3QJrVbS8TDnrIgeL8MNhyVHQbuSyh2MlXKcjiKlJHdHXSlYSINgpUsc/Eg
cTSgod0JXvjbExrtBx2mODwM5hzDkGpdub+TptXinQg3FQjUKhBh/+wrP0HoKBcn
UFE1emd3n1s0MFN28uSN3OcX3833Lt4KAnxF4xaPfWEAk/2yuukiUqKU+K9cEhNX
V1arxKq8RLB7n7o6YFt3xuVgAJYWDk6nyr/0I2LgFj2Jz/C2v+YBFYGUcQUKgHQw
OLzzZnCrPj8JIP2cUqagZrW7JOoMsFCtroJptImaqhsm/4i3tyf2uoUWglZN8DVE
WbNbnAr5KZSl9U1/sNuEesixIWd+RrJC/l0tNmScCvJifL9WrJnccOI83EAkmz/+
W8UpcPCscAmAdOcjFQl8T37xHGxwVcvh8LyaoacBqQCYiZzO/M6bA2YuBYVpkk4v
DFXMmy2SaHGGhGHDmyn4uuzykGCOn1ZN92eT6PXZCmHz0/QCH6RIGx2cK5frfhUP
icU30GnK1jRv8QFHVx9IZQpHbALRgSNMbtF8EqWmONUIs9wQIQtEMZ2AYwq8gKL2
9Cwk2SkqO0Y8dbE/lw+iBA37/NO7KiSLB/Mpq0/zX5SfBVcGZAVzGKiyeOW5sKcI
pSOTTv5jLkoEnels2f0jsPM7aMjG+ys6wveL0tDhfKSbtjyC8Zw/eXpK9AHGW8Hr
xM7hwTkQpznyt/NUIDmjrDHg7n6O9sp7KWduP1L9bYC/n5Dj2gnxHj6FFTpMqmm7
Q6GEj/dttmqvSYeG93heWqoS/j6j45dppoKG/3vU9UWODStcc3y66WJ2ULEY0/CF
IiBd33GJgIKUJlrMGwUSAPxH2wklF3VwWFVXMnLbqpggaWlVxzVnvGjnzoHm3AW6
hWCMnvsP/pYVBMpaKKdPF6PCW1yQXjTbA67gxpGECoin2Bu/rp+t0GeVmgTcCS9a
Y2Su4cpwCD1ngIrdodWhVVJSObApRdn3SDI2xOZUgZPVT52AtEMPQ3R5eoIOfLI6
CPC7cYl2JDmMkKGLaSom1zZpCoXtPTkxDAIpaG4ofT6pIDibCSywllL1KeeVw4WX
Cr2b/BS5TZNFyPzdrMaN5og6hNkbyca73SyEADnJtHTQc6mi/Q93al4TI3RYaVpk
KWwIW4kZE/p5pONeZDNNt7dKrgkjaTylNpM9jdnBL3hU5Fxr4I6a6+IBWQC03EwC
o2zT+g6YmVkod050GMv0V60npTpbOpWIamzB+q3GMMkU9NNyw8xH7RkNS78eWLVv
niWQmWlbkzLEf5PT264+c4w9IkE8aUKY2V8Ev2k1FXZcLdfw3G5yVzrjXoAwFUaY
xnOAdO/QLMtD55Kn+jzV6dCXmyZQkBJAMLBF5xEX9DcnXCptZ2Asgvxa4EpO7jzX
v5o=
-----END ENCRYPTED PRIVATE KEY-----
"""

let sampleDerCertSPKI = Array(Data(base64Encoded: """
'MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA72vMk44TxyawioAkwKscPGQEAyBmEywnzrcyda1XPkkgkroIoj827bq0TOiQfLcQj3nrlHCKS9q6F4yxZpMUDg8P8/6zUO3FEIYhwrnH5KhM3sOuflm56gk1lF9Ni436DDKGmvOtmtiNem8RU9i5Ih5SorlcatPIUDa4aP3Bjd/0gXit3slPR7BFvVTw5xHvFBtcoaORjiIkTVPJ+YiwFlugpob9phr0pudbJOQOyxoQtZQgquPDC4+BWBK+UBiajXYyWwYTOQ73PvyO8WaFQ6xoSV0zxRrYCE4pbShJiBq5W6uj8Cn+jnOfw8MgNqmX2D7m+M3Yu5ypfZr262gW/FIpdPg29+kv18m/N0E0wzjGmq0ciRXR+SIxtaQRbYUWU5cqcglXzBPhr2J264gMyDw7uhz6C32kb0wdNa2FebhLb0MBFOp9njxtbvvPxGsRRFXTejTlv+3C4AlJHLI4JSLrXIyjdg3K15uNjZbc/Gqmr5iZPmqGoFkMuVMsym24V0hK/pJCCDsmgUcYxZFdRq8yP+yfmpkPilDJlOgcnZW2Dlb8wjWkrBzegoPozf/sZ/fmv3ZX+jHpdPv5+cSwAfwC1CJkmQRu/MnmWlSKFIhpXdr9L6OeTsvDxOm+O2l+M6D7AFuVzfw5r22TZZ1fBgNue9t4vbpabIfBBNQGLWMCAwEAAQ=='
""", options: .ignoreUnknownCharacters)!)

let sampleDerCert = pemToDer(samplePemCert)
let sampleDerKey = pemToDer(samplePemKey)
// No DER version of the private key becuase encrypted DERs aren't real.

func pemToDer(_ pem: String) -> Data {
    var lines = [String]()

    // This is very inefficient, but it doesn't really matter because this
    // code is run very infrequently and only in testing. Blame the inefficiency
    // on Linux Foundation, which currently lacks String.enumerateLines.
    let originalLines = pem.split(separator: "\n")
    for line in originalLines {
        let line = String(line)
        if !line.hasPrefix("-----") {
            lines.append(line)
        }
    }

    let encodedData = lines.joined(separator: "")
    return Data(base64Encoded: encodedData)!
}

// This function generates a random number suitable for use in an X509
// serial field. This needs to be a positive number less than 2^159
// (such that it will fit into 20 ASN.1 bytes).
// This also needs to be portable across operating systems, and the easiest
// way to do that is to use either getentropy() or read from urandom. Sadly
// we need to support old Linuxes which may not possess getentropy as a syscall
// (and definitely don't support it in glibc), so we need to read from urandom.
// In the future we should just use getentropy and be happy.
func randomSerialNumber() -> ASN1_INTEGER {
    let bytesToRead = 20
    let fd = open("/dev/urandom", O_RDONLY)
    precondition(fd != -1)
    defer {
        close(fd)
    }

    var readBytes = Array.init(repeating: UInt8(0), count: bytesToRead)
    let readCount = readBytes.withUnsafeMutableBytes {
        return read(fd, $0.baseAddress, bytesToRead)
    }
    precondition(readCount == bytesToRead)

    // Our 20-byte number needs to be converted into an integer. This is
    // too big for Swift's numbers, but BoringSSL can handle it fine.
    let bn = CNIOBoringSSL_BN_new()
    defer {
        CNIOBoringSSL_BN_free(bn)
    }
    
    _ = readBytes.withUnsafeBufferPointer {
        CNIOBoringSSL_BN_bin2bn($0.baseAddress, $0.count, bn)
    }

    // We want to bitshift this right by 1 bit to ensure it's smaller than
    // 2^159.
    CNIOBoringSSL_BN_rshift1(bn, bn)

    // Now we can turn this into our ASN1_INTEGER.
    var asn1int = ASN1_INTEGER()
    CNIOBoringSSL_BN_to_ASN1_INTEGER(bn, &asn1int)

    return asn1int
}

func generateRSAPrivateKey() -> UnsafeMutablePointer<EVP_PKEY> {
    let exponent = CNIOBoringSSL_BN_new()
    defer {
        CNIOBoringSSL_BN_free(exponent)
    }

    CNIOBoringSSL_BN_set_u64(exponent, 0x10001)

    let rsa = CNIOBoringSSL_RSA_new()!
    let generateRC = CNIOBoringSSL_RSA_generate_key_ex(rsa, CInt(2048), exponent, nil)
    precondition(generateRC == 1)

    let pkey = CNIOBoringSSL_EVP_PKEY_new()!
    let assignRC = CNIOBoringSSL_EVP_PKEY_assign(pkey, EVP_PKEY_RSA, rsa)
    
    precondition(assignRC == 1)
    return pkey
}

func addExtension(x509: UnsafeMutablePointer<X509>, nid: Int32, value: String) {
    var extensionContext = X509V3_CTX()
    
    CNIOBoringSSL_X509V3_set_ctx(&extensionContext, x509, x509, nil, nil, 0)
    let ext = value.withCString { (pointer) in
        return CNIOBoringSSL_X509V3_EXT_nconf_nid(nil, &extensionContext, nid, UnsafeMutablePointer(mutating: pointer))
    }!
    CNIOBoringSSL_X509_add_ext(x509, ext, -1)
    CNIOBoringSSL_X509_EXTENSION_free(ext)
}

func generateSelfSignedCert() -> (NIOSSLCertificate, NIOSSLPrivateKey) {
    let pkey = generateRSAPrivateKey()
    let x = CNIOBoringSSL_X509_new()!
    CNIOBoringSSL_X509_set_version(x, 2)

    // NB: X509_set_serialNumber uses an internal copy of the ASN1_INTEGER, so this is
    // safe, there will be no use-after-free.
    var serial = randomSerialNumber()
    CNIOBoringSSL_X509_set_serialNumber(x, &serial)
    
    let notBefore = CNIOBoringSSL_ASN1_TIME_new()!
    var now = time(nil)
    CNIOBoringSSL_ASN1_TIME_set(notBefore, now)
    CNIOBoringSSL_X509_set_notBefore(x, notBefore)
    CNIOBoringSSL_ASN1_TIME_free(notBefore)
    
    now += 60 * 60  // Give ourselves an hour
    let notAfter = CNIOBoringSSL_ASN1_TIME_new()!
    CNIOBoringSSL_ASN1_TIME_set(notAfter, now)
    CNIOBoringSSL_X509_set_notAfter(x, notAfter)
    CNIOBoringSSL_ASN1_TIME_free(notAfter)
    
    CNIOBoringSSL_X509_set_pubkey(x, pkey)
    
    let commonName = "localhost"
    let name = CNIOBoringSSL_X509_get_subject_name(x)
    commonName.withCString { (pointer: UnsafePointer<Int8>) -> Void in
        pointer.withMemoryRebound(to: UInt8.self, capacity: commonName.lengthOfBytes(using: .utf8)) { (pointer: UnsafePointer<UInt8>) -> Void in
            CNIOBoringSSL_X509_NAME_add_entry_by_NID(name,
                                                     NID_commonName,
                                                     MBSTRING_UTF8,
                                                     UnsafeMutablePointer(mutating: pointer),
                                                     Int32(commonName.lengthOfBytes(using: .utf8)),
                                                     -1,
                                                     0)
        }
    }
    CNIOBoringSSL_X509_set_issuer_name(x, name)
    
    addExtension(x509: x, nid: NID_basic_constraints, value: "critical,CA:FALSE")
    addExtension(x509: x, nid: NID_subject_key_identifier, value: "hash")
    addExtension(x509: x, nid: NID_subject_alt_name, value: "DNS:localhost")
    
    CNIOBoringSSL_X509_sign(x, pkey, CNIOBoringSSL_EVP_sha256())
    
    return (NIOSSLCertificate.fromUnsafePointer(takingOwnership: x), NIOSSLPrivateKey.fromUnsafePointer(takingOwnership: pkey))
}
