//
//  ClipboardHistoryView.swift
//  boringNotch
//

import AppKit
import SwiftUI

struct ClipboardHistoryView: View {
    @EnvironmentObject var vm: BoringViewModel
    @StateObject private var viewModel = ClipboardHistoryViewModel.shared
    private let spacing: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10]))
            .overlay {
                content
                    .padding()
            }
            .transaction { transaction in
                transaction.animation = vm.animation
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "doc.on.clipboard")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white, .gray)
                    .imageScale(.large)

                Text("Clipboard history is empty")
                    .foregroundStyle(.gray)
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.medium)
            }
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: spacing) {
                    ForEach(viewModel.items) { item in
                        ClipboardItemCard(item: item)
                    }
                }
            }
            .padding(-spacing)
            .scrollIndicators(.never)
        }
    }
}

private struct ClipboardItemCard: View {
    let item: ClipboardItem
    @StateObject private var viewModel = ClipboardHistoryViewModel.shared
    @State private var isHovering = false
    @State private var justCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            contentPreview
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Text(item.timestamp, format: .relative(presentation: .named))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.gray)
        }
        .padding(8)
        .frame(width: 140)
        .frame(maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .secondarySystemFill).opacity(isHovering ? 1 : 0.6))
        }
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button {
                    viewModel.remove(item)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(4)
            }
        }
        .overlay {
            if justCopied {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.55))
                    .overlay {
                        Label("Copied", systemImage: "checkmark")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.white)
                    }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            viewModel.copyToPasteboard(item)
            withAnimation(.smooth(duration: 0.15)) { justCopied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.smooth(duration: 0.3)) { justCopied = false }
            }
        }
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.15)) { isHovering = hovering }
        }
    }

    @ViewBuilder
    private var contentPreview: some View {
        switch item.content {
        case .text(let string):
            Text(string.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
        case .image(let data):
            if let nsImage = ClipboardImageCache.shared.image(for: item.id, data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Label("Image", systemImage: "photo")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.gray)
            }
        }
    }
}

/// Avoids re-decoding PNG data on every row render.
@MainActor
final class ClipboardImageCache {
    static let shared = ClipboardImageCache()
    private let cache = NSCache<NSUUID, NSImage>()

    private init() {
        cache.countLimit = ClipboardHistoryViewModel.historyLimit
    }

    func image(for id: UUID, data: Data) -> NSImage? {
        if let cached = cache.object(forKey: id as NSUUID) {
            return cached
        }
        guard let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: id as NSUUID)
        return image
    }
}
