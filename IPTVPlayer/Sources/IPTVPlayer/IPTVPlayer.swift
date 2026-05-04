//
//  IPTVPlayer.swift
//  IPTVPlayer
//
//  Module entry point. Player implementations and protocol layer migrated
//  here from mks-multiplatform-iptv/IPTVDownloader/Core/Player/ during
//  Phase 1 SPM extraction.
//

import Foundation
import IPTVCore
import TransmuxCore

public enum IPTVPlayerModule {
    public static let version = "0.1.0"

    /// Sanity helper to confirm cross-package linkage during migration. Not for
    /// production use.
    public static func dependencyCheck() -> String {
        "IPTVPlayer \(version) → IPTVCore \(IPTVCoreModule.version) + TransmuxCore"
    }
}
