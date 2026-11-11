import BoardViewKit
import Foundation
import PDFKit
import Security

/// Explain This Part: asks Claude what a part does, from its schematic page. Only when people ask,
/// and only the page, the part's name, value, and pin nets are sent: never a customer or a repair.
enum PartExplainer {
    static let model = "claude-opus-5-5"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    /// What is sent about one part.
    struct Question: Sendable {
        var part: String
        var type: String?
        var value: String?
        /// "1: PP3V3_S0 (3.3 V in S0)", one per pin, grounds grouped.
        var pins: [String]
        /// The page it is on, from 1.
        var pageNumber: Int
        /// That one page, as a PDF.
        var page: Data
        /// "French (Canada)" or "English".
        var language: String
    }

    enum Failure: LocalizedError, Equatable {
        case noKey, notInSchematic, invalidKey, busy, refused, server(String), network(String)

        var errorDescription: String? {
            switch self {
            case .noKey: String(localized: "Add a Claude API key in Settings > Board first.")
            case .notInSchematic: String(localized: "This part isn't in the schematic, so there is no page to send.")
            case .invalidKey: String(localized: "Claude didn't accept the API key. Check it in Settings > Board.")
            case .busy: String(localized: "Claude is busy. Try again in a minute.")
            case .refused: String(localized: "Claude declined to answer about this part.")
            case .server(let message): String(localized: "Claude couldn't answer: \(message)")
            case .network(let message): String(localized: "BenchLog couldn't reach Claude: \(message)")
            }
        }
    }

    // MARK: The request

    static let instructions = """
        You help a technician who repairs laptops and other electronics at the board level. You get one page \
        of a schematic and one part on it, with the nets on its pins as the board file names them. Say what the \
        part does in this circuit in 2 to 5 short sentences: its job, the nets it takes power or signals from \
        and the ones it makes, and how to check it with a multimeter (the voltages to expect, or diode mode or \
        resistance to ground). Use what the page shows and what is standard for this part number. When the page \
        doesn't show enough, say so instead of guessing. Plain text: no headings, lists, or Markdown.
        """

    /// The one-page PDF of a schematic page.
    static func pagePDF(_ document: PDFDocument, page index: Int) -> Data? {
        guard let page = document.page(at: index)?.copy() as? PDFPage else { return nil }
        let single = PDFDocument()
        single.insert(page, at: 0)
        return single.dataRepresentation()
    }

    /// The Messages API request body, as JSON.
    static func body(for question: Question) -> Data {
        var facts = "Part: \(question.part)"
        if let type = question.type { facts += " (\(type))" }
        facts += "\nOn schematic page \(question.pageNumber)."
        if let value = question.value { facts += "\nThe schematic prints: \(value)" }
        facts += "\nPins and their nets:\n" + question.pins.joined(separator: "\n")
        facts += "\n\nAnswer in \(question.language)."
        let json: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "output_config": ["effort": "medium"],
            // On a safety decline, the API reruns the question on a fallback model.
            "fallbacks": "default",
            "system": instructions,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "document",
                     "source": ["type": "base64", "media_type": "application/pdf", "data": question.page.base64EncodedString()]],
                    ["type": "text", "text": facts],
                ],
            ]],
        ]
        return (try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])) ?? Data()
    }

    static func request(for question: Question, key: String) -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: 180)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = body(for: question)
        return request
    }

    /// Asks Claude. Returns its answer, or throws a `Failure`.
    static func ask(_ question: Question, key: String) async throws -> String {
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request(for: question, key: key))
        } catch {
            throw Failure.network(error.localizedDescription)
        }
        return try answer(from: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// Reads a Messages API response: its text, or why there is none.
    static func answer(from data: Data, status: Int) throws -> String {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        switch status {
        case 200: break
        case 401, 403: throw Failure.invalidKey
        case 429, 529: throw Failure.busy
        default:
            let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? HTTPURLResponse.localizedString(forStatusCode: status)
            throw Failure.server(message)
        }
        if json?["stop_reason"] as? String == "refusal" { throw Failure.refused }
        let blocks = json?["content"] as? [[String: Any]] ?? []
        let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }
            .joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw Failure.server(String(localized: "an empty answer")) }
        return text
    }

    /// The language answers come in: the app's.
    static var language: String {
        Bundle.main.preferredLocalizations.first?.hasPrefix("fr") == true ? "French (Canada)" : "English"
    }

    // MARK: The key, in the Keychain (in memory in test runs)

    private static let service = "com.mathieuares.benchlog.claude"
    private static let account = "api-key"
    private static var memoryKey: String?

    static var apiKey: String? {
        if Store.isOverridden { return memoryKey }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        let key = String(decoding: data, as: UTF8.self)
        return key.isEmpty ? nil : key
    }

    static func saveKey(_ key: String?) {
        let key = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        if Store.isOverridden { memoryKey = key?.isEmpty == false ? key : nil; return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        guard let key, !key.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    // MARK: Answers kept with the schematic

    /// Explanations/<schematic>-<size>.json next to the library: part name → answer.
    static func cacheURL(for schematic: URL) -> URL {
        let folder = (Store.isOverridden ? Store.url.deletingLastPathComponent() : Store.folder)
            .appending(path: "Explanations", directoryHint: .isDirectory)
        let size = (try? schematic.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let name = schematic.deletingPathExtension().lastPathComponent
            .map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? String($0) : "_" }.joined()
        return folder.appending(path: "\(name)-\(size).json")
    }

    static func cached(for schematic: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: cacheURL(for: schematic)),
              let answers = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return answers
    }

    static func keep(_ answers: [String: String], for schematic: URL) {
        let url = cacheURL(for: schematic)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(answers).write(to: url, options: .atomic)
    }
}
