//
//  ClaudeUsageService.swift
//  boringNotch
//

import Foundation
import Security

enum ClaudeUsageError: Error, Equatable {
    case notLoggedIn
    case keychainDenied(OSStatus)
    case tokenExpired
    case authFailed(Int)
    case rateLimited
    case badResponse(Int)
    case network
    case decoding

    var userMessage: String {
        switch self {
        case .notLoggedIn:
            return "Not logged in — sign in with Claude Code"
        case .keychainDenied:
            return "Keychain access denied"
        case .tokenExpired:
            return "Session expired — run claude to refresh"
        case .authFailed:
            return "Authentication failed"
        case .rateLimited:
            return "Rate limited — try again later"
        case .badResponse(let code):
            return "Unexpected response (\(code))"
        case .network:
            return "Unable to fetch usage"
        case .decoding:
            return "Unexpected usage data format"
        }
    }
}

struct ClaudeUsageSnapshot: Decodable {
    struct Window: Decodable {
        let utilization: Double?
        let resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }

        // Verified against a live response: utilization is on a 0–100 scale.
        var utilizationPercent: Double? { utilization }

        var resetsAtDate: Date? {
            guard let resetsAt else { return nil }
            let withFractional = ISO8601DateFormatter()
            withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFractional.date(from: resetsAt) { return date }
            return ISO8601DateFormatter().date(from: resetsAt)
        }
    }

    let fiveHour: Window?
    let sevenDay: Window?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

struct ClaudeUsageService {
    private static let keychainService = "Claude Code-credentials"
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// Blocking; may show the macOS Keychain consent dialog — call off the main actor.
    static func readAccessToken() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { throw ClaudeUsageError.notLoggedIn }
        guard status == errSecSuccess, let data = result as? Data else {
            throw ClaudeUsageError.keychainDenied(status)
        }

        struct Credentials: Decodable {
            struct OAuth: Decodable {
                let accessToken: String
                let expiresAt: Double?
            }
            let claudeAiOauth: OAuth
        }
        guard let credentials = try? JSONDecoder().decode(Credentials.self, from: data) else {
            throw ClaudeUsageError.decoding
        }
        if let expiresAtMs = credentials.claudeAiOauth.expiresAt,
           Date(timeIntervalSince1970: expiresAtMs / 1000) <= Date().addingTimeInterval(30) {
            throw ClaudeUsageError.tokenExpired
        }
        return credentials.claudeAiOauth.accessToken
    }

    static func fetchUsage() async throws -> ClaudeUsageSnapshot {
        let token = try await Task.detached(priority: .userInitiated) {
            try readAccessToken()
        }.value

        var request = URLRequest(url: usageURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ClaudeUsageError.network
        }

        guard let http = response as? HTTPURLResponse else { throw ClaudeUsageError.network }
        switch http.statusCode {
        case 200:
            break
        case 401, 403:
            throw ClaudeUsageError.authFailed(http.statusCode)
        case 429:
            throw ClaudeUsageError.rateLimited
        default:
            throw ClaudeUsageError.badResponse(http.statusCode)
        }

        guard let snapshot = try? JSONDecoder().decode(ClaudeUsageSnapshot.self, from: data) else {
            throw ClaudeUsageError.decoding
        }
        return snapshot
    }
}
