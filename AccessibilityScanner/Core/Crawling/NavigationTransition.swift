//
//  NavigationTransition.swift
//  AccessibilityScanner

//Created by Ravish Kumar on 29/09/26.

import Foundation
import CoreGraphics

struct NavigationTransition: Identifiable, Codable, Hashable {
    let id: UUID
    let sourceSignature: String
    let targetSignature: String
    let actionID: String
    let actionLabel: String
    let actionIdentifier: String
    let actionType: String
    let actionFrameX: Double
    let actionFrameY: Double
    let actionFrameWidth: Double
    let actionFrameHeight: Double
    let xpath: String?

    init(
        sourceSignature: String,
        targetSignature: String,
        action: NavigationAction
    ) {
        self.id = UUID()
        self.sourceSignature = sourceSignature
        self.targetSignature = targetSignature
        self.actionID = action.id
        self.actionLabel = action.label
        self.actionIdentifier = action.identifier
        self.actionType = action.type
        self.actionFrameX = action.frame.origin.x
        self.actionFrameY = action.frame.origin.y
        self.actionFrameWidth = action.frame.width
        self.actionFrameHeight = action.frame.height
        self.xpath = action.xpath
    }

    var frame: CGRect {
        CGRect(
            x: actionFrameX,
            y: actionFrameY,
            width: actionFrameWidth,
            height: actionFrameHeight
        )
    }

    var displayName: String {
        let label = actionLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty { return label }

        let identifier = actionIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if !identifier.isEmpty { return identifier }

        return actionType
    }
}
