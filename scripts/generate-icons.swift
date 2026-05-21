#!/usr/bin/env swift
//
// PanBar 图标生成器 — 用 Core Graphics 画字母 P,导出所有 macOS 需要的尺寸。
//
// 运行:  swift scripts/generate-icons.swift
// 输出:  PanBar/Resources/Assets.xcassets/AppIcon.appiconset/icon_*.png
//

import AppKit
import CoreGraphics

// MARK: 配置

/// macOS AppIcon 需要的所有像素尺寸(每个 dimension 的 1x 和 2x 合并去重后)。
let sizes: [Int] = [16, 32, 64, 128, 256, 512, 1024]

/// 输出目录(相对项目根)。
let outDir = "PanBar/Resources/Assets.xcassets/AppIcon.appiconset"

// MARK: 绘制单个图标

/// 渲染一张 size×size 的 PanBar AppIcon。
func renderIcon(size: Int) -> Data? {
    let dim = CGFloat(size)
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // 背景透明
    ctx.clear(CGRect(x: 0, y: 0, width: dim, height: dim))

    // ====== macOS 标准 ratio: icon body 占 75%,周围留 padding(系统会再补一点 ambient shadow) ======
    let inset = dim * 0.10
    let iconRect = CGRect(x: inset, y: inset, width: dim - 2 * inset, height: dim - 2 * inset)
    let cornerRadius = iconRect.width * 0.22  // macOS Big Sur+ 圆角约 22.5%

    // ====== 渐变背景(紫色 → 浅紫,与 Popover 内的 P 标识保持一致) ======
    let path = CGPath(roundedRect: iconRect,
                      cornerWidth: cornerRadius,
                      cornerHeight: cornerRadius,
                      transform: nil)
    ctx.addPath(path)
    ctx.clip()

    let colors = [
        CGColor(red: 0.486, green: 0.361, blue: 1.0,  alpha: 1.0),   // #7C5CFF top-left
        CGColor(red: 0.722, green: 0.651, blue: 1.0,  alpha: 1.0)    // #B8A6FF bottom-right
    ] as CFArray
    let locations: [CGFloat] = [0.0, 1.0]
    if let gradient = CGGradient(colorsSpace: cs, colors: colors, locations: locations) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: iconRect.minX, y: iconRect.maxY),
            end: CGPoint(x: iconRect.maxX, y: iconRect.minY),
            options: []
        )
    }

    // ====== 内嵌微高光(顶部细微的内阴影,增强立体感) ======
    ctx.saveGState()
    let highlightRect = CGRect(x: iconRect.minX, y: iconRect.midY, width: iconRect.width, height: iconRect.height / 2)
    let highlightColors = [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.12),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.0)
    ] as CFArray
    if let g2 = CGGradient(colorsSpace: cs, colors: highlightColors, locations: locations) {
        ctx.drawLinearGradient(
            g2,
            start: CGPoint(x: 0, y: highlightRect.maxY),
            end: CGPoint(x: 0, y: highlightRect.minY),
            options: []
        )
    }
    ctx.restoreGState()

    // ====== 字母 P ======
    ctx.resetClip()
    // 移除裁剪后,再 clip 一次(系统不需要圆角外的内容)
    ctx.addPath(path)
    ctx.clip()

    // 字号约为 icon body 的 60%
    let fontSize = iconRect.height * 0.62
    // 用更"科技感"的 rounded design,heavy weight
    let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
    let descriptor = font.fontDescriptor.withDesign(.rounded) ?? font.fontDescriptor
    let roundedFont = NSFont(descriptor: descriptor, size: fontSize) ?? font

    let attrs: [NSAttributedString.Key: Any] = [
        .font: roundedFont,
        .foregroundColor: NSColor.white
    ]
    let text = "P" as NSString
    let textSize = text.size(withAttributes: attrs)

    // 居中。Y 上的视觉中心补偿(P 字下方留白多,稍微下移)
    let textX = iconRect.midX - textSize.width / 2
    let textY = iconRect.midY - textSize.height / 2 + dim * 0.015

    // 用 NSGraphicsContext 包装,以便 NSAttributedString.draw 工作
    let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx
    text.draw(at: CGPoint(x: textX, y: textY), withAttributes: attrs)
    NSGraphicsContext.restoreGraphicsState()

    // 转 PNG
    guard let cgImage = ctx.makeImage() else { return nil }
    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    return bitmap.representation(using: .png, properties: [:])
}

// MARK: Contents.json 模板

/// macOS AppIcon 各 idiom/size/scale 与文件名的映射。
let manifest: [(size: String, scale: String, filename: String, pixels: Int)] = [
    ("16x16",   "1x", "icon_16.png",     16),
    ("16x16",   "2x", "icon_32.png",     32),
    ("32x32",   "1x", "icon_32.png",     32),
    ("32x32",   "2x", "icon_64.png",     64),
    ("128x128", "1x", "icon_128.png",   128),
    ("128x128", "2x", "icon_256.png",   256),
    ("256x256", "1x", "icon_256.png",   256),
    ("256x256", "2x", "icon_512.png",   512),
    ("512x512", "1x", "icon_512.png",   512),
    ("512x512", "2x", "icon_1024.png", 1024),
]

func writeContentsJSON(to dir: String) {
    let imagesJSON = manifest.map { entry in
        """
            {
              "idiom" : "mac",
              "size" : "\(entry.size)",
              "scale" : "\(entry.scale)",
              "filename" : "\(entry.filename)"
            }
        """
    }.joined(separator: ",\n")

    let json = """
    {
      "images" : [
    \(imagesJSON)
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }
    """
    let path = "\(dir)/Contents.json"
    try? json.write(toFile: path, atomically: true, encoding: .utf8)
    print("✓ wrote \(path)")
}

// MARK: 主流程

let fm = FileManager.default
let cwd = fm.currentDirectoryPath
let outFull = "\(cwd)/\(outDir)"

if !fm.fileExists(atPath: outFull) {
    try? fm.createDirectory(atPath: outFull, withIntermediateDirectories: true)
}

print("⚙️  rendering icons to \(outFull)")
for px in sizes {
    guard let data = renderIcon(size: px) else {
        print("✗ failed to render \(px)px")
        continue
    }
    let filename = "icon_\(px).png"
    let path = "\(outFull)/\(filename)"
    try? data.write(to: URL(fileURLWithPath: path))
    print("  · \(filename) (\(data.count) bytes)")
}

writeContentsJSON(to: outFull)
print("✅ done")
