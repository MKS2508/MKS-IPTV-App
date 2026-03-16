import SwiftUI
import AVFoundation

enum PlayerControlsMode: String, CaseIterable {
    case native = "native"
    case glass = "glass"
    
    var displayName: String {
        switch self {
        case .native: "Native Controls"
        case .glass: "Liquid Glass"
        }
    }
    
    var icon: String {
        switch self {
        case .native: "play.rectangle"
        case .glass: "rectangle.split.3x3.fill"
        }
    }
}

struct PlayerControlsConfiguration {
    var mode: PlayerControlsMode = .glass
    var showSeekBar: Bool = true
    var showVolumeControl: Bool = true
    var showSpeedControl: Bool = true
    var showFullscreenButton: Bool = true
    var showPictureInPictureButton: Bool = true
    var showAirPlayButton: Bool = true
    var showChaptersButton: Bool = false
    var showSubtitlesButton: Bool = true
    var showAudioTracksButton: Bool = true
    var autoHideControls: Bool = true
    var autoHideDelay: TimeInterval = 4.0
    var seekIntervals: [TimeInterval] = [10, 15, 30]
    var speedOptions: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    var defaultSpeed: Float = 1.0
    var enableHapticFeedback: Bool = true
    var doubleTapSeekEnabled: Bool = false
    var doubleTapSeekInterval: TimeInterval = 10

    static let `default` = PlayerControlsConfiguration()
    
    static let glass = PlayerControlsConfiguration(
        mode: .glass,
        showSeekBar: true,
        showVolumeControl: true,
        showSpeedControl: true,
        showFullscreenButton: true,
        showPictureInPictureButton: true,
        showAirPlayButton: true,
        autoHideControls: true,
        autoHideDelay: 4.0
    )
    
    static let native = PlayerControlsConfiguration(
        mode: .native
    )
    
    static let minimal = PlayerControlsConfiguration(
        mode: .glass,
        showSeekBar: true,
        showVolumeControl: false,
        showSpeedControl: false,
        showFullscreenButton: true,
        showPictureInPictureButton: false,
        showAirPlayButton: false,
        autoHideControls: true,
        autoHideDelay: 3.0
    )
    
    static let live = PlayerControlsConfiguration(
        mode: .glass,
        showSeekBar: false,
        showVolumeControl: true,
        showSpeedControl: false,
        showFullscreenButton: true,
        showPictureInPictureButton: true,
        showAirPlayButton: true,
        autoHideControls: true,
        autoHideDelay: 5.0
    )
}

enum PlayerVideoGravity: String, CaseIterable {
    case resize = "resize"
    case resizeAspect = "resizeAspect"
    case resizeAspectFill = "resizeAspectFill"
    
    var avGravity: AVLayerVideoGravity {
        switch self {
        case .resize: return .resize
        case .resizeAspect: return .resizeAspect
        case .resizeAspectFill: return .resizeAspectFill
        }
    }
    
    var displayName: String {
        switch self {
        case .resize: "Stretch"
        case .resizeAspect: "Fit"
        case .resizeAspectFill: "Fill"
        }
    }
    
    var icon: String {
        switch self {
        case .resize: "rectangle.arrowtriangle.2.inward"
        case .resizeAspect: "rectangle.checkered"
        case .resizeAspectFill: "rectangle.arrowtriangle.2.outward"
        }
    }
}

struct PlayerTimeInfo {
    var currentTime: Double
    var duration: Double
    var bufferedTime: Double
    
    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
    
    var bufferedProgress: Double {
        guard duration > 0 else { return 0 }
        return bufferedTime / duration
    }
    
    var remainingTime: Double {
        max(0, duration - currentTime)
    }
    
    var formattedCurrentTime: String {
        PlayerTimeInfo.formatTime(currentTime)
    }
    
    var formattedDuration: String {
        PlayerTimeInfo.formatTime(duration)
    }
    
    var formattedRemaining: String {
        PlayerTimeInfo.formatTime(remainingTime)
    }
    
    static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
    
    static let idle = PlayerTimeInfo(currentTime: 0, duration: 0, bufferedTime: 0)
}
