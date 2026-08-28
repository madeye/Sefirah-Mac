import AppKit
import SefirahCore
import SwiftUI

@main
struct SefirahApp: App {
    @State private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Sefirah", id: "main") {
            RootView(model: model)
                .environment(model)
                .frame(minWidth: 960, minHeight: 600)
                .onOpenURL { model.handleURL($0) }
        }
        .defaultSize(width: 980, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Window("Incoming Call", id: "call") {
            CallOverlayView(model: model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)

        MenuBarExtra("Sefirah", systemImage: "iphone") {
            MenuBarView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NSApp.windows.first { $0.identifier?.rawValue == "main" }?.makeKeyAndOrderFront(nil)
        }
        return true
    }
}
