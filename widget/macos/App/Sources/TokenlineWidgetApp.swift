import SwiftUI

@main
struct TokenlineWidgetApp: App {
    @StateObject private var model = WidgetModel()
    var body: some Scene {
        MenuBarExtra {
            DropdownView(model: model)
        } label: {
            // Symbol + number: the glyph gives the item presence in a crowded
            // menu bar (and past the notch); the number carries the value.
            Image(systemName: model.barSymbol)
            Text(model.barLabel)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
