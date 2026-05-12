import Foundation
import ServiceManagement
import OSLog

private let log = Logger(subsystem: "ai.mypet", category: "LoginItem")

/// Wraps SMAppService for "launch at login" toggle.
/// Requires macOS 13+. Safe no-op on older systems (test build target may be lower).
struct LoginItem {

    /// Returns true if mypet is currently registered to launch at login.
    static func isEnabled() -> Bool {
        if #available(macOS 13, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    /// Registers the app to launch at login. Returns true on success.
    @discardableResult
    static func enable() -> Bool {
        if #available(macOS 13, *) {
            do {
                try SMAppService.mainApp.register()
                log.info("login item registered")
                return true
            } catch {
                log.error("register failed: \(error.localizedDescription)")
                return false
            }
        }
        return false
    }

    /// Unregisters from launch-at-login. Returns true on success.
    @discardableResult
    static func disable() -> Bool {
        if #available(macOS 13, *) {
            do {
                try SMAppService.mainApp.unregister()
                log.info("login item unregistered")
                return true
            } catch {
                log.error("unregister failed: \(error.localizedDescription)")
                return false
            }
        }
        return false
    }
}
