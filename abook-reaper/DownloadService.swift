//
//  DownloadService.swift
//  abook-reaper
//
//  Wraps ffmpeg to download audio from HLS m3u8 streams.
//  Supports per-chapter and single-file downloads in mp3/m4b formats.
//  Supports cancellation via Task cancellation.
//

import Foundation

actor DownloadService {

    static let ffmpegPath = "/opt/homebrew/bin/ffmpeg"

    /// Thread-safe wrapper for the running ffmpeg process, enabling cancellation.
    private final class ProcessRef: @unchecked Sendable {
        private let lock = NSLock()
        private var _process: Process?

        var process: Process? {
            get { lock.withLock { _process } }
            set { lock.withLock { _process = newValue } }
        }

        func terminate() {
            lock.withLock {
                guard let p = _process, p.isRunning else { return }
                p.terminate()
            }
        }
    }

    private let processRef = ProcessRef()

    /// Cancel the currently running ffmpeg process (if any).
    func cancelCurrentDownload() {
        processRef.terminate()
    }

    /// Download a single chapter from the m3u8 stream.
    func downloadChapter(
        m3u8URL: String,
        chapter: Chapter,
        format: AudioFormat,
        outputDir: URL,
        filename: String,
        onProgress: @Sendable @escaping (String) -> Void
    ) async throws {
        try Task.checkCancellation()

        let outputFile = outputDir
            .appendingPathComponent(sanitizeFilename(filename))
            .appendingPathExtension(format.fileExtension)

        var args = [
            "-y",
            "-headers", "Referer: https://akniga.org/\r\n",
            "-i", m3u8URL,
            "-ss", String(format: "%.3f", chapter.startTime),
            "-t", String(format: "%.3f", chapter.duration),
        ]

        switch format {
        case .m4b:
            args += ["-c", "copy"]
        case .mp3:
            args += ["-c:a", "libmp3lame", "-q:a", "2"]
        }

        args += ["-vn", outputFile.path]

        try await runFFmpeg(args: args, onProgress: onProgress)
    }

    /// Download the entire book as a single file.
    func downloadSingleFile(
        m3u8URL: String,
        format: AudioFormat,
        outputDir: URL,
        filename: String,
        onProgress: @Sendable @escaping (String) -> Void
    ) async throws {
        try Task.checkCancellation()

        let outputFile = outputDir
            .appendingPathComponent(sanitizeFilename(filename))
            .appendingPathExtension(format.fileExtension)

        var args = [
            "-y",
            "-headers", "Referer: https://akniga.org/\r\n",
            "-i", m3u8URL,
        ]

        switch format {
        case .m4b:
            args += ["-c", "copy"]
        case .mp3:
            args += ["-c:a", "libmp3lame", "-q:a", "2"]
        }

        args += ["-vn", outputFile.path]

        try await runFFmpeg(args: args, onProgress: onProgress)
    }

    // MARK: - ffmpeg runner with cancellation support

    private func runFFmpeg(
        args: [String],
        onProgress: @Sendable @escaping (String) -> Void
    ) async throws {
        let ffmpeg = Self.ffmpegPath
        guard FileManager.default.fileExists(atPath: ffmpeg) else {
            throw DownloadError.ffmpegNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = args

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = FileHandle.nullDevice

        // Store for cancellation
        processRef.process = process

        let localProcessRef = processRef

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                var stderrOutput = ""

                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
                    stderrOutput += line
                    if line.contains("time=") {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        onProgress(trimmed)
                    }
                }

                process.terminationHandler = { proc in
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    if proc.terminationStatus == 0 {
                        continuation.resume()
                    } else if proc.terminationReason == .uncaughtSignal {
                        continuation.resume(throwing: DownloadError.cancelled)
                    } else {
                        continuation.resume(throwing: DownloadError.ffmpegFailed(
                            proc.terminationStatus, stderrOutput
                        ))
                    }
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            localProcessRef.terminate()
        }

        // Clear process ref
        processRef.process = nil
    }

    private func sanitizeFilename(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return name.components(separatedBy: illegal).joined(separator: "_")
    }
}
