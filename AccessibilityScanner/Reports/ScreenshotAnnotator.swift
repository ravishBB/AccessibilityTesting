//
//  ScreenshotAnnotator.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 25/09/26.
//

import Foundation
import AppKit

final class ScreenshotAnnotator {

    // MARK: - Main Annotation Method

    func annotate(
        imageData: Data,
        screenshotWidth: Double,
        screenshotHeight: Double,
        hierarchyWidth: Double,
        hierarchyHeight: Double,
        evaluations: [AccessibilityRuleEvaluation]
    ) -> Data? {

        // ---------------------------------------------------------
        // 1. Decode screenshot
        // ---------------------------------------------------------

        guard let sourceImage = NSImage(data: imageData) else {
            print("ANNOTATOR: Could not decode source image.")
            return nil
        }

        guard
            screenshotWidth > 0,
            screenshotHeight > 0,
            hierarchyWidth > 0,
            hierarchyHeight > 0
        else {
            print("ANNOTATOR: Invalid dimensions.")
            return nil
        }

        // ---------------------------------------------------------
        // 2. Get actual screenshot pixel dimensions
        // ---------------------------------------------------------

        guard let sourceCGImage = sourceImage.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else {
            print("ANNOTATOR: Could not obtain CGImage.")
            return nil
        }

        let pixelWidth = sourceCGImage.width
        let pixelHeight = sourceCGImage.height

        guard pixelWidth > 0, pixelHeight > 0 else {
            print("ANNOTATOR: Invalid screenshot pixel dimensions.")
            return nil
        }

        print("""
        ==========================================
        SCREENSHOT ANNOTATOR
        ==========================================

        NSImage size:
            \(sourceImage.size.width) × \(sourceImage.size.height)

        Screenshot supplied dimensions:
            \(screenshotWidth) × \(screenshotHeight)

        Actual screenshot pixels:
            \(pixelWidth) × \(pixelHeight)

        Accessibility hierarchy:
            \(hierarchyWidth) × \(hierarchyHeight)
        """)

        // ---------------------------------------------------------
        // 3. Create issue annotations
        // ---------------------------------------------------------

        let annotations = evaluations
            .filter {
                $0.status == .fail ||
                $0.status == .warning ||
                $0.status == .validate
            }
            .enumerated()
            .map { index, evaluation in
                ScreenshotAnnotation(
                    number: index + 1,
                    evaluation: evaluation
                )
            }

        print("""
        Issues:
            \(annotations.count)

        ==========================================
        """)

        // ---------------------------------------------------------
        // 4. Create bitmap
        // ---------------------------------------------------------

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            print("ANNOTATOR: Could not create bitmap.")
            return nil
        }

        bitmap.size = NSSize(
            width: CGFloat(pixelWidth),
            height: CGFloat(pixelHeight)
        )

        guard let graphicsContext =
                NSGraphicsContext(bitmapImageRep: bitmap)
        else {
            print("ANNOTATOR: Could not create graphics context.")
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext

        // ---------------------------------------------------------
        // 5. Draw original screenshot
        // ---------------------------------------------------------

        let destinationRect = NSRect(
            x: 0,
            y: 0,
            width: CGFloat(pixelWidth),
            height: CGFloat(pixelHeight)
        )

        sourceImage.draw(
            in: destinationRect,
            from: NSRect(
                x: 0,
                y: 0,
                width: sourceImage.size.width,
                height: sourceImage.size.height
            ),
            operation: .copy,
            fraction: 1.0
        )

        // ---------------------------------------------------------
        // 6. Coordinate conversion
        // ---------------------------------------------------------

        let screenshotPixelWidth = CGFloat(pixelWidth)
        let screenshotPixelHeight = CGFloat(pixelHeight)

        let hierarchyW = CGFloat(hierarchyWidth)
        let hierarchyH = CGFloat(hierarchyHeight)

        /*
         WDA normally reports coordinates in the same aspect ratio
         as the iOS screen.

         We calculate both scales first.
         */

        let scaleX =
            screenshotPixelWidth / hierarchyW

        let scaleY =
            screenshotPixelHeight / hierarchyH

        /*
         For a normal iOS screenshot these should be almost equal.

         Use separate X/Y scales because some devices/screenshots
         can have different pixel scaling.
         */

        let screenshotBounds = NSRect(
            x: 0,
            y: 0,
            width: screenshotPixelWidth,
            height: screenshotPixelHeight
        )

        print("""
        ==========================================
        COORDINATE SYSTEM
        ==========================================

        Hierarchy:
            \(hierarchyW) × \(hierarchyH)

        Screenshot:
            \(screenshotPixelWidth) × \(screenshotPixelHeight)

        Scale X:
            \(scaleX)

        Scale Y:
            \(scaleY)

        ==========================================
        """)

        // ---------------------------------------------------------
        // 7. Draw every issue
        // ---------------------------------------------------------

        for annotation in annotations {

            let frame = annotation.frame

            print("""
            ==========================================
            ISSUE #\(annotation.number)
            ==========================================

            Type:
                \(annotation.elementType)

            Label:
                \(annotation.elementLabel)

            WDA frame:
                x = \(frame.origin.x)
                y = \(frame.origin.y)
                width = \(frame.width)
                height = \(frame.height)
            """)

            // -----------------------------------------------------
            // Convert WDA X/Y/width/height to screenshot pixels
            // -----------------------------------------------------

            let convertedX =
                frame.origin.x * scaleX

            let convertedWidth =
                frame.width * scaleX

            let convertedHeight =
                frame.height * scaleY

            /*
             WDA/XCUITest uses a top-left coordinate origin.

             AppKit uses a bottom-left coordinate origin.

             Convert Y after scaling.
             */

            let convertedTopY =
                frame.origin.y * scaleY

            let convertedY =
                screenshotPixelHeight -
                convertedTopY -
                convertedHeight

            let convertedRect = NSRect(
                x: convertedX,
                y: convertedY,
                width: convertedWidth,
                height: convertedHeight
            )

            print("""
            Converted frame:
                x = \(convertedRect.origin.x)
                y = \(convertedRect.origin.y)
                width = \(convertedRect.width)
                height = \(convertedRect.height)
            """)

            // -----------------------------------------------------
            // Clip to screenshot
            // -----------------------------------------------------

            let clippedRect =
                clipRect(
                    convertedRect,
                    to: screenshotBounds
                )

            guard
                clippedRect.width > 1,
                clippedRect.height > 1
            else {
                print(
                    "ANNOTATOR: Issue #\(annotation.number) " +
                    "is outside screenshot."
                )

                continue
            }

            print("""
            Clipped frame:
                x = \(clippedRect.origin.x)
                y = \(clippedRect.origin.y)
                width = \(clippedRect.width)
                height = \(clippedRect.height)
            """)

            // -----------------------------------------------------
            // Draw rectangle
            // -----------------------------------------------------

            drawRectangle(
                rect: clippedRect,
                severity: annotation.severity
            )

            // -----------------------------------------------------
            // Draw marker
            // -----------------------------------------------------

            drawMarker(
                number: annotation.number,
                rect: clippedRect,
                screenshotBounds: screenshotBounds,
                severity: annotation.severity
            )

            print(
                "ANNOTATOR: Issue #\(annotation.number) drawn."
            )
        }

        graphicsContext.flushGraphics()

        NSGraphicsContext.restoreGraphicsState()

        guard let pngData =
                bitmap.representation(
                    using: .png,
                    properties: [:]
                )
        else {
            print(
                "ANNOTATOR: Could not create PNG representation."
            )

            return nil
        }

        print("""

        PNG bytes:
            \(pngData.count)

        Pixel dimensions:
            \(pixelWidth) × \(pixelHeight)
        """)

        return pngData
    }

    // MARK: - Clip Rectangle

    private func clipRect(
        _ rect: NSRect,
        to bounds: NSRect
    ) -> NSRect {

        let minX =
            max(
                rect.minX,
                bounds.minX
            )

        let minY =
            max(
                rect.minY,
                bounds.minY
            )

        let maxX =
            min(
                rect.maxX,
                bounds.maxX
            )

        let maxY =
            min(
                rect.maxY,
                bounds.maxY
            )

        guard
            maxX > minX,
            maxY > minY
        else {
            return .zero
        }

        return NSRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }

    // MARK: - Draw Rectangle

    private func drawRectangle(
        rect: NSRect,
        severity: AccessibilityFinding.Severity
    ) {

        let color =
            colorForSeverity(severity)

        color.setStroke()

        let path =
            NSBezierPath(
                rect: rect
            )

        path.lineWidth = 4

        path.stroke()
    }

    // MARK: - Draw Number Marker

    private func drawMarker(
        number: Int,
        rect: NSRect,
        screenshotBounds: NSRect,
        severity: AccessibilityFinding.Severity
    ) {

        let markerSize: CGFloat = 30

        // ---------------------------------------------------------
        // Try to put marker at top-left INSIDE the rectangle.
        // ---------------------------------------------------------

        var markerX =
            rect.minX

        var markerY =
            rect.maxY - markerSize

        // ---------------------------------------------------------
        // Horizontal safety
        // ---------------------------------------------------------

        markerX =
            max(
                screenshotBounds.minX,
                markerX
            )

        markerX =
            min(
                markerX,
                screenshotBounds.maxX - markerSize
            )

        // ---------------------------------------------------------
        // Vertical safety
        // ---------------------------------------------------------

        markerY =
            max(
                screenshotBounds.minY,
                markerY
            )

        markerY =
            min(
                markerY,
                screenshotBounds.maxY - markerSize
            )

        let markerRect =
            NSRect(
                x: markerX,
                y: markerY,
                width: markerSize,
                height: markerSize
            )

        let color =
            colorForSeverity(severity)

        // ---------------------------------------------------------
        // Circle
        // ---------------------------------------------------------

        color.setFill()

        let circle =
            NSBezierPath(
                ovalIn: markerRect
            )

        circle.fill()

        // ---------------------------------------------------------
        // Number
        // ---------------------------------------------------------

        let text = "\(number)"

        let attributes:
            [NSAttributedString.Key: Any] = [

                .foregroundColor:
                    NSColor.white,

                .font:
                    NSFont.boldSystemFont(
                        ofSize: 15
                    )
            ]

        let attributedText =
            NSAttributedString(
                string: text,
                attributes: attributes
            )

        let textSize =
            attributedText.size()

        let textX =
            markerRect.midX -
            (textSize.width / 2)

        let textY =
            markerRect.midY -
            (textSize.height / 2)

        attributedText.draw(
            at: NSPoint(
                x: textX,
                y: textY
            )
        )
    }

    // MARK: - Severity Color

    private func colorForSeverity(
        _ severity: AccessibilityFinding.Severity
    ) -> NSColor {

        switch severity {

        case .error:
            return NSColor.systemRed

        case .warning:
            return NSColor.systemOrange

        case .info:
            return NSColor.systemBlue
        }
    }
}
