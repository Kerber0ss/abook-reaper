# abook-reaper

A macOS app for downloading audiobooks from [akniga.org](https://akniga.org).

Paste a book URL, pick a format, and hit Download — the app extracts metadata, decrypts the audio stream, and saves it via `ffmpeg`.

[Ukrainian documentation](README_UA.md) · [Russian docs](README_RU.md)

## Features

- Download by chapters or as a single file
- Formats: **M4B** (no re-encoding, original AAC) and **MP3**
- Select specific chapters via checkboxes
- Cancel downloads at any time
- Localization: English, Русский, Українська
- macOS 26+, Liquid Glass UI

## Requirements

- **macOS 26.2+**
- **Xcode 26.3+** (to build)
- **ffmpeg** installed at `/opt/homebrew/bin/ffmpeg`

```bash
brew install ffmpeg
```

## Build

```bash
git clone https://github.com/<your-username>/abook-reaper.git
cd abook-reaper
open abook-reaper.xcodeproj
```

Press **Run** (⌘R) in Xcode.

## Usage

1. Paste a book URL from akniga.org (e.g. `https://akniga.org/author-book-name`)
2. Click **Fetch**
3. Choose format (M4B / MP3) and mode (by chapters / single file)
4. Check the chapters you want
5. Pick a download folder
6. Click **Download**

## Architecture

```
abook-reaper/
├── abook_reaperApp.swift        # App entry point
├── ContentView.swift            # UI (SwiftUI)
├── BookDownloadViewModel.swift  # ViewModel
├── AknigaService.swift          # akniga.org API client
├── CryptoUtils.swift            # AES decryption (CommonCrypto)
├── DownloadService.swift        # ffmpeg wrapper (Process)
├── Models.swift                 # Data models
└── Localizable.xcstrings        # Localization EN/RU/UK
```
