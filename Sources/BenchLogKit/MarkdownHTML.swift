import Foundation

/// A heading in a rendered guide, for the table of contents.
public struct GuideHeading: Hashable, Sendable, Identifiable {
    public var level: Int
    public var text: String
    /// The HTML id the heading has, for scrolling to it.
    public var anchor: String
    public var id: String { anchor }
}

/// Renders a Markdown guide, Obsidian flavour, to HTML: headings, paragraphs, lists (nested,
/// numbered, tasks), quotes and callouts (`> [!tip] Title`), code, tables, rules, emphasis,
/// links, wiki links (`[[note|alias]]`, `[[#Heading]]`), images (`![](a.png)`, `![[a.png|300]]`),
/// and tags. Plain Foundation, so the iOS app can use it too.
public struct MarkdownHTML {
    /// Turns an image name from the note ("nes_console.png", "Pictures/a.png") into an `src`.
    public var imageSource: (String) -> String?
    /// The scheme of links to other guides: `benchlog-guide:blinking-red-light`.
    public static let guideScheme = "benchlog-guide"

    public init(imageSource: @escaping (String) -> String? = { _ in nil }) {
        self.imageSource = imageSource
    }

    public struct Result: Sendable {
        public var body: String
        public var headings: [GuideHeading]

        public init(body: String, headings: [GuideHeading]) {
            self.body = body
            self.headings = headings
        }
    }

    public func render(_ markdown: String) -> Result {
        var headings: [GuideHeading] = []
        var anchors: [String: Int] = [:]
        let lines = Self.stripFrontMatter(markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n"))
        let body = blocks(lines[...], headings: &headings, anchors: &anchors)
        return Result(body: body, headings: headings)
    }

    // MARK: Blocks

    private func blocks(_ lines: ArraySlice<String>, headings: inout [GuideHeading], anchors: inout [String: Int]) -> String {
        var html = ""
        var index = lines.startIndex
        var paragraph: [String] = []

        func flush() {
            guard !paragraph.isEmpty else { return }
            html += "<p>" + paragraph.map(inline).joined(separator: "<br>\n") + "</p>\n"
            paragraph.removeAll()
        }

        while index < lines.endIndex {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flush()
                index += 1
                continue
            }
            // Fenced code.
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush()
                let fence = String(trimmed.prefix(3))
                var code: [String] = []
                index += 1
                while index < lines.endIndex, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    code.append(lines[index])
                    index += 1
                }
                index += 1
                html += "<pre><code>" + Self.escape(code.joined(separator: "\n")) + "</code></pre>\n"
                continue
            }
            // Headings.
            if let level = Self.headingLevel(trimmed) {
                flush()
                let text = String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                var anchor = Self.slug(text)
                if let seen = anchors[anchor] {
                    anchors[anchor] = seen + 1
                    anchor += "-\(seen + 1)"
                } else {
                    anchors[anchor] = 0
                }
                if level <= 3 { headings.append(GuideHeading(level: level, text: Self.plain(text), anchor: anchor)) }
                html += "<h\(level) id=\"\(anchor)\">\(inline(text))</h\(level)>\n"
                index += 1
                continue
            }
            // Rules.
            if ["---", "***", "___"].contains(trimmed.replacingOccurrences(of: " ", with: "")) && trimmed.count >= 3
                && Set(trimmed.replacingOccurrences(of: " ", with: "")).count == 1 {
                flush()
                html += "<hr>\n"
                index += 1
                continue
            }
            // Quotes and callouts.
            if trimmed.hasPrefix(">") {
                flush()
                var quoted: [String] = []
                while index < lines.endIndex, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    var inner = lines[index].trimmingCharacters(in: .whitespaces).dropFirst()
                    if inner.hasPrefix(" ") { inner = inner.dropFirst() }
                    quoted.append(String(inner))
                    index += 1
                }
                if let first = quoted.first, let callout = Self.callout(first) {
                    let title = callout.title.isEmpty ? callout.type.prefix(1).uppercased() + callout.type.dropFirst() : callout.title
                    html += "<div class=\"callout callout-\(Self.escape(callout.type))\"><div class=\"callout-title\">\(inline(title))</div>\n"
                    html += blocks(quoted.dropFirst()[...], headings: &headings, anchors: &anchors)
                    html += "</div>\n"
                } else {
                    html += "<blockquote>\n" + blocks(quoted[...], headings: &headings, anchors: &anchors) + "</blockquote>\n"
                }
                continue
            }
            // Lists.
            if Self.listMarker(line) != nil {
                flush()
                var items: [String] = []
                let ordered = Self.listMarker(line)?.ordered
                let baseIndent = Self.indent(line)
                while index < lines.endIndex {
                    let next = lines[index]
                    let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
                    // A top-level item of the other kind starts a new list.
                    if let marker = Self.listMarker(next), Self.indent(next) <= baseIndent, marker.ordered != ordered { break }
                    if Self.listMarker(next) != nil || (!nextTrimmed.isEmpty && next.hasPrefix("  ") && !items.isEmpty) {
                        items.append(next)
                        index += 1
                    } else {
                        break
                    }
                }
                html += list(items[...])
                continue
            }
            // Tables: a row of pipes, then a separator row.
            if trimmed.hasPrefix("|"), index + 1 < lines.endIndex, Self.isTableSeparator(lines[index + 1]) {
                flush()
                let header = Self.cells(trimmed)
                index += 2
                var rows: [[String]] = []
                while index < lines.endIndex, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    rows.append(Self.cells(lines[index].trimmingCharacters(in: .whitespaces)))
                    index += 1
                }
                html += "<table><thead><tr>" + header.map { "<th>\(inline($0))</th>" }.joined() + "</tr></thead><tbody>\n"
                for row in rows { html += "<tr>" + row.map { "<td>\(inline($0))</td>" }.joined() + "</tr>\n" }
                html += "</tbody></table>\n"
                continue
            }
            paragraph.append(trimmed)
            index += 1
        }
        flush()
        return html
    }

    /// A list, nested by indentation.
    private func list(_ lines: ArraySlice<String>) -> String {
        guard let first = lines.first, let marker = Self.listMarker(first) else { return "" }
        let baseIndent = Self.indent(first)
        let tag = marker.ordered ? "ol" : "ul"
        var html = "<\(tag)>\n"
        var index = lines.startIndex
        while index < lines.endIndex {
            guard let item = Self.listMarker(lines[index]), Self.indent(lines[index]) <= baseIndent else {
                index += 1
                continue
            }
            let text = item.text
            var more: [String] = []
            var childLines: [String] = []
            index += 1
            while index < lines.endIndex, Self.indent(lines[index]) > baseIndent {
                if Self.listMarker(lines[index]) == nil, childLines.isEmpty {
                    more.append(inline(lines[index].trimmingCharacters(in: .whitespaces)))
                } else {
                    childLines.append(lines[index])
                }
                index += 1
            }
            var content: String
            if text.hasPrefix("[ ] ") || text.hasPrefix("[x] ") || text.hasPrefix("[X] ") {
                let done = !text.hasPrefix("[ ]")
                content = "<span class=\"task\(done ? " done" : "")\">\(done ? "☑" : "☐")</span> " + inline(String(text.dropFirst(4)))
            } else {
                content = inline(text)
            }
            for line in more { content += "<br>" + line }
            if !childLines.isEmpty { content += "\n" + list(childLines[...]) }
            html += "<li>\(content)</li>\n"
        }
        return html + "</\(tag)>\n"
    }

    // MARK: Inline

    private func inline(_ raw: String) -> String {
        var text = Self.escape(raw)
        var stash: [String] = []
        func keep(_ html: String) -> String {
            stash.append(html)
            return "\u{1}\(stash.count - 1)\u{2}"
        }

        // Code spans first, so nothing inside them changes.
        text = Self.replace(#"`([^`]+)`"#, in: text) { keep("<code>\($0[1])</code>") }
        // Obsidian image embeds: ![[name.png|300]].
        text = Self.replace(#"!\[\[([^\]|]+)(?:\|([^\]]*))?\]\]"#, in: text) { groups in
            let name = Self.unescape(groups[1]).trimmingCharacters(in: .whitespaces)
            if Self.isImage(name), let src = imageSource(name) {
                let width = Int(groups[2]).map { " width=\"\($0)\"" } ?? ""
                return keep("<img src=\"\(Self.escape(src))\" alt=\"\(Self.escape(name))\"\(width)>")
            }
            if Self.isImage(name) { return keep("<span class=\"missing\">\(Self.escape(name))</span>") }
            return keep(guideLink(target: name, label: nil))
        }
        // Standard images: ![alt](path).
        text = Self.replace(#"!\[([^\]]*)\]\(([^)\s]+)(?:\s+&quot;[^)]*&quot;)?\)"#, in: text) { groups in
            let path = Self.unescape(groups[2]).removingPercentEncoding ?? Self.unescape(groups[2])
            let src = path.hasPrefix("http") ? path : imageSource(path)
            guard let src else { return keep("<span class=\"missing\">\(groups[1].isEmpty ? Self.escape(path) : groups[1])</span>") }
            return keep("<img src=\"\(Self.escape(src))\" alt=\"\(groups[1])\">")
        }
        // Wiki links: [[note]], [[note|alias]], [[#Heading]], [[note#Heading|alias]].
        text = Self.replace(#"\[\[([^\]|]+)(?:\|([^\]]*))?\]\]"#, in: text) { groups in
            keep(guideLink(target: Self.unescape(groups[1]), label: groups[2].isEmpty ? nil : groups[2]))
        }
        // Links: [text](url).
        text = Self.replace(#"\[([^\]]+)\]\(([^)\s]+)\)"#, in: text) { groups in
            keep("<a href=\"\(groups[2])\">\(groups[1])</a>")
        }
        // Bare web addresses.
        text = Self.replace(#"(?<![\w"=/])(https?://[^\s<]+[^\s<.,;:!?)])"#, in: text) { keep("<a href=\"\($0[1])\">\($0[1])</a>") }
        // Emphasis.
        text = Self.replace(#"\*\*(.+?)\*\*"#, in: text) { "<strong>\($0[1])</strong>" }
        text = Self.replace(#"__(.+?)__"#, in: text) { "<strong>\($0[1])</strong>" }
        text = Self.replace(#"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])"#, in: text) { "<em>\($0[1])</em>" }
        text = Self.replace(#"(?<![\w_])_(?!\s)(.+?)(?<!\s)_(?![\w_])"#, in: text) { "<em>\($0[1])</em>" }
        text = Self.replace(#"~~(.+?)~~"#, in: text) { "<del>\($0[1])</del>" }
        text = Self.replace(#"==(.+?)=="#, in: text) { "<mark>\($0[1])</mark>" }
        // Tags: #power, #nes/fault.
        text = Self.replace(#"(^|\s)#([\p{L}\p{N}_/-]*\p{L}[\p{L}\p{N}_/-]*)"#, in: text) { "\($0[1])<span class=\"tag\">#\($0[2])</span>" }

        // Put the kept pieces back.
        return Self.replace("\u{1}(\\d+)\u{2}", in: text) { stash[Int($0[1]) ?? 0] }
    }

    private func guideLink(target: String, label: String?) -> String {
        let parts = target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let note = parts[0].trimmingCharacters(in: .whitespaces)
        let heading = parts.count > 1 ? parts[1] : ""
        let shown = label ?? (note.isEmpty ? heading : (note as NSString).lastPathComponent)
        if note.isEmpty {
            return "<a href=\"#\(Self.slug(heading))\">\(Self.escape(shown))</a>"
        }
        let encoded = note.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? note
        return "<a class=\"guide-link\" href=\"\(Self.guideScheme):\(Self.escape(encoded))\">\(Self.escape(shown))</a>"
    }

    // MARK: Helpers

    /// The id a heading gets, and the target of `[[#Heading]]`: lowercase letters and digits,
    /// words joined with "-". "🚀 Getting Started" → "getting-started".
    public static func slug(_ text: String) -> String {
        let plain = Self.plain(text).lowercased()
        var words: [String] = []
        var word = ""
        for scalar in plain.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                word.unicodeScalars.append(scalar)
            } else if !word.isEmpty {
                words.append(word)
                word = ""
            }
        }
        if !word.isEmpty { words.append(word) }
        return words.isEmpty ? "section" : words.joined(separator: "-")
    }

    /// Text without Markdown marks, for the table of contents.
    static func plain(_ text: String) -> String {
        var result = text
        result = replace(#"\[\[([^\]|]+)\|([^\]]+)\]\]"#, in: result) { $0[2] }
        result = replace(#"\[\[([^\]]+)\]\]"#, in: result) { $0[1] }
        result = replace(#"\[([^\]]+)\]\([^)]*\)"#, in: result) { $0[1] }
        for mark in ["**", "__", "`", "~~", "=="] { result = result.replacingOccurrences(of: mark, with: "") }
        return result.trimmingCharacters(in: .whitespaces)
    }

    static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    static func listMarker(_ line: String) -> (ordered: Bool, text: String)? {
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        if let first = trimmed.first, "-*+".contains(first), trimmed.dropFirst().first == " " {
            return (false, String(trimmed.dropFirst(2)))
        }
        let digits = trimmed.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count < 4 {
            let rest = trimmed.dropFirst(digits.count)
            if rest.first == "." || rest.first == ")", rest.dropFirst().first == " " {
                return (true, String(rest.dropFirst(2)))
            }
        }
        return nil
    }

    static func indent(_ line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
    }

    static func callout(_ line: String) -> (type: String, title: String)? {
        guard let match = line.firstMatch(of: /^\[!([A-Za-z-]+)\][+-]?\s*(.*)$/) else { return nil }
        return (String(match.1).lowercased(), String(match.2))
    }

    static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("|") && trimmed.contains("-") && trimmed.allSatisfy { "|-: ".contains($0) }
    }

    static func cells(_ row: String) -> [String] {
        var inner = Substring(row)
        if inner.hasPrefix("|") { inner = inner.dropFirst() }
        if inner.hasSuffix("|") { inner = inner.dropLast() }
        return inner.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func stripFrontMatter(_ lines: [String]) -> [String] {
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else { return lines }
        return Array(lines[(end + 1)...])
    }

    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "svg", "tif", "tiff"]

    static func isImage(_ name: String) -> Bool {
        imageExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    public static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&amp;", with: "&")
    }

    /// Replaces every match of a pattern; the closure gets the groups (0 is the whole match,
    /// a group that did not take part is "").
    static func replace(_ pattern: String, in text: String, with transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return text }
        let ns = text as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let groups = (0..<match.numberOfRanges).map { i -> String in
                let range = match.range(at: i)
                return range.location == NSNotFound ? "" : ns.substring(with: range)
            }
            result += transform(groups)
            last = match.range.location + match.range.length
        }
        result += ns.substring(from: last)
        return result
    }

    // MARK: Page

    /// A whole HTML page around a rendered body, light and dark, in the system font.
    public static func page(body: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="color-scheme" content="light dark">
        <style>
        :root { --text: #1d1d1f; --muted: #6e6e73; --line: #d2d2d7; --code: #f2f2f7; --accent: #0a84ff;
                --note: #0a84ff; --tip: #30a46c; --warning: #e5850b; --danger: #e5484d; --mark: #fff3a3; }
        @media (prefers-color-scheme: dark) {
          :root { --text: #f5f5f7; --muted: #a1a1a6; --line: #3a3a3c; --code: #2c2c2e; --mark: #6b5d0f; }
        }
        html { font: -apple-system-body; font-family: -apple-system, system-ui; -webkit-text-size-adjust: 100%; }
        body { color: var(--text); background: transparent; margin: 0; padding: 24px 32px 64px; max-width: 760px; line-height: 1.5; } /* grid: ok line-height is a ratio */
        h1 { font-size: 1.8em; margin: 0 0 .6em; } h2 { font-size: 1.35em; margin: 1.6em 0 .5em; } h3 { font-size: 1.1em; margin: 1.3em 0 .4em; }
        h1, h2, h3, h4 { line-height: 1.25; scroll-margin-top: 16px; } /* grid: ok line-height is a ratio */
        p, ul, ol, table, pre, blockquote, .callout { margin: 0 0 1em; }
        ul, ol { padding-left: 1.4em; } li { margin: .2em 0; } li > ul, li > ol { margin: .2em 0; }
        img { max-width: 100%; height: auto; border-radius: 8px; display: block; margin: .6em 0; }
        a { color: var(--accent); text-decoration: none; } a:hover { text-decoration: underline; }
        code { font: .9em ui-monospace, SF Mono, Menlo, monospace; background: var(--code); padding: .1em .35em; border-radius: 4px; }
        pre { background: var(--code); padding: 12px 14px; border-radius: 8px; overflow-x: auto; }
        pre code { background: none; padding: 0; }
        hr { border: 0; border-top: 1px solid var(--line); margin: 1.6em 0; }
        blockquote { border-left: 3px solid var(--line); margin-left: 0; padding-left: 14px; color: var(--muted); }
        table { border-collapse: collapse; } th, td { border: 1px solid var(--line); padding: 6px 10px; text-align: left; vertical-align: top; }
        mark { background: var(--mark); color: inherit; padding: 0 .15em; border-radius: 3px; }
        .tag { color: var(--accent); background: color-mix(in srgb, var(--accent) 12%, transparent); padding: .05em .45em; border-radius: 999px; font-size: .9em; }
        .task { margin-right: .2em; } .task.done + * { color: var(--muted); }
        .missing { color: var(--muted); font-style: italic; }
        .callout { --c: var(--note); border-left: 3px solid var(--c); background: color-mix(in srgb, var(--c) 9%, transparent); padding: 10px 14px; border-radius: 6px; }
        .callout > :last-child { margin-bottom: 0; }
        .callout-title { font-weight: 600; color: var(--c); margin-bottom: .3em; }
        .callout-tip, .callout-success, .callout-check, .callout-done, .callout-hint { --c: var(--tip); }
        .callout-warning, .callout-caution, .callout-attention, .callout-question, .callout-help, .callout-faq { --c: var(--warning); }
        .callout-danger, .callout-error, .callout-bug, .callout-failure, .callout-fail, .callout-missing { --c: var(--danger); }
        </style></head><body>
        \(body)
        </body></html>
        """
    }
}
