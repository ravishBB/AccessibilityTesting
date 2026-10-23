//
//  VisualOrder.swift
//  AccessibilityScanner


import Foundation
import CoreGraphics

nonisolated enum VisualOrder {

    struct Assessment {
        /// Elements compared.
        let count: Int
    
        let inOrder: Int

        var outOfOrder: Int { count - inOrder }
        var ratio: Double { count == 0 ? 1 : Double(inOrder) / Double(count) }
    }

    /// Slack for frames that touch or overlap by a hair.
    private static let tolerance: CGFloat = 4
    static func mustPrecede(_ a: CGRect, _ b: CGRect) -> Bool {
        let horizontalOverlap = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        let verticalOverlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        if horizontalOverlap > tolerance, a.maxY <= b.minY + tolerance {
            return true
        }
        if verticalOverlap > min(a.height, b.height) * 0.5, a.maxX <= b.minX + tolerance {
            return true
        }
        return false
    }

    static func assess(frames: [CGRect]) -> Assessment? {
        guard frames.count >= 3 else { return nil }

        // Longest run, in traversal order, in which no element is read
        // after one it must precede.
        // Each run is checked as a whole: the pair rule is not transitive.
        var longest = [Int](repeating: 1, count: frames.count)
        var previous = [Int?](repeating: nil, count: frames.count)
        for j in frames.indices {
            for i in 0..<j where longest[i] + 1 > longest[j] {
                var member: Int? = i
                var fits = true
                while let m = member {
                    if mustPrecede(frames[j], frames[m]) { fits = false; break }
                    member = previous[m]
                }
                if fits {
                    longest[j] = longest[i] + 1
                    previous[j] = i
                }
            }
        }

        return Assessment(count: frames.count, inOrder: longest.max() ?? frames.count)
    }

    /// At or above this share of elements in order, the order is reported as correct.
    static let passThreshold = 0.9
}
