import Foundation

/// Rules for linking a board to its schematic PDF, without PDFKit.
public enum Schematic {
    /// A match of "C713" inside "C7130" or "PP3V3" inside "PP3V3_S0" is not the same name.
    /// `before` and `after` are the characters around the match, nil at the edge of the text.
    public static func isWholeName(before: Character?, after: Character?) -> Bool {
        !isNameCharacter(before) && !isNameCharacter(after)
    }

    private static func isNameCharacter(_ c: Character?) -> Bool {
        guard let c else { return false }
        return c.isLetter || c.isNumber || c == "_"
    }

    /// The schematic to open with a board, from the PDFs beside it: one whose name says
    /// "sch" or shares a number with the board's name (4924 in 820-4924-A), else the first.
    public static func pick(for boardName: String, from pdfNames: [String]) -> Int? {
        guard !pdfNames.isEmpty else { return nil }
        let base = (boardName as NSString).deletingPathExtension.lowercased()
        let tokens = base.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init).filter { $0.count >= 4 && $0.contains(where: \.isNumber) }
        func score(_ name: String) -> Int {
            let lower = name.lowercased()
            var s = 0
            if lower.contains("sch") { s += 2 }
            if tokens.contains(where: { lower.contains($0) }) { s += 1 }
            return s
        }
        // The first of the best: max(by:) keeps the earlier element on a tie.
        return pdfNames.indices.max { score(pdfNames[$0]) < score(pdfNames[$1]) }
    }

    /// The text a person selected in the schematic, as a name to look up on the board:
    /// one word, trimmed of spaces and punctuation around it.
    public static func name(fromSelection text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters).subtracting(CharacterSet(charactersIn: "_")))
        guard !trimmed.isEmpty, trimmed.count <= 64, !trimmed.contains(where: \.isWhitespace) else { return nil }
        return trimmed
    }
}
