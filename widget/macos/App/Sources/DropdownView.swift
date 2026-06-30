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
                    if idx > 0 { Divider().opacity(0.35) }
                    AccountRow(view: view, labels: model.labels)
                        .padding(.vertical, 11)
                }
            }

            Divider().opacity(0.45)
            footer
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Text("Perch").font(.system(size: 13, weight: .semibold))
            Spacer()
            if !model.accounts.isEmpty {
                Text(model.accounts.count == 1 ? "1 conta" : "\(model.accounts.count) contas")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
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

            Button {
                NSApplication.shared.terminate(nil)
            } label: { Label("Sair", systemImage: "power") }
                .keyboardShortcut("q")
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.borderless)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.top, 9)
    }
}

private struct AccountRow: View {
    let view: AccountView
    let labels: Labels
    private var s: Snapshot { view.snapshot }
    private var p5: Double { s.rate.five_hour.pct }

    private var cacheNote: String {
        if view.isStale { return "idle" }
        if s.cache.state == "HOT" { return "HOT · \(s.cache.ttl_label)" }
        return s.cache.state
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Circle()
                    .fill(view.isStale ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Usage.color(p5)))
                    .frame(width: 7, height: 7)
                Text(labels.displayName(for: s.account_key))
                    .font(.system(size: 13, weight: .semibold))
                if !cacheNote.isEmpty {
                    Text(cacheNote).font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text(s.model).font(.system(size: 11)).foregroundStyle(.tertiary)
            }

            UsageBar(pct: p5)

            HStack(spacing: 12) {
                Metric("5h", "\(Int(p5))%", color: Usage.color(p5), emphasis: true)
                Metric("7d", "\(Int(s.rate.seven_day.pct))%")
                Metric("ctx", "\(Int(s.context.used_pct))%")
                Metric("save", "\(Int(s.saving_pct))%")
                Spacer()
                Text(fmtTokens(s.spend.session_tokens))
                    .font(.system(size: 11, weight: .medium)).monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .opacity(view.isStale ? 0.45 : 1)
    }
}

private struct UsageBar: View {
    let pct: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Usage.track)
                Capsule().fill(Usage.color(pct))
                    .frame(width: max(3, geo.size.width * min(pct, 100) / 100))
            }
        }
        .frame(height: 4)
        .animation(.easeOut(duration: 0.35), value: pct)
    }
}

private struct Metric: View {
    let label: String
    let value: String
    var color: Color?
    var emphasis: Bool

    init(_ label: String, _ value: String, color: Color? = nil, emphasis: Bool = false) {
        self.label = label; self.value = value; self.color = color; self.emphasis = emphasis
    }

    private var valueStyle: AnyShapeStyle {
        if let color { return AnyShapeStyle(color) }
        return emphasis ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
    }

    var body: some View {
        HStack(spacing: 3) {
            Text(label).font(.system(size: 10)).foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 11, weight: emphasis ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(valueStyle)
        }
    }
}
