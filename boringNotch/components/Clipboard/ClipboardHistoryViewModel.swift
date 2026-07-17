//
//  ClipboardHistoryViewModel.swift
//  boringNotch
//

import AppKit
import Combine
import Defaults
import Foundation

@MainActor
final class ClipboardHistoryViewModel: ObservableObject {
    static let shared = ClipboardHistoryViewModel()

    static let historyLimit = 50

    @Published private(set) var items: [ClipboardItem] = [] {
        didSet { ClipboardPersistenceService.shared.save(items) }
    }

    var isEmpty: Bool { items.isEmpty }

    private let monitor = ClipboardMonitor()
    private var enabledCancellable: AnyCancellable?

    private init() {
        items = ClipboardPersistenceService.shared.load()

        monitor.onNewContent = { [weak self] content in
            self?.add(content)
        }

        enabledCancellable = Defaults.publisher(.enableClipboardHistory)
            .sink { [weak self] change in
                Task { @MainActor in
                    self?.setMonitoring(enabled: change.newValue)
                }
            }
    }

    private func setMonitoring(enabled: Bool) {
        if enabled {
            monitor.start()
        } else {
            monitor.stop()
            if BoringViewCoordinator.shared.currentView == .clipboard {
                BoringViewCoordinator.shared.currentView = .home
            }
        }
    }

    func add(_ content: ClipboardContent) {
        let newItem = ClipboardItem(content: content)
        let key = newItem.identityKey

        var merged = items
        if let existingIndex = merged.firstIndex(where: { $0.identityKey == key }) {
            // Refresh recency instead of duplicating
            merged.remove(at: existingIndex)
        }
        merged.insert(newItem, at: 0)
        if merged.count > Self.historyLimit {
            merged = Array(merged.prefix(Self.historyLimit))
        }
        items = merged
    }

    func copyToPasteboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.content {
        case .text(let string):
            pasteboard.setString(string, forType: .string)
        case .image(let data):
            pasteboard.setData(data, forType: .png)
        }
        monitor.markOwnChange()

        // Move the copied item to the front
        var merged = items
        if let index = merged.firstIndex(where: { $0.id == item.id }), index != 0 {
            let moved = merged.remove(at: index)
            merged.insert(moved, at: 0)
            items = merged
        }
    }

    func remove(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
    }

    func clear() {
        items = []
    }

    func stopMonitoring() {
        monitor.stop()
    }
}
