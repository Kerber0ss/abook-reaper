//
//  ContentView.swift
//  abook-reaper
//
//  Liquid Glass: used ONLY on toolbar buttons (automatic) and the primary
//  download action. Everything else uses standard native macOS controls.
//

import SwiftUI

struct ContentView: View {
    @State private var viewModel = BookDownloadViewModel()

    var body: some View {
        VStack(spacing: 0) {
            if let book = viewModel.book {
                bookContentView(book)
            } else {
                emptyStateView
            }
        }
        .frame(
            minWidth: 500,
            idealWidth: viewModel.book != nil ? 620 : 500,
            minHeight: viewModel.book != nil ? 420 : 120,
            idealHeight: viewModel.book != nil ? 600 : 120
        )
        .animation(.easeInOut(duration: 0.3), value: viewModel.book != nil)
        .toolbar {
            ToolbarItemGroup(placement: .principal) {
                HStack(spacing: 12) {
                    Image(systemName: "book.closed.fill")
                        .foregroundStyle(.secondary)
                    TextField("https://akniga.org/...",
                              text: $viewModel.bookURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 320)
                        .onSubmit { Task { await viewModel.fetchBook() } }
                }
            }

            ToolbarItem(placement: .primaryAction) {
                if viewModel.isFetchingBook {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button(String(localized: "Fetch")) {
                        Task { await viewModel.fetchBook() }
                    }
                    .disabled(!viewModel.canFetch)
                }
            }
        }
    }

    // MARK: - Empty state (before fetch)

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            if let error = viewModel.fetchError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            } else if viewModel.isFetchingBook {
                ProgressView()
                Text(String(localized: "Loading book info..."))
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                Image(systemName: "headphones")
                    .font(.system(size: 36))
                    .foregroundStyle(.quaternary)
                Text(String(localized: "Paste a book URL and press Fetch"))
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Book content (after fetch)

    private func bookContentView(_ book: BookInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Error banner
            if let error = viewModel.fetchError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }

            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)

                Text("\(book.chapters.count) " + String(localized: "chapters") + " · \(book.formattedTotalDuration)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Settings
            settingsSection
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            Divider()
                .padding(.horizontal, 16)

            // Chapter list or spacer
            if viewModel.downloadMode == .chapters {
                chapterListSection(book)
            } else {
                Spacer()
            }

            Divider()
                .padding(.horizontal, 16)

            // Bottom bar
            downloadBar
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
        }
    }

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 16) {
                Text(String(localized: "Format"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize()

                Picker(String(localized: "Format"), selection: $viewModel.audioFormat) {
                    ForEach(AudioFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                Text(String(localized: "Mode"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .padding(.leading, 8)

                Picker(String(localized: "Mode"), selection: $viewModel.downloadMode) {
                    Text(String(localized: "Chapters")).tag(DownloadMode.chapters)
                    Text(String(localized: "Single File")).tag(DownloadMode.singleFile)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                Spacer()
            }

            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                    .font(.caption)

                Text(viewModel.outputDirectory.path(percentEncoded: false))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .font(.system(.caption, design: .monospaced))

                Spacer()

                Button(String(localized: "Change...")) {
                    viewModel.chooseOutputDirectory()
                }
                .controlSize(.small)
            }
        }
    }

    // MARK: - Chapter list

    private func chapterListSection(_ book: BookInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Selection header
            HStack {
                Text(String(localized: "Chapters"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Button(String(localized: "All")) { viewModel.selectAll() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.tint)

                Text("/").foregroundStyle(.quaternary).font(.caption)

                Button(String(localized: "None")) { viewModel.deselectAll() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.tint)

                Text("(\(viewModel.selectedCount)/\(book.chapters.count))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 4)

            // Chapter rows
            List(book.chapters) { chapter in
                chapterRow(chapter)
                    .listRowSeparator(.visible)
                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func chapterRow(_ chapter: Chapter) -> some View {
        let isSelected = viewModel.selectedChapterIDs.contains(chapter.id)
        let isCompleted = viewModel.completedChapterIDs.contains(chapter.id)
        let isActive = viewModel.currentChapterID == chapter.id

        return HStack(spacing: 10) {
            // Checkbox
            Image(systemName: isCompleted ? "checkmark.circle.fill" :
                    isSelected ? "checkmark.square.fill" : "square")
                .foregroundStyle(isCompleted ? Color.green : isSelected ? Color.accentColor : Color.gray.opacity(0.4))
                .font(.body)

            Text(chapter.title)
                .font(.callout)
                .lineLimit(1)
                .foregroundStyle(isSelected || isCompleted ? .primary : .secondary)

            Spacer()

            Text(chapter.formattedDuration)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            if isActive {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !viewModel.isDownloading {
                viewModel.toggleChapter(chapter.id)
            }
        }
    }

    // MARK: - Download bar

    private var downloadBar: some View {
        HStack(spacing: 12) {
            if viewModel.isDownloading {
                Button(role: .cancel) {
                    viewModel.cancelDownload()
                } label: {
                    Text(String(localized: "Cancel"))
                }
                .keyboardShortcut(.escape, modifiers: [])

                ProgressView()
                    .controlSize(.small)

                Text(viewModel.downloadProgress)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Button {
                    viewModel.startDownload()
                } label: {
                    Label(String(localized: "Download"), systemImage: "arrow.down.circle.fill")
                }
                .disabled(!viewModel.canDownload)
                .keyboardShortcut("d", modifiers: .command)

                if viewModel.downloadComplete {
                    Label(String(localized: "Complete!"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout.weight(.medium))
                        .transition(.opacity)
                }

                if let error = viewModel.downloadError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
    }
}

#Preview {
    ContentView()
}
