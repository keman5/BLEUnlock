import Cocoa

private final class FocusNeutralView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

struct DeviceListEntry: Equatable {
    let id: UUID
    let name: String
    let displayModel: String?
    let osVersion: String?
    let serialSuffix6: String?
    let shortIdentifierSuffix6: String
    let macAddress: String?
    let rssi: Int
    let isMonitored: Bool
    private let rawModel: String?
    private let fullSerial: String?

    init(device: Device, monitoredUUID: UUID?) {
        id = device.uuid
        name = device.description
        displayModel = device.displayModel
        osVersion = device.displayOSVersion
        serialSuffix6 = device.serialSuffix6
        shortIdentifierSuffix6 = device.shortIdentifierSuffix6
        macAddress = device.macAddr?.replacingOccurrences(of: "-", with: ":").uppercased()
        rssi = device.rssi
        isMonitored = id == monitoredUUID
        rawModel = device.model
        fullSerial = device.serialNumber
    }

    var subtitleText: String {
        var parts: [String] = []
        if let model = displayModel, !model.isEmpty, model != name {
            parts.append(model)
        }
        if let os = osVersion, !os.isEmpty {
            parts.append(os)
        }
        if let sn6 = serialSuffix6 {
            parts.append("\(t("sn_last6", "SN末6位")) \(sn6)")
        } else {
            parts.append("\(t("id_last6", "ID末6位")) \(shortIdentifierSuffix6)")
        }
        return parts.joined(separator: " · ")
    }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let addressQuery = query.replacingOccurrences(of: "-", with: ":")
        return [name, displayModel, osVersion, serialSuffix6, shortIdentifierSuffix6, fullSerial, rawModel, id.uuidString]
            .compactMap { $0 }
            .contains { $0.localizedStandardContains(query) }
            || macAddress?.localizedStandardContains(addressQuery) == true
    }
}

// MARK: - Visual Signal Gauge Bar (-100 dBm to -30 dBm)

private final class SignalThresholdBarView: NSView {
    var rssi: Int? = nil { didSet { needsDisplay = true } }
    var unlockRSSI: Int = -60 { didSet { needsDisplay = true } }
    var lockRSSI: Int = -80 { didSet { needsDisplay = true } }
    var unlockDisabled: Bool = false { didSet { needsDisplay = true } }
    var lockDisabled: Bool = false { didSet { needsDisplay = true } }

    private func normalized(_ value: Int) -> CGFloat {
        let clamped = max(-100, min(-30, value))
        return CGFloat(clamped + 100) / 70.0
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let bounds = self.bounds
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let trackPath = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        (isDark ? NSColor(calibratedWhite: 1.0, alpha: 0.16) : NSColor(calibratedWhite: 0.0, alpha: 0.12)).setFill()
        trackPath.fill()

        NSGraphicsContext.current?.saveGraphicsState()
        trackPath.addClip()

        if let r = rssi {
            let ratio = max(0.04, normalized(r))
            let fillRect = NSRect(x: 0, y: 0, width: bounds.width * ratio, height: bounds.height)
            let fillColor: NSColor
            if !unlockDisabled && r >= unlockRSSI {
                fillColor = .systemGreen
            } else if !lockDisabled && r < lockRSSI {
                fillColor = .systemRed
            } else {
                fillColor = .systemOrange
            }
            fillColor.setFill()
            NSBezierPath(rect: fillRect).fill()
        }

        if !lockDisabled {
            let lockX = bounds.width * normalized(lockRSSI)
            NSColor.systemOrange.setFill()
            NSBezierPath(rect: NSRect(x: max(0, min(bounds.width - 2, lockX - 1)), y: 0, width: 2, height: bounds.height)).fill()
        }

        if !unlockDisabled {
            let unlockX = bounds.width * normalized(unlockRSSI)
            NSColor.systemBlue.setFill()
            NSBezierPath(rect: NSRect(x: max(0, min(bounds.width - 2, unlockX - 1)), y: 0, width: 2, height: bounds.height)).fill()
        }

        NSGraphicsContext.current?.restoreGraphicsState()
    }
}

// MARK: - 4-Bar Signal Strength Indicator

private final class SignalBarsView: NSView {
    var rssi: Int = -70 { didSet { needsDisplay = true } }
    var unlockRSSI: Int = -60 { didSet { needsDisplay = true } }
    var lockRSSI: Int = -80 { didSet { needsDisplay = true } }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 18, height: 14)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let level: Int
        if rssi >= -58 { level = 4 }
        else if rssi >= -67 { level = 3 }
        else if rssi >= -76 { level = 2 }
        else { level = 1 }

        let activeColor: NSColor
        if rssi >= unlockRSSI { activeColor = .systemGreen }
        else if rssi >= lockRSSI { activeColor = .systemOrange }
        else { activeColor = .systemRed }

        let barWidth: CGFloat = 3
        let spacing: CGFloat = 2
        let heights: [CGFloat] = [4, 7, 10, 14]

        for i in 0..<4 {
            let x = CGFloat(i) * (barWidth + spacing)
            let h = heights[i]
            let rect = NSRect(x: x, y: 0, width: barWidth, height: h)
            let path = NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1)
            let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let inactiveColor = isDark ? NSColor(calibratedWhite: 1.0, alpha: 0.25) : NSColor(calibratedWhite: 0.0, alpha: 0.20)
            (i < level ? activeColor : inactiveColor).setFill()
            path.fill()
        }
    }
}

// MARK: - High-Contrast Adaptive Surface Views

private final class PanelBackgroundView: NSView {
    override var wantsUpdateLayer: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func updateLayer() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = (isDark
            ? NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.14, alpha: 0.98)
            : NSColor(calibratedRed: 0.94, green: 0.95, blue: 0.97, alpha: 0.98)).cgColor
    }
}

private final class CardSurfaceView: NSView {
    var isHighlighted: Bool = false {
        didSet { needsDisplay = true }
    }
    var cornerRadius: CGFloat = 8 {
        didSet { layer?.cornerRadius = cornerRadius }
    }

    override var wantsUpdateLayer: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.borderWidth = 1
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.borderWidth = 1
    }

    override func updateLayer() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.cornerRadius = cornerRadius
        if isHighlighted {
            layer?.borderWidth = 1.5
            if isDark {
                layer?.backgroundColor = NSColor(calibratedRed: 0.14, green: 0.25, blue: 0.42, alpha: 0.98).cgColor
                layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.85).cgColor
            } else {
                layer?.backgroundColor = NSColor(calibratedRed: 0.88, green: 0.94, blue: 1.0, alpha: 0.99).cgColor
                layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.75).cgColor
            }
        } else {
            layer?.borderWidth = 1
            if isDark {
                layer?.backgroundColor = NSColor(calibratedRed: 0.18, green: 0.19, blue: 0.22, alpha: 0.98).cgColor
                layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.16).cgColor
            } else {
                layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.99).cgColor
                layer?.borderColor = NSColor(calibratedWhite: 0.0, alpha: 0.14).cgColor
            }
        }
    }
}

// MARK: - Custom 2-Line Device Card Row View

private final class DeviceCardRowView: NSTableCellView {
    private let cardBox = CardSurfaceView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let badgeLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let rssiLabel = NSTextField(labelWithString: "")
    private let signalBars = SignalBarsView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        cardBox.cornerRadius = 8
        cardBox.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cardBox)

        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        badgeLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        badgeLabel.textColor = .white
        badgeLabel.wantsLayer = true
        badgeLabel.layer?.backgroundColor = NSColor.systemBlue.cgColor
        badgeLabel.layer?.cornerRadius = 4
        badgeLabel.alignment = .center
        badgeLabel.setContentHuggingPriority(.required, for: .horizontal)
        badgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        subtitleLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        subtitleLabel.textColor = NSColor.labelColor.withAlphaComponent(0.78)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        rssiLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        rssiLabel.textColor = .labelColor
        rssiLabel.alignment = .right
        rssiLabel.setContentHuggingPriority(.required, for: .horizontal)
        rssiLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        signalBars.translatesAutoresizingMaskIntoConstraints = false
        signalBars.setContentHuggingPriority(.required, for: .horizontal)

        for v in [titleLabel, badgeLabel, subtitleLabel, rssiLabel, signalBars] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            cardBox.addSubview(v)
        }

        NSLayoutConstraint.activate([
            cardBox.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            cardBox.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            cardBox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            cardBox.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),

            titleLabel.topAnchor.constraint(equalTo: cardBox.topAnchor, constant: 7),
            titleLabel.leadingAnchor.constraint(equalTo: cardBox.leadingAnchor, constant: 10),

            badgeLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            badgeLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 6),
            badgeLabel.trailingAnchor.constraint(lessThanOrEqualTo: rssiLabel.leadingAnchor, constant: -8),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: rssiLabel.leadingAnchor, constant: -8),
            subtitleLabel.bottomAnchor.constraint(lessThanOrEqualTo: cardBox.bottomAnchor, constant: -6),

            signalBars.trailingAnchor.constraint(equalTo: cardBox.trailingAnchor, constant: -10),
            signalBars.centerYAnchor.constraint(equalTo: cardBox.centerYAnchor),
            signalBars.widthAnchor.constraint(equalToConstant: 18),
            signalBars.heightAnchor.constraint(equalToConstant: 14),

            rssiLabel.trailingAnchor.constraint(equalTo: signalBars.leadingAnchor, constant: -8),
            rssiLabel.centerYAnchor.constraint(equalTo: cardBox.centerYAnchor)
        ])
    }

    func configure(with entry: DeviceListEntry, unlockRSSI: Int, lockRSSI: Int) {
        titleLabel.stringValue = entry.isMonitored ? "✓ " + entry.name : entry.name
        badgeLabel.stringValue = " " + t("current_monitored", "当前监控") + " "
        badgeLabel.isHidden = !entry.isMonitored
        subtitleLabel.stringValue = entry.subtitleText
        rssiLabel.stringValue = "\(entry.rssi) dBm"
        signalBars.rssi = entry.rssi
        signalBars.unlockRSSI = unlockRSSI
        signalBars.lockRSSI = lockRSSI
        toolTip = "\(entry.name)\n\(entry.subtitleText)\n\(entry.rssi) dBm"

        cardBox.isHighlighted = entry.isMonitored
    }
}

// MARK: - 450pt Menu Bar Panel View Controller

final class MenuBarPanelViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSPopoverDelegate {
    static let panelWidth: CGFloat = 450
    static let panelHeight: CGFloat = 660

    let popover = NSPopover()
    private let ble: BLE
    private let prefs = UserDefaults.standard

    // Callbacks to AppDelegate
    var onChooseDevice: ((UUID) -> Void)?
    var onLockNow: (() -> Void)?
    var onAskPassword: (() -> Void)?
    var onSetMinimumRSSI: (() -> Void)?
    var onToggleLaunchAtLogin: ((Bool) -> Void)?
    var onTogglePassiveMode: ((Bool) -> Void)?
    var onAuthorizationSettingChanged: (() -> Void)?
    var onHideMenuBarIcon: ((Bool) -> Void)?
    var onEditPausePeriods: (() -> Void)?
    var onShowAbout: (() -> Void)?
    var onQuit: (() -> Void)?
    var hasStoredPassword: (() -> Bool)?

    // Header
    private let scanDot = NSView()
    private let scanStatusLabel = NSTextField(labelWithString: "")
    private let tabSwitcher = NSSegmentedControl()

    // Monitored Device Hero Card
    private let heroCard = CardSurfaceView()
    private let heroDot = NSView()
    private let heroNameLabel = NSTextField(labelWithString: "")
    private let heroModeBadge = NSTextField(labelWithString: "")
    private let heroMetaLabel = NSTextField(labelWithString: "")
    private let lockNowButton = NSButton()
    private let heroStateLabel = NSTextField(labelWithString: "")
    private let heroRSSILabel = NSTextField(labelWithString: "")
    private let signalGauge = SignalThresholdBarView()
    private let lockScaleLabel = NSTextField(labelWithString: "")
    private let unlockScaleLabel = NSTextField(labelWithString: "")
    private let heroPauseScheduleLabel = NSTextField(labelWithString: "")
    private var pauseScheduleSpacing: NSLayoutConstraint?
    private var hiddenPauseScheduleHeight: NSLayoutConstraint?

    // Tab Container
    private let tabContainer = NSView()
    private let deviceTabView = NSView()
    private let settingsTabView = NSView()

    // Device List Tab Views
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let emptyStateLabel = NSTextField(labelWithString: "")
    private let footerCountLabel = NSTextField(labelWithString: "")

    // Settings Tab Controls
    private let unlockEnableCheck = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let unlockValueLabel = NSTextField(labelWithString: "")
    private let unlockSlider = NSSlider(value: -60, minValue: -95, maxValue: -30, target: nil, action: nil)

    private let lockEnableCheck = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let lockValueLabel = NSTextField(labelWithString: "")
    private let lockSlider = NSSlider(value: -80, minValue: -95, maxValue: -30, target: nil, action: nil)

    private let delaySegmented = NSSegmentedControl()
    private let delayValues = [2, 5, 15, 30, 60, 120, 300]

    private let timeoutSegmented = NSSegmentedControl()
    private let timeoutValues = [30, 60, 120, 300, 600]

    private let wakeOnProximityCheck = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let wakeWithoutUnlockCheck = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let passwordStatusLabel = NSTextField(labelWithString: "")
    private let setPasswordButton = NSButton()

    private let pauseMediaCheck = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let sleepDisplayCheck = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let screensaverCheck = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let autoApproveAuthorizationCheck = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let authorizationAppsButton = NSButton()

    private let passiveModeCheck = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let launchAtLoginCheck = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let hideMenuBarIconCheck = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let minRSSIButton = NSButton()

    // State
    private var entries: [DeviceListEntry] = []
    private var visibleEntries: [DeviceListEntry] = []
    private var liveRSSI: Int? = nil
    private var liveActiveMode: Bool = false
    private var pausePeriods: [PausePeriod] = []
    private var autoLockPaused = false

    init(ble: BLE) {
        self.ble = ble
        super.init(nibName: nil, bundle: nil)
        popover.contentViewController = self
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isShown: Bool {
        popover.isShown
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            close()
        } else {
            show(relativeTo: button)
        }
    }

    func close() {
        popover.performClose(nil)
    }

    func show(relativeTo button: NSStatusBarButton) {
        syncControlsFromState()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func selectSettings() {
        _ = view
        tabSwitcher.selectedSegment = 1
        tabChanged()
    }

    func updatePauseSchedule(_ periods: [PausePeriod], isPaused: Bool) {
        pausePeriods = periods
        autoLockPaused = isPaused
        if isViewLoaded {
            refreshPauseScheduleLabel()
        }
    }

    private func refreshPauseScheduleLabel() {
        let ranges = pausePeriods.map(\.timeRange).joined(separator: " · ")
        let status = autoLockPaused ? t("auto_lock_paused", "Auto-lock paused") : t("pause_periods", "Auto-Lock Pause Schedule")
        heroPauseScheduleLabel.stringValue = ranges.isEmpty ? "" : "\(status)  \(ranges)"
        heroPauseScheduleLabel.toolTip = ranges.isEmpty ? nil : heroPauseScheduleLabel.stringValue
        heroPauseScheduleLabel.textColor = autoLockPaused ? .systemOrange : .secondaryLabelColor
        heroPauseScheduleLabel.isHidden = ranges.isEmpty
        pauseScheduleSpacing?.constant = ranges.isEmpty ? 0 : 4
        hiddenPauseScheduleHeight?.isActive = ranges.isEmpty
    }

    // MARK: - NSPopoverDelegate

    func popoverWillShow(_ notification: Notification) {
        syncControlsFromState()
        update(devices: Array(ble.devices.values), monitoredUUID: ble.monitoredUUID)
        ble.startScanning()
        scanDot.isHidden = false
    }

    func popoverDidClose(_ notification: Notification) {
        ble.stopScanning()
    }

    // MARK: - View Construction

    override func loadView() {
        let root = PanelBackgroundView(frame: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.panelHeight))
        self.view = root

        // 1. Header Bar
        let headerBar = buildHeaderBar()
        // 2. Monitored Device Hero Card
        buildHeroCard()
        // 3. Tab Views
        buildDeviceTabView()
        buildSettingsTabView()
        // 4. Footer Bar
        let footerBar = buildFooterBar()

        tabContainer.translatesAutoresizingMaskIntoConstraints = false
        deviceTabView.translatesAutoresizingMaskIntoConstraints = false
        settingsTabView.translatesAutoresizingMaskIntoConstraints = false
        tabContainer.addSubview(deviceTabView)
        tabContainer.addSubview(settingsTabView)
        settingsTabView.isHidden = true

        for v in [headerBar, heroCard, tabContainer, footerBar] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }

        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: Self.panelWidth),
            root.heightAnchor.constraint(equalToConstant: Self.panelHeight),

            headerBar.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            headerBar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            headerBar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),

            heroCard.topAnchor.constraint(equalTo: headerBar.bottomAnchor, constant: 10),
            heroCard.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            heroCard.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),

            tabContainer.topAnchor.constraint(equalTo: heroCard.bottomAnchor, constant: 10),
            tabContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            tabContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            tabContainer.bottomAnchor.constraint(equalTo: footerBar.topAnchor, constant: -8),

            deviceTabView.topAnchor.constraint(equalTo: tabContainer.topAnchor),
            deviceTabView.leadingAnchor.constraint(equalTo: tabContainer.leadingAnchor),
            deviceTabView.trailingAnchor.constraint(equalTo: tabContainer.trailingAnchor),
            deviceTabView.bottomAnchor.constraint(equalTo: tabContainer.bottomAnchor),

            settingsTabView.topAnchor.constraint(equalTo: tabContainer.topAnchor),
            settingsTabView.leadingAnchor.constraint(equalTo: tabContainer.leadingAnchor),
            settingsTabView.trailingAnchor.constraint(equalTo: tabContainer.trailingAnchor),
            settingsTabView.bottomAnchor.constraint(equalTo: tabContainer.bottomAnchor),

            footerBar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            footerBar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            footerBar.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            footerBar.heightAnchor.constraint(equalToConstant: 24)
        ])

        syncControlsFromState()
        refreshHeroCard()
    }

    private func buildHeaderBar() -> NSView {
        let bar = NSView()
        let titleLabel = NSTextField(labelWithString: "BLEUnlock")
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .bold)

        scanDot.wantsLayer = true
        scanDot.layer?.cornerRadius = 3.5
        scanDot.layer?.backgroundColor = NSColor.systemBlue.cgColor

        scanStatusLabel.font = NSFont.systemFont(ofSize: 11)
        scanStatusLabel.textColor = .secondaryLabelColor
        scanStatusLabel.stringValue = t("scanning", "扫描中…")

        tabSwitcher.segmentCount = 2
        tabSwitcher.setLabel(t("device", "设备列表"), forSegment: 0)
        tabSwitcher.setLabel(t("rules_and_settings", "规则设置"), forSegment: 1)
        tabSwitcher.selectedSegment = 0
        tabSwitcher.segmentStyle = .rounded
        tabSwitcher.target = self
        tabSwitcher.action = #selector(tabChanged)

        for v in [titleLabel, scanDot, scanStatusLabel, tabSwitcher] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview(v)
        }

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),

            scanDot.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            scanDot.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            scanDot.widthAnchor.constraint(equalToConstant: 7),
            scanDot.heightAnchor.constraint(equalToConstant: 7),

            scanStatusLabel.leadingAnchor.constraint(equalTo: scanDot.trailingAnchor, constant: 5),
            scanStatusLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),

            tabSwitcher.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            tabSwitcher.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            tabSwitcher.topAnchor.constraint(equalTo: bar.topAnchor),
            tabSwitcher.bottomAnchor.constraint(equalTo: bar.bottomAnchor)
        ])
        return bar
    }

    private func buildHeroCard() {
        heroCard.cornerRadius = 10

        heroDot.wantsLayer = true
        heroDot.layer?.cornerRadius = 4.5
        heroDot.layer?.backgroundColor = NSColor.systemGray.cgColor

        heroNameLabel.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        heroNameLabel.textColor = .labelColor
        heroNameLabel.lineBreakMode = .byTruncatingTail
        heroNameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        heroModeBadge.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)
        heroModeBadge.wantsLayer = true
        heroModeBadge.layer?.cornerRadius = 4
        heroModeBadge.alignment = .center
        heroModeBadge.setContentHuggingPriority(.required, for: .horizontal)

        heroMetaLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        heroMetaLabel.textColor = NSColor.labelColor.withAlphaComponent(0.8)
        heroMetaLabel.lineBreakMode = .byTruncatingTail

        lockNowButton.title = "🔒 " + t("lock_now", "立刻锁定屏幕")
        lockNowButton.bezelStyle = .rounded
        lockNowButton.controlSize = .small
        lockNowButton.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        lockNowButton.target = self
        lockNowButton.action = #selector(handleLockNow)
        lockNowButton.setContentHuggingPriority(.required, for: .horizontal)

        heroStateLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
        heroRSSILabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        heroRSSILabel.textColor = .labelColor
        heroRSSILabel.alignment = .right
        heroPauseScheduleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        heroPauseScheduleLabel.lineBreakMode = .byTruncatingTail

        let farLabel = NSTextField(labelWithString: "-100 dBm")
        farLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        farLabel.textColor = .secondaryLabelColor

        lockScaleLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        lockScaleLabel.textColor = .systemOrange

        unlockScaleLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        unlockScaleLabel.textColor = .systemBlue

        let nearLabel = NSTextField(labelWithString: "-30 dBm")
        nearLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        nearLabel.textColor = .secondaryLabelColor

        let scaleRow = NSStackView(views: [farLabel, lockScaleLabel, unlockScaleLabel, nearLabel])
        scaleRow.orientation = .horizontal
        scaleRow.distribution = .equalSpacing

        for v in [heroDot, heroNameLabel, heroModeBadge, heroMetaLabel, lockNowButton, heroStateLabel, heroRSSILabel, signalGauge, scaleRow, heroPauseScheduleLabel] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            heroCard.addSubview(v)
        }

        let scheduleSpacing = heroPauseScheduleLabel.topAnchor.constraint(equalTo: scaleRow.bottomAnchor)
        pauseScheduleSpacing = scheduleSpacing
        hiddenPauseScheduleHeight = heroPauseScheduleLabel.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            heroDot.leadingAnchor.constraint(equalTo: heroCard.leadingAnchor, constant: 12),
            heroDot.centerYAnchor.constraint(equalTo: heroNameLabel.centerYAnchor),
            heroDot.widthAnchor.constraint(equalToConstant: 9),
            heroDot.heightAnchor.constraint(equalToConstant: 9),

            heroNameLabel.topAnchor.constraint(equalTo: heroCard.topAnchor, constant: 10),
            heroNameLabel.leadingAnchor.constraint(equalTo: heroDot.trailingAnchor, constant: 7),

            heroModeBadge.centerYAnchor.constraint(equalTo: heroNameLabel.centerYAnchor),
            heroModeBadge.leadingAnchor.constraint(equalTo: heroNameLabel.trailingAnchor, constant: 6),
            heroModeBadge.trailingAnchor.constraint(lessThanOrEqualTo: lockNowButton.leadingAnchor, constant: -8),

            lockNowButton.topAnchor.constraint(equalTo: heroCard.topAnchor, constant: 8),
            lockNowButton.trailingAnchor.constraint(equalTo: heroCard.trailingAnchor, constant: -10),

            heroMetaLabel.topAnchor.constraint(equalTo: heroNameLabel.bottomAnchor, constant: 3),
            heroMetaLabel.leadingAnchor.constraint(equalTo: heroNameLabel.leadingAnchor),
            heroMetaLabel.trailingAnchor.constraint(equalTo: heroCard.trailingAnchor, constant: -12),

            heroStateLabel.topAnchor.constraint(equalTo: heroMetaLabel.bottomAnchor, constant: 8),
            heroStateLabel.leadingAnchor.constraint(equalTo: heroCard.leadingAnchor, constant: 12),

            heroRSSILabel.centerYAnchor.constraint(equalTo: heroStateLabel.centerYAnchor),
            heroRSSILabel.trailingAnchor.constraint(equalTo: heroCard.trailingAnchor, constant: -12),
            heroRSSILabel.leadingAnchor.constraint(greaterThanOrEqualTo: heroStateLabel.trailingAnchor, constant: 8),

            signalGauge.topAnchor.constraint(equalTo: heroStateLabel.bottomAnchor, constant: 5),
            signalGauge.leadingAnchor.constraint(equalTo: heroCard.leadingAnchor, constant: 12),
            signalGauge.trailingAnchor.constraint(equalTo: heroCard.trailingAnchor, constant: -12),
            signalGauge.heightAnchor.constraint(equalToConstant: 8),

            scaleRow.topAnchor.constraint(equalTo: signalGauge.bottomAnchor, constant: 4),
            scaleRow.leadingAnchor.constraint(equalTo: signalGauge.leadingAnchor),
            scaleRow.trailingAnchor.constraint(equalTo: signalGauge.trailingAnchor),
            scheduleSpacing,
            heroPauseScheduleLabel.leadingAnchor.constraint(equalTo: scaleRow.leadingAnchor),
            heroPauseScheduleLabel.trailingAnchor.constraint(equalTo: scaleRow.trailingAnchor),
            heroPauseScheduleLabel.bottomAnchor.constraint(equalTo: heroCard.bottomAnchor, constant: -9)
        ])
        refreshPauseScheduleLabel()
    }

    private func buildDeviceTabView() {
        searchField.placeholderString = t("search_devices_placeholder", "搜索名称 / 机型 / 版本号 / 序列号后6位…")
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchChanged)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("deviceCard"))
        column.title = ""
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = 52
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.target = self
        tableView.action = #selector(deviceRowClicked)
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = tableView

        emptyStateLabel.font = NSFont.systemFont(ofSize: 12)
        emptyStateLabel.textColor = .secondaryLabelColor
        emptyStateLabel.alignment = .center

        for v in [searchField, scrollView, emptyStateLabel] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            deviceTabView.addSubview(v)
        }

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: deviceTabView.topAnchor),
            searchField.leadingAnchor.constraint(equalTo: deviceTabView.leadingAnchor),
            searchField.trailingAnchor.constraint(equalTo: deviceTabView.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: deviceTabView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: deviceTabView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: deviceTabView.bottomAnchor),

            emptyStateLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor)
        ])
    }

    private func makeSettingsSectionBox() -> NSView {
        let box = CardSurfaceView()
        box.cornerRadius = 8
        box.translatesAutoresizingMaskIntoConstraints = false
        return box
    }

    private func buildSettingsTabView() {
        // Section 1: Distance & Timing Thresholds
        let thresholdBox = makeSettingsSectionBox()

        unlockEnableCheck.title = "🔓 " + t("unlock_rssi", "解锁 RSSI")
        unlockEnableCheck.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        unlockEnableCheck.target = self
        unlockEnableCheck.action = #selector(unlockEnableToggled)

        unlockValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        unlockValueLabel.textColor = .systemBlue
        unlockValueLabel.alignment = .right

        unlockSlider.numberOfTickMarks = 14
        unlockSlider.allowsTickMarkValuesOnly = true
        unlockSlider.isContinuous = true
        unlockSlider.target = self
        unlockSlider.action = #selector(unlockSliderChanged)

        lockEnableCheck.title = "🔒 " + t("lock_rssi", "锁定 RSSI")
        lockEnableCheck.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        lockEnableCheck.target = self
        lockEnableCheck.action = #selector(lockEnableToggled)

        lockValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        lockValueLabel.textColor = .systemOrange
        lockValueLabel.alignment = .right

        lockSlider.numberOfTickMarks = 14
        lockSlider.allowsTickMarkValuesOnly = true
        lockSlider.isContinuous = true
        lockSlider.target = self
        lockSlider.action = #selector(lockSliderChanged)

        let delayTitle = NSTextField(labelWithString: t("lock_delay", "Lock after moving away"))
        delayTitle.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        delayTitle.textColor = .secondaryLabelColor
        let delayHint = t("lock_delay_hint", "How long to wait before locking when the device moves out of range.")
        delayTitle.toolTip = delayHint
        delayTitle.maximumNumberOfLines = 1
        delayTitle.lineBreakMode = .byTruncatingTail

        let delayLabels = ["2s", "5s", "15s", "30s", "1m", "2m", "5m"]
        delaySegmented.segmentCount = delayLabels.count
        for (index, label) in delayLabels.enumerated() {
            delaySegmented.setLabel(label, forSegment: index)
        }
        delaySegmented.controlSize = .small
        delaySegmented.font = NSFont.systemFont(ofSize: 11)
        delaySegmented.setAccessibilityLabel(delayTitle.stringValue)
        delaySegmented.toolTip = delayHint
        delaySegmented.target = self
        delaySegmented.action = #selector(delaySegmentChanged)

        let timeoutTitle = NSTextField(labelWithString: t("timeout", "无信号超时"))
        timeoutTitle.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        timeoutTitle.textColor = .secondaryLabelColor
        timeoutTitle.maximumNumberOfLines = 1
        timeoutTitle.lineBreakMode = .byTruncatingTail

        let timeoutLabels = ["30s", "1m", "2m", "5m", "10m"]
        timeoutSegmented.segmentCount = timeoutLabels.count
        for (i, lbl) in timeoutLabels.enumerated() {
            timeoutSegmented.setLabel(lbl, forSegment: i)
        }
        timeoutSegmented.controlSize = .small
        timeoutSegmented.font = NSFont.systemFont(ofSize: 11)
        timeoutSegmented.setAccessibilityLabel(timeoutTitle.stringValue)
        timeoutSegmented.target = self
        timeoutSegmented.action = #selector(timeoutSegmentChanged)

        for control in [unlockSlider, lockSlider, delaySegmented, timeoutSegmented] as [NSControl] {
            control.setContentCompressionResistancePriority(.required, for: .vertical)
        }

        for v in [unlockEnableCheck, unlockValueLabel, unlockSlider, lockEnableCheck, lockValueLabel, lockSlider, delayTitle, delaySegmented, timeoutTitle, timeoutSegmented] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            thresholdBox.addSubview(v)
        }

        NSLayoutConstraint.activate([
            unlockEnableCheck.topAnchor.constraint(equalTo: thresholdBox.topAnchor, constant: 16),
            unlockEnableCheck.leadingAnchor.constraint(equalTo: thresholdBox.leadingAnchor, constant: 16),

            unlockValueLabel.centerYAnchor.constraint(equalTo: unlockEnableCheck.centerYAnchor),
            unlockValueLabel.trailingAnchor.constraint(equalTo: thresholdBox.trailingAnchor, constant: -16),

            unlockSlider.topAnchor.constraint(equalTo: unlockEnableCheck.bottomAnchor, constant: 8),
            unlockSlider.leadingAnchor.constraint(equalTo: unlockEnableCheck.leadingAnchor),
            unlockSlider.trailingAnchor.constraint(equalTo: unlockValueLabel.trailingAnchor),

            lockEnableCheck.topAnchor.constraint(equalTo: unlockSlider.bottomAnchor, constant: 16),
            lockEnableCheck.leadingAnchor.constraint(equalTo: unlockEnableCheck.leadingAnchor),

            lockValueLabel.centerYAnchor.constraint(equalTo: lockEnableCheck.centerYAnchor),
            lockValueLabel.trailingAnchor.constraint(equalTo: unlockValueLabel.trailingAnchor),

            lockSlider.topAnchor.constraint(equalTo: lockEnableCheck.bottomAnchor, constant: 8),
            lockSlider.leadingAnchor.constraint(equalTo: unlockSlider.leadingAnchor),
            lockSlider.trailingAnchor.constraint(equalTo: unlockSlider.trailingAnchor),

            delayTitle.leadingAnchor.constraint(equalTo: unlockEnableCheck.leadingAnchor),
            delayTitle.centerYAnchor.constraint(equalTo: delaySegmented.centerYAnchor),
            delayTitle.trailingAnchor.constraint(lessThanOrEqualTo: delaySegmented.leadingAnchor, constant: -12),

            delaySegmented.topAnchor.constraint(equalTo: lockSlider.bottomAnchor, constant: 20),
            delaySegmented.trailingAnchor.constraint(equalTo: unlockValueLabel.trailingAnchor),

            timeoutTitle.leadingAnchor.constraint(equalTo: delayTitle.leadingAnchor),
            timeoutTitle.centerYAnchor.constraint(equalTo: timeoutSegmented.centerYAnchor),
            timeoutTitle.trailingAnchor.constraint(lessThanOrEqualTo: timeoutSegmented.leadingAnchor, constant: -12),

            timeoutSegmented.topAnchor.constraint(equalTo: delaySegmented.bottomAnchor, constant: 22),
            timeoutSegmented.bottomAnchor.constraint(equalTo: thresholdBox.bottomAnchor, constant: -22),
            timeoutSegmented.trailingAnchor.constraint(equalTo: delaySegmented.trailingAnchor)
        ])

        // Section 2: Two-column Wake/Unlock & Lock Behavior
        let behaviorBox = makeSettingsSectionBox()

        wakeOnProximityCheck.title = t("wake_on_proximity", "靠近唤醒")
        wakeOnProximityCheck.font = NSFont.systemFont(ofSize: 12)
        wakeOnProximityCheck.target = self
        wakeOnProximityCheck.action = #selector(togglePrefCheckbox(_:))

        wakeWithoutUnlockCheck.title = t("wake_without_unlocking", "唤醒时不需解锁")
        wakeWithoutUnlockCheck.font = NSFont.systemFont(ofSize: 12)
        wakeWithoutUnlockCheck.target = self
        wakeWithoutUnlockCheck.action = #selector(togglePrefCheckbox(_:))

        passwordStatusLabel.font = NSFont.systemFont(ofSize: 11.5)
        setPasswordButton.title = t("set_password", "设置密码…")
        setPasswordButton.bezelStyle = .rounded
        setPasswordButton.controlSize = .small
        setPasswordButton.font = NSFont.systemFont(ofSize: 11)
        setPasswordButton.target = self
        setPasswordButton.action = #selector(handleSetPassword)

        pauseMediaCheck.title = t("pause_now_playing", "锁定时暂停\"播放中\"")
        pauseMediaCheck.font = NSFont.systemFont(ofSize: 12)
        pauseMediaCheck.target = self
        pauseMediaCheck.action = #selector(togglePrefCheckbox(_:))

        sleepDisplayCheck.title = t("sleep_display", "锁定时关闭屏幕")
        sleepDisplayCheck.font = NSFont.systemFont(ofSize: 12)
        sleepDisplayCheck.target = self
        sleepDisplayCheck.action = #selector(togglePrefCheckbox(_:))

        screensaverCheck.title = t("use_screensaver_to_lock", "开启屏保")
        screensaverCheck.font = NSFont.systemFont(ofSize: 12)
        screensaverCheck.target = self
        screensaverCheck.action = #selector(togglePrefCheckbox(_:))

        autoApproveAuthorizationCheck.title = t("auto_approve_authorization", "自动批准管理员授权")
        autoApproveAuthorizationCheck.font = NSFont.systemFont(ofSize: 11)
        autoApproveAuthorizationCheck.toolTip = t("auto_approve_authorization_hint", "仅在已选蓝牙设备靠近且系统授权弹窗等待输入密码时生效。")
        autoApproveAuthorizationCheck.target = self
        autoApproveAuthorizationCheck.action = #selector(togglePrefCheckbox(_:))
        authorizationAppsButton.bezelStyle = .rounded
        authorizationAppsButton.controlSize = .small
        authorizationAppsButton.font = .systemFont(ofSize: 10)
        authorizationAppsButton.target = self
        authorizationAppsButton.action = #selector(editAuthorizationApps)
        let authorizationRow = NSStackView(views: [autoApproveAuthorizationCheck, authorizationAppsButton])
        authorizationRow.orientation = .horizontal
        authorizationRow.alignment = .centerY
        authorizationRow.spacing = 4

        let leftStack = NSStackView(views: [wakeOnProximityCheck, wakeWithoutUnlockCheck, passwordStatusLabel, setPasswordButton])
        leftStack.orientation = .vertical
        leftStack.alignment = .leading
        leftStack.spacing = 6

        let rightStack = NSStackView(views: [pauseMediaCheck, sleepDisplayCheck, screensaverCheck, authorizationRow])
        rightStack.orientation = .vertical
        rightStack.alignment = .leading
        rightStack.spacing = 6

        for v in [leftStack, rightStack] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            behaviorBox.addSubview(v)
        }

        NSLayoutConstraint.activate([
            leftStack.topAnchor.constraint(equalTo: behaviorBox.topAnchor, constant: 9),
            leftStack.leadingAnchor.constraint(equalTo: behaviorBox.leadingAnchor, constant: 10),
            leftStack.bottomAnchor.constraint(lessThanOrEqualTo: behaviorBox.bottomAnchor, constant: -9),
            leftStack.widthAnchor.constraint(equalTo: behaviorBox.widthAnchor, multiplier: 0.48),

            rightStack.topAnchor.constraint(equalTo: behaviorBox.topAnchor, constant: 9),
            rightStack.leadingAnchor.constraint(equalTo: leftStack.trailingAnchor, constant: 8),
            rightStack.trailingAnchor.constraint(equalTo: behaviorBox.trailingAnchor, constant: -10),
            rightStack.bottomAnchor.constraint(lessThanOrEqualTo: behaviorBox.bottomAnchor, constant: -9)
        ])

        // Section 3: System & Scan Bar
        let systemBox = makeSettingsSectionBox()

        passiveModeCheck.title = t("passive_mode", "被动模式")
        passiveModeCheck.font = NSFont.systemFont(ofSize: 12)
        passiveModeCheck.target = self
        passiveModeCheck.action = #selector(togglePrefCheckbox(_:))

        minRSSIButton.bezelStyle = .rounded
        minRSSIButton.controlSize = .small
        minRSSIButton.font = NSFont.systemFont(ofSize: 11)
        minRSSIButton.target = self
        minRSSIButton.action = #selector(handleSetMinimumRSSI)

        launchAtLoginCheck.title = t("launch_at_login", "开机启动")
        launchAtLoginCheck.font = NSFont.systemFont(ofSize: 12)
        launchAtLoginCheck.target = self
        launchAtLoginCheck.action = #selector(togglePrefCheckbox(_:))

        for v in [passiveModeCheck, minRSSIButton, launchAtLoginCheck] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            systemBox.addSubview(v)
        }

        NSLayoutConstraint.activate([
            passiveModeCheck.leadingAnchor.constraint(equalTo: systemBox.leadingAnchor, constant: 10),
            passiveModeCheck.centerYAnchor.constraint(equalTo: systemBox.centerYAnchor),

            minRSSIButton.centerXAnchor.constraint(equalTo: systemBox.centerXAnchor),
            minRSSIButton.centerYAnchor.constraint(equalTo: systemBox.centerYAnchor),

            launchAtLoginCheck.trailingAnchor.constraint(equalTo: systemBox.trailingAnchor, constant: -10),
            launchAtLoginCheck.centerYAnchor.constraint(equalTo: systemBox.centerYAnchor),

            systemBox.heightAnchor.constraint(equalToConstant: 34)
        ])

        let preferencesBox = makeSettingsSectionBox()
        let scheduleButton = NSButton(title: t("pause_periods_button", "Auto-Lock Schedule…"),
                                      target: self, action: #selector(handlePauseSchedule))
        let aboutButton = NSButton(title: t("about", "About BLEUnlock"),
                                   target: self, action: #selector(handleAbout))
        for button in [scheduleButton, aboutButton] {
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.font = .systemFont(ofSize: 11)
        }
        hideMenuBarIconCheck.title = t("hide_menu_bar_icon", "Hide Menu Bar Icon")
        hideMenuBarIconCheck.toolTip = t("hide_menu_bar_icon_hint", "Reopen BLEUnlock from Finder or Spotlight to open Settings below the menu bar icon.")
        hideMenuBarIconCheck.font = .systemFont(ofSize: 12)
        hideMenuBarIconCheck.target = self
        hideMenuBarIconCheck.action = #selector(togglePrefCheckbox(_:))

        let preferences = NSStackView(views: [scheduleButton, hideMenuBarIconCheck, aboutButton])
        preferences.alignment = .centerY
        preferences.distribution = .equalSpacing
        preferences.spacing = 6
        preferences.translatesAutoresizingMaskIntoConstraints = false
        preferencesBox.addSubview(preferences)

        for v in [thresholdBox, behaviorBox, systemBox, preferencesBox] {
            settingsTabView.addSubview(v)
        }

        NSLayoutConstraint.activate([
            thresholdBox.topAnchor.constraint(equalTo: settingsTabView.topAnchor),
            thresholdBox.leadingAnchor.constraint(equalTo: settingsTabView.leadingAnchor),
            thresholdBox.trailingAnchor.constraint(equalTo: settingsTabView.trailingAnchor),

            behaviorBox.topAnchor.constraint(equalTo: thresholdBox.bottomAnchor, constant: 8),
            behaviorBox.leadingAnchor.constraint(equalTo: settingsTabView.leadingAnchor),
            behaviorBox.trailingAnchor.constraint(equalTo: settingsTabView.trailingAnchor),

            systemBox.topAnchor.constraint(equalTo: behaviorBox.bottomAnchor, constant: 8),
            systemBox.leadingAnchor.constraint(equalTo: settingsTabView.leadingAnchor),
            systemBox.trailingAnchor.constraint(equalTo: settingsTabView.trailingAnchor),
            preferencesBox.topAnchor.constraint(equalTo: systemBox.bottomAnchor, constant: 8),
            preferencesBox.leadingAnchor.constraint(equalTo: settingsTabView.leadingAnchor),
            preferencesBox.trailingAnchor.constraint(equalTo: settingsTabView.trailingAnchor),
            preferencesBox.bottomAnchor.constraint(lessThanOrEqualTo: settingsTabView.bottomAnchor, constant: -12),
            preferencesBox.heightAnchor.constraint(equalToConstant: 34),
            preferences.leadingAnchor.constraint(equalTo: preferencesBox.leadingAnchor, constant: 10),
            preferences.trailingAnchor.constraint(equalTo: preferencesBox.trailingAnchor, constant: -10),
            preferences.centerYAnchor.constraint(equalTo: preferencesBox.centerYAnchor)
        ])
    }

    private func buildFooterBar() -> NSView {
        let bar = NSView()
        footerCountLabel.font = NSFont.systemFont(ofSize: 11)
        footerCountLabel.textColor = .secondaryLabelColor

        let quitButton = NSButton(title: t("quit", "退出 BLEUnlock"), target: self, action: #selector(handleQuit))
        quitButton.isBordered = false
        quitButton.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        quitButton.contentTintColor = .systemRed

        for v in [footerCountLabel, quitButton] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview(v)
        }

        NSLayoutConstraint.activate([
            footerCountLabel.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            footerCountLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),

            quitButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            quitButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor)
        ])
        return bar
    }

    // MARK: - Live State & Data Updates

    func update(devices: [Device], monitoredUUID: UUID?) {
        var allDevices = devices
        if let monitoredUUID = monitoredUUID, !allDevices.contains(where: { $0.uuid == monitoredUUID }) {
            let monitoredDevice = Device(uuid: monitoredUUID)
            monitoredDevice.peripheral = ble.monitoredPeripheral
            monitoredDevice.rssi = liveRSSI ?? -60
            allDevices.append(monitoredDevice)
        }
        entries = allDevices.map { DeviceListEntry(device: $0, monitoredUUID: monitoredUUID) }.sorted {
            if $0.isMonitored != $1.isMonitored {
                return $0.isMonitored && !$1.isMonitored
            }
            if $0.rssi != $1.rssi {
                return $0.rssi > $1.rssi
            }
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id.uuidString < $1.id.uuidString : order == .orderedAscending
        }
        guard isViewLoaded else { return }
        applySearch()
        refreshHeroCard()
    }

    func updateMonitoredRSSI(rssi: Int?, active: Bool) {
        liveRSSI = rssi
        liveActiveMode = active
        guard isViewLoaded else { return }
        if popover.isShown {
            update(devices: Array(ble.devices.values), monitoredUUID: ble.monitoredUUID)
        } else {
            refreshHeroCard()
        }
    }

    func syncControlsFromState() {
        guard isViewLoaded else { return }

        // Unlock RSSI
        let unlockDisabled = (ble.unlockRSSI == ble.UNLOCK_DISABLED)
        unlockEnableCheck.state = unlockDisabled ? .off : .on
        unlockSlider.isEnabled = !unlockDisabled
        if !unlockDisabled {
            unlockSlider.integerValue = ble.unlockRSSI
            unlockValueLabel.stringValue = "\(ble.unlockRSSI) dBm"
        } else {
            unlockValueLabel.stringValue = t("disabled", "禁用")
        }

        // Lock RSSI
        let lockDisabled = (ble.lockRSSI == ble.LOCK_DISABLED)
        lockEnableCheck.state = lockDisabled ? .off : .on
        lockSlider.isEnabled = !lockDisabled
        if !lockDisabled {
            lockSlider.integerValue = ble.lockRSSI
            lockValueLabel.stringValue = "\(ble.lockRSSI) dBm"
        } else {
            lockValueLabel.stringValue = t("disabled", "禁用")
        }

        // Delay & Timeout
        delaySegmented.selectedSegment = delayValues.firstIndex(of: Int(ble.proximityTimeout)) ?? -1
        if let timeoutIdx = timeoutValues.firstIndex(of: Int(ble.signalTimeout)) {
            timeoutSegmented.selectedSegment = timeoutIdx
        }

        // Toggles
        wakeOnProximityCheck.state = prefs.bool(forKey: "wakeOnProximity") ? .on : .off
        wakeWithoutUnlockCheck.state = prefs.bool(forKey: "wakeWithoutUnlocking") ? .on : .off
        pauseMediaCheck.state = prefs.bool(forKey: "pauseItunes") ? .on : .off
        sleepDisplayCheck.state = prefs.bool(forKey: "sleepDisplay") ? .on : .off
        screensaverCheck.state = prefs.bool(forKey: "screensaver") ? .on : .off
        autoApproveAuthorizationCheck.state = prefs.bool(forKey: "autoApproveAuthorization") ? .on : .off
        let allowedApps = prefs.stringArray(forKey: "authorizationAllowedApps") ?? []
        authorizationAppsButton.title = allowedApps.isEmpty
            ? t("authorization_all_apps", "全部…")
            : t("authorization_list_apps", "名单…")
        passiveModeCheck.state = prefs.bool(forKey: "passiveMode") ? .on : .off
        launchAtLoginCheck.state = prefs.bool(forKey: "launchAtLogin") ? .on : .off
        hideMenuBarIconCheck.state = prefs.bool(forKey: "hideMenuBarIcon") ? .on : .off

        let pwStored = hasStoredPassword?() ?? false
        passwordStatusLabel.stringValue = pwStored
            ? "🔑 " + t("password_configured", "钥匙串密码已设置")
            : "⚠️ " + t("password_not_set", "密码未设置")
        passwordStatusLabel.textColor = pwStored ? .systemGreen : .systemOrange

        minRSSIButton.title = "\(t("set_rssi_threshold", "设置最小RSSI…")) (\(ble.thresholdRSSI) dBm)"
        refreshHeroCard()
    }

    private func refreshHeroCard() {
        guard isViewLoaded else { return }

        let unlockDisabled = (ble.unlockRSSI == ble.UNLOCK_DISABLED)
        let lockDisabled = (ble.lockRSSI == ble.LOCK_DISABLED)

        signalGauge.unlockDisabled = unlockDisabled
        signalGauge.lockDisabled = lockDisabled
        signalGauge.unlockRSSI = ble.unlockRSSI
        signalGauge.lockRSSI = ble.lockRSSI
        signalGauge.rssi = liveRSSI

        lockScaleLabel.stringValue = lockDisabled ? "🔒 \(t("disabled", "禁用"))" : "🔒 \(ble.lockRSSI) dBm"
        unlockScaleLabel.stringValue = unlockDisabled ? "🔓 \(t("disabled", "禁用"))" : "🔓 \(ble.unlockRSSI) dBm"

        let monitoredEntry = entries.first(where: { $0.isMonitored })
        if let uuid = ble.monitoredUUID {
            heroNameLabel.stringValue = monitoredEntry?.name ?? uuid.uuidString
            heroMetaLabel.stringValue = monitoredEntry?.subtitleText ?? "\(t("id_last6", "ID末6位")) \(String(uuid.uuidString.suffix(6)))"
        } else {
            heroNameLabel.stringValue = t("device_not_set", "未选择设备")
            heroMetaLabel.stringValue = t("click_device_below_hint", "请在下方设备列表中点击选择要监控的蓝牙设备")
        }

        if let r = liveRSSI {
            heroRSSILabel.stringValue = "\(r) dBm"
            let modeText = prefs.bool(forKey: "passiveMode") ? " Passive " : (liveActiveMode ? " Active " : " Scanning ")
            heroModeBadge.stringValue = modeText
            heroModeBadge.isHidden = false
            heroModeBadge.textColor = .systemGreen
            heroModeBadge.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.15).cgColor

            if !unlockDisabled && r >= ble.unlockRSSI {
                heroDot.layer?.backgroundColor = NSColor.systemGreen.cgColor
                heroStateLabel.textColor = .systemGreen
                heroStateLabel.stringValue = "● " + t("status_in_unlock_range", "在解锁范围内（靠近）")
            } else if !lockDisabled && r < ble.lockRSSI {
                heroDot.layer?.backgroundColor = NSColor.systemRed.cgColor
                heroStateLabel.textColor = .systemRed
                heroStateLabel.stringValue = "● " + t("status_out_of_lock_range", "已超出锁定阈值（远离）")
            } else {
                heroDot.layer?.backgroundColor = NSColor.systemOrange.cgColor
                heroStateLabel.textColor = .systemOrange
                heroStateLabel.stringValue = "● " + t("status_in_buffer_range", "缓冲区间（保持当前状态）")
            }
        } else {
            heroDot.layer?.backgroundColor = NSColor.systemRed.cgColor
            heroModeBadge.isHidden = true
            heroRSSILabel.stringValue = "—"
            heroStateLabel.textColor = .secondaryLabelColor
            heroStateLabel.stringValue = "● " + (ble.monitoredUUID == nil ? t("device_not_set", "未选择设备") : t("not_detected", "未检测到信号"))
        }
    }

    // MARK: - Search & TableView

    func controlTextDidChange(_ obj: Notification) {
        applySearch()
    }

    @objc private func searchChanged() {
        applySearch()
    }

    private func applySearch() {
        guard isViewLoaded else { return }
        let results = entries.filter { $0.matches(searchField.stringValue) }
        visibleEntries = results
        tableView.reloadData()

        if results.isEmpty {
            emptyStateLabel.stringValue = entries.isEmpty ? t("scanning", "扫描中…") : t("no_matching_devices", "没有匹配的设备")
            emptyStateLabel.isHidden = false
        } else {
            emptyStateLabel.isHidden = true
        }
        footerCountLabel.stringValue = "\(t("device", "设备列表")): \(results.count) · ≥ \(ble.thresholdRSSI) dBm"
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        visibleEntries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("DeviceCardRowView")
        let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? DeviceCardRowView) ?? DeviceCardRowView()
        cell.identifier = id
        let entry = visibleEntries[row]
        cell.configure(with: entry, unlockRSSI: ble.unlockRSSI, lockRSSI: ble.lockRSSI)
        return cell
    }

    @objc private func deviceRowClicked() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard visibleEntries.indices.contains(row) else { return }
        let chosen = visibleEntries[row]
        onChooseDevice?(chosen.id)
        update(devices: Array(ble.devices.values), monitoredUUID: chosen.id)
    }

    // MARK: - Actions

    @objc private func tabChanged() {
        let showDevices = (tabSwitcher.selectedSegment == 0)
        deviceTabView.isHidden = !showDevices
        settingsTabView.isHidden = showDevices
        if !showDevices {
            syncControlsFromState()
        }
    }

    @objc private func handleLockNow() {
        popover.performClose(nil)
        onLockNow?()
    }

    @objc private func unlockEnableToggled() {
        if unlockEnableCheck.state == .on {
            let defaultVal = max(ble.lockRSSI == ble.LOCK_DISABLED ? -60 : ble.lockRSSI, -60)
            ble.unlockRSSI = defaultVal
            prefs.set(defaultVal, forKey: "unlockRSSI")
        } else {
            ble.unlockRSSI = ble.UNLOCK_DISABLED
            prefs.set(ble.UNLOCK_DISABLED, forKey: "unlockRSSI")
        }
        syncControlsFromState()
        tableView.reloadData()
    }

    @objc private func lockEnableToggled() {
        if lockEnableCheck.state == .on {
            let defaultVal = min(ble.unlockRSSI == ble.UNLOCK_DISABLED ? -80 : ble.unlockRSSI, -80)
            ble.lockRSSI = defaultVal
            prefs.set(defaultVal, forKey: "lockRSSI")
        } else {
            ble.lockRSSI = ble.LOCK_DISABLED
            prefs.set(ble.LOCK_DISABLED, forKey: "lockRSSI")
        }
        syncControlsFromState()
        tableView.reloadData()
    }

    @objc private func unlockSliderChanged() {
        let stepped = Int(round(unlockSlider.doubleValue / 5.0) * 5.0)
        ble.unlockRSSI = stepped
        prefs.set(stepped, forKey: "unlockRSSI")
        if ble.lockRSSI != ble.LOCK_DISABLED && ble.lockRSSI > stepped {
            ble.lockRSSI = stepped
            prefs.set(stepped, forKey: "lockRSSI")
        }
        syncControlsFromState()
        tableView.reloadData()
    }

    @objc private func lockSliderChanged() {
        let stepped = Int(round(lockSlider.doubleValue / 5.0) * 5.0)
        ble.lockRSSI = stepped
        prefs.set(stepped, forKey: "lockRSSI")
        if ble.unlockRSSI != ble.UNLOCK_DISABLED && ble.unlockRSSI < stepped {
            ble.unlockRSSI = stepped
            prefs.set(stepped, forKey: "unlockRSSI")
        }
        syncControlsFromState()
        tableView.reloadData()
    }

    @objc private func delaySegmentChanged() {
        let index = delaySegmented.selectedSegment
        guard delayValues.indices.contains(index) else { return }
        let val = delayValues[index]
        prefs.set(val, forKey: "lockDelay")
        ble.proximityTimeout = Double(val)
    }

    @objc private func timeoutSegmentChanged() {
        let idx = timeoutSegmented.selectedSegment
        guard timeoutValues.indices.contains(idx) else { return }
        let val = timeoutValues[idx]
        prefs.set(val, forKey: "timeout")
        ble.signalTimeout = Double(val)
    }

    @objc private func togglePrefCheckbox(_ sender: NSButton) {
        let isOn = (sender.state == .on)
        switch sender {
        case wakeOnProximityCheck:
            prefs.set(isOn, forKey: "wakeOnProximity")
        case wakeWithoutUnlockCheck:
            prefs.set(isOn, forKey: "wakeWithoutUnlocking")
        case pauseMediaCheck:
            prefs.set(isOn, forKey: "pauseItunes")
        case sleepDisplayCheck:
            prefs.set(isOn, forKey: "sleepDisplay")
        case screensaverCheck:
            prefs.set(isOn, forKey: "screensaver")
        case autoApproveAuthorizationCheck:
            prefs.set(isOn, forKey: "autoApproveAuthorization")
            onAuthorizationSettingChanged?()
        case passiveModeCheck:
            prefs.set(isOn, forKey: "passiveMode")
            onTogglePassiveMode?(isOn)
            refreshHeroCard()
        case launchAtLoginCheck:
            prefs.set(isOn, forKey: "launchAtLogin")
            onToggleLaunchAtLogin?(isOn)
        case hideMenuBarIconCheck:
            onHideMenuBarIcon?(isOn)
            if isOn {
                popover.performClose(nil)
            }
        default:
            break
        }
    }

    @objc private func handleSetPassword() {
        onAskPassword?()
        syncControlsFromState()
    }

    @objc private func editAuthorizationApps() {
        popover.performClose(nil)
        let alert = NSAlert()
        alert.messageText = t("authorization_apps_title", "允许自动批准的程序")
        alert.informativeText = t("authorization_apps_hint", "留空表示全部程序。填写弹窗显示的程序名，用逗号分隔。Python 无法区分不同脚本。")
        alert.addButton(withTitle: t("ok"))
        alert.addButton(withTitle: t("cancel"))
        let field = NSTextField()
        field.stringValue = (prefs.stringArray(forKey: "authorizationAllowedApps") ?? []).joined(separator: ", ")
        field.placeholderString = t("authorization_apps_placeholder", "例如 Python, Installer")
        let accessory = FocusNeutralView(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        field.translatesAutoresizingMaskIntoConstraints = false
        accessory.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: accessory.leadingAnchor),
            field.trailingAnchor.constraint(equalTo: accessory.trailingAnchor),
            field.centerYAnchor.constraint(equalTo: accessory.centerYAnchor)
        ])
        accessory.nextKeyView = field
        alert.accessoryView = accessory
        alert.window.initialFirstResponder = accessory
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let names = field.stringValue
            .components(separatedBy: CharacterSet(charactersIn: ",，\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        prefs.set(Array(Set(names)).sorted(), forKey: "authorizationAllowedApps")
        onAuthorizationSettingChanged?()
        syncControlsFromState()
    }

    @objc private func handleSetMinimumRSSI() {
        onSetMinimumRSSI?()
        syncControlsFromState()
        applySearch()
    }

    @objc private func handleAbout() {
        popover.performClose(nil)
        onShowAbout?()
    }

    @objc private func handlePauseSchedule() {
        popover.performClose(nil)
        onEditPausePeriods?()
    }

    @objc private func handleQuit() {
        popover.performClose(nil)
        onQuit?()
    }
}
