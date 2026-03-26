//
//  AknigaService.swift
//  abook-reaper
//
//  Handles all communication with akniga.org:
//  1. Scrape page for book ID, security key, chapter titles
//  2. Fetch player token
//  3. Fetch book data (encrypted m3u8 + chapter items)
//  4. Decrypt m3u8 URL
//

import Foundation

actor AknigaService {

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpCookieStorage = HTTPCookieStorage.shared
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Given a book page URL, returns fully resolved BookInfo with m3u8 URL.
    func fetchBook(from pageURL: String) async throws -> BookInfo {
        // Step 1: Get page HTML
        print("[AknigaService] Step 1: Fetching page: \(pageURL)")
        let html = try await fetchPage(pageURL)
        print("[AknigaService] Step 1: Got HTML, length=\(html.count)")

        // Parse metadata from HTML
        guard let bid = extractBookID(from: html) else {
            print("[AknigaService] ERROR: Book ID not found in HTML")
            throw AknigaError.bookIdNotFound
        }
        print("[AknigaService] Book ID: \(bid)")
        guard let securityKey = extractSecurityKey(from: html) else {
            print("[AknigaService] ERROR: Security key not found in HTML")
            throw AknigaError.securityKeyNotFound
        }
        print("[AknigaService] Security key: \(securityKey)")
        let title = extractTitle(from: html) ?? "Unknown Book"
        let chapterTitles = extractChapterTitles(from: html)
        print("[AknigaService] Title: \(title), chapters from HTML: \(chapterTitles.count)")

        // Step 2: Get player token
        print("[AknigaService] Step 2: Fetching token...")
        let token = try await fetchToken(bid: bid, securityKey: securityKey, referer: pageURL)
        print("[AknigaService] Token: \(token.prefix(20))...")

        // Step 3: Get book data
        print("[AknigaService] Step 3: Fetching book data...")
        let (hres, itemsJSON) = try await fetchBookData(
            bid: bid, token: token, securityKey: securityKey, referer: pageURL
        )
        print("[AknigaService] hres length: \(hres.count), items length: \(itemsJSON.count)")

        // Step 4: Decrypt m3u8 URL
        print("[AknigaService] Step 4: Decrypting hres...")
        guard let decrypted = CryptoUtils.decryptHres(hres) else {
            print("[AknigaService] ERROR: CryptoUtils.decryptHres returned nil")
            print("[AknigaService] hres value: \(hres.prefix(100))...")
            throw AknigaError.decryptionFailed
        }
        print("[AknigaService] Decrypted: \(decrypted.prefix(80))...")
        guard let m3u8URL = extractURL(from: decrypted) else {
            print("[AknigaService] ERROR: extractURL returned nil for decrypted: \(decrypted)")
            throw AknigaError.decryptionFailed
        }
        print("[AknigaService] m3u8 URL: \(m3u8URL.prefix(80))...")

        // Step 5: Parse chapters
        print("[AknigaService] Step 5: Parsing chapters...")
        let chapters = try parseChapters(itemsJSON: itemsJSON, fallbackTitles: chapterTitles)
        print("[AknigaService] Parsed \(chapters.count) chapters")

        return BookInfo(id: bid, title: title, chapters: chapters, m3u8URL: m3u8URL)
    }

    // MARK: - Step 1: Fetch page

    private func fetchPage(_ urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw AknigaError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.5", forHTTPHeaderField: "Accept-Language")

        let (data, _) = try await session.data(for: request)
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1251) else {
            throw AknigaError.invalidURL
        }
        return html
    }

    // MARK: - Step 2: Fetch token

    private func fetchToken(bid: String, securityKey: String, referer: String) async throws -> String {
        guard let url = URL(string: "https://akniga.org/ajax/player/token") else {
            throw AknigaError.tokenFetchFailed("invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let ts = String(Int(Date().timeIntervalSince1970 * 1000))
        let body = "bid=\(bid)&ts=\(ts)&security_ls_key=\(securityKey)"
        request.httpBody = body.data(using: .utf8)

        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("https://akniga.org", forHTTPHeaderField: "Origin")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue(browserUA, forHTTPHeaderField: "User-Agent")
        request.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        request.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AknigaError.tokenFetchFailed("HTTP \(code)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["token"] as? String else {
            throw AknigaError.tokenFetchFailed("no token in response")
        }

        return token
    }

    // MARK: - Step 3: Fetch book data

    private func fetchBookData(bid: String, token: String, securityKey: String, referer: String) async throws -> (String, String) {
        guard let url = URL(string: "https://akniga.org/ajax/b/\(bid)") else {
            throw AknigaError.bookDataFetchFailed("invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let body = "bid=\(bid)&token=\(token)&hls=1&security_ls_key=\(securityKey)"
        request.httpBody = body.data(using: .utf8)

        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("https://akniga.org", forHTTPHeaderField: "Origin")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue(browserUA, forHTTPHeaderField: "User-Agent")
        request.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        request.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AknigaError.bookDataFetchFailed("HTTP \(code)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hres = json["hres"] as? String,
              let items = json["items"] as? String else {
            throw AknigaError.bookDataFetchFailed("missing hres/items in response")
        }

        return (hres, items)
    }

    // MARK: - Parsing helpers

    private func extractBookID(from html: String) -> String? {
        // data-bid="XXXXX"
        guard let range = html.range(of: #"data-bid="(\d+)""#, options: .regularExpression),
              let match = html[range].split(separator: "\"").dropFirst().first else {
            return nil
        }
        return String(match)
    }

    private func extractSecurityKey(from html: String) -> String? {
        // var LIVESTREET_SECURITY_KEY = 'XXXXX';
        guard let range = html.range(of: #"LIVESTREET_SECURITY_KEY\s*=\s*'([^']+)'"#, options: .regularExpression) else {
            return nil
        }
        let segment = html[range]
        guard let qStart = segment.range(of: "'"),
              let qEnd = segment[segment.index(after: qStart.lowerBound)...].range(of: "'") else {
            return nil
        }
        return String(segment[segment.index(after: qStart.lowerBound)..<qEnd.lowerBound])
    }

    private func extractTitle(from html: String) -> String? {
        // <meta property="og:title" content="TITLE">
        guard let range = html.range(of: #"<meta\s+property="og:title"\s+content="([^"]+)""#, options: .regularExpression) else {
            // Try <h1> or <title>
            if let tRange = html.range(of: #"<title>([^<]+)</title>"#, options: .regularExpression) {
                let segment = html[tRange]
                let inner = segment.drop(while: { $0 != ">" }).dropFirst()
                return String(inner.prefix(while: { $0 != "<" }))
            }
            return nil
        }
        let segment = html[range]
        // Extract content="..."
        if let cRange = segment.range(of: #"content="([^"]+)""#, options: .regularExpression) {
            let val = segment[cRange]
            let inner = val.dropFirst(9).dropLast(1) // drop content=" and trailing "
            return String(inner)
        }
        return nil
    }

    private func extractChapterTitles(from html: String) -> [String] {
        // <span class="chapter__default--title">TITLE</span>
        var titles = [String]()
        let pattern = #"chapter__default--title[^>]*>([^<]+)<"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let nsHTML = html as NSString
        let matches = regex?.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)) ?? []

        for match in matches {
            if match.numberOfRanges > 1 {
                let titleRange = match.range(at: 1)
                let title = nsHTML.substring(with: titleRange)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                titles.append(title)
            }
        }
        return titles
    }

    private func extractURL(from decrypted: String) -> String? {
        // Decrypted result may be a JSON string (quoted URL) or plain URL
        if decrypted.hasPrefix("\"") {
            // JSON-encoded string — need .fragmentsAllowed to parse a bare string
            if let data = decrypted.data(using: .utf8),
               let url = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? String {
                return url
            }
        }
        if decrypted.hasPrefix("http") {
            return decrypted.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    /// Parse chapter items from the JSON string returned by the API.
    /// Each item: {"title":"...", "duration":N, "time":CUMULATIVE_END, "time_from_start":N, "file":"..."}
    private func parseChapters(itemsJSON: String, fallbackTitles: [String]) throws -> [Chapter] {
        guard let data = itemsJSON.data(using: .utf8),
              let items = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw AknigaError.itemsParsingFailed
        }

        var chapters = [Chapter]()
        for (i, item) in items.enumerated() {
            let title: String
            if let t = item["title"] as? String, !t.isEmpty {
                title = t
            } else if i < fallbackTitles.count {
                title = fallbackTitles[i]
            } else {
                title = "Chapter \(i + 1)"
            }

            let duration: TimeInterval
            if let d = item["duration"] as? TimeInterval {
                duration = d
            } else if let d = item["duration"] as? Int {
                duration = TimeInterval(d)
            } else {
                duration = 0
            }

            let startTime: TimeInterval
            if i == 0 {
                startTime = 0
            } else {
                // Previous chapter's cumulative end time = this chapter's start
                if let prevTime = items[i - 1]["time"] as? TimeInterval {
                    startTime = prevTime
                } else if let prevTime = items[i - 1]["time"] as? Int {
                    startTime = TimeInterval(prevTime)
                } else {
                    startTime = 0
                }
            }

            chapters.append(Chapter(id: i, title: title, duration: duration, startTime: startTime))
        }

        return chapters
    }

    private let browserUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
}
