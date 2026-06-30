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
                ForEach(Array(model.accounts.enumerated()), id: \.element.id) { idx, group in
                    if idx > 0 { Divider().opacity(0.35) }
                    AccountBlock(group: group, labels: model.labels)
                        .padding(.vertical, 11)
                }
            }

            Divider().opacity(0.45)
            footer
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .frame(width: 340)
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

private struct AccountBlock: View {
    let group: AccountGroup
    let labels: Labels
    private var p5: Double { group.fiveHour.pct }

    private var countLabel: String {
        if group.isStale { return "idle" }
        return group.liveCount == 1 ? "1 sessão" : "\(group.liveCount) sessões"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Circle()
                    .fill(group.isStale ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Usage.color(p5)))
                    .frame(width: 7, height: 7)
                Text(labels.displayName(for: group.key))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(Int(p5))%")
                    .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Usage.color(p5))
            }

            UsageBar(pct: p5)

            HStack(spacing: 8) {
                Text("7d \(Int(group.sevenDay.pct))%")
                Text("·")
                Text(countLabel)
            }
            .font(.system(size: 10)).foregroundStyle(.tertiary)

            ForEach(group.sessions) { SessionRow(session: $0) }
                .padding(.leading, 2)
        }
        .opacity(group.isStale ? 0.5 : 1)
    }
}

private struct SessionRow: View {
    let session: SessionInfo
    private var s: Snapshot { session.snapshot }
    private var cache: String { s.cache.state == "HOT" ? "HOT·\(s.cache.ttl_label)" : s.cache.state }
    private var ctxTokens: String { "\(fmtTokens(s.context.tokens_used))/\(fmtTokens(s.context.size))" }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(session.isActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.quaternary))
                    .frame(width: 4, height: 4)
                Text(s.model).font(.system(size: 11, weight: .medium))
                Spacer()
                Text(fmtTokens(s.spend.session_tokens))
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(.tertiary)
            }
            HStack(spacing: 6) {
                Text(ctxTokens).monospacedDigit()
                Text("\(Int(s.context.used_pct))%").monospacedDigit().foregroundStyle(.primary)
                if !cache.isEmpty { Text("· \(cache)") }
                Text("· save \(Int(s.saving_pct))%")
            }
            .font(.system(size: 10)).foregroundStyle(.secondary)
            .padding(.leading, 10)
        }
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
