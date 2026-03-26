# abook-reaper

macOS-застосунок для завантаження аудіокниг з [akniga.org](https://akniga.org).

Вставте посилання на книгу, оберіть формат і натисніть «Завантажити» — застосунок сам витягне метадані, розшифрує потік та збереже аудіо через `ffmpeg`.

[English documentation](README.md) ·

## Можливості

- Завантаження по розділах або одним файлом
- Формати: **M4B** (без перекодування, оригінальний AAC) та **MP3**
- Вибір конкретних розділів через чекбокси
- Скасування завантаження у будь-який момент
- Локалізація: English, Русский, Українська
- macOS 26+, Liquid Glass UI

## Вимоги

- **macOS 26.2+**
- **Xcode 26.3+** (для збірки)
- **ffmpeg** — встановлений за шляхом `/opt/homebrew/bin/ffmpeg`

```bash
brew install ffmpeg
```

## Збірка

```bash
git clone https://github.com/<your-username>/abook-reaper.git
cd abook-reaper
open abook-reaper.xcodeproj
```

В Xcode натисніть **Run** (⌘R).

## Використання

1. Вставте URL книги з akniga.org у поле введення (наприклад `https://akniga.org/author-book-name`)
2. Натисніть **Завантажити** (Fetch)
3. Оберіть формат (M4B / MP3) та режим (по розділах / один файл)
4. Позначте потрібні розділи
5. Оберіть теку для збереження
6. Натисніть **Завантажити** (Download)

## Архітектура

```
abook-reaper/
├── abook_reaperApp.swift        # Точка входу
├── ContentView.swift            # UI (SwiftUI)
├── BookDownloadViewModel.swift  # ViewModel
├── AknigaService.swift          # Робота з API akniga.org
├── CryptoUtils.swift            # AES-дешифрування (CommonCrypto)
├── DownloadService.swift        # Обгортка над ffmpeg (Process)
├── Models.swift                 # Моделі даних
└── Localizable.xcstrings        # Локалізація EN/RU/UK
```
