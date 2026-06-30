import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    var body: some View {
        Form {
            Toggle("Iniciar no login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { on in
                    do {
                        if on { try SMAppService.mainApp.register() }
                        else  { try SMAppService.mainApp.unregister() }
                    } catch {
                        launchAtLogin = (SMAppService.mainApp.status == .enabled)
                    }
                }
            Text("Contas e rótulos: edite ~/Library/Application Support/tokenline/labels.json")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16).frame(width: 360)
    }
}
