import SwiftUI
import UIKit

/// A synthetic page of maths, drawn at runtime and shown where the camera feed
/// would be when demo mode is on.
///
/// Two reasons it is drawn rather than bundled as a photograph: a simulator has
/// no camera, so the scanner screen is otherwise a black rectangle that looks
/// like a bug in every screenshot; and a photograph of real homework would be
/// someone's work. This is nobody's work.
enum DemoPage {

    static let image: UIImage = render()

    private static func render() -> UIImage {
        let size = CGSize(width: 1200, height: 2600)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            let cg = context.cgContext

            // Paper, very slightly warm and unevenly lit, because a flat white
            // rectangle does not read as paper.
            UIColor(red: 0.976, green: 0.972, blue: 0.960, alpha: 1).setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            if let shade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: [UIColor(white: 0, alpha: 0.06).cgColor,
                                               UIColor(white: 0, alpha: 0).cgColor] as CFArray,
                                      locations: [0, 1]) {
                cg.drawRadialGradient(shade,
                                      startCenter: CGPoint(x: size.width * 0.85, y: size.height * 0.95),
                                      startRadius: 0,
                                      endCenter: CGPoint(x: size.width * 0.85, y: size.height * 0.95),
                                      endRadius: size.width * 0.9, options: [])
            }

            // Ruled lines, pale enough to sit behind the text.
            UIColor(red: 0.80, green: 0.84, blue: 0.90, alpha: 0.55).setStroke()
            cg.setLineWidth(2)
            var y: CGFloat = 620
            while y < size.height - 80 {
                cg.move(to: CGPoint(x: 140, y: y))
                cg.addLine(to: CGPoint(x: size.width - 140, y: y))
                y += 92
            }
            cg.strokePath()

            func draw(_ text: String, at point: CGPoint, size fontSize: CGFloat,
                      font name: String = "Times New Roman", colour: UIColor = UIColor(white: 0.13, alpha: 1)) {
                let font = UIFont(name: name, size: fontSize)
                    ?? UIFont.systemFont(ofSize: fontSize)
                NSAttributedString(string: text, attributes: [
                    .font: font, .foregroundColor: colour,
                ]).draw(at: point)
            }

            draw("Worksheet 4 — Definite Integrals", at: CGPoint(x: 150, y: 520), size: 46)
            draw("1.  Evaluate", at: CGPoint(x: 150, y: 700), size: 54)
            draw("∫", at: CGPoint(x: 400, y: 678), size: 100)
            draw("1", at: CGPoint(x: 438, y: 672), size: 32)
            draw("0", at: CGPoint(x: 438, y: 754), size: 32)
            draw("3x² dx", at: CGPoint(x: 486, y: 702), size: 54)
            draw("2.  Differentiate  x³ − 4x", at: CGPoint(x: 150, y: 900), size: 54)
            draw("3.  Find  lim (sin x)/x  as  x → 0", at: CGPoint(x: 150, y: 1090), size: 54)
        }
    }
}
