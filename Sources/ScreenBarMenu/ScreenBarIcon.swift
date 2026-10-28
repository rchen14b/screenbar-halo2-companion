import AppKit

/// The menu bar icon: a light bar, with a soft beam below it while the lamp is on. A template
/// image, so the menu bar tints it for light and dark appearances.
enum ScreenBarIcon {
    static func image(on: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 16), flipped: true) { _ in
            NSColor.black.set()
            // The bar, as it sits on top of the monitor.
            let bar = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 2.5, width: 17, height: 3.4), xRadius: 1.7, yRadius: 1.7)
            if on {
                bar.fill()
            } else {
                bar.lineWidth = 1.3
                bar.stroke()
            }
            // The clip that holds it on the monitor's edge.
            NSBezierPath(roundedRect: NSRect(x: 8, y: 5.9, width: 4, height: 2.6), xRadius: 0.8, yRadius: 0.8).fill()
            if on {
                // Light falling onto the desk: a widening beam that fades out.
                let beam = NSBezierPath()
                beam.move(to: NSPoint(x: 3.5, y: 6.6))
                beam.line(to: NSPoint(x: 16.5, y: 6.6))
                beam.line(to: NSPoint(x: 19.5, y: 15.5))
                beam.line(to: NSPoint(x: 0.5, y: 15.5))
                beam.close()
                NSGradient(starting: NSColor.black.withAlphaComponent(0.6), ending: NSColor.black.withAlphaComponent(0.05))?
                    .draw(in: beam, angle: 90)  // strongest under the bar, fading downward (checked)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = on ? "ScreenBar on" : "ScreenBar off"
        return image
    }
}
