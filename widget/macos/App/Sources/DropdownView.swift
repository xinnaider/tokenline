import SwiftUI
import TokenlineWidgetKit

struct DropdownView: View {
    @ObservedObject var model: WidgetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CONTAS").font(.caption2).foregroundStyle(.secondary)
            if model.accounts.isEmpty {
                Text("Nenhuma conta ainda.\nRode uma sessão Claude com TOKENLINE_WIDGET=1.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(model.accounts) { AccountBlock(view: $0, labels: model.labels) }
            }
            Divider()
            Button("Ajustes…") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            Button("Sair") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 320)
    }
}

struct AccountBlock: View {
    let view: AccountView
    let labels: Labels
    private var s: Snapshot { view.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(labels.displayName(for: s.account_key)).fontWeight(.semibold)
                if view.isStale { Text("idle").font(.caption2).foregroundStyle(.secondary) }
                else { Text(s.cache.state).font(.caption2).foregroundStyle(.orange) }
                Spacer()
                Text(s.model).font(.caption2).foregroundStyle(.secondary)
            }
            ProgressView(value: min(s.rate.five_hour.pct, 100), total: 100)
                .tint(Palette.color(forPct: s.rate.five_hour.pct))
            HStack(spacing: 8) {
                Text("5h \(Int(s.rate.five_hour.pct))%").foregroundStyle(Palette.color(forPct: s.rate.five_hour.pct))
                Text("7d \(Int(s.rate.seven_day.pct))%")
                Text("ctx \(Int(s.context.used_pct))%")
                Text("save \(Int(s.saving_pct))%").foregroundStyle(.green)
                Text(fmtTokens(s.spend.session_tokens))
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .opacity(view.isStale ? 0.5 : 1)
    }
}
