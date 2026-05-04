//
//  TransmuxLogBridge.swift
//  mks-multiplatform-iptv
//
//  Bridge between MKSLogConfig.Level and TransmuxCore.TransmuxLog.Level.
//  Lives at the consumer (player) layer, not in IPTVCore — keeps IPTVCore
//  free of TransmuxCore dependency. Will move to IPTVPlayer SPM in Block 5.
//

import Foundation
import TransmuxCore
import IPTVCore

extension MKSLogConfig.Level {
    /// Convert to TransmuxLog.Level for configuring the TransmuxCore SPM package.
    func toTransmuxLevel() -> TransmuxLog.Level {
        switch self {
        case .debug:   return .debug
        case .info:    return .info
        case .warning: return .warn
        case .error:   return .error
        }
    }
}
