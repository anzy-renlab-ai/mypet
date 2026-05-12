import SwiftUI

@main
struct MyPetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // Hidden Settings scene — no auto-opened window.
        // All UI is driven by AppDelegate via NSWindow.
        Settings {
            EmptyView()
        }
    }
}
