// Renders the app icon set (icons/svg/NN-name.svg, 24×24 monoline) into
// vector PDFs the app loads as template images:
//     Type.Oh/Icons/icon-<name>.pdf        (1.5 px stroke)
//     Type.Oh/Icons/icon-<name>-bold.pdf   (2 px stroke — active / hover)
// PDFs load the same way on macOS 13 and macOS 26 (Xcode bundles the folder
// automatically; build-app.sh copies it for the SwiftPM build).
//
// Run after changing anything in icons/svg (needs macOS 14+ for CGPath
// boolean operations):
//     swift tools/build-icons.swift
//
// Most icons are drawn by macOS's own SVG renderer (NSImage). Icons with a
// <mask> cut-out (a filled circle with stroked marks punched out) are built
// here as exact vector geometry instead, because NSImage rasterizes masks.
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let sourceDir = root.appendingPathComponent("icons/svg")
let outputDir = root.appendingPathComponent("Type.Oh/Icons")
let gridSize: CGFloat = 24
let regularStrokeWidth = "1.5"
let boldStrokeWidth = "2"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

// MARK: - SVG path data (M L H V C Q Z, absolute and relative)

func parsePathData(_ d: String) -> CGMutablePath {
    let path = CGMutablePath()
    var tokens: [String] = []
    let scanner = Scanner(string: d)
    scanner.charactersToBeSkipped = CharacterSet(charactersIn: " ,\n\t")
    while !scanner.isAtEnd {
        if let command = scanner.scanCharacter(), command.isLetter {
            tokens.append(String(command))
        } else {
            scanner.currentIndex = scanner.string.index(before: scanner.currentIndex)
            guard let number = scanner.scanDouble() else { fail("bad path data: \(d)") }
            tokens.append(String(number))
        }
    }
    var index = 0
    var current = CGPoint.zero
    var command = ""
    func number() -> CGFloat {
        guard index < tokens.count, let value = Double(tokens[index]) else { fail("bad path data: \(d)") }
        index += 1
        return CGFloat(value)
    }
    func point(relative: Bool) -> CGPoint {
        let x = number(), y = number()
        return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
    }
    while index < tokens.count {
        if Double(tokens[index]) == nil {
            command = tokens[index]
            index += 1
        }
        let relative = command == command.lowercased()
        switch command.uppercased() {
        case "M":
            current = point(relative: relative)
            path.move(to: current)
            command = relative ? "l" : "L" // further pairs are line-tos
        case "L":
            current = point(relative: relative)
            path.addLine(to: current)
        case "H":
            let x = number()
            current = CGPoint(x: relative ? current.x + x : x, y: current.y)
            path.addLine(to: current)
        case "V":
            let y = number()
            current = CGPoint(x: current.x, y: relative ? current.y + y : y)
            path.addLine(to: current)
        case "C":
            let c1 = point(relative: relative), c2 = point(relative: relative), end = point(relative: relative)
            path.addCurve(to: end, control1: c1, control2: c2)
            current = end
        case "Q":
            let c = point(relative: relative), end = point(relative: relative)
            path.addQuadCurve(to: end, control: c)
            current = end
        case "Z":
            path.closeSubpath()
            current = path.currentPoint
        default:
            fail("unsupported path command '\(command)' in mask geometry")
        }
    }
    return path
}

func attribute(_ element: XMLElement, _ name: String) -> String? {
    element.attribute(forName: name)?.stringValue
}

func number(_ element: XMLElement, _ name: String) -> CGFloat {
    guard let value = attribute(element, name).flatMap(Double.init) else {
        fail("<\(element.name ?? "?")> is missing a numeric \(name)")
    }
    return CGFloat(value)
}

// MARK: - Masked icons → exact vector geometry

/// Supports the set's cut-out pattern: `<circle … mask="url(#id)"/>` whose
/// mask is a full white rect plus black strokes (paths) and black dots
/// (circles). Anything else fails loudly rather than shipping a raster.
func maskedCutoutPath(_ svg: String, strokeWidth: CGFloat) -> CGPath {
    guard let document = try? XMLDocument(xmlString: svg),
          let svgElement = document.rootElement() else { fail("can't parse SVG") }
    let all = (try? svgElement.nodes(forXPath: ".//*"))?.compactMap { $0 as? XMLElement } ?? []
    guard let masked = all.first(where: { attribute($0, "mask") != nil }), masked.name == "circle" else {
        fail("masked element must be a <circle>")
    }
    let maskID = attribute(masked, "mask")!
        .replacingOccurrences(of: "url(#", with: "").replacingOccurrences(of: ")", with: "")
    guard let mask = all.first(where: { $0.name == "mask" && attribute($0, "id") == maskID }) else {
        fail("mask \(maskID) not found")
    }

    var shape: CGPath = CGPath(ellipseIn: CGRect(
        x: number(masked, "cx") - number(masked, "r"), y: number(masked, "cy") - number(masked, "r"),
        width: 2 * number(masked, "r"), height: 2 * number(masked, "r")), transform: nil)

    let maskChildren = (try? mask.nodes(forXPath: ".//*"))?.compactMap { $0 as? XMLElement } ?? []
    for element in maskChildren {
        switch element.name {
        case "rect":
            guard attribute(element, "fill") == "white" else { fail("mask rect must be white") }
        case "g":
            continue
        case "path":
            let outline = parsePathData(attribute(element, "d") ?? "")
                .copy(strokingWithWidth: strokeWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)
            shape = shape.subtracting(outline)
        case "circle":
            let r = number(element, "r")
            let dot = CGPath(ellipseIn: CGRect(x: number(element, "cx") - r, y: number(element, "cy") - r,
                                               width: 2 * r, height: 2 * r), transform: nil)
            shape = shape.subtracting(dot)
        default:
            fail("unsupported <\(element.name ?? "?")> inside a mask")
        }
    }
    return shape
}

// MARK: - PDF output

func writePDF(to url: URL, draw: (CGContext) -> Void) {
    var box = CGRect(x: 0, y: 0, width: gridSize, height: gridSize)
    guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { fail("can't write \(url.path)") }
    context.beginPDFPage(nil)
    draw(context)
    context.endPDFPage()
    context.closePDF()
}

func render(svg: String, to url: URL, strokeWidth: CGFloat) {
    if svg.contains("<mask") {
        let shape = maskedCutoutPath(svg, strokeWidth: strokeWidth)
        writePDF(to: url) { context in
            // SVG is y-down, PDF is y-up.
            context.translateBy(x: 0, y: gridSize)
            context.scaleBy(x: 1, y: -1)
            context.addPath(shape)
            context.setFillColor(.black)
            context.fillPath()
        }
    } else {
        guard let image = NSImage(data: Data(svg.utf8)),
              image.representations.contains(where: { String(describing: type(of: $0)).contains("SVG") }) else {
            fail("macOS couldn't load \(url.lastPathComponent) as SVG")
        }
        writePDF(to: url) { context in
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            image.draw(in: CGRect(x: 0, y: 0, width: gridSize, height: gridSize))
            NSGraphicsContext.restoreGraphicsState()
        }
    }
    // Template icons must stay vector: no embedded bitmaps.
    guard let pdf = try? Data(contentsOf: url), !String(decoding: pdf, as: UTF8.self).contains("/Subtype /Image") else {
        fail("\(url.lastPathComponent) contains a raster image")
    }
}

// MARK: - Main

let fileManager = FileManager.default
let sources = (try? fileManager.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: nil))?
    .filter { $0.pathExtension == "svg" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
guard !sources.isEmpty else { fail("no SVGs in \(sourceDir.path)") }

try? fileManager.removeItem(at: outputDir)
try fileManager.createDirectory(at: outputDir, withIntermediateDirectories: true)

for source in sources {
    // "04-translate.svg" → "translate"
    let name = source.deletingPathExtension().lastPathComponent
        .replacingOccurrences(of: #"^\d+-"#, with: "", options: .regularExpression)
    guard let svg = try? String(contentsOf: source, encoding: .utf8) else { fail("can't read \(source.path)") }
    guard svg.contains("stroke-width=\"\(regularStrokeWidth)\"") else {
        fail("\(source.lastPathComponent): expected stroke-width=\"\(regularStrokeWidth)\" on the root")
    }
    let bold = svg.replacingOccurrences(of: "stroke-width=\"\(regularStrokeWidth)\"", with: "stroke-width=\"\(boldStrokeWidth)\"")
    render(svg: svg, to: outputDir.appendingPathComponent("icon-\(name).pdf"), strokeWidth: 1.5)
    render(svg: bold, to: outputDir.appendingPathComponent("icon-\(name)-bold.pdf"), strokeWidth: 2)
}
print("wrote \(sources.count * 2) PDFs to \(outputDir.path)")
