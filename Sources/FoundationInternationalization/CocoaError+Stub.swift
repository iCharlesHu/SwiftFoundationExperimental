//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#if !FOUNDATION_FRAMEWORK
internal struct CocoaError : Error {
    enum Code : Int, Sendable {
        case formatting = 2048
    }

    internal let code: Code
    internal let description: String

    init(_ code: Code, description: String = "") {
        self.code = code
        self.description = description
    }
}
#endif
