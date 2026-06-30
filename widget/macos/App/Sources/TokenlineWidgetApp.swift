import SwiftUI

@main
struct TokenlineWidgetApp: App {
    @StateObject private var model = WidgetModel()
    var body: some Scene {
        MenuBarExtra {
            DropdownView(model: model)
        } label: {
            // Colored per-account bar chart (real color via a non-template
            // image). Falls back to text only when there are no accounts, so the
            // menu bar item never becomes invisible/unclickable.
            if let img = model.barImage {
                Image(nsImage: img).renderingMode(.original)
            } else {
                Text(model.barLabel)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
