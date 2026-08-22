import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Composites the raw simulator screenshots in docs/images/ into presentation
// renders: a hero, a GitHub social card, and per-feature cards.
//
// Committed rather than done once in a design tool, for the same reason the
// screenshot script is: the images in the README should be reproducible from the
// repo by anyone, including future me after a UI change.
//
//   swift tools/render-mockups.swift            (run from the repo root)

// MARK: - Palette
// Pulled from the app's own accent rather than invented: indigo is what the
// interface uses, so the renders should not introduce a second brand.
let indigo   = CGColor(red: 0.36, green: 0.33, blue: 0.86, alpha: 1)
let indigoHi = CGColor(red: 0.52, green: 0.49, blue: 0.98, alpha: 1)
let ink      = CGColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1)
let inkSoft  = CGColor(red: 0.09, green: 0.09, blue: 0.13, alpha: 1)
let paper    = CGColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1)
let white    = CGColor(gray: 1, alpha: 1)

let root = FileManager.default.currentDirectoryPath
let imagesDir = "\(root)/docs/images"

func loadImage(_ name: String) -> CGImage {
    let url = URL(fileURLWithPath: "\(imagesDir)/\(name).png")
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        fatalError("missing \(url.path) -- run ./tools/screenshots.sh first")
    }
    return img
}

func context(_ w: Int, _ h: Int) -> CGContext {
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("cannot create context")
    }
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    return ctx
}

func save(_ ctx: CGContext, as name: String) {
    guard let img = ctx.makeImage() else { fatalError("no image") }
    let url = URL(fileURLWithPath: "\(imagesDir)/\(name).png")
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("cannot write \(name)") }
    CGImageDestinationAddImage(dest, img, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("cannot finalise \(name)") }
    print("  docs/images/\(name).png  \(img.width)x\(img.height)")
}

// MARK: - Backgrounds

func fillVerticalGradient(_ ctx: CGContext, rect: CGRect, from: CGColor, to: CGColor) {
    let space = CGColorSpaceCreateDeviceRGB()
    guard let g = CGGradient(colorsSpace: space, colors: [from, to] as CFArray, locations: [0, 1]) else { return }
    ctx.saveGState()
    ctx.clip(to: rect)
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])
    ctx.restoreGState()
}

/// A soft off-centre glow. Keeps a flat dark background from looking like a
/// rendering bug, and gives the phones something to sit in front of.
func drawGlow(_ ctx: CGContext, centre: CGPoint, radius: CGFloat, colour: CGColor, strength: CGFloat) {
    let space = CGColorSpaceCreateDeviceRGB()
    let c = colour.components ?? [0, 0, 0, 1]
    let mid = CGColor(red: c[0], green: c[1], blue: c[2], alpha: strength * 0.45)
    let edge = CGColor(red: c[0], green: c[1], blue: c[2], alpha: 0)
    guard let g = CGGradient(colorsSpace: space,
                             colors: [CGColor(red: c[0], green: c[1], blue: c[2], alpha: strength), mid, edge] as CFArray,
                             locations: [0, 0.45, 1]) else { return }
    ctx.drawRadialGradient(g, startCenter: centre, startRadius: 0,
                           endCenter: centre, endRadius: radius, options: [])
}

// MARK: - Device frame

/// Draw a screenshot inside an iPhone-shaped body.
/// `rotation` is in degrees, applied about the phone's centre.
func drawPhone(_ ctx: CGContext, image: CGImage, centre: CGPoint, screenHeight: CGFloat,
               rotation: CGFloat = 0, shadow: Bool = true) {
    let aspect = CGFloat(image.width) / CGFloat(image.height)
    let screenW = screenHeight * aspect
    let bezel = screenHeight * 0.0125          // proportional, so any size works
    let bodyW = screenW + bezel * 2
    let bodyH = screenHeight + bezel * 2
    let corner = bodyH * 0.0655                // iPhone 17 Pro corner, to scale

    ctx.saveGState()
    ctx.translateBy(x: centre.x, y: centre.y)
    ctx.rotate(by: rotation * .pi / 180)
    ctx.translateBy(x: -bodyW / 2, y: -bodyH / 2)

    let body = CGRect(x: 0, y: 0, width: bodyW, height: bodyH)

    if shadow {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -screenHeight * 0.035),
                      blur: screenHeight * 0.06,
                      color: CGColor(gray: 0, alpha: 0.55))
        ctx.addPath(CGPath(roundedRect: body, cornerWidth: corner, cornerHeight: corner, transform: nil))
        ctx.setFillColor(CGColor(gray: 0.02, alpha: 1))
        ctx.fillPath()
        ctx.restoreGState()
    }

    // Body, then a hairline rim: without it the black body dissolves into a dark
    // background and the phone reads as a floating rectangle of UI.
    ctx.addPath(CGPath(roundedRect: body, cornerWidth: corner, cornerHeight: corner, transform: nil))
    ctx.setFillColor(CGColor(gray: 0.06, alpha: 1))
    ctx.fillPath()

    ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 0.5, dy: 0.5),
                       cornerWidth: corner, cornerHeight: corner, transform: nil))
    ctx.setStrokeColor(CGColor(gray: 0.42, alpha: 0.55))
    ctx.setLineWidth(max(1, screenHeight * 0.0016))
    ctx.strokePath()

    let screen = CGRect(x: bezel, y: bezel, width: screenW, height: screenHeight)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: screen, cornerWidth: corner - bezel * 0.55,
                       cornerHeight: corner - bezel * 0.55, transform: nil))
    ctx.clip()
    ctx.draw(image, in: screen)
    ctx.restoreGState()

    ctx.restoreGState()
}

// MARK: - Type

enum Align { case left, centre }

func draw(_ text: String, at point: CGPoint, size: CGFloat, weight: NSFont.Weight,
          colour: CGColor, in ctx: CGContext, align: Align = .left,
          tracking: CGFloat = 0, maxWidth: CGFloat? = nil) -> CGFloat {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    var attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(cgColor: colour) ?? .white,
    ]
    if tracking != 0 { attrs[.kern] = tracking }

    let para = NSMutableParagraphStyle()
    para.alignment = align == .centre ? .center : .left
    para.lineSpacing = size > 50 ? size * 0.04 : size * 0.16   // display type sets tighter
    attrs[.paragraphStyle] = para

    let attributed = NSAttributedString(string: text, attributes: attrs)
    let width = maxWidth ?? CGFloat(ctx.width)
    let framesetter = CTFramesetterCreateWithAttributedString(attributed)
    let constraints = CGSize(width: width, height: .greatestFiniteMagnitude)
    let bounds = CTFramesetterSuggestFrameSizeWithConstraints(
        framesetter, CFRange(location: 0, length: 0), nil, constraints, nil)

    let originX = align == .centre ? point.x - width / 2 : point.x
    let box = CGRect(x: originX, y: point.y - bounds.height, width: width, height: bounds.height)
    let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0),
                                         CGPath(rect: box, transform: nil), nil)
    ctx.saveGState()
    ctx.textMatrix = .identity
    CTFrameDraw(frame, ctx)
    ctx.restoreGState()
    return bounds.height
}

// MARK: - Renders

func renderHero() {
    let W = 2400, H = 1350
    let ctx = context(W, H)
    let rect = CGRect(x: 0, y: 0, width: W, height: H)
    fillVerticalGradient(ctx, rect: rect, from: inkSoft, to: ink)
    drawGlow(ctx, centre: CGPoint(x: CGFloat(W) * 0.5, y: CGFloat(H) * 0.16),
             radius: CGFloat(W) * 0.62, colour: indigo, strength: 0.30)

    let steps = loadImage("steps")
    let lesson = loadImage("lesson")
    let formulas = loadImage("formulas")

    // Centre phone forward, flankers behind and rotated: depth without a 3D
    // library, and the middle screen stays fully legible.
    let h: CGFloat = 880
    drawPhone(ctx, image: formulas, centre: CGPoint(x: CGFloat(W) * 0.245, y: CGFloat(H) * 0.60),
              screenHeight: h * 0.86, rotation: -7)
    drawPhone(ctx, image: lesson, centre: CGPoint(x: CGFloat(W) * 0.755, y: CGFloat(H) * 0.60),
              screenHeight: h * 0.86, rotation: 7)
    drawPhone(ctx, image: steps, centre: CGPoint(x: CGFloat(W) * 0.5, y: CGFloat(H) * 0.615),
              screenHeight: h)

    _ = draw("solvr.", at: CGPoint(x: CGFloat(W) / 2, y: 226), size: 112,
             weight: .bold, colour: white, in: ctx, align: .centre, tracking: -3)
    _ = draw("Photograph a maths problem. Get the working, and the lesson behind it.",
             at: CGPoint(x: CGFloat(W) / 2, y: 104), size: 42,
             weight: .regular, colour: CGColor(gray: 0.70, alpha: 1), in: ctx,
             align: .centre, maxWidth: 1700)
    save(ctx, as: "hero")
}

func renderSocialCard() {
    // GitHub's Open Graph card is 1280x640 and gets cropped in some clients, so
    // nothing important goes near the edges.
    let W = 1280, H = 640
    let ctx = context(W, H)
    fillVerticalGradient(ctx, rect: CGRect(x: 0, y: 0, width: W, height: H), from: inkSoft, to: ink)
    drawGlow(ctx, centre: CGPoint(x: CGFloat(W) * 0.78, y: CGFloat(H) * 0.5),
             radius: 620, colour: indigoHi, strength: 0.26)

    drawPhone(ctx, image: loadImage("steps"), centre: CGPoint(x: CGFloat(W) * 0.80, y: CGFloat(H) * 0.46),
              screenHeight: 560, rotation: -6)

    _ = draw("solvr.", at: CGPoint(x: 96, y: 470), size: 96, weight: .bold, colour: white, in: ctx, tracking: -2)
    _ = draw("Step-by-step maths solutions and lesson plans, from a photo. Built in Swift and SwiftUI on the Claude API.",
             at: CGPoint(x: 96, y: 340), size: 34, weight: .regular,
             colour: CGColor(gray: 0.74, alpha: 1), in: ctx, maxWidth: 600)
    _ = draw("iOS · SWIFT · SWIFTUI · UNRELEASED", at: CGPoint(x: 96, y: 120), size: 22,
             weight: .semibold, colour: indigoHi, in: ctx, tracking: 3)
    save(ctx, as: "social-card")
}

func renderFeature(_ name: String, screenshot: String, headline: String, body: String, dark: Bool) {
    let W = 2000, H = 1150
    let ctx = context(W, H)
    let rect = CGRect(x: 0, y: 0, width: W, height: H)
    if dark {
        fillVerticalGradient(ctx, rect: rect, from: inkSoft, to: ink)
        drawGlow(ctx, centre: CGPoint(x: CGFloat(W) * 0.72, y: CGFloat(H) * 0.5),
                 radius: 900, colour: indigo, strength: 0.22)
    } else {
        fillVerticalGradient(ctx, rect: rect, from: white, to: paper)
    }

    drawPhone(ctx, image: loadImage(screenshot),
              centre: CGPoint(x: CGFloat(W) * 0.735, y: CGFloat(H) * 0.5),
              screenHeight: 880, rotation: 0, shadow: true)

    let textColour = dark ? white : ink
    let bodyColour = dark ? CGColor(gray: 0.72, alpha: 1) : CGColor(gray: 0.36, alpha: 1)
    let x: CGFloat = 130
    _ = draw(headline, at: CGPoint(x: x, y: CGFloat(H) * 0.70), size: 76, weight: .bold,
             colour: textColour, in: ctx, maxWidth: 780)
    _ = draw(body, at: CGPoint(x: x, y: CGFloat(H) * 0.42), size: 33, weight: .regular,
             colour: bodyColour, in: ctx, maxWidth: 760)
    save(ctx, as: name)
}

print("==> rendering")
renderHero()
renderSocialCard()
renderFeature("feature-steps", screenshot: "steps",
              headline: "Every step, with the reason for it",
              body: "Not just the answer. Each line says which rule is being applied and why it is the right one, typeset properly rather than squeezed into plain text.",
              dark: true)
renderFeature("feature-lesson", screenshot: "lesson",
              headline: "The lesson behind the problem",
              body: "The concept the question was testing, written as a tutor would explain it. This is the part that came out of years of rebuilding the same lesson plans by hand.",
              dark: false)
print("==> done")
