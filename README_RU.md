# abook-reaper

macOS-приложение для скачивания аудиокниг с [akniga.org](https://akniga.org).

Вставьте ссылку на книгу, выберите формат и нажмите «Скачать» — приложение само извлечёт метаданные, расшифрует поток и загрузит аудио через `ffmpeg`.

[English documentation](README.md) · [Документация на украинском](README_UA.md)

## Возможности

- Скачивание по главам или одним файлом
- Форматы: **M4B** (без перекодирования, оригинальный AAC) и **MP3**
- Выбор конкретных глав через чекбоксы
- Отмена загрузки в любой момент
- Локализация: English, Русский, Українська
- macOS 26+, Liquid Glass UI

## Требования

- **macOS 26.2+**
- **Xcode 26.3+** (для сборки)
- **ffmpeg** — установлен по пути `/opt/homebrew/bin/ffmpeg`

```bash
brew install ffmpeg
```

## Сборка

```bash
git clone https://github.com/<your-username>/abook-reaper.git
cd abook-reaper
open abook-reaper.xcodeproj
```

В Xcode нажмите **Run** (⌘R).

## Использование

1. Вставьте URL книги с akniga.org в поле ввода (например `https://akniga.org/author-book-name`)
2. Нажмите **Загрузить** (Fetch)
3. Выберите формат (M4B / MP3) и режим (по главам / один файл)
4. Отметьте нужные главы
5. Выберите папку для сохранения
6. Нажмите **Скачать** (Download)

## Архитектура

```
abook-reaper/
├── abook_reaperApp.swift        # Точка входа
├── ContentView.swift            # UI (SwiftUI)
├── BookDownloadViewModel.swift  # ViewModel
├── AknigaService.swift          # Работа с API akniga.org
├── CryptoUtils.swift            # AES-дешифровка (CommonCrypto)
├── DownloadService.swift        # Обёртка над ffmpeg (Process)
├── Models.swift                 # Модели данных
└── Localizable.xcstrings        # Локализация EN/RU/UK
```
