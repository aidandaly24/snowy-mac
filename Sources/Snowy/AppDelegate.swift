import AppKit
import SnowCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSMenuDelegate {
    private var coordinator: DesktopCoordinator?
    private var statusItem: NSStatusItem?
    private let batteryItem = NSMenuItem(title: "Battery-Friendly Mode", action: #selector(toggleBattery), keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "Pause Snow", action: #selector(togglePause), keyEquivalent: "p")
    private let stateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var friendItems: [NSMenuItem] = []
    private var vibeItems: [NSMenuItem] = []
    private let vibeMenuItem = NSMenuItem(title: "This Desktop", action: nil, keyEquivalent: "")
    private var weatherItems: [NSMenuItem] = []
    private var windPopover: NSPopover?
    private var toolItems: [NSMenuItem] = []
    private var welcomeWindow: WelcomeWindowController?
    private var snowyWindow: SnowyWindowController?
    private let decorationSettings = DecorationSettings()
    private let updater = SnowyUpdater()
    private let updateItem = NSMenuItem(title: "Update", action: #selector(installUpdate), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Read the persisted domain before coordinator startup can write settings.
        let defaults = UserDefaults.standard
        let domainName = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        let shouldShowWelcome = FirstLaunchPolicy.shouldPresent(in: defaults, domainName: domainName)
        buildMenu()
        updater.onChange = { [weak self] in self?.updateAvailableRelease() }
        updater.start()
        do {
            let coordinator = try DesktopCoordinator(configuration: decorationSettings.configuration)
            self.coordinator = coordinator
            coordinator.onStateChange = { [weak self] in
                self?.synchronizeSettings()
                self?.updateMenu()
            }
            decorationSettings.onChange = { [weak coordinator] configuration in
                coordinator?.setDecorations(configuration)
            }
            decorationSettings.desktops = coordinator.editorDesktops
            decorationSettings.onEditorVisibility = { [weak coordinator] visible in
                coordinator?.setEditorVisible(visible)
            }
            coordinator.onDesktopGeometryChange = { [weak self] desktops in
                self?.decorationSettings.desktops = desktops
            }
            decorationSettings.onVibeChange = { [weak coordinator] in coordinator?.setVibe($0) }
            decorationSettings.onWeatherChange = { [weak coordinator] in coordinator?.setWeather($0, wind: $1) }
            decorationSettings.onFriendsChange = { [weak coordinator] in coordinator?.setFriends($0, count: $1) }
            decorationSettings.onLightSnowCatchChange = { [weak coordinator] in coordinator?.setLightSnowCatch($0) }
            decorationSettings.onBatteryChange = { [weak coordinator] in coordinator?.batteryFriendly = $0 }
            decorationSettings.onSaveVibe = { [weak coordinator] in coordinator?.saveCurrentVibe() ?? false }
            decorationSettings.onResetVibe = { [weak coordinator] in coordinator?.resetCurrentVibe() }
            decorationSettings.onToolChange = { [weak coordinator] in coordinator?.tool = $0 }
            decorationSettings.onClearSnow = { [weak coordinator] in coordinator?.clear() }
            decorationSettings.onResetPositions = { [weak coordinator] in coordinator?.resetDecorations() }
            synchronizeSettings()
        } catch {
            stateItem.title = "Metal is unavailable on this Mac"
            pauseItem.isEnabled = false
        }
        updateMenu()
        if coordinator != nil {
            FirstLaunchPolicy.markConsidered(in: defaults)
            if ProcessInfo.processInfo.arguments.contains("--settings") { presentSnowyWindow() }
            else if shouldShowWelcome { presentWelcome() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let welcomeWindow { welcomeWindow.present() }
        else { presentSnowyWindow() }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        welcomeWindow?.close()
        snowyWindow?.close()
        windPopover?.performClose(nil)
        coordinator?.stop()
    }

    private func buildMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "snowflake", accessibilityDescription: "Snowy")
        item.button?.image?.isTemplate = true
        item.button?.toolTip = "Snowy — desktop snowfall"
        statusItem = item
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        let title = NSMenuItem(title: "Snowy", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(.separator())
        let open = NSMenuItem(title: "Open Snowy…", action: #selector(openSnowyWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        let vibes = NSMenu(title: "This Desktop")
        vibes.autoenablesItems = false
        for (index, vibe) in DesktopVibe.allCases.enumerated() {
            let option = NSMenuItem(title: vibe.rawValue, action: #selector(selectVibe(_:)), keyEquivalent: "")
            option.tag = index
            option.target = self
            vibes.addItem(option)
            vibeItems.append(option)
        }
        let friendMenu = NSMenu(title: "Winter Friends")
        friendMenu.autoenablesItems = false
        for (index, kind) in WinterFriendKind.allCases.enumerated() {
            let option = NSMenuItem(title: kind.rawValue, action: #selector(selectFriend(_:)), keyEquivalent: "")
            option.tag = index
            option.target = self
            friendMenu.addItem(option)
            friendItems.append(option)
        }
        let friendItem = NSMenuItem(title: "Winter Friends", action: nil, keyEquivalent: "")
        friendItem.submenu = friendMenu
        vibeMenuItem.submenu = vibes
        menu.addItem(vibeMenuItem)
        menu.addItem(friendItem)
        batteryItem.target = self
        menu.addItem(batteryItem)
        menu.addItem(.separator())
        pauseItem.target = self
        menu.addItem(pauseItem)
        let clear = NSMenuItem(title: "Clear Settled Snow", action: #selector(clearSnow), keyEquivalent: "k")
        clear.target = self
        menu.addItem(clear)
        let tool = NSMenuItem(title: "Cursor Tool", action: nil, keyEquivalent: "")
        let tools = NSMenu(title: "Cursor Tool")
        tools.autoenablesItems = false
        for (index, tool) in SnowTool.allCases.enumerated() {
            let option = NSMenuItem(title: tool.rawValue, action: #selector(selectTool(_:)), keyEquivalent: "")
            option.tag = index
            option.target = self
            tools.addItem(option)
            toolItems.append(option)
        }
        tool.submenu = tools
        menu.addItem(tool)
        menu.addItem(.separator())
        for (index, snowfall) in Snowfall.allCases.enumerated() {
            let option = NSMenuItem(title: snowfall.rawValue, action: #selector(setSnowfall(_:)), keyEquivalent: "")
            option.target = self
            option.tag = index
            weatherItems.append(option)
            menu.addItem(option)
        }
        let wind = NSMenuItem(title: "Wind…", action: #selector(showWind), keyEquivalent: "w")
        wind.target = self
        menu.addItem(wind)
        menu.addItem(.separator())
        updateItem.target = self
        updateItem.isHidden = true
        updateItem.isEnabled = false
        menu.addItem(updateItem)
        let quit = NSMenuItem(title: "Quit Snowy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        item.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) { updateAvailableRelease() }

    private func updateAvailableRelease() {
        guard let version = updater.availableVersion else {
            updateItem.isHidden = true
            return
        }
        updateItem.attributedTitle = NSAttributedString(
            string: "Update to \(version)…",
            attributes: [.foregroundColor: NSColor.linkColor]
        )
        updateItem.isHidden = false
        updateItem.isEnabled = updater.canInstall
    }

    @objc private func installUpdate() { updater.install() }

    @objc private func openSnowyWindow() {
        DispatchQueue.main.async { [weak self] in self?.presentSnowyWindow() }
    }

    private func presentSnowyWindow() {
        if snowyWindow == nil {
            snowyWindow = SnowyWindowController(
                settings: decorationSettings,
                resetDecorations: { [weak self] in self?.coordinator?.resetDecorations() },
                replayWalkthrough: { [weak self] in self?.presentWelcome() }
            )
        }
        snowyWindow?.present()
    }

    private func presentWelcome() {
        if welcomeWindow == nil {
            let welcome = WelcomeWindowController()
            welcome.onClose = { [weak self] in self?.welcomeWindow = nil }
            welcomeWindow = welcome
        }
        welcomeWindow?.present()
    }

    private func synchronizeSettings() {
        guard let coordinator else { return }
        decorationSettings.load(coordinator.currentConfiguration)
        if decorationSettings.savedPresetAssets != coordinator.savedPresetAssets {
            decorationSettings.savedPresetAssets = coordinator.savedPresetAssets
        }
        decorationSettings.loadControls(vibe: coordinator.vibe, snowfall: coordinator.snowfall,
            wind: coordinator.wind, friendKind: coordinator.friendKind, friendCount: coordinator.friendCount,
            battery: coordinator.batteryFriendly, saved: coordinator.hasSavedVibe, tool: coordinator.tool,
            lightSnowCatch: coordinator.lightSnowCatch)
    }

    private func updateMenu() {
        guard let coordinator else { return }
        vibeMenuItem.title = "This Desktop: \(coordinator.vibe.rawValue)"
        for (index, item) in vibeItems.enumerated() {
            item.state = DesktopVibe.allCases[index] == coordinator.vibe ? .on : .off
        }
        for (index, item) in friendItems.enumerated() {
            item.state = WinterFriendKind.allCases[index] == coordinator.friendKind ? .on : .off
        }
        batteryItem.state = coordinator.batteryFriendly ? .on : .off
        pauseItem.title = coordinator.paused ? "Resume Snow" : "Pause Snow"
        if coordinator.failed { stateItem.title = "Rendering stopped — relaunch to retry" }
        else if coordinator.policy.suspended { stateItem.title = "Resting while your Mac cools down" }
        else if coordinator.paused { stateItem.title = "Snow is paused" }
        else if coordinator.batteryFriendly { stateItem.title = "Battery mode · settled snow and decorations" }
        else if coordinator.policy.reducedMotion { stateItem.title = "Quiet drifts · Reduce Motion" }
        else if coordinator.policy.particleScale < 1 { stateItem.title = "Gentle snowfall · saving energy" }
        else if coordinator.tool == .snowball { stateItem.title = "Hold Option, flick the pointer, release to throw" }
        else if coordinator.tool == .snowman { stateItem.title = "Hold Option on empty desktop to build a snowman" }
        else { stateItem.title = "Brush snow, or shake a window to shed its cap" }
        for (index, item) in weatherItems.enumerated() {
            item.state = Snowfall.allCases[index] == coordinator.snowfall ? .on : .off
        }
        for (index, item) in toolItems.enumerated() {
            item.state = SnowTool.allCases[index] == coordinator.tool ? .on : .off
        }
    }

    @objc private func toggleBattery() { coordinator?.batteryFriendly.toggle() }
    @objc private func togglePause() { coordinator?.paused.toggle() }
    @objc private func clearSnow() { coordinator?.clear() }
    @objc private func showWind() {
        // A menu action runs during tracking; show after it closes so the popover receives focus.
        DispatchQueue.main.async { [weak self] in
            guard let self, let button = self.statusItem?.button, let coordinator = self.coordinator else { return }
            if let popover = self.windPopover, popover.isShown { popover.performClose(nil); return }
            let content = WindViewController()
            content.settings = coordinator.wind
            content.onChange = { [weak coordinator] value in coordinator?.wind = value }
            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            popover.contentViewController = content
            popover.delegate = self
            content.onClose = { [weak popover] in popover?.performClose(nil) }
            self.windPopover = popover
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate()
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        guard let closed = notification.object as? NSPopover, closed === windPopover else { return }
        windPopover = nil
    }

    @objc private func selectFriend(_ sender: NSMenuItem) {
        guard WinterFriendKind.allCases.indices.contains(sender.tag) else { return }
        coordinator?.setFriend(WinterFriendKind.allCases[sender.tag])
    }

    @objc private func selectVibe(_ sender: NSMenuItem) {
        guard DesktopVibe.allCases.indices.contains(sender.tag) else { return }
        coordinator?.setVibe(DesktopVibe.allCases[sender.tag])
    }

    @objc private func selectTool(_ sender: NSMenuItem) {
        guard SnowTool.allCases.indices.contains(sender.tag) else { return }
        coordinator?.tool = SnowTool.allCases[sender.tag]
    }
    @objc private func setSnowfall(_ sender: NSMenuItem) {
        guard Snowfall.allCases.indices.contains(sender.tag) else { return }
        coordinator?.snowfall = Snowfall.allCases[sender.tag]
    }
}
