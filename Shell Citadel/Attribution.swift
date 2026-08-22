//
//  Attribution.swift
//  Shell Citadel
//
//  Third-party credit and the full license texts the licenses actually require.
//
//  WHY THE FULL TEXT AND NOT A THANK-YOU LINE: the MIT License requires that the
//  copyright notice AND the permission notice be included in copies. Apache 2.0
//  section 4 carries its own attribution duty. A one-line credit does not meet
//  either. Verified against the repositories on 2026-08-22, not recalled.
//

import Foundation

enum Attribution {

    /// Shown at the top of the About sheet. Michael's call, 2026-08-22: name the
    /// author, name the license, and say plainly that this app is not official.
    static let disclaimer = """
    Shell Citadel is not affiliated with, endorsed by, or an official product of \
    the Citadel project. Citadel remains the intellectual property of its authors.
    """

    struct Component: Identifiable {
        var id: String { name }
        let name: String
        let url: String
        let holder: String
        let license: String
        let text: String
    }

    static let components: [Component] = [citadel, swiftNIOSSH]

    static let citadel = Component(
        name: "Citadel",
        url: "https://github.com/orlandos-nl/Citadel",
        holder: "Copyright © 2022 Orlandos",
        license: "MIT License",
        text: mitLicense
    )

    static let swiftNIOSSH = Component(
        name: "SwiftNIO SSH",
        url: "https://github.com/apple/swift-nio-ssh",
        holder: "Copyright © Apple Inc.",
        license: "Apache License 2.0",
        text: apacheNotice
    )

    static let mitLicense = """
    MIT License

    Copyright (c) 2022 Orlandos

    Permission is hereby granted, free of charge, to any person obtaining a copy \
    of this software and associated documentation files (the "Software"), to deal \
    in the Software without restriction, including without limitation the rights \
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell \
    copies of the Software, and to permit persons to whom the Software is \
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all \
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR \
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, \
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE \
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER \
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, \
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE \
    SOFTWARE.
    """

    static let apacheNotice = """
    SwiftNIO SSH
    Copyright © Apple Inc. and the SwiftNIO project authors.

    Licensed under the Apache License, Version 2.0 (the "License"); you may not \
    use this file except in compliance with the License. You may obtain a copy of \
    the License at:

        http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software \
    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT \
    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the \
    License for the specific language governing permissions and limitations under \
    the License.
    """
}
