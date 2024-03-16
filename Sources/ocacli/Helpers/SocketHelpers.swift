//
// Copyright (c) 2024 PADL Software Pty Ltd
//
// Licensed under the Apache License, Version 2.0 (the License);
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an 'AS IS' BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Foundation
import SwiftOCA

extension in_addr {
    init(_ string: String) throws {
        var address = in_addr()
        guard inet_pton(AF_INET, string, &address) == 1 else {
            throw Ocp1Error.serviceResolutionFailed
        }
        self = address
    }
}

extension in6_addr {
    init(_ string: String) throws {
        var address = in6_addr()
        guard inet_pton(AF_INET6, string, &address) == 1 else {
            throw Ocp1Error.serviceResolutionFailed
        }
        self = address
    }
}

extension sockaddr_in {
    init(_ string: String, port: UInt16? = nil) throws {
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr = try in_addr(string)
        if let port { address.sin_port = port.bigEndian }
        address.sin_len = UInt8(MemoryLayout<Self>.size)
        self = address
    }
}

extension sockaddr_in6 {
    init(_ string: String, port: UInt16? = nil) throws {
        var address = sockaddr_in6()
        address.sin6_family = sa_family_t(AF_INET6)
        address.sin6_addr = try in6_addr(string)
        if let port { address.sin6_port = port.bigEndian }
        address.sin6_len = UInt8(MemoryLayout<Self>.size)
        self = address
    }
}
