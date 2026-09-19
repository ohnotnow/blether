import AppKit

/// The menubar icon: a robot head drawn in code as a template image, so it follows the bar's light
/// or dark look like a system symbol would. Ours because no SF Symbol is both distinctive as
/// blether's and unmistakable between on and off (blether-UkLWZ.11): speakers look like the Sound
/// menu, waveforms hide their own slash. On has round eyes and an open mouth; off has flat dashes
/// for both, a robot powered down. Designed 2026-09-19.
enum MenuBarIcon {
    /// Points. Menubar template images are 18 high on macOS; the head sits inside with a margin.
    static let size = NSSize(width: 18, height: 18)

    static func image(enabled: Bool) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            draw(enabled: enabled)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = enabled ? "blether, speaking" : "blether, not speaking"
        return image
    }

    /// Everything is black on clear; the template mechanism recolours it.
    private static func draw(enabled: Bool) {
        NSColor.black.set()
        let stroke: CGFloat = 1.5

        // Head: a rounded box, outlined.
        let head = NSBezierPath(roundedRect: NSRect(x: 3, y: 2, width: 12, height: 10.5), xRadius: 2.5, yRadius: 2.5)
        head.lineWidth = stroke
        head.stroke()

        // Ears: a small block either side.
        NSBezierPath(roundedRect: NSRect(x: 0.75, y: 5.5, width: 1.75, height: 3.5), xRadius: 0.6, yRadius: 0.6).fill()
        NSBezierPath(roundedRect: NSRect(x: 15.5, y: 5.5, width: 1.75, height: 3.5), xRadius: 0.6, yRadius: 0.6).fill()

        // Antenna: a stalk from the crown and a bobble.
        let stalk = NSBezierPath()
        stalk.move(to: NSPoint(x: 9, y: 12.5))
        stalk.line(to: NSPoint(x: 9, y: 14.75))
        stalk.lineWidth = stroke
        stalk.stroke()
        NSBezierPath(ovalIn: NSRect(x: 7.6, y: 14.5, width: 2.8, height: 2.8)).fill()

        // Eyes: round and awake, or flat dashes when powered down.
        for x: CGFloat in [6.5, 11.5] {
            if enabled {
                NSBezierPath(ovalIn: NSRect(x: x - 1.4, y: 6.6, width: 2.8, height: 2.8)).fill()
            } else {
                NSBezierPath(roundedRect: NSRect(x: x - 1.6, y: 7.4, width: 3.2, height: 1.3), xRadius: 0.65, yRadius: 0.65).fill()
            }
        }

        // Mouth: open and round while speaking, a flat bar when silenced (the user's ask, so the
        // state reads at a glance without looking at the eyes).
        if enabled {
            NSBezierPath(ovalIn: NSRect(x: 6.9, y: 3.4, width: 4.2, height: 2.6)).fill()
        } else {
            NSBezierPath(roundedRect: NSRect(x: 6.75, y: 3.9, width: 4.5, height: 1.3), xRadius: 0.65, yRadius: 0.65).fill()
        }
    }
}
