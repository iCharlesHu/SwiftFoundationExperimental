//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

import System
#if canImport(TestSupport)
import TestSupport
#endif
@testable import FoundationEssentials

final class SubprocessTests : XCTestCase {
    func testCURL() throws {
        struct Address: Codable {
            let ip: String
        }

        let (readFd, writeFd) = try FileDescriptor.pipe()
        let curl = Subprocess(
            executablePath: "/usr/bin/curl",
            arguments: ["http://ip.jsontest.com/"],
            environments: [:],
            standardOutput: writeFd
        )

        let buffer: UnsafeMutableRawBufferPointer = .allocate(byteCount: 1024, alignment: 1)
        defer { buffer.deallocate() }
        let readSize = try readFd.read(into: buffer)
        let data = Data(bytes: buffer.baseAddress!, count: readSize)
        let address = try JSONDecoder().decode(Address.self, from: data)
        XCTAssertTrue(address.ip.contains(":") || address.ip.contains("."))
    }
}
