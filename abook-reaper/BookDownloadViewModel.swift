//
//  BookDownloadViewModel.swift
//  abook-reaper
//

import Foundation
import SwiftUI

@Observable
@MainActor
final class BookDownloadViewModel {

    // MARK: - Input state
    var bookURL: String = ""
    var audioFormat: AudioFormat = .m4b
    var downloadMode: DownloadMode = .chapters
    var outputDirectory: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!

    // MARK: - Book state
    var book: BookInfo?
    var isFetchingBook = false
    var fetchError: String?

    // MARK: - Chapter selection
    var selectedChapterIDs: Set<Int> = []

    // MARK: - Download state
    var isDownloading = false
    var downloadProgress: String = ""
    var currentChapterID: Int? = nil
    var completedChapterIDs: Set<Int> = []
    var downloadError: String?
    var downloadComplete = false

    // MARK: - Cancellation
    private var downloadTask: Task<Void, Never>?

    // MARK: - Services
    private let aknigaService = AknigaService()
    private let downloadService = DownloadService()

    // MARK: - Fetch

    func fetchBook() async {
        guard !bookURL.isEmpty else {
            fetchError = String(localized: "Please enter a book URL")
            return
        }

        isFetchingBook = true
        fetchError = nil
        book = nil
        downloadComplete = false
        downloadError = nil
        selectedChapterIDs = []
        completedChapterIDs = []

        do {
            let info = try await aknigaService.fetchBook(from: bookURL)
            book = info
            // Select all chapters by default
            selectedChapterIDs = Set(info.chapters.map(\.id))
        } catch {
            fetchError = error.localizedDescription
        }

        isFetchingBook = false
    }

    // MARK: - Download

    func startDownload() {
        downloadTask = Task { await performDownload() }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        Task { await downloadService.cancelCurrentDownload() }
        isDownloading = false
        currentChapterID = nil
        downloadProgress = ""
    }

    private func performDownload() async {
        guard let book = book else { return }

        isDownloading = true
        downloadError = nil
        downloadComplete = false
        completedChapterIDs = []
        downloadProgress = String(localized: "Starting...")

        do {
            let bookDir: URL
            if downloadMode == .chapters {
                bookDir = outputDirectory.appendingPathComponent(sanitize(book.title))
                try FileManager.default.createDirectory(at: bookDir, withIntermediateDirectories: true)
            } else {
                bookDir = outputDirectory
            }

            switch downloadMode {
            case .chapters:
                let chaptersToDownload = book.chapters.filter { selectedChapterIDs.contains($0.id) }
                let total = chaptersToDownload.count

                for (i, chapter) in chaptersToDownload.enumerated() {
                    try Task.checkCancellation()

                    currentChapterID = chapter.id
                    let paddedIndex = String(format: "%02d", chapter.id + 1)
                    let filename = "\(paddedIndex) - \(chapter.title)"
                    downloadProgress = String(localized: "Chapter \(i + 1)/\(total): \(chapter.title)")

                    try await downloadService.downloadChapter(
                        m3u8URL: book.m3u8URL,
                        chapter: chapter,
                        format: audioFormat,
                        outputDir: bookDir,
                        filename: filename
                    ) { [weak self] progress in
                        Task { @MainActor in
                            self?.downloadProgress = "Chapter \(i + 1)/\(total): \(progress)"
                        }
                    }

                    completedChapterIDs.insert(chapter.id)
                }

            case .singleFile:
                downloadProgress = String(localized: "Downloading full book...")

                try await downloadService.downloadSingleFile(
                    m3u8URL: book.m3u8URL,
                    format: audioFormat,
                    outputDir: bookDir,
                    filename: book.title
                ) { [weak self] progress in
                    Task { @MainActor in
                        self?.downloadProgress = progress
                    }
                }
            }

            downloadComplete = true
            downloadProgress = String(localized: "Complete!")
        } catch is CancellationError {
            // User cancelled — don't show error
        } catch let error as DownloadError where error == .cancelled {
            // ffmpeg was terminated by cancel
        } catch {
            downloadError = error.localizedDescription
        }

        isDownloading = false
        currentChapterID = nil
        downloadTask = nil
    }

    // MARK: - Chapter selection

    func selectAll() {
        guard let book = book else { return }
        selectedChapterIDs = Set(book.chapters.map(\.id))
    }

    func deselectAll() {
        selectedChapterIDs = []
    }

    func toggleChapter(_ id: Int) {
        if selectedChapterIDs.contains(id) {
            selectedChapterIDs.remove(id)
        } else {
            selectedChapterIDs.insert(id)
        }
    }

    // MARK: - Directory picker

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Choose")

        if panel.runModal() == .OK, let url = panel.url {
            outputDirectory = url
        }
    }

    // MARK: - Computed

    var canFetch: Bool {
        !bookURL.isEmpty && !isFetchingBook && !isDownloading
    }

    var canDownload: Bool {
        guard book != nil, !isDownloading, !isFetchingBook else { return false }
        if downloadMode == .chapters {
            return !selectedChapterIDs.isEmpty
        }
        return true
    }

    var selectedCount: Int {
        selectedChapterIDs.count
    }

    var allSelected: Bool {
        guard let book = book else { return false }
        return selectedChapterIDs.count == book.chapters.count
    }

    private func sanitize(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return name.components(separatedBy: illegal).joined(separator: "_")
    }
}

// Allow equating DownloadError for the catch clause
extension DownloadError: Equatable {
    nonisolated static func == (lhs: DownloadError, rhs: DownloadError) -> Bool {
        switch (lhs, rhs) {
        case (.cancelled, .cancelled): return true
        case (.ffmpegNotFound, .ffmpegNotFound): return true
        default: return false
        }
    }
}
