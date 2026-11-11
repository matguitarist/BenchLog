import AppKit
import BoardViewKit
import SwiftUI

/// The board, drawn by hand: thousands of pins pan and zoom smoothly in one view.
struct BoardCanvas: NSViewRepresentable {
    let viewer: BoardViewer

    func makeNSView(context: Context) -> BoardCanvasView {
        let view = BoardCanvasView()
        view.board = viewer.board
        view.onSelect = { [weak viewer] selection in viewer?.select(selection, from: .board) }
        view.onFlip = { [weak viewer] in viewer?.flip() }
        viewer.canvas = view
        return view
    }

    func updateNSView(_ view: BoardCanvasView, context: Context) {
        view.side = viewer.side
        view.selection = viewer.selection
        view.accent = NSColor(Palette.accent)
        view.accentText = NSColor(Palette.accentText)
        view.onAccent = NSColor(Palette.onAccent)
    }
}

final class BoardCanvasView: NSView {
    var board: Board?
    var side: BoardSide = .top {
        didSet {
            guard side != oldValue else { return }
            needsDisplay = true
            updateAccessibility()
        }
    }
    var selection: BoardSelection? {
        didSet {
            guard selection != oldValue else { return }
            highlighted = Set(board?.highlightedPins(for: selection) ?? [])
            needsDisplay = true
        }
    }
    var accent: NSColor = .controlAccentColor { didSet { if accent != oldValue { needsDisplay = true } } }
    var accentText: NSColor = .controlAccentColor { didSet { if accentText != oldValue { needsDisplay = true } } }
    var onAccent: NSColor = .white { didSet { if onAccent != oldValue { needsDisplay = true } } }
    var onSelect: ((BoardSelection?) -> Void)?
    var onFlip: (() -> Void)?

    /// Points per board unit, and the board point at the middle of the view.
    private var scale: CGFloat = 0
    private var center = BoardPoint(x: 0, y: 0)
    private var highlighted: Set<Int> = []
    private var dragStart: NSPoint?
    private var dragged = false
    /// What the last zoom fitted, and its margin: kept in view when the view changes size
    /// (the schematic opening or closing), until the person pans or zooms.
    private var fitted: (rect: BoardRect, margin: Double)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        updateAccessibility()
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { false }
    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private func updateAccessibility() {
        setAccessibilityLabel(side == .top ? String(localized: "Board, top side") : String(localized: "Board, bottom side"))
    }

    // MARK: Coordinates

    private var mirror: Double { side == .bottom ? -1 : 1 }

    private func toView(_ p: BoardPoint) -> CGPoint {
        CGPoint(x: bounds.midX + (p.x - center.x) * mirror * scale, y: bounds.midY + (p.y - center.y) * scale)
    }

    private func toBoard(_ p: CGPoint) -> BoardPoint {
        BoardPoint(x: center.x + (p.x - bounds.midX) / scale * mirror, y: center.y + (p.y - bounds.midY) / scale)
    }

    private func toView(_ r: BoardRect) -> CGRect {
        let a = toView(BoardPoint(x: r.minX, y: r.minY)), b = toView(BoardPoint(x: r.maxX, y: r.maxY))
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    /// The part of the board in view, in board units.
    private var visibleBoardRect: BoardRect {
        let a = toBoard(CGPoint(x: bounds.minX, y: bounds.minY)), b = toBoard(CGPoint(x: bounds.maxX, y: bounds.maxY))
        return BoardRect(minX: min(a.x, b.x), minY: min(a.y, b.y), maxX: max(a.x, b.x), maxY: max(a.y, b.y))
    }

    // MARK: Zoom

    private var fitScale: CGFloat {
        guard let board, bounds.width > 0, bounds.height > 0 else { return 1 }
        return min(bounds.width / max(board.bounds.width * 1.08, 1), bounds.height / max(board.bounds.height * 1.08, 1))
    }

    private func clamp(_ s: CGFloat) -> CGFloat { min(max(s, fitScale * 0.5), 40) }

    /// 1 zooms in, -1 out, 0 shows the whole board.
    func zoom(_ direction: Int) {
        switch direction {
        case 0:
            guard let board else { return }
            fit(board.bounds, margin: 1.08)
        default:
            zoom(by: direction > 0 ? 1.5 : 1 / 1.5, at: CGPoint(x: bounds.midX, y: bounds.midY))
        }
    }

    /// Fits a rectangle in view, at least `minimumSize` board units wide, so a small part keeps
    /// its neighbors around it.
    func zoom(to rect: BoardRect, minimumSize: Double) {
        let c = rect.center, w = max(rect.width, minimumSize) / 2, h = max(rect.height, minimumSize) / 2
        fit(BoardRect(minX: c.x - w, minY: c.y - h, maxX: c.x + w, maxY: c.y + h), margin: 1.3)
    }

    /// The part of the board in view, to come back to with `show(_:)`.
    var shownRect: BoardRect { visibleBoardRect }

    /// Shows what `shownRect` gave, as it was.
    func show(_ rect: BoardRect) { fit(rect, margin: 1) }

    private func fit(_ rect: BoardRect, margin: Double) {
        fitted = (rect, margin)
        guard bounds.width > 0, bounds.height > 0 else { return }
        scale = clamp(min(bounds.width / max(rect.width * margin, 1), bounds.height / max(rect.height * margin, 1)))
        center = rect.center
        needsDisplay = true
    }

    private func zoom(by factor: CGFloat, at point: CGPoint) {
        fitted = nil
        let before = toBoard(point)
        scale = clamp(scale * factor)
        let after = toBoard(point)
        center.x += before.x - after.x
        center.y += before.y - after.y
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard newSize.width > 0, newSize.height > 0 else { return }
        if let fitted {
            fit(fitted.rect, margin: fitted.margin)
        } else if scale == 0 {
            zoom(0)
        }
    }

    // MARK: Drawing

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        NSColor.underPageBackgroundColor.setFill()
        dirtyRect.fill()
        guard let board, scale > 0 else { return }
        let visible = visibleBoardRect

        // The board's outline.
        let outline = CGMutablePath()
        let points = board.outline.count >= 3 ? board.outline : [
            BoardPoint(x: board.bounds.minX, y: board.bounds.minY), BoardPoint(x: board.bounds.maxX, y: board.bounds.minY),
            BoardPoint(x: board.bounds.maxX, y: board.bounds.maxY), BoardPoint(x: board.bounds.minX, y: board.bounds.maxY),
        ]
        outline.addLines(between: points.map(toView))
        outline.closeSubpath()
        context.addPath(outline)
        context.setFillColor(NSColor.textBackgroundColor.cgColor)
        context.fillPath()
        context.addPath(outline)
        context.setStrokeColor(NSColor.separatorColor.cgColor)
        context.setLineWidth(1)
        context.strokePath()

        // Parts on this side, their pins, and the highlighted pins on the other side.
        let parts = CGMutablePath(), pins = CGMutablePath(), ground = CGMutablePath()
        let lit = CGMutablePath(), litBehind = CGMutablePath()
        var labels: [(String, CGRect, Bool)] = []
        var netLabels: [(String, CGRect, Bool)] = []
        let selectedPart: Int? = switch selection {
        case .part(let index): index
        case .pin(let index): board.pins[index].part
        default: nil
        }
        for part in board.parts where part.bounds.intersects(visible) {
            let onThisSide = part.isThroughHole || part.side == side
            let radius = max(part.pinRadius * scale, 1)
            if onThisSide {
                let rect = toView(part.bounds)
                parts.addRect(rect)
                if rect.width >= 28, rect.height >= 12 { labels.append((part.name, rect, part.id == selectedPart)) }
            }
            for index in part.pins {
                let pin = board.pins[index]
                let isLit = highlighted.contains(index)
                guard onThisSide || isLit else { continue }
                let p = toView(pin.position)
                let circle = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
                if !onThisSide {
                    litBehind.addEllipse(in: circle)
                } else if isLit {
                    lit.addEllipse(in: circle)
                } else if Board.isGround(pin.net) {
                    ground.addEllipse(in: circle)
                } else {
                    pins.addEllipse(in: circle)
                }
                if onThisSide, radius >= 14, !pin.net.isEmpty { netLabels.append((pin.net, circle, isLit)) }
            }
        }
        context.addPath(parts)
        context.setStrokeColor(NSColor.tertiaryLabelColor.cgColor)
        context.setLineWidth(1)
        context.strokePath()
        for (path, color) in [(ground, NSColor.tertiaryLabelColor), (pins, NSColor.secondaryLabelColor), (lit, accent)] {
            context.addPath(path)
            context.setFillColor(color.cgColor)
            context.fillPath()
        }
        context.addPath(litBehind)
        context.setStrokeColor(accent.withAlphaComponent(0.6).cgColor)
        context.setLineWidth(1.5)
        context.strokePath()

        // The selected part's outline, and a ring around the selected pin.
        if let selectedPart, board.parts[selectedPart].isThroughHole || board.parts[selectedPart].side == side {
            context.setStrokeColor(accent.cgColor)
            context.setLineWidth(2)
            context.stroke(toView(board.parts[selectedPart].bounds).insetBy(dx: -2, dy: -2))
        }
        if case .pin(let index) = selection, board.shows(pin: index, on: side) {
            let part = board.parts[board.pins[index].part]
            let p = toView(board.pins[index].position)
            let r = max(part.pinRadius * scale, 1) + 4
            context.setStrokeColor(NSColor.labelColor.cgColor)
            context.setLineWidth(2)
            context.strokeEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        }

        // Names, once a part is big enough to hold one; net names inside large pins.
        for (name, rect, isSelected) in labels {
            let size = min(max(min(rect.width / CGFloat(max(name.count, 2)) * 1.4, rect.height * 0.5), 9), 15)
            let text = NSAttributedString(string: name, attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: isSelected ? .semibold : .regular),
                .foregroundColor: isSelected ? accentText : NSColor.secondaryLabelColor,
            ])
            let textSize = text.size()
            guard textSize.width <= rect.width + 8 else { continue }
            text.draw(at: CGPoint(x: rect.midX - textSize.width / 2, y: rect.maxY + 2))
        }
        for (net, circle, isLit) in netLabels.prefix(400) {
            let text = NSAttributedString(string: net, attributes: [
                .font: NSFont.systemFont(ofSize: min(max(circle.width / 5, 8), 12)),
                .foregroundColor: isLit ? onAccent : NSColor.labelColor,
            ])
            let size = text.size()
            guard size.width <= circle.width * 0.92 else { continue }
            text.draw(at: CGPoint(x: circle.midX - size.width / 2, y: circle.midY - size.height / 2))
        }
    }

    // MARK: Events

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        dragStart = convert(event.locationInWindow, from: nil)
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragStart != nil else { return }
        if !dragged { NSCursor.closedHand.push() }
        dragged = true
        pan(dx: event.deltaX, dy: -event.deltaY)
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil }
        if dragged {
            NSCursor.pop()
            return
        }
        guard let board else { return }
        let point = toBoard(convert(event.locationInWindow, from: nil))
        let hit = board.hitTest(point, side: side, tolerance: 3 / scale)
        onSelect?(hit)
        // A double-click zooms to the part.
        if event.clickCount == 2, let hit {
            let part: Int = switch hit {
            case .part(let index): index
            case .pin(let index): board.pins[index].part
            case .net: -1
            }
            if part >= 0 { zoom(to: board.parts[part].bounds, minimumSize: 200) }
        }
    }

    /// Two fingers pan, a pinch zooms; a mouse wheel or Command with two fingers zooms.
    override func scrollWheel(with event: NSEvent) {
        if event.hasPreciseScrollingDeltas, !event.modifierFlags.contains(.command) {
            pan(dx: event.scrollingDeltaX, dy: -event.scrollingDeltaY)
        } else {
            let step = event.hasPreciseScrollingDeltas ? 0.01 : 0.1
            zoom(by: exp(event.scrollingDeltaY * step), at: convert(event.locationInWindow, from: nil))
        }
    }

    override func magnify(with event: NSEvent) {
        zoom(by: 1 + event.magnification, at: convert(event.locationInWindow, from: nil))
    }

    /// Moves the board by a distance in points (y up).
    private func pan(dx: CGFloat, dy: CGFloat) {
        guard scale > 0 else { return }
        fitted = nil
        center.x -= dx / scale * mirror
        center.y -= dy / scale
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch event.charactersIgnoringModifiers {
        case " ": onFlip?()
        case "\u{1B}": onSelect?(nil)
        default: super.keyDown(with: event)
        }
    }
}
