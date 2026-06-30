import SwiftUI
import AppKit
import Combine
import TokenlineWidgetKit

@MainActor
final class WidgetModel: ObservableObject {
    @Published var accounts: [AccountGroup] = []
    @Published var barLabel: String = "–"
    @Published var barImage: NSImage?
    @Published var labels = Labels.load()

    private let store: Store
    private var timer: Timer?
    private var source: DispatchSourceFileSystemObject?

    init(store: Store = Store(dir: Store.defaultDir)) {
        self.store = store
        try? FileManager.default.createDirectory(at: store.dir, withIntermediateDirectories: true)
        reload()
        // Poll fallback (also refreshes staleness without a new write).
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        watchDir()
    }

    private func watchDir() {
        let fd = open(store.dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let s = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .rename], queue: .main)
        s.setEventHandler { [weak self] in self?.reload() }
        s.setCancelHandler { close(fd) }
        s.resume()
        source = s
    }

    func reload() {
        labels = Labels.load()
        let groups = store.load()
        accounts = groups
        // Colored mini bar chart (one bar per account) + the worst number.
        barImage = menuBarBars(groups)
        if let worst = store.worstFiveHour(groups) {
            barLabel = "\(Int(worst))%"
        } else {
            barLabel = groups.isEmpty ? "–" : "idle"
        }
    }

    deinit { timer?.invalidate(); source?.cancel() }
}
