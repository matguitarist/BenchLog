import Foundation
import GRDB

// Starter parts: the parts, accessories, cables, and controllers a retro-console bench
// usually stocks, one set per console. Adding a set puts them in the inventory at zero
// stock with a suggested price; people then count what they have and set their own
// cost and price.

/// One part of a starter set.
public struct StarterPart: Hashable, Sendable {
    public var name: String
    public var kind: PartKind
    /// A suggested price in cents (CAD), a starting point to change.
    public var priceCents: Int
    public var condition: PartCondition?
    /// Other sets whose console it fits too (a PlayStation AV cable fits the PS1 and the PS2).
    public var alsoFits: [StarterSet]

    init(_ name: String, _ kind: PartKind, _ priceCents: Int, _ condition: PartCondition? = nil, alsoFits: [StarterSet] = []) {
        self.name = name
        self.kind = kind
        self.priceCents = priceCents
        self.condition = condition
        self.alsoFits = alsoFits
    }
}

/// A console with its starter parts.
public enum StarterSet: String, CaseIterable, Sendable, Identifiable {
    case ps1, ps2, xbox
    public var id: String { rawValue }

    /// The catalog model the set's parts fit.
    public var fit: PartFit {
        switch self {
        case .ps1: PartFit(category: .console, brand: "Sony", model: "PS1")
        case .ps2: PartFit(category: .console, brand: "Sony", model: "PS2")
        case .xbox: PartFit(category: .console, brand: "Microsoft", model: "Xbox")
        }
    }

    public var title: String { fit.title }

    public var parts: [StarterPart] {
        switch self {
        case .ps1: [
            StarterPart("PS1 laser assembly KSM-440ACM", .part, 2999),
            StarterPart("PS1 laser assembly KSM-440ADM", .part, 2999),
            StarterPart("PSone laser assembly KSM-440BAM", .part, 2999),
            StarterPart("PS1 power supply board", .part, 2499, .used),
            StarterPart("PS1 controller port assembly", .part, 1499, .used),
            StarterPart("PS1 disc lid switch", .part, 599),
            StarterPart("PS1 capacitor kit", .part, 1499),
            StarterPart("PS1 console screw and feet set", .part, 799),
            StarterPart("PS1 DualShock controller (SCPH-1200)", .controller, 2499, .used),
            StarterPart("PS1 digital controller (SCPH-1080)", .controller, 1499, .used),
            StarterPart("PS1 memory card (15 blocks)", .accessory, 999, .used),
            StarterPart("PS1 multitap (SCPH-1070)", .accessory, 2499, .used),
            StarterPart("PSone AC adapter", .accessory, 1999, .used),
            StarterPart("PlayStation AV cable (composite)", .cable, 999, alsoFits: [.ps2]),
            StarterPart("PlayStation S-Video cable", .cable, 1499, alsoFits: [.ps2]),
            StarterPart("PlayStation RF adapter", .cable, 999, .used, alsoFits: [.ps2]),
            StarterPart("PlayStation to HDMI adapter", .cable, 2499, alsoFits: [.ps2]),
            StarterPart("PlayStation power cord (2-prong)", .cable, 799, alsoFits: [.ps2]),
            StarterPart("PS1 link cable", .cable, 999, .used),
        ]
        case .ps2: [
            StarterPart("PS2 Fat laser assembly KHS-400C", .part, 2999),
            StarterPart("PS2 Slim laser assembly KHM-430", .part, 2499),
            StarterPart("PS2 Slim laser assembly PVR-802W", .part, 2499),
            StarterPart("PS2 Slim laser ribbon cable", .part, 699),
            StarterPart("PS2 Fat power and eject ribbon cable", .part, 699),
            StarterPart("PS2 Fat cooling fan", .part, 1499),
            StarterPart("PS2 Slim cooling fan", .part, 1499),
            StarterPart("PS2 Fat power supply", .part, 2999, .used),
            StarterPart("PS2 controller and memory card port assembly", .part, 1999, .used),
            StarterPart("PS2 clock battery (CR2032)", .supply, 399),
            StarterPart("PS2 capacitor kit", .part, 1499),
            StarterPart("PS2 DualShock 2 controller (SCPH-10010)", .controller, 2999, .used),
            StarterPart("PS2 DualShock 2 analog stick", .part, 599),
            StarterPart("PS2 memory card (8 MB)", .accessory, 1499, .used),
            StarterPart("PS2 multitap", .accessory, 2499, .used),
            StarterPart("PS2 network adapter (Fat)", .accessory, 2999, .used),
            StarterPart("PS2 DVD remote control", .accessory, 1499, .used),
            StarterPart("PS2 Slim AC adapter (8.5 V)", .accessory, 2499, .used),
            StarterPart("PS2 component AV cable", .cable, 1999),
        ]
        case .xbox: [
            StarterPart("Xbox DVD drive", .part, 3999, .used),
            StarterPart("Xbox DVD drive belt", .part, 499),
            StarterPart("Xbox clock capacitor (1 F, 2.5 V)", .part, 599),
            StarterPart("Xbox capacitor kit", .part, 1999),
            StarterPart("Xbox power supply", .part, 3499, .used),
            StarterPart("Xbox cooling fan", .part, 1499),
            StarterPart("Xbox hard drive", .part, 2999, .used),
            StarterPart("Xbox IDE cable (80-wire)", .part, 999),
            StarterPart("Xbox controller port board", .part, 1499, .used),
            StarterPart("Xbox power and eject button board", .part, 1299, .used),
            StarterPart("Xbox Controller S", .controller, 2999, .used),
            StarterPart("Xbox Duke controller", .controller, 3999, .used),
            StarterPart("Xbox controller analog stick", .part, 599),
            StarterPart("Xbox controller breakaway cable", .cable, 999, .used),
            StarterPart("Xbox memory unit (8 MB)", .accessory, 1499, .used),
            StarterPart("Xbox DVD playback kit", .accessory, 1999, .used),
            StarterPart("Xbox AV cable (composite)", .cable, 1299),
            StarterPart("Xbox component AV cable", .cable, 2499),
            StarterPart("Xbox to HDMI adapter", .cable, 2999),
            StarterPart("Xbox power cord", .cable, 999),
        ]
        }
    }
}

extension Library {
    /// Adds the sets' parts to the inventory at zero stock with their suggested price. A part
    /// whose name is already in the inventory is left as it is. Returns how many were added.
    @discardableResult
    public func addStarterParts(_ sets: [StarterSet] = StarterSet.allCases, now: Date = .now) throws -> Int {
        var known = try Set(parts().map { $0.name.lowercased() })
        var added = 0
        for set in sets {
            for starter in set.parts where known.insert(starter.name.lowercased()).inserted {
                try save(Part(name: starter.name, priceCents: starter.priceCents, kind: starter.kind,
                              condition: starter.condition, now: now),
                         fits: [set.fit] + starter.alsoFits.map(\.fit), now: now)
                added += 1
            }
        }
        return added
    }

    /// How many of the sets' parts are not in the inventory yet.
    public func missingStarterParts(_ sets: [StarterSet] = StarterSet.allCases) throws -> Int {
        let known = try Set(parts().map { $0.name.lowercased() })
        return Set(sets.flatMap(\.parts).map { $0.name.lowercased() }).subtracting(known).count
    }
}
