//
//  Models.swift
//  abook-reaper
//

import Foundation

enum AudioFormat: String, CaseIterable, Identifiable, Sendable {
    case m4b
    case mp3

    var id: String { rawValue }
    var fileExtension: String { rawValue }
    var displayName: String { rawValue.uppercased() }
}

enum DownloadMode: String, CaseIterable, Identifiable, Sendable {
    case chapters
    case singleFile

    var id: String { rawValue }
}

struct Chapter: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let duration: TimeInterval
    let startTime: TimeInterval

    var formattedDuration: String {
        let total = Int(duration)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

struct BookInfo: Sendable {
    let id: String
    let title: String
    let chapters: [Chapter]
    let m3u8URL: String

    var totalDuration: TimeInterval {
        chapters.reduce(0) { $0 + $1.duration }
    }

    var formattedTotalDuration: String {
        let total = Int(totalDuration)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 {
            return "\(h)h \(m)m"
        }
        return "\(m)m"
    }
}

enum DownloadError: LocalizedError, Sendable {
    case ffmpegNotFound
    case ffmpegFailed(Int32, String)
    case cancelled

    nonisolated var errorDescription: String? {
        switch self {
        case .ffmpegNotFound:
            return "ffmpeg not found at /opt/homebrew/bin/ffmpeg"
        case .ffmpegFailed(let code, let output):
            return "ffmpeg exited with code \(code): \(output.suffix(200))"
        case .cancelled:
            return "Download cancelled"
        }
    }
}

enum AknigaError: LocalizedError, Sendable {
    case invalidURL
    case bookIdNotFound
    case securityKeyNotFound
    case tokenFetchFailed(String)
    case bookDataFetchFailed(String)
    case decryptionFailed
    case itemsParsingFailed

    nonisolated var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid book URL"
        case .bookIdNotFound: return "Could not find book ID on the page"
        case .securityKeyNotFound: return "Could not find security key on the page"
        case .tokenFetchFailed(let msg): return "Token fetch failed: \(msg)"
        case .bookDataFetchFailed(let msg): return "Book data fetch failed: \(msg)"
        case .decryptionFailed: return "Failed to decrypt m3u8 URL"
        case .itemsParsingFailed: return "Failed to parse chapter items"
        }
    }
}
