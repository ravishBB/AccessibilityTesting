//
//  ScreenshotAnnotator.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 25/09/26.
//

import Foundation
import AppKit

final class ScreenshotAnnotator {

    struct Result {

        let image: NSImage

        let annotations:
            [ScreenshotAnnotation]
    }

    func annotate(
        imageData: Data,
        screenshotWidth: CGFloat,
        screenshotHeight: CGFloat,
        evaluations: [AccessibilityRuleEvaluation]
    ) throws -> Result {

        guard let originalImage =
                NSImage(data: imageData) else {

            throw ScreenshotAnnotatorError.invalidImage
        }

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

        let annotatedImage =
            drawAnnotations(
                image: originalImage,
                screenshotWidth:
                    screenshotWidth,
                screenshotHeight:
                    screenshotHeight,
                annotations:
                    annotations
            )

        return Result(
            image: annotatedImage,
            annotations: annotations
        )
    }

    private func drawAnnotations(
        image: NSImage,
        screenshotWidth: CGFloat,
        screenshotHeight: CGFloat,
        annotations: [ScreenshotAnnotation]
    ) -> NSImage {

        let imageSize =
            NSSize(
                width: screenshotWidth,
                height: screenshotHeight
            )

        let result =
            NSImage(
                size: imageSize
            )

        result.lockFocus()

        defer {
            result.unlockFocus()
        }

        // Draw original screenshot.
        image.draw(
            in: NSRect(
                x: 0,
                y: 0,
                width: screenshotWidth,
                height: screenshotHeight
            ),
            from: .zero,
            operation: .copy,
            fraction: 1.0
        )

        guard !annotations.isEmpty else {
            return result
        }

        let context =
            NSGraphicsContext.current?
                .cgContext

        guard let context else {
            return result
        }

        for annotation in annotations {

            let scaledFrame =
                scaleFrame(
                    annotation.frame,
                    screenshotWidth:
                        screenshotWidth,
                    screenshotHeight:
                        screenshotHeight
                )

            drawAnnotation(
                context:
                    context,
                frame:
                    scaledFrame,
                number:
                    annotation.number,
                severity:
                    annotation.severity
            )
        }

        return result
    }

    private func scaleFrame(
        _ frame: CGRect,
        screenshotWidth: CGFloat,
        screenshotHeight: CGFloat
    ) -> CGRect {

        // Appium/WDA coordinates are based on the
        // application's logical screen dimensions.
        //
        // The screenshot can have a different pixel
        // resolution, so scale the hierarchy coordinates.

        let sourceWidth =
            CGFloat(
                402
            )

        let sourceHeight =
            CGFloat(
                874
            )

        let scaleX =
            screenshotWidth /
            sourceWidth

        let scaleY =
            screenshotHeight /
            sourceHeight

        let x =
            frame.origin.x *
            scaleX

        let y =
            frame.origin.y *
            scaleY

        let width =
            frame.width *
            scaleX

        let height =
            frame.height *
            scaleY

        // Convert from top-left Appium coordinates
        // to bottom-left Core Graphics coordinates.
        let flippedY =
            screenshotHeight -
            y -
            height

        return CGRect(
            x: x,
            y: flippedY,
            width: width,
            height: height
        )
    }

    private func drawAnnotation(
        context: CGContext,
        frame: CGRect,
        number: Int,
        severity:
            AccessibilityFinding.Severity
    ) {

        let strokeColor:
            NSColor

        switch severity {

        case .error:
            strokeColor =
                .systemRed

        case .warning:
            strokeColor =
                .systemOrange

        case .info:
            strokeColor =
                .systemBlue
        }

        // =========================================
        // Bounding Box
        // =========================================

        context.setStrokeColor(
            strokeColor.cgColor
        )

        context.setLineWidth(4)

        context.stroke(
            frame
        )

        // =========================================
        // Marker Circle
        // =========================================

        let markerSize:
            CGFloat = 28

        let markerX =
            max(
                2,
                frame.minX -
                    markerSize / 2
            )

        let markerY =
            min(
                frame.maxY -
                    markerSize / 2,
                frame.maxY
            )

        let markerRect =
            CGRect(
                x: markerX,
                y: markerY,
                width: markerSize,
                height: markerSize
            )

        context.setFillColor(
            strokeColor.cgColor
        )

        context.fillEllipse(
            in: markerRect
        )

        // =========================================
        // Number
        // =========================================

        let numberText =
            "\(number)" as NSString

        let attributes:
            [NSAttributedString.Key: Any] = [

                .font:
                    NSFont.boldSystemFont(
                        ofSize: 14
                    ),

                .foregroundColor:
                    NSColor.white
            ]

        let textSize =
            numberText.size(
                withAttributes:
                    attributes
            )

        let textRect =
            CGRect(
                x:
                    markerRect.midX -
                    textSize.width / 2,

                y:
                    markerRect.midY -
                    textSize.height / 2,

                width:
                    textSize.width,

                height:
                    textSize.height
            )

        numberText.draw(
            in: textRect,
            withAttributes:
                attributes
        )
    }
}

enum ScreenshotAnnotatorError:
    Error,
    LocalizedError {

    case invalidImage

    var errorDescription: String? {

        switch self {

        case .invalidImage:
            return
                "The Appium screenshot could not be decoded."
        }
    }
}
