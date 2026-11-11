import AppKit
import SwiftUI

/// How the Board window paints a board. "Standard" follows light and dark mode with system
/// colors; the others look like a real solder mask, the same in both modes. The lit net and the
/// selection always use the accent. People pick one in Settings > Appearance or Board > Board Colors.
struct BoardColors: Identifiable, Hashable {
    let id: String
    let name: String
    /// The board inside its outline, and the outline.
    let board: NSColor
    let edge: NSColor
    /// Part outlines and part names.
    let part: NSColor
    let label: NSColor
    /// Pads, ground pads (quieter), and a net's name drawn on a pad.
    let pin: NSColor
    let ground: NSColor
    let pinText: NSColor

    static let standard = BoardColors(
        id: "standard", name: String(localized: "Standard"),
        board: .textBackgroundColor, edge: .separatorColor,
        part: .tertiaryLabelColor, label: .secondaryLabelColor,
        pin: .secondaryLabelColor, ground: .tertiaryLabelColor, pinText: .labelColor)

    static let all: [BoardColors] = [
        standard,
        BoardColors(id: "green", name: String(localized: "Green"),
                    board: NSColor(hex: 0x1E5631), edge: NSColor(hex: 0x0F2E1A),
                    part: NSColor(hex: 0xE8EDE6).withAlphaComponent(0.55), label: NSColor(hex: 0xF2F5F0),
                    pin: NSColor(hex: 0xD9B45A), ground: NSColor(hex: 0x9C8A5C), pinText: NSColor(hex: 0x1C1A14)),
        BoardColors(id: "blue", name: String(localized: "Blue"),
                    board: NSColor(hex: 0x1D3F7A), edge: NSColor(hex: 0x0E2147),
                    part: NSColor(hex: 0xE6ECF5).withAlphaComponent(0.55), label: NSColor(hex: 0xF0F4FA),
                    pin: NSColor(hex: 0xC9CDD3), ground: NSColor(hex: 0x8B929C), pinText: NSColor(hex: 0x15181D)),
        BoardColors(id: "black", name: String(localized: "Black"),
                    board: NSColor(hex: 0x18191B), edge: NSColor(hex: 0x3A3C40),
                    part: NSColor(hex: 0xE4E4E7).withAlphaComponent(0.45), label: NSColor(hex: 0xE4E4E7),
                    pin: NSColor(hex: 0xD4AF5F), ground: NSColor(hex: 0x7D6B45), pinText: NSColor(hex: 0x18191B)),
        BoardColors(id: "contrast", name: String(localized: "High Contrast"),
                    board: NSColor(hex: 0x000000), edge: NSColor(hex: 0xFFFFFF),
                    part: NSColor(hex: 0xFFFFFF).withAlphaComponent(0.7), label: NSColor(hex: 0xFFFFFF),
                    pin: NSColor(hex: 0xFFFFFF), ground: NSColor(hex: 0x8E8E93), pinText: NSColor(hex: 0x000000)),
    ]

    static func named(_ id: String) -> BoardColors { all.first { $0.id == id } ?? standard }
}
