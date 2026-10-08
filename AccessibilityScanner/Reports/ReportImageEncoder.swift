//
//  ReportImageEncoder.swift
//  AccessibilityScanner
//
//  Downscales screenshots so exported reports stay a reasonable size, and
//  encodes them for embedding (data URI for HTML, base64 for JSON).
//

import Foundation
import ImageIO

enum ReportImageEncoder {

    struct EncodedImage {
        let data: Data
        let mimeType: String

        var base64: String { data.base64EncodedString() }
        var dataURI: String { "data:\(mimeType);base64,\(base64)" }
    }

    /// Returns the image scaled so its longest side is at most `maxPixelSize`,
    /// re-encoded as JPEG. Falls back to the original bytes if decoding fails.
    static func encode(
        _ data: Data,
        maxPixelSize: Int = 900,
        quality: Double = 0.78
    ) -> EncodedImage? {
        guard !data.isEmpty else { return nil }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return EncodedImage(data: data, mimeType: sniffMimeType(data))
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            return EncodedImage(data: data, mimeType: sniffMimeType(data))
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            "public.jpeg" as CFString,
            1,
            nil
        ) else {
            return EncodedImage(data: data, mimeType: sniffMimeType(data))
        }

        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            return EncodedImage(data: data, mimeType: sniffMimeType(data))
        }

        return EncodedImage(data: output as Data, mimeType: "image/jpeg")
    }

    private static func sniffMimeType(_ data: Data) -> String {
        let bytes = [UInt8](data.prefix(4))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if bytes.starts(with: [0xFF, 0xD8]) { return "image/jpeg" }
        return "application/octet-stream"
    }
}
