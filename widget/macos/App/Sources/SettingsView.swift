import SwiftUI
import ServiceManagement
import TokenlineWidgetKit

struct SettingsView: View {
    private struct Row: Identifiable { let id = UUID(); var key: String; var alias: String }
    @State private var rows: [Row] = []
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Apelidos das contas").font(.headline)
            Text("O apelido substitui o nome da conta (o “pai”) no widget — não afeta as sessões.")
                .font(.caption).foregroundStyle(.secondary)

            VStack(spacing: 6) {
                ForEach($rows) { $row in
                    HStack(spacing: 8) {
                        TextField("conta (ex: claude-pessoal)", text: $row.key)
                            .textFieldStyle(.roundedBorder).frame(width: 170)
                        Image(systemName: "arrow.right").imageScale(.small).foregroundStyle(.tertiary)
                        TextField(row.key.isEmpty ? "apelido" : Labels.prettify(row.key),
                                  text: $row.alias)
                            .textFieldStyle(.roundedBorder)
                        Button { rows.removeAll { $0.id == row.id } } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Button { rows.append(Row(key: "", alias: "")) } label: {
                    Label("Adicionar conta", systemImage: "plus")
                }
                Spacer()
                Button("Salvar") { save() }.keyboardShortcut(.defaultAction)
            }

            Divider()
            Toggle("Iniciar no login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { on in setLogin(on) }
        }
        .padding(18)
        .frame(width: 430)
        .onAppear(perform: load)
        .onDisappear {
            save()
            NSApp.setActivationPolicy(.accessory)   // back to menu-bar agent
        }
    }

    private func load() {
        let labels = Labels.load()
        var keys = Set(labels.entries.keys)
        keys.formUnion(Store(dir: Store.defaultDir).load().map(\.key))
        rows = keys.sorted().map { Row(key: $0, alias: labels.entries[$0]?.label ?? "") }
        if rows.isEmpty { rows = [Row(key: "", alias: "")] }
    }

    private func save() {
        var map: [String: Labels.Entry] = [:]
        for r in rows {
            let k = r.key.trimmingCharacters(in: .whitespaces)
            let a = r.alias.trimmingCharacters(in: .whitespaces)
            if !k.isEmpty, !a.isEmpty { map[k] = Labels.Entry(label: a) }
        }
        try? Labels.write(map)
    }

    private func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }
}
