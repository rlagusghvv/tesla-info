import AppIntents
import Foundation

struct StartCarModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Car Mode"
    static var description = IntentDescription("Open the app directly in Car Mode.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: LaunchFlags.startCarModeFromIntent)
        return .result()
    }
}

struct TeslaSubDashShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        return [
            AppShortcut(
                intent: StartCarModeIntent(),
                phrases: [
                    "Start car mode in \(.applicationName)",
                    "Open \(.applicationName) car mode",
                    "Launch \(.applicationName) for driving"
                ],
                shortTitle: "Car Mode",
                systemImageName: "steeringwheel"
            )
        ]
    }

    static var shortcutTileColor: ShortcutTileColor = .blue
}
