//
//  ClaudeUsageView.swift
//  boringNotch
//

import SwiftUI

struct ClaudeUsageView: View {
    @StateObject private var viewModel = ClaudeUsageViewModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "gauge.with.needle")
                    .imageScale(.small)
                Text("Claude")
                    .font(.system(.caption, design: .rounded))
                    .fontWeight(.semibold)
                Spacer(minLength: 0)
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.mini)
                } else if viewModel.error != nil, viewModel.snapshot != nil {
                    // Stale data indicator: last fetch failed but old values shown
                    Image(systemName: "exclamationmark.triangle.fill")
                        .imageScale(.small)
                        .foregroundStyle(.yellow)
                        .help(viewModel.error?.userMessage ?? "")
                }
            }
            .foregroundStyle(.gray)

            if let snapshot = viewModel.snapshot {
                usageRow(label: "5h", window: snapshot.fiveHour)
                usageRow(label: "7d", window: snapshot.sevenDay)
            } else if let error = viewModel.error {
                Text(error.userMessage)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.leading)
                Button("Retry") {
                    viewModel.refresh()
                }
                .buttonStyle(.plain)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.white)
            } else if !viewModel.isLoading {
                Text("—")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.gray)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 120)
        .frame(maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .secondarySystemFill).opacity(0.6))
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            viewModel.refresh()
        }
        .onAppear {
            viewModel.cardDidAppear()
        }
        .onDisappear {
            viewModel.cardDidDisappear()
        }
    }

    @ViewBuilder
    private func usageRow(label: String, window: ClaudeUsageSnapshot.Window?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.gray)
                Spacer(minLength: 0)
                if let percent = window?.utilizationPercent {
                    Text("\(Int(percent.rounded()))%")
                        .font(.system(.caption, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                } else {
                    Text("—")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.gray)
                }
            }

            ProgressView(value: min(max((window?.utilizationPercent ?? 0) / 100, 0), 1))
                .progressViewStyle(.linear)
                .controlSize(.small)
                .tint(tint(for: window?.utilizationPercent))

            if let resetsAt = window?.resetsAtDate {
                Text("resets \(resetsAt, format: .relative(presentation: .named))")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.gray)
            }
        }
    }

    private func tint(for percent: Double?) -> Color {
        guard let percent else { return .gray }
        switch percent {
        case ..<60: return .green
        case ..<85: return .yellow
        default: return .red
        }
    }
}
