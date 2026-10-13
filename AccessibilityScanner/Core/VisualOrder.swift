//
//  VisualOrder.swift
//  AccessibilityScanner
//
//  Compares an observed traversal order (accessibility tree order or the
//  runtime keyboard focus sequence) with the visual reading order: rows from
//  top to bottom, then left to right within a row.
//

import Foundation
import CoreGraphics

enum VisualOrder {

    struct Assessment {
        /// Elements compared.
        let count: Int
        /// Largest group of elements that appear in the same relative order
        /// in both the observed traversal and the visual reading order.
        let inOrder: Int

        var outOfOrder: Int { count - inOrder }
        var ratio: Double { count == 0 ? 1 : Double(inOrder) / Double(count) }
    }

    /// Elements whose tops are within one row band are treated as one row.
    private static let rowHeight: CGFloat = 20

    /// `frames` must be in the observed traversal order. Returns nil when there
    /// are too few elements for an order to mean anything.
    static func assess(frames: [CGRect]) -> Assessment? {
        guard frames.count >= 3 else { return nil }

        let visualOrder = frames.indices.sorted { a, b in
            let rowA = Int((frames[a].minY / rowHeight).rounded(.down))
            let rowB = Int((frames[b].minY / rowHeight).rounded(.down))
            if rowA != rowB { return rowA < rowB }
            if frames[a].minX != frames[b].minX { return frames[a].minX < frames[b].minX }
            return a < b
        }

        // rank[i] = visual position of the i-th element in traversal order.
        var rank = [Int](repeating: 0, count: frames.count)
        for (position, index) in visualOrder.enumerated() {
            rank[index] = position
        }

        // Longest increasing subsequence of the ranks.
        var tails: [Int] = []
        for value in rank {
            var low = 0
            var high = tails.count
            while low < high {
                let mid = (low + high) / 2
                if tails[mid] < value {
                    low = mid + 1
                } else {
                    high = mid
                }
            }
            if low == tails.count {
                tails.append(value)
            } else {
                tails[low] = value
            }
        }

        return Assessment(count: frames.count, inOrder: tails.count)
    }

    /// At or above this share of elements in order, the order is reported as correct.
    static let passThreshold = 0.9
}
