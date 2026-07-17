//
//  ClipboardModels.swift
//  boringNotch
//

import AppKit
import CryptoKit
import Foundation

enum ClipboardContent: Codable, Equatable, Sendable {
    case text(String)
    case image(Data)

    enum CodingKeys: String, CodingKey { case type, value }

    enum KindTag: String, Codable { case text, image }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(KindTag.self, forKey: .type)
        switch type {
        case .text:
            self = .text(try container.decode(String.self, forKey: .value))
        case .image:
            self = .image(try container.decode(Data.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let string):
            try container.encode(KindTag.text, forKey: .type)
            try container.encode(string, forKey: .value)
        case .image(let data):
            try container.encode(KindTag.image, forKey: .type)
            try container.encode(data, forKey: .value)
        }
    }
}

struct ClipboardItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let content: ClipboardContent
    let timestamp: Date

    init(id: UUID = UUID(), content: ClipboardContent, timestamp: Date = Date()) {
        self.id = id
        self.content = content
        self.timestamp = timestamp
    }

    var identityKey: String {
        switch content {
        case .text(let string):
            return "text://" + string
        case .image(let data):
            let digest = SHA256.hash(data: data)
            return "image://" + digest.map { String(format: "%02x", $0) }.joined()
        }
    }

    var preview: String {
        switch content {
        case .text(let string):
            let firstLine = string
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines)
                .first ?? ""
            if firstLine.count > 120 {
                return String(firstLine.prefix(117)) + "..."
            }
            return firstLine
        case .image(let data):
            if let rep = NSBitmapImageRep(data: data) {
                return "Image \(rep.pixelsWide)×\(rep.pixelsHigh)"
            }
            return "Image"
        }
    }

    var isImage: Bool {
        if case .image = content { return true }
        return false
    }
}
