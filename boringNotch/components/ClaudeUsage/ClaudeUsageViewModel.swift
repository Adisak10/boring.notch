//
//  ClaudeUsageViewModel.swift
//  boringNotch
//

import Foundation

@MainActor
final class ClaudeUsageViewModel: ObservableObject {
    static let shared = ClaudeUsageViewModel()

    static let refreshInterval: TimeInterval = 300

    @Published private(set) var snapshot: ClaudeUsageSnapshot?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isLoading = false
    @Published private(set) var error: ClaudeUsageError?

    private var refreshTimer: Timer?
    private var refreshTask: Task<Void, Never>?

    private init() {}

    // Fetches only happen while the card is visible, mirroring how the
    // camera session only runs while the preview is expanded.
    func cardDidAppear() {
        refreshIfStale()
        startTimer()
    }

    func cardDidDisappear() {
        stopTimer()
    }

    private func startTimer() {
        guard refreshTimer == nil else { return }
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func stopTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    /// Refresh only when the data is stale.
    private func refreshIfStale() {
        if let lastUpdated, Date().timeIntervalSince(lastUpdated) < Self.refreshInterval {
            return
        }
        refresh()
    }

    func refresh() {
        guard refreshTask == nil else { return }
        isLoading = true
        refreshTask = Task { [weak self] in
            defer { self?.refreshTask = nil }
            do {
                let snapshot = try await ClaudeUsageService.fetchUsage()
                guard let self, !Task.isCancelled else { return }
                self.snapshot = snapshot
                self.lastUpdated = Date()
                self.error = nil
                self.isLoading = false
            } catch {
                guard let self, !Task.isCancelled else { return }
                // Keep the last good snapshot so stale data stays visible
                self.error = (error as? ClaudeUsageError) ?? .network
                self.isLoading = false
            }
        }
    }
}
