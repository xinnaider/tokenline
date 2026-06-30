import SwiftUI

@main
struct TokenlineWidgetApp: App {
    @StateObject private var model = WidgetModel()
    var body: some Scene {
        MenuBarExtra {
            DropdownView(model: model)
        } label: {
            Text(model.barLabel)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
