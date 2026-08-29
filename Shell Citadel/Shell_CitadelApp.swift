//
//  Shell_CitadelApp.swift
//  Shell Citadel
//
//  Created by Michael Fluharty on 8/22/26.
//

import SwiftUI

@main
struct Shell_CitadelApp: App {
    // His desktop terminal font, bundled. Registered before the first view renders so no
    // frame is ever drawn in the system fallback. See TerminalFont.
    init() { TerminalFont.register() }

    var body: some Scene {
        WindowGroup {
            TerminalView()
        }
    }
}
