//
//  TotemSlot.swift
//  totem-encryption
//
//  Three physical objects you register. ANY ONE unlocks. ANY ONE re-enrolls the others.
//

import Foundation

enum TotemSlot: String, CaseIterable, Identifiable {
    case carry     = "carry"       // Something you always have (wrist, palm, fingernail)
    case anchor    = "anchor"      // A special item that never changes (watch, ring, key)
    case workspace = "workspace"   // Something at your desk (keyboard, mousepad, mug)

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .carry:     return "Carry"
        case .anchor:    return "Anchor"
        case .workspace: return "Workspace"
        }
    }

    var description: String {
        switch self {
        case .carry:     return "Something you always have — wrist, palm, fingernail"
        case .anchor:    return "A special item that never changes — watch, ring, key"
        case .workspace: return "Something at your desk — keyboard, mousepad, notebook"
        }
    }

    var icon: String {
        switch self {
        case .carry:     return "hand.raised.fill"
        case .anchor:    return "star.fill"
        case .workspace: return "desktopcomputer"
        }
    }

    /// Keychain account key for this slot's helper string.
    var keychainAccount: String { "totem_helper_\(rawValue)" }

    /// UserDefaults key to track whether this slot is enrolled.
    var enrolledKey: String { "totem_enrolled_\(rawValue)" }
}
