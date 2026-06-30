import SwiftUI
import TokenlineWidgetKit

struct DropdownView: View {
    @ObservedObject var model: WidgetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if model.accounts.isEmpty {
                emptyState
            } else {
                ForEach(Array(model.accounts.enumerated()), id: \.element.id) { idx, view in
                    if idx > 0 { Divider().opacity(0.45) }
                    AccountRow(view: view, labels: model.labels)
                        .padding(.vertical, 11)
                }
            }

            Divider().opacity(0.6)
            footer
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .frame(width: 326)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "gauge.medium")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("tokenline").font(.system(size: 13, weight: .semibold))
            Spacer()
            if !model.accounts.isEmpty {
                Text(model.accounts.count == 1 ? "1 conta" : "\(model.accounts.count) contas")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 9)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nenhuma conta ainda").font(.system(size: 13, weight: .medium))
            Text("Rode uma sessão Claude com TOKENLINE_WIDGET=1 e CLAUDE_CONFIG_DIR definido.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 14)
    }

    private var footer: some View {
        HStack {
            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: { Label("Ajustes", systemImage: "gearshape") }

            Spacer()

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: { Label("Sair", systemImage: "power") }
                .keyboardShortcut("q")
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.borderless)
        .font(.system(size: 12))
        .padding(.top, 9)
    }
}

private struct AccountRow: View {
    let view: AccountView
    let labels: Labels
    private var s: Snapshot { view.snapshot }
    private var p5: Double { s.rate.five_hour.pct }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Circle().fill(Usage.color(p5)).frame(width: 7, height: 7)
                Text(labels.displayName(for: s.account_key))
                    .font(.system(size: 13, weight: .semibold))
                CachePill(state: s.cache.state, ttl: s.cache.ttl_label, stale: view.isStale)
                Spacer()
                Text(s.model)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            UsageBar(pct: p5)

            HStack(spacing: 11) {
                Metric("5h", "\(Int(p5))%", color: Usage.color(p5))
                Metric("7d", "\(Int(s.rate.seven_day.pct))%")
                Metric("ctx", "\(Int(s.context.used_pct))%")
                Metric("save", "\(Int(s.saving_pct))%", color: Color(red: 0.18, green: 0.80, blue: 0.34))
                Spacer()
                Text(fmtTokens(s.spend.session_tokens))
                    .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(view.isStale ? 0.5 : 1)
    }
}

private struct UsageBar: View {
    let pct: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                Capsule().fill(Usage.color(pct))
                    .frame(width: max(3, geo.size.width * min(pct, 100) / 100))
            }
        }
        .frame(height: 5)
        .animation(.easeOut(duration: 0.35), value: pct)
    }
}

private struct CachePill: View {
    let state: String
    let ttl: String
    let stale: Bool

    var body: some View {
        if stale {
            pill("idle", .secondary)
        } else if !state.isEmpty {
            pill(state == "HOT" ? "HOT · \(ttl)" : state,
                 state == "HOT" ? .orange : Color(red: 0.39, green: 0.55, blue: 0.96))
        }
    }

    private func pill(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}

private struct Metric: View {
    let label: String
    let value: String
    var color: Color = .primary

    init(_ label: String, _ value: String, color: Color = .primary) {
        self.label = label; self.value = value; self.color = color
    }

    var body: some View {
        HStack(spacing: 3) {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 11, weight: .semibold))
                .monospacedDigit().foregroundStyle(color)
        }
    }
}
