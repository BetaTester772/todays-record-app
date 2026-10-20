// 앱 아이콘을 그려 Resources/AppIcon.icns로 만든다. 앱 화면(index.html 미리보기 첫 앨범)과 같은 색을 쓴다.
//   swift scripts/make-icon.swift            # .icns 생성
//   swift scripts/make-icon.swift preview.png  # 1024px PNG만 저장(확인용)
import AppKit

let pink = NSColor(srgbRed: 0xEF / 255, green: 0xDA / 255, blue: 0xDD / 255, alpha: 1)
let green = NSColor(srgbRed: 0x2D / 255, green: 0x5C / 255, blue: 0x48 / 255, alpha: 1)
let cream = NSColor(srgbRed: 0xF6 / 255, green: 0xE6 / 255, blue: 0xE8 / 255, alpha: 1)
let accent = NSColor(srgbRed: 0xEE / 255, green: 0x5A / 255, blue: 0x36 / 255, alpha: 1)
let metal = NSColor(srgbRed: 0xFA / 255, green: 0xF5 / 255, blue: 0xF2 / 255, alpha: 1)

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let g = NSGraphicsContext.current!.cgContext
    g.scaleBy(x: size / 1024, y: size / 1024)

    // macOS 아이콘 격자: 1024 캔버스 안 824px 둥근 사각형, 그림자
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    g.saveGState()
    g.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: NSColor.black.withAlphaComponent(0.28).cgColor)
    g.addPath(CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil))
    g.setFillColor(pink.cgColor); g.fillPath()
    g.restoreGState()

    g.saveGState()
    g.addPath(CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)); g.clip()
    // 받침: 화면처럼 비스듬히 놓인 초록 판
    g.saveGState()
    g.translateBy(x: 560, y: 470); g.rotate(by: 0.28)
    g.addPath(CGPath(roundedRect: CGRect(x: -400, y: -900, width: 1500, height: 1220), cornerWidth: 70, cornerHeight: 70, transform: nil))
    g.setFillColor(green.cgColor); g.fillPath()
    g.restoreGState()

    // 레코드
    let c = CGPoint(x: 470, y: 470), R: CGFloat = 300
    g.saveGState()
    g.setShadow(offset: CGSize(width: 14, height: -20), blur: 30, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    g.setFillColor(cream.blended(withFraction: 0.12, of: .black)!.cgColor)
    g.fillEllipse(in: CGRect(x: c.x - R, y: c.y - R - 10, width: 2 * R, height: 2 * R))
    g.restoreGState()
    g.setFillColor(cream.cgColor)
    g.fillEllipse(in: CGRect(x: c.x - R, y: c.y - R, width: 2 * R, height: 2 * R))
    // 홈 무늬
    g.setLineWidth(3)
    for (i, f) in stride(from: 0.5, to: 0.97, by: 0.05).enumerated() {
        g.setStrokeColor((i % 3 == 0 ? NSColor.black.withAlphaComponent(0.09) : NSColor.white.withAlphaComponent(0.55)).cgColor)
        let r = R * CGFloat(f)
        g.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }
    // 바늘이 남긴 선
    g.setStrokeColor(accent.cgColor); g.setLineWidth(9); g.setLineCap(.round)
    g.addArc(center: c, radius: R * 0.8, startAngle: -0.4, endAngle: 0.9, clockwise: false); g.strokePath()
    // 라벨과 축
    let lr = R * 0.38
    g.setFillColor(green.cgColor); g.fillEllipse(in: CGRect(x: c.x - lr, y: c.y - lr, width: 2 * lr, height: 2 * lr))
    g.setFillColor(accent.cgColor)
    g.fillEllipse(in: CGRect(x: c.x - lr * 0.55, y: c.y + lr * 0.25, width: lr * 0.5, height: lr * 0.5))
    g.setFillColor(metal.cgColor); g.fillEllipse(in: CGRect(x: c.x - 16, y: c.y - 16, width: 32, height: 32))

    // 톤암: 오른쪽 위 축에서 판 위로
    let pivot = CGPoint(x: 800, y: 790), tip = CGPoint(x: 640, y: 330)
    g.setShadow(offset: CGSize(width: 10, height: -12), blur: 14, color: NSColor.black.withAlphaComponent(0.25).cgColor)
    g.setFillColor(metal.cgColor); g.fillEllipse(in: CGRect(x: pivot.x - 64, y: pivot.y - 64, width: 128, height: 128))
    g.setStrokeColor(metal.cgColor); g.setLineWidth(26); g.setLineCap(.round)
    g.move(to: pivot); g.addLine(to: CGPoint(x: 720, y: 430)); g.addLine(to: tip); g.strokePath()
    g.setShadow(offset: .zero, blur: 0, color: nil)
    g.setFillColor(accent.cgColor)
    g.addPath(CGPath(roundedRect: CGRect(x: tip.x - 34, y: tip.y - 40, width: 68, height: 80), cornerWidth: 14, cornerHeight: 14, transform: nil))
    g.fillPath()
    g.setFillColor(green.blended(withFraction: 0.3, of: .black)!.cgColor)
    g.fillEllipse(in: CGRect(x: pivot.x - 28, y: pivot.y - 28, width: 56, height: 56))
    g.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
if CommandLine.arguments.count > 1 {
    try! drawIcon(size: 1024).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    exit(0)
}
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(ProcessInfo.processInfo.processIdentifier).iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! drawIcon(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
let out = root.appendingPathComponent("Resources/AppIcon.icns")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try! p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(p.terminationStatus == 0 ? out.path : "iconutil 실패")
