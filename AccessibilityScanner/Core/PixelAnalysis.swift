//
//  PixelAnalysis.swift
//  AccessibilityScanner
//
//  Measures rendered colours from the screenshot. Shared by the text contrast
//  rules, non-text contrast, form borders, loading indicators and link colour.


import AppKit
import Vision

// MARK: - Colour

nonisolated struct PixelColor {
    let r: Double
    let g: Double
    let b: Double

    /// WCAG relative luminance.
    var luminance: Double {
        func linear(_ v: Double) -> Double {
            v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}

nonisolated enum PixelMath {

    static func contrast(_ a: Double, _ b: Double) -> Double {
        (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    /// `fraction` in 0...1, nearest-rank.
    static func percentile(_ values: [Double], _ fraction: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * fraction).rounded())))
        return sorted[index]
    }
}

// MARK: - Sampler

nonisolated struct PixelRect {
    let x0: Int
    let y0: Int
    let x1: Int
    let y1: Int

    var width: Int { x1 - x0 + 1 }
    var height: Int { y1 - y0 + 1 }

    func contains(x: Int, y: Int) -> Bool {
        x >= x0 && x <= x1 && y >= y0 && y <= y1
    }
}

nonisolated enum PixelEdge {
    case top, bottom, left, right
}

nonisolated final class PixelSampler {

    private let bitmap: NSBitmapImageRep
    private let hierarchyWidth: Double
    private let hierarchyHeight: Double
    private let scaleX: CGFloat
    private let scaleY: CGFloat
    private let width: Int
    private let height: Int
    private let useRaw: Bool
    private let bytesPerPixel: Int
    private let bytesPerRow: Int

    // The screenshot is decoded once and reused across every rule call.
    private static let lock = NSLock()
    private static var cachedData: Data?
    private static var cachedSampler: PixelSampler?

    static func make(context: AccessibilityRuleContext) -> PixelSampler? {
        guard let data = context.screenshotData,
              context.hierarchyWidth > 0,
              context.hierarchyHeight > 0
        else { return nil }

        lock.lock()
        defer { lock.unlock() }

        if let cachedData, let cachedSampler,
           cachedData == data,
           cachedSampler.hierarchyWidth == context.hierarchyWidth,
           cachedSampler.hierarchyHeight == context.hierarchyHeight {
            return cachedSampler
        }

        guard let bitmap = NSBitmapImageRep(data: data) else { return nil }
        let sampler = PixelSampler(
            bitmap: bitmap,
            hierarchyWidth: context.hierarchyWidth,
            hierarchyHeight: context.hierarchyHeight
        )
        cachedData = data
        cachedSampler = sampler
        return sampler
    }

    private init(bitmap: NSBitmapImageRep, hierarchyWidth: Double, hierarchyHeight: Double) {
        self.bitmap = bitmap
        self.hierarchyWidth = hierarchyWidth
        self.hierarchyHeight = hierarchyHeight
        self.width = bitmap.pixelsWide
        self.height = bitmap.pixelsHigh
        self.scaleX = CGFloat(bitmap.pixelsWide) / CGFloat(hierarchyWidth)
        self.scaleY = CGFloat(bitmap.pixelsHigh) / CGFloat(hierarchyHeight)
        self.bytesPerPixel = max(1, bitmap.bitsPerPixel / 8)
        self.bytesPerRow = bitmap.bytesPerRow
        self.useRaw = bitmap.bitmapData != nil &&
            bitmap.bitsPerSample == 8 &&
            bitmap.samplesPerPixel >= 3 &&
            !bitmap.isPlanar
    }

    // MARK: Geometry

    /// Converts a hierarchy frame to a pixel rectangle clamped to the image.
    func pixelRect(for frame: CGRect) -> PixelRect? {
        let x0 = max(0, Int((frame.minX * scaleX).rounded(.down)))
        let y0 = max(0, Int((frame.minY * scaleY).rounded(.down)))
        let x1 = min(width - 1, Int((frame.maxX * scaleX).rounded(.up)) - 1)
        let y1 = min(height - 1, Int((frame.maxY * scaleY).rounded(.up)) - 1)
        guard x1 - x0 >= 3, y1 - y0 >= 3 else { return nil }
        return PixelRect(x0: x0, y0: y0, x1: x1, y1: y1)
    }

    /// The screenshot region under a hierarchy frame, for text recognition.
    func image(cropping frame: CGRect) -> CGImage? {
        guard let rect = pixelRect(for: frame), let image = bitmap.cgImage else { return nil }
        return image.cropping(to: CGRect(x: rect.x0, y: rect.y0, width: rect.width, height: rect.height))
    }

    // MARK: Pixels (y counts from the top row)

    func color(x: Int, y: Int) -> PixelColor? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }

        if useRaw, let data = bitmap.bitmapData {
            let offset = y * bytesPerRow + x * bytesPerPixel
            return PixelColor(
                r: Double(data[offset]) / 255,
                g: Double(data[offset + 1]) / 255,
                b: Double(data[offset + 2]) / 255
            )
        }

        guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return nil }
        return PixelColor(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent))
    }

    // MARK: Sampling

    /// Evenly spread samples across a rectangle, at most about `maxSamples`.
    func gridSamples(in rect: PixelRect, maxSamples: Int, excluding: PixelRect? = nil) -> [PixelColor] {
        let total = max(1, rect.width * rect.height)
        let step = max(1, Int(sqrt(Double(total) / Double(max(1, maxSamples))).rounded(.up)))
        var result: [PixelColor] = []

        for y in stride(from: rect.y0, through: rect.y1, by: step) {
            for x in stride(from: rect.x0, through: rect.x1, by: step) {
                if let excluding, excluding.contains(x: x, y: y) { continue }
                if let c = color(x: x, y: y) { result.append(c) }
            }
        }
        return result
    }

    /// Samples in a ring `offset` pixels outside the rectangle. Points that fall
    /// off the image are skipped.
    func outerRingSamples(of rect: PixelRect, offset: Int, maxSamples: Int) -> [PixelColor] {
        let perimeter = max(1, 2 * (rect.width + rect.height))
        let step = max(1, perimeter / max(1, maxSamples))
        var result: [PixelColor] = []

        for x in stride(from: rect.x0, through: rect.x1, by: step) {
            if let c = color(x: x, y: rect.y0 - offset) { result.append(c) }
            if let c = color(x: x, y: rect.y1 + offset) { result.append(c) }
        }
        for y in stride(from: rect.y0, through: rect.y1, by: step) {
            if let c = color(x: rect.x0 - offset, y: y) { result.append(c) }
            if let c = color(x: rect.x1 + offset, y: y) { result.append(c) }
        }
        return result
    }

    /// Samples along one edge, `inset` pixels inside it, skipping the outer 20%
    /// at each end so rounded corners do not count as the border.
    func edgeSamples(of rect: PixelRect, edge: PixelEdge, inset: Int) -> [PixelColor] {
        var result: [PixelColor] = []

        switch edge {
        case .top, .bottom:
            let y = edge == .top ? rect.y0 + inset : rect.y1 - inset
            let trim = rect.width / 5
            guard rect.x0 + trim <= rect.x1 - trim else { return [] }
            for x in stride(from: rect.x0 + trim, through: rect.x1 - trim, by: 1) {
                if let c = color(x: x, y: y) { result.append(c) }
            }
        case .left, .right:
            let x = edge == .left ? rect.x0 + inset : rect.x1 - inset
            let trim = rect.height / 5
            guard rect.y0 + trim <= rect.y1 - trim else { return [] }
            for y in stride(from: rect.y0 + trim, through: rect.y1 - trim, by: 1) {
                if let c = color(x: x, y: y) { result.append(c) }
            }
        }
        return result
    }
}

// MARK: - Analyzer

nonisolated enum PixelAnalyzer {

    // MARK: Ink against background (text, icons, indicators)

    struct InkMeasurement {
        let ratio: Double
        let inkLuminance: Double
        let backgroundLuminance: Double
        let variedBackground: Bool
    }

    static func inkContrast(
        frame: CGRect,
        sampler: PixelSampler,
        excluding: CGRect? = nil
    ) -> InkMeasurement? {

        guard let rect = sampler.pixelRect(for: frame) else { return nil }
        let excludedRect = excluding.flatMap { sampler.pixelRect(for: $0) }

        var background = sampler.outerRingSamples(of: rect, offset: 2, maxSamples: 160)
        if background.count < 12 {
            for edge in [PixelEdge.top, .bottom, .left, .right] {
                background += sampler.edgeSamples(of: rect, edge: edge, inset: 0)
            }
        }
        guard background.count >= 8 else { return nil }

        let backgroundLuminances = background.map(\.luminance)
        let backgroundMedian = PixelMath.median(backgroundLuminances)
        let spread = PixelMath.percentile(backgroundLuminances, 0.9) -
            PixelMath.percentile(backgroundLuminances, 0.1)
        let varied = spread > 0.08

        let interior = sampler.gridSamples(in: rect, maxSamples: 4000, excluding: excludedRect)
        guard interior.count >= 8 else { return nil }

        let deltas = interior.map { abs($0.luminance - backgroundMedian) }
        guard let maxDelta = deltas.max(), maxDelta >= 0.02 else { return nil }

        var inkLuminances: [Double] = []
        for (index, delta) in deltas.enumerated() where delta >= 0.6 * maxDelta {
            inkLuminances.append(interior[index].luminance)
        }
        guard inkLuminances.count >= 3 else { return nil }

        let inkLuminance = PixelMath.median(inkLuminances)

        let ratio: Double
        if varied {
            let ratios = backgroundLuminances.map { PixelMath.contrast(inkLuminance, $0) }
            ratio = PixelMath.percentile(ratios, 0.1)
        } else {
            ratio = PixelMath.contrast(inkLuminance, backgroundMedian)
        }

        return InkMeasurement(
            ratio: ratio,
            inkLuminance: inkLuminance,
            backgroundLuminance: backgroundMedian,
            variedBackground: varied
        )
    }

    // MARK: Component boundary or fill against its surroundings

    struct ComponentMeasurement {
        let fillRatio: Double
        let borderRatio: Double

        var best: Double { max(fillRatio, borderRatio) }

        /// False when neither a border nor a fill is distinguishable, which means
        /// the control is identified by its text or icon rather than its shape.
        var hasBoundary: Bool { best >= 1.05 }
    }

    static func componentContrast(
        frame: CGRect,
        sampler: PixelSampler
    ) -> ComponentMeasurement? {

        guard let rect = sampler.pixelRect(for: frame) else { return nil }

        let outer = sampler.outerRingSamples(of: rect, offset: 3, maxSamples: 120)
        guard outer.count >= 12 else { return nil }
        let backgroundLuminance = PixelMath.median(outer.map(\.luminance))

        // Fill: the middle of the control.
        let insetX = max(1, rect.width / 4)
        let insetY = max(1, rect.height / 4)
        guard rect.x0 + insetX < rect.x1 - insetX, rect.y0 + insetY < rect.y1 - insetY else { return nil }
        let core = PixelRect(
            x0: rect.x0 + insetX,
            y0: rect.y0 + insetY,
            x1: rect.x1 - insetX,
            y1: rect.y1 - insetY
        )
        let fillSamples = sampler.gridSamples(in: core, maxSamples: 400)
        guard fillSamples.count >= 4 else { return nil }
        let fillRatio = PixelMath.contrast(
            PixelMath.median(fillSamples.map(\.luminance)),
            backgroundLuminance
        )

        // Border: strongest edge, looking up to 2 px inside the frame so a
        // border drawn just inside the bounds is found. A single strong edge
        // counts, which covers underlined text fields.
        var borderRatio = 1.0
        for edge in [PixelEdge.top, .bottom, .left, .right] {
            for inset in 0...2 {
                let samples = sampler.edgeSamples(of: rect, edge: edge, inset: inset)
                guard samples.count >= 4 else { continue }
                let ratio = PixelMath.contrast(
                    PixelMath.median(samples.map(\.luminance)),
                    backgroundLuminance
                )
                borderRatio = max(borderRatio, ratio)
            }
        }

        return ComponentMeasurement(fillRatio: fillRatio, borderRatio: borderRatio)
    }

    // MARK: Underline

    /// True when a line of non-background colour runs under most of `frame`.
    static func hasUnderline(
        frame: CGRect,
        sampler: PixelSampler,
        backgroundLuminance: Double
    ) -> Bool {

        guard let rect = sampler.pixelRect(for: frame) else { return false }

        for y in (rect.y1 - 2)...(rect.y1 + 4) {
            var covered = 0
            var total = 0
            for x in rect.x0...rect.x1 {
                guard let c = sampler.color(x: x, y: y) else { continue }
                total += 1
                if abs(c.luminance - backgroundLuminance) >= 0.2 { covered += 1 }
            }
            if total >= 8, Double(covered) / Double(total) >= 0.8 {
                return true
            }
        }
        return false
    }
}

// MARK: - Text recognition

/// Reads the visible text of a control from the screenshot (Vision OCR).
/// Used where the hierarchy does not expose the visible label separately
/// from the accessible name: iOS, and Flutter/Compose on Android.
nonisolated enum TextRecognizer {

    private static let lock = NSLock()
    private static var cache: [String: String?] = [:]

    /// Text rendered inside `frame`, or nil when none is legible. Results are
    /// cached per screenshot and frame: viewports repeat the same controls.
    static func text(in frame: CGRect, context: AccessibilityRuleContext) -> String? {
        guard let data = context.screenshotData,
              frame.width >= 8, frame.height >= 8
        else { return nil }

        let key = "\(fingerprint(data))|\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width)),\(Int(frame.height))"
        lock.lock()
        if let cached = cache[key] { lock.unlock(); return cached }
        lock.unlock()

        let result = recognize(frame: frame, context: context)

        lock.lock()
        if cache.count > 2_000 { cache.removeAll() }
        cache[key] = result
        lock.unlock()
        return result
    }

    private static func fingerprint(_ data: Data) -> Int {
        var hasher = Hasher()
        hasher.combine(data.count)
        let step = max(1, data.count / 512)
        data.withUnsafeBytes { bytes in
            var index = 0
            while index < bytes.count {
                hasher.combine(bytes[index])
                index += step
            }
        }
        return hasher.finalize()
    }

    private static func recognize(frame: CGRect, context: AccessibilityRuleContext) -> String? {
        guard let sampler = PixelSampler.make(context: context),
              let image = sampler.image(cropping: frame)
        else { return nil }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        // Inside this app Vision's Neural Engine model fails to compile
        // (ANECCompile FAILED) and retries on every call. usesCPUOnly turns
        // the Neural Engine off entirely; it is deprecated, so it is set
        // through KVC only when the request still supports it.
        if request.responds(to: NSSelectorFromString("setUsesCPUOnly:")) {
            request.setValue(true, forKey: "usesCPUOnly")
        }
        if let devices = try? request.supportedComputeStageDevices {
            for (stage, stageDevices) in devices {
                if let cpu = stageDevices.first(where: { if case .cpu = $0 { return true }; return false }) {
                    request.setComputeDevice(cpu, for: stage)
                }
            }
        }

        let handler = VNImageRequestHandler(cgImage: image)
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        let lines = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first }
            .filter { $0.confidence >= 0.5 }
            .map(\.string)
        let text = lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
