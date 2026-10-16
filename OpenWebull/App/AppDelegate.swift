import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var env: AppEnvironment?
    private var mainWindow: MainWindowController?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.mainMenu = MainMenu.build()

        let env = AppEnvironment()
        self.env = env
        if !Self.isRunningTests {
            env.market.start()
        }
        let controller = MainWindowController(env: env)
        mainWindow = controller
        controller.showWindow(nil)
        NSApp.activate()
    }

    func applicationWillTerminate(_ notification: Notification) {
        env?.market.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    // MARK: Menu actions

    @objc func showSettings(_ sender: Any?) {
        guard let env else { return }
        let controller = settingsWindow ?? SettingsWindowController(env: env)
        settingsWindow = controller
        controller.showWindow(sender)
    }

    @objc func showWorkspace(_ sender: NSMenuItem) {
        guard let workspace = Workspace(rawValue: sender.tag) else { return }
        mainWindow?.show(workspace)
    }

    @objc func findSymbol(_ sender: Any?) {
        mainWindow?.focusSearch()
    }

    @objc func cancelAllOrders(_ sender: Any?) {
        env?.broker.cancelAllWorkingOrders()
    }
}
