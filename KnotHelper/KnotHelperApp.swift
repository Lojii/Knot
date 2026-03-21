//
//  KnotHelperApp.swift
//  KnotHelper
//
//  Copyright © 2026 Lojii. All rights reserved.
//

import SwiftUI

@main
struct KnotHelperApp: App {
    @StateObject private var vm = HelperViewModel()

    var body: some Scene {
        Window("KnotHelper", id: "main") {
            HelperWindow(vm: vm)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 320, height: 240)
    }
}
