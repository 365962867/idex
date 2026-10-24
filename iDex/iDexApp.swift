//
//  iDexApp.swift
//  iDex
//
//  Created by Zihang Huang on 2026/10/24.
//

import SwiftUI

@main
struct iDexApp: App {
    @UIApplicationDelegateAdaptor(DexAppDelegate.self) private var appDelegate
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
