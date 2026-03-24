import SwiftUI
import AVKit

#if os(iOS) || os(tvOS)

struct NativeAVPlayerViewController: UIViewControllerRepresentable {
    let player: AVPlayer
    var onDismiss: (() -> Void)?
    var showsPlaybackControls: Bool = true
    var videoGravity: AVLayerVideoGravity = .resizeAspect
    var allowsPictureInPicture: Bool = true
    var allowsVideoFrameAnalysis: Bool = true

    // MARK: - Remote Play

    /// Discovered DLNA/Cast devices.
    var remoteDevices: [RemoteDevice] = []
    /// Currently connected device.
    var connectedDevice: RemoteDevice? = nil
    /// Called when the user selects a device.
    var onDeviceSelected: ((RemoteDevice) -> Void)? = nil
    /// Called when the user chooses "Disconnect".
    var onDisconnect: (() -> Void)? = nil
    /// Called when the user chooses "Refresh Devices".
    var onRefreshDevices: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = showsPlaybackControls
        controller.allowsPictureInPicturePlayback = allowsPictureInPicture
        controller.videoGravity = videoGravity
        controller.delegate = context.coordinator
        // We manage MPNowPlayingInfoCenter manually via PlayerMetadataHelper.
        // Prevent AVPlayerViewController from overwriting our metadata.
        controller.updatesNowPlayingInfoCenter = false

        #if os(iOS)
        if #available(iOS 16.0, *) {
            controller.allowsVideoFrameAnalysis = allowsVideoFrameAnalysis
        }
        #endif

        let coordinator = context.coordinator
        coordinator.remoteDevices = remoteDevices
        coordinator.connectedDevice = connectedDevice
        coordinator.onDeviceSelected = onDeviceSelected
        coordinator.onDisconnect = onDisconnect
        coordinator.onRefreshDevices = onRefreshDevices

        #if os(tvOS)
        // tvOS: inject Cast menu into native transport bar
        controller.transportBarCustomMenuItems = coordinator.buildTransportBarMenuItems()
        #elseif os(iOS)
        // iOS: embed RemotePlayButton in contentOverlayView (Apple's official
        // layer between video and native controls — no tvOS menu API on iOS).
        coordinator.installCastButton(in: controller)
        #endif

        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
        if controller.videoGravity != videoGravity {
            controller.videoGravity = videoGravity
        }

        let coordinator = context.coordinator
        coordinator.remoteDevices = remoteDevices
        coordinator.connectedDevice = connectedDevice
        coordinator.onDeviceSelected = onDeviceSelected
        coordinator.onDisconnect = onDisconnect
        coordinator.onRefreshDevices = onRefreshDevices

        #if os(tvOS)
        controller.transportBarCustomMenuItems = coordinator.buildTransportBarMenuItems()
        #endif
        // iOS: contentOverlayView hosting controller updates automatically via
        // RemotePlayManager @Observable environment — no manual rebuild needed.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var onDismiss: (() -> Void)?
        var remoteDevices: [RemoteDevice] = []
        var connectedDevice: RemoteDevice?
        var onDeviceSelected: ((RemoteDevice) -> Void)?
        var onDisconnect: (() -> Void)?
        var onRefreshDevices: (() -> Void)?

        /// Tag to find the hosting view in contentOverlayView
        private let castButtonTag = 9999

        init(onDismiss: (() -> Void)?) {
            self.onDismiss = onDismiss
        }

        // MARK: - iOS: Cast Button in contentOverlayView

        #if os(iOS)
        /// Embeds a RemotePlayButton (SwiftUI) into the AVPlayerViewController's
        /// contentOverlayView using UIHostingController. This is Apple's recommended
        /// layer for custom controls — sits between the video and native chrome.
        func installCastButton(in controller: AVPlayerViewController) {
            guard let overlay = controller.contentOverlayView else { return }
            // Avoid duplicate installs
            guard overlay.viewWithTag(castButtonTag) == nil else { return }

            let button = RemotePlayButton()
                .buttonStyle(.plain)
                .adaptiveGlass(in: Capsule())
                .environment(RemotePlayManager.shared)

            let host = UIHostingController(rootView: button)
            host.view.backgroundColor = .clear
            host.view.tag = castButtonTag
            host.view.translatesAutoresizingMaskIntoConstraints = false

            overlay.addSubview(host.view)
            NSLayoutConstraint.activate([
                host.view.topAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.topAnchor, constant: 8),
                host.view.trailingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            ])

            // Let the hosting view size itself
            host.view.setContentHuggingPriority(.required, for: .horizontal)
            host.view.setContentHuggingPriority(.required, for: .vertical)
        }
        #endif

        // MARK: - tvOS: Transport Bar Menu

        #if os(tvOS)
        func buildTransportBarMenuItems() -> [UIMenuElement] {
            var items: [UIMenuElement] = []

            if remoteDevices.isEmpty {
                let searching = UIAction(
                    title: "Searching for devices...",
                    image: UIImage(systemName: "wifi"),
                    attributes: .disabled
                ) { _ in }
                items.append(searching)
            } else {
                let deviceActions = remoteDevices.map { device in
                    let title = "\(device.name) (\(device.type.displayName))"
                    let isConnected = connectedDevice?.id == device.id
                    return UIAction(
                        title: title,
                        image: UIImage(systemName: device.type.icon),
                        state: isConnected ? .on : .off
                    ) { [weak self] _ in
                        self?.onDeviceSelected?(device)
                    }
                }
                items.append(UIMenu(title: "Cast To", options: .displayInline, children: deviceActions))

                if let connected = connectedDevice {
                    items.append(UIAction(
                        title: "Disconnect from \(connected.name)",
                        image: UIImage(systemName: "xmark.circle"),
                        attributes: .destructive
                    ) { [weak self] _ in
                        self?.onDisconnect?()
                    })
                }
            }

            items.append(UIAction(
                title: "Refresh Devices",
                image: UIImage(systemName: "arrow.clockwise")
            ) { [weak self] _ in
                self?.onRefreshDevices?()
            })

            return [UIMenu(
                title: "Cast",
                image: UIImage(systemName: "tv.badge.wifi"),
                children: items
            )]
        }
        #endif

        // MARK: - AVPlayerViewControllerDelegate

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willBeginFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator
        ) {
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator
        ) {
            coordinator.animate(alongsideTransition: nil) { _ in
                self.onDismiss?()
            }
        }
    }
}

#elseif os(macOS)

struct NativeAVPlayerView: NSViewRepresentable {
    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity = .resizeAspect
    var controlsStyle: AVPlayerViewControlsStyle = .floating
    var showsFullScreenToggleButton: Bool = true
    var showsSharingServiceButton: Bool = true
    var showsTimecodes: Bool = true
    var allowsPictureInPicture: Bool = true

    // MARK: - Remote Play (actionPopUpButtonMenu)

    /// Discovered DLNA/Cast devices to show in the gear menu.
    var remoteDevices: [RemoteDevice] = []
    /// Currently connected device (shown with checkmark, enables "Disconnect").
    var connectedDevice: RemoteDevice? = nil
    /// Called when the user selects a device from the menu.
    var onDeviceSelected: ((RemoteDevice) -> Void)? = nil
    /// Called when the user chooses "Disconnect".
    var onDisconnect: (() -> Void)? = nil
    /// Called when the user chooses "Copy Stream URL".
    var onCopyStreamURL: (() -> Void)? = nil
    /// Called when the user chooses "Refresh Devices" to trigger a new SSDP scan.
    var onRefreshDevices: (() -> Void)? = nil

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = controlsStyle
        view.videoGravity = videoGravity
        view.showsFullScreenToggleButton = showsFullScreenToggleButton
        view.showsSharingServiceButton = showsSharingServiceButton
        view.showsTimecodes = showsTimecodes
        view.allowsPictureInPicturePlayback = allowsPictureInPicture
        view.updatesNowPlayingInfoCenter = false

        // Seed coordinator with initial data
        let coordinator = context.coordinator
        coordinator.remoteDevices = remoteDevices
        coordinator.connectedDevice = connectedDevice
        coordinator.onDeviceSelected = onDeviceSelected
        coordinator.onDisconnect = onDisconnect
        coordinator.onCopyStreamURL = onCopyStreamURL
        coordinator.onRefreshDevices = onRefreshDevices

        // Build the gear menu (actionPopUpButtonMenu) for DLNA/Cast.
        // Must populate with initial items — AppKit hides the gear button
        // when the menu has zero items.
        let menu = NSMenu(title: "Cast & Settings")
        menu.delegate = coordinator
        coordinator.populateMenu(menu)
        view.actionPopUpButtonMenu = menu

        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player { nsView.player = player }
        if nsView.videoGravity != videoGravity { nsView.videoGravity = videoGravity }
        if nsView.controlsStyle != controlsStyle { nsView.controlsStyle = controlsStyle }

        // Update coordinator state — menu rebuilds dynamically via menuNeedsUpdate
        let coordinator = context.coordinator
        coordinator.remoteDevices = remoteDevices
        coordinator.connectedDevice = connectedDevice
        coordinator.onDeviceSelected = onDeviceSelected
        coordinator.onDisconnect = onDisconnect
        coordinator.onCopyStreamURL = onCopyStreamURL
        coordinator.onRefreshDevices = onRefreshDevices

        // Re-populate so the gear button stays visible even if SwiftUI
        // recreates the view identity (e.g. when avPlayer becomes non-nil).
        if let menu = nsView.actionPopUpButtonMenu {
            coordinator.populateMenu(menu)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Coordinator (NSMenuDelegate)

    class Coordinator: NSObject, NSMenuDelegate {
        var remoteDevices: [RemoteDevice] = []
        var connectedDevice: RemoteDevice?
        var onDeviceSelected: ((RemoteDevice) -> Void)?
        var onDisconnect: (() -> Void)?
        var onCopyStreamURL: (() -> Void)?
        var onRefreshDevices: (() -> Void)?

        /// Rebuilds the menu items. Called from both `makeNSView`/`updateNSView`
        /// (to ensure the gear button is visible) and `menuNeedsUpdate` (to
        /// refresh device list right before the menu opens).
        func populateMenu(_ menu: NSMenu) {
            menu.removeAllItems()

            if remoteDevices.isEmpty {
                let searching = NSMenuItem(title: "Searching for devices...", action: nil, keyEquivalent: "")
                searching.isEnabled = false
                searching.image = NSImage(systemSymbolName: "wifi", accessibilityDescription: nil)
                menu.addItem(searching)
            } else {
                let header = NSMenuItem(title: "Cast To", action: nil, keyEquivalent: "")
                header.isEnabled = false
                header.attributedTitle = NSAttributedString(
                    string: "Cast To",
                    attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold)]
                )
                menu.addItem(header)

                for (index, device) in remoteDevices.enumerated() {
                    let title = "\(device.name) (\(device.type.displayName))"
                    let item = NSMenuItem(title: title, action: #selector(deviceSelected(_:)), keyEquivalent: "")
                    item.target = self
                    item.tag = index
                    item.image = NSImage(systemSymbolName: device.type.icon, accessibilityDescription: device.type.displayName)

                    if connectedDevice?.id == device.id {
                        item.state = .on
                    }

                    menu.addItem(item)
                }

                if let connected = connectedDevice {
                    menu.addItem(.separator())
                    let disconnect = NSMenuItem(
                        title: "Disconnect from \(connected.name)",
                        action: #selector(disconnectAction),
                        keyEquivalent: ""
                    )
                    disconnect.target = self
                    disconnect.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "Disconnect")
                    menu.addItem(disconnect)
                }
            }

            menu.addItem(.separator())

            let copyURL = NSMenuItem(title: "Copy Stream URL", action: #selector(copyStreamURLAction), keyEquivalent: "")
            copyURL.target = self
            copyURL.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy")
            menu.addItem(copyURL)

            let refresh = NSMenuItem(title: "Refresh Devices", action: #selector(refreshDevicesAction), keyEquivalent: "")
            refresh.target = self
            refresh.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
            menu.addItem(refresh)
        }

        /// NSMenuDelegate — rebuilds items each time the menu opens for fresh device data.
        /// Also triggers an SSDP refresh so the next open will have the latest devices.
        func menuNeedsUpdate(_ menu: NSMenu) {
            populateMenu(menu)
            onRefreshDevices?()
        }

        @objc func deviceSelected(_ sender: NSMenuItem) {
            let index = sender.tag
            guard index >= 0, index < remoteDevices.count else { return }
            onDeviceSelected?(remoteDevices[index])
        }

        @objc func disconnectAction() {
            onDisconnect?()
        }

        @objc func copyStreamURLAction() {
            onCopyStreamURL?()
        }

        @objc func refreshDevicesAction() {
            onRefreshDevices?()
        }
    }
}

#endif


