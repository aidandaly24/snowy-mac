import AppKit
import MetalKit
import SnowCore

private final class SnowPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class DesktopCoordinator {
    var onStateChange: (() -> Void)?
    var onDesktopGeometryChange: (([SceneDesktop]) -> Void)?
    private(set) var failed = false
    private(set) var policy: RenderPolicy
    var batteryFriendly: Bool {
        didSet {
            UserDefaults.standard.set(batteryFriendly, forKey: "batteryFriendly")
            refreshPolicy()
        }
    }
    var paused: Bool {
        didSet {
            UserDefaults.standard.set(paused, forKey: "paused")
            updateState()
        }
    }
    private var defaultSnowfall: Snowfall
    private var defaultWind: WindSettings
    var snowfall: Snowfall {
        get { activeDisplays.first?.renderer.simulation.snowfall ?? defaultSnowfall }
        set {
            for display in activeDisplays { display.renderer.simulation.snowfall = newValue }
            onStateChange?()
        }
    }
    var wind: WindSettings {
        get { activeDisplays.first?.renderer.simulation.wind ?? defaultWind }
        set {
            for display in activeDisplays { display.renderer.simulation.wind = newValue }
            onStateChange?()
        }
    }
    var friendKind: WinterFriendKind { activeDisplays.first?.friend.kind ?? .mixed }
    var friendCount: Int { activeDisplays.first?.friend.count ?? 3 }
    var lightSnowCatch: Float { activeDisplays.first?.lightSnowCatch ?? 0.2 }
    func setLightSnowCatch(_ fraction: Float) {
        guard fraction.isFinite else { return }
        for display in activeDisplays {
            display.lightSnowCatch = min(1, max(0, fraction))
            applyScene(for: display)
        }
        onStateChange?()
    }
    var hasSavedVibe: Bool { savedVibes[vibe.rawValue] != nil }
    var savedPresetAssets: [String: [String]] { savedVibes.mapValues { $0.scene.props.map(\.assetID) } }
    func setFriends(_ kind: WinterFriendKind, count: Int) {
        for display in activeDisplays { display.friend.kind = kind; display.friend.count = min(5, max(1, count)) }
        updateState()
    }
    func setWeather(_ snowfall: Snowfall, wind: WindSettings) {
        for display in activeDisplays { display.renderer.simulation.snowfall = snowfall; display.renderer.simulation.wind = wind }
        onStateChange?()
    }

    func setFriend(_ kind: WinterFriendKind) {
        for display in activeDisplays { display.friend.kind = kind }
        updateState()
    }
    var vibe: DesktopVibe { activeDisplays.first?.vibe ?? .cozyVillage }
    var currentConfiguration: DecorationConfiguration { activeDisplays.first?.configuration ?? decorationConfiguration }

    func setVibe(_ vibe: DesktopVibe) {
        for display in activeDisplays { applyVibe(vibe, to: display); applyScene(for: display) }
        updateIconTracking()
        updateState()
    }

    private func applyVibe(_ vibe: DesktopVibe, to display: Display) {
        display.vibe = vibe
        display.followsFactoryVillageLayout = vibe == .cozyVillage && savedVibes[vibe.rawValue] == nil
        if let saved = savedVibes[vibe.rawValue] {
            display.configuration = DecorationConfiguration(usesCustomScenes: true,
                scenes: [display.geometry.id: saved.scene.bounded()])
            display.renderer.simulation.snowfall = saved.weather
            display.renderer.simulation.wind = saved.wind
            display.friend.kind = saved.friends
            display.friend.count = min(5, max(1, saved.friendCount))
            display.lightSnowCatch = saved.lightSnowCatchFraction
        } else {
            display.configuration = vibe.decorations(in: display.desktop, fallback: decorationConfiguration)
            if vibe != .custom {
                display.renderer.simulation.snowfall = vibe.snowfall
                display.renderer.simulation.wind = vibe.wind
                display.friend.kind = .mixed
                display.friend.count = 3
                display.lightSnowCatch = 0.2
            }
        }
        configureDecorations(for: display)
    }

    @discardableResult
    func saveCurrentVibe() -> Bool {
        guard let display = activeDisplays.first else { return false }
        let wind = display.renderer.simulation.wind.vector
        let saved = SavedDesktopVibe(scene: display.configuration.scene(for: display.desktop).bounded(),
            snowfall: display.renderer.simulation.snowfall.rawValue, windX: wind.x, windY: wind.y,
            friendKind: display.friend.kind.rawValue, friendCount: display.friend.count, lightSnowCatch: display.lightSnowCatch)
        var updated = savedVibes
        updated[display.vibe.rawValue] = saved
        guard let data = try? JSONEncoder().encode(updated), data.count <= 256_000 else { return false }
        savedVibes = updated
        display.followsFactoryVillageLayout = false
        UserDefaults.standard.set(data, forKey: "personalVibePresets")
        onStateChange?()
        return true
    }

    func resetCurrentVibe() {
        savedVibes[vibe.rawValue] = nil
        if let data = try? JSONEncoder().encode(savedVibes) { UserDefaults.standard.set(data, forKey: "personalVibePresets") }
        setVibe(vibe)
    }
    var tool: SnowTool {
        didSet {
            UserDefaults.standard.set(tool.rawValue, forKey: "cursorTool")
            for display in displays {
                display.renderer.simulation.tool = tool
                display.renderer.simulation.resetPointer()
                display.playground.resetInteraction()
                display.gusts.resetInteraction()
            }
            onStateChange?()
        }
    }
    private let context: MetalContext
    private let tracker = WindowTracker()
    private var displays: [Display] = []
    private var screenLayout: [ScreenLayout] = []
    private static let cachedDesktopsPerDisplay = 8

    private struct ScreenLayout: Equatable {
        let id: UInt32
        let frame: CGRect
        let scale: CGFloat
    }

    private var activeDisplays: [Display] { displays.filter(\.wasActive) }
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var metadataTimer: Timer?
    private var screensAwake = true
    private var sessionActive = true
    private var primaryTop: CGFloat = 0
    private var reconfiguring = false
    private var stopping = false
    private var updatingState = false
    private var draggingWindow = false
    private var lastDockGeometryRead: CFTimeInterval = -.infinity
    private var dockBottomInsets: [UInt32: Float] = [:]
    private var decorationConfiguration = DecorationConfiguration()
    private var savedVibes: [String: SavedDesktopVibe] = [:]
    private var editorVisible = false

    var editorDesktops: [SceneDesktop] { activeDisplays.map(\.desktop) }

    @MainActor
    private final class Display {
        let geometry: DisplayGeometry
        let panel: SnowPanel
        let renderer: MetalRenderer
        let nativeScale: CGFloat
        let decorations: DesktopDecorations
        let lights: DesktopHangingLights
        let friend: WinterFriendView
        let playground: SnowPlayground
        let gusts: WindGustView
        var lightSnowSurfaces: [Surface] = []
        var lastLightSnowUpdate: TimeInterval = -.infinity
        var shakeDetector = WindowShakeDetector()
        var snapshot: DisplaySnapshot?
        var vibe: DesktopVibe = .cozyVillage
        var followsFactoryVillageLayout = false
        var lightSnowCatch: Float = 0.2
        var configuration = DecorationConfiguration()
        var fullscreen = false
        var geometryReady = false
        var lastUsed: TimeInterval = 0
        var wasActive = false
        var desktop: SceneDesktop {
            snapshot?.desktop ?? SceneDesktop(id: geometry.id, size: geometry.bounds.size, dock: nil, anchors: [])
        }

        init(geometry: DisplayGeometry, panel: SnowPanel, renderer: MetalRenderer, nativeScale: CGFloat,
             decorations: DesktopDecorations, lights: DesktopHangingLights, friend: WinterFriendView, playground: SnowPlayground, gusts: WindGustView) {
            self.geometry = geometry
            self.panel = panel
            self.renderer = renderer
            self.nativeScale = nativeScale
            self.decorations = decorations
            self.lights = lights
            self.friend = friend
            self.playground = playground
            self.gusts = gusts
        }
    }

    init(configuration: DecorationConfiguration = DecorationConfiguration()) throws {
        decorationConfiguration = configuration
        if let data = UserDefaults.standard.data(forKey: "personalVibePresets"), data.count <= 256_000,
           let presets = try? JSONDecoder().decode([String: SavedDesktopVibe].self, from: data) {
            savedVibes = presets.filter { DesktopVibe(rawValue: $0.key) != nil }
        }
        context = try MetalContext()
        batteryFriendly = UserDefaults.standard.bool(forKey: "batteryFriendly")
        paused = UserDefaults.standard.bool(forKey: "paused")
        defaultSnowfall = Snowfall(rawValue: UserDefaults.standard.string(forKey: "snowfall") ?? "") ?? .steady
        defaultWind = WindSettings(vector: SIMD2(UserDefaults.standard.float(forKey: "windX"),
                                         UserDefaults.standard.float(forKey: "windY")))
        tool = SnowTool(rawValue: UserDefaults.standard.string(forKey: "cursorTool") ?? "") ?? .glove
        policy = Self.readPolicy(batteryFriendly: batteryFriendly)
        installObservers()
        configureDisplays()
    }

    func clear() {
        for display in activeDisplays { display.renderer.simulation.clear(); display.playground.clear() }
    }

    func setDecorations(_ configuration: DecorationConfiguration) {
        decorationConfiguration = configuration
        for display in activeDisplays {
            display.configuration = configuration
            display.followsFactoryVillageLayout = false
            configureDecorations(for: display)
            applyScene(for: display)
        }
        updateIconTracking()
        updateState()
    }

    func setEditorVisible(_ visible: Bool) {
        editorVisible = visible
        updateIconTracking()
        updateState()
    }

    func resetDecorations() {
        for display in activeDisplays {
            display.decorations.reset()
            display.friend.resetPositions()
            display.lights.configure([])
            display.lights.configure(display.configuration.scene(for: display.desktop).lights)
            applyScene(for: display)
        }
        updateState()
    }

    func stop() {
        stopping = true
        metadataTimer?.invalidate()
        metadataTimer = nil
        tracker.invalidate()
        for display in displays {
            display.renderer.view.isPaused = true
            display.renderer.spotlightOverlay.close()
            display.panel.close()
        }
        displays.removeAll()
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
    }

    private static func readPolicy(batteryFriendly: Bool) -> RenderPolicy {
        let process = ProcessInfo.processInfo
        return RenderPolicy(lowPower: process.isLowPowerModeEnabled,
                            thermalLevel: process.thermalState.rawValue,
                            reducedMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, batteryFriendly: batteryFriendly)
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         action: @escaping @MainActor @Sendable () -> Void) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { action() }
        }
        observers.append((center, observer))
    }

    private func installObservers() {
        let notifications = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        observe(notifications, .NSProcessInfoPowerStateDidChange) { [weak self] in self?.refreshPolicy() }
        observe(notifications, ProcessInfo.thermalStateDidChangeNotification) { [weak self] in self?.refreshPolicy() }
        observe(workspace, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) { [weak self] in self?.refreshPolicy() }
        observe(notifications, NSApplication.didChangeScreenParametersNotification) { [weak self] in self?.configureDisplays() }
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] in
            guard let self else { return }
            self.activateDesktop()
        }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] in
            self?.screensAwake = false
            self?.updateState()
        }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] in
            self?.screensAwake = true
            self?.tracker.invalidate()
            self?.updateState()
        }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in
            self?.sessionActive = false
            self?.updateState()
        }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in
            self?.sessionActive = true
            self?.tracker.invalidate()
            self?.updateState()
        }
    }

    private func refreshPolicy() {
        policy = Self.readPolicy(batteryFriendly: batteryFriendly)
        updateState()
    }

    private func configureDisplays() {
        let screens = Array(NSScreen.screens.prefix(6))
        let layout = screens.compactMap { screen -> ScreenLayout? in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return ScreenLayout(id: id.uint32Value, frame: screen.frame, scale: screen.backingScaleFactor)
        }
        // Dock/fullscreen changes can send this notification too. A desktop swipe
        // must not destroy cached scenes when the physical screens are unchanged.
        guard layout != screenLayout || displays.isEmpty else {
            activateDesktop()
            return
        }
        reconfiguring = true
        tracker.invalidate()
        for display in displays { close(display) }
        displays.removeAll()
        screenLayout = layout
        dockBottomInsets.removeAll(keepingCapacity: true)
        primaryTop = screens.first?.frame.maxY ?? 0
        reconfiguring = false
        activateDesktop()
    }

    private func activateDesktop() {
        guard !stopping, !reconfiguring else { return }
        reconfiguring = true
        tracker.invalidate()
        draggingWindow = false
        lastDockGeometryRead = -.infinity
        let screens = Array(NSScreen.screens.prefix(6))
        let totalArea = max(1, screens.reduce(CGFloat(0)) { $0 + $1.frame.width * $1.frame.height })
        let totalFlakes = min(900, max(80, Int(totalArea / 1_000_000 * 180)))
        do {
            for screen in screens {
                guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
                if !displays.contains(where: { $0.geometry.id == id.uint32Value && $0.panel.isOnActiveSpace }) {
                    try makeDisplay(for: screen, totalArea: totalArea, totalFlakes: totalFlakes)
                }
            }
        } catch { failed = true }
        let now = CACurrentMediaTime()
        for display in displays {
            let active = display.panel.isOnActiveSpace
            if active != display.wasActive {
                recordDesktop(display, event: active ? "resume" : "suspend")
                display.renderer.simulation.resetPointer()
                display.decorations.resetInteraction()
                display.lights.resetInteraction()
                display.friend.resetInteraction()
                display.playground.resetInteraction()
                display.gusts.resetInteraction()
                display.shakeDetector = WindowShakeDetector()
            }
            display.wasActive = active
            if active { display.lastUsed = now }
        }
        // Bound inactive CPU state and retained presentation frames. Simulation
        // and GPU mesh/particle buffers run only on the active desktops.
        for id in Set(displays.map { $0.geometry.id }) {
            var cached = displays.filter { $0.geometry.id == id && !$0.wasActive }
                .sorted { $0.lastUsed < $1.lastUsed }
            let excess = max(0, displays.filter { $0.geometry.id == id }.count - Self.cachedDesktopsPerDisplay)
            for _ in 0..<min(excess, cached.count) {
                let expired = cached.removeFirst()
                close(expired)
                displays.removeAll { $0 === expired }
            }
        }
        reconfiguring = false
        updateIconTracking()
        onDesktopGeometryChange?(editorDesktops)
        updateState()
        refreshMetadata()
    }

    private func close(_ display: Display) {
        display.renderer.apply(policy: policy, scale: 1, paused: true)
        display.renderer.spotlightOverlay.close()
        display.panel.close()
    }

    private func recordDesktop(_ display: Display, event: String) {
        guard let path = ProcessInfo.processInfo.environment["SNOWY_SPACE_DIAGNOSTICS_PATH"] else { return }
        let simulation = display.renderer.simulation
        var fingerprint = Hasher()
        for drift in simulation.drifts {
            fingerprint.combine(drift.surface.id)
            fingerprint.combine(drift.heights)
        }
        fingerprint.combine(simulation.looseSnow.totalMass)
        for flake in simulation.flakes { fingerprint.combine(flake.position) }
        let line = "\(Date()) \(event) panel=\(display.panel.windowNumber) display=\(display.geometry.id) state=\(fingerprint.finalize()) surfaces=\(simulation.drifts.count)\n"
        let data = Data(line.utf8)
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else { try? data.write(to: URL(fileURLWithPath: path)) }
    }

    private func makeDisplay(for screen: NSScreen, totalArea: CGFloat, totalFlakes: Int) throws {
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return }
        let frame = screen.frame
        let visible = screen.visibleFrame
        let share = frame.width * frame.height / totalArea
        let geometry = DisplayGeometry(
            id: id.uint32Value,
            bounds: CGRect(x: frame.minX, y: primaryTop - frame.maxY, width: frame.width, height: frame.height),
            menuInset: Float(max(0, frame.maxY - visible.maxY)),
            dockBottomInset: Float(max(0, visible.minY - frame.minY))
        )
        let budget = SimulationBudget(flakes: Int(CGFloat(totalFlakes) * share),
                                      debris: Int(192 * share), cells: Int(4096 * share),
                                      surfaces: Int(48 * share))
        let renderer = try MetalRenderer(context: context, size: frame.size, menuInset: geometry.menuInset,
                                         budget: budget, seed: UInt64(geometry.id) ^ (UInt64(displays.count) << 32))
        renderer.simulation.snowfall = snowfall
        renderer.simulation.wind = wind
        renderer.simulation.tool = tool
        let panel = SnowPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.animationBehavior = .none
        // Immediately above wallpaper, below desktop icons/widgets and all app windows.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        // A separate window belongs to each native desktop. macOS moves it with
        // that desktop during a swipe; it must never join all Spaces.
        panel.collectionBehavior = [.fullScreenAuxiliary, .managed, .ignoresCycle]
        panel.isExcludedFromWindowsMenu = true
        let decorations = DesktopDecorations(size: frame.size)
        let lights = DesktopHangingLights(size: frame.size)
        let friend = WinterFriendView(size: frame.size)
        let playground = SnowPlayground(size: frame.size)
        let gusts = WindGustView(size: frame.size)
        let content = NSView(frame: CGRect(origin: .zero, size: frame.size))
        renderer.view.autoresizingMask = [.width, .height]
        content.addSubview(renderer.view)
        content.addSubview(gusts.view)
        // Like desktop windows, opaque sprite pixels cover snow behind
        // them while leaving their transparent outline and tops visible.
        content.addSubview(decorations.view)
        content.addSubview(lights.view)
        content.addSubview(friend.view)
        content.addSubview(playground.view)
        panel.contentView = content
        panel.setFrame(frame, display: false)
        let display = Display(geometry: geometry, panel: panel, renderer: renderer,
                              nativeScale: screen.backingScaleFactor, decorations: decorations, lights: lights, friend: friend, playground: playground, gusts: gusts)
        playground.onImpact = { [weak renderer] position, mass in
            renderer?.simulation.addPlayfulSnow(at: position, mass: mass)
        }
        playground.onBuildSnowman = { [weak self, weak display] x in
            guard let self, let display else { return }
            self.buildSnowman(at: x, on: display)
        }
        let initialVibe: DesktopVibe = displays.filter { $0.geometry.id == geometry.id }.count.isMultiple(of: 2) ? .cozyVillage : .blizzard
        applyVibe(initialVibe, to: display)
        renderer.shouldRender = { [weak panel] in panel?.isOnActiveSpace == true }
        renderer.view.isHidden = true
        renderer.cursorPosition = { [weak self] in
            let point = NSEvent.mouseLocation
            guard !NSApp.windows.contains(where: {
                $0.isVisible && $0.level.rawValue >= NSWindow.Level.normal.rawValue && $0.frame.contains(point)
            }) else { return nil }
            return SIMD2(Float(point.x - geometry.bounds.minX),
                         Float((self?.primaryTop ?? 0) - point.y - geometry.bounds.minY))
        }
        renderer.beforeFrame = { [weak self, weak display] now, cursor in
            guard let self else { return }
            let down = NSEvent.pressedMouseButtons != 0
            if down || self.draggingWindow { self.refreshMetadata(dragging: down) }
            self.draggingWindow = down
            guard let display, let snapshot = display.snapshot else { return }
            let pointer = down ? nil : cursor
            let isCoveredByOwnWindow: (SIMD2<Float>) -> Bool = { point in
                let global = CGPoint(x: geometry.bounds.minX + CGFloat(point.x),
                                     y: self.primaryTop - geometry.bounds.minY - CGFloat(point.y))
                return NSApp.windows.contains {
                    $0.isVisible && $0.level.rawValue >= NSWindow.Level.normal.rawValue
                        && $0.frame.contains(global)
                }
            }
            let friendCursor = pointer.flatMap { point in
                snapshot.bodies.contains { $0.contains(point) } || isCoveredByOwnWindow(point) ? nil : point
            }
            display.gusts.advance(now: now, wind: display.renderer.simulation.wind,
                                  snowfall: display.renderer.simulation.snowfall,
                                  quiet: self.batteryFriendly || self.policy.reducedMotion)
            display.playground.advance(now: now, cursor: pointer, canStart: friendCursor != nil,
                                       optionDown: NSEvent.modifierFlags.contains(.option), tool: self.tool,
                                       bodies: display.renderer.simulation.collisionBodies, wind: display.renderer.simulation.wind,
                                       dock: display.desktop.dock)
            display.friend.advance(now: now, cursor: friendCursor,
                                   bodies: snapshot.bodies, reducedMotion: self.policy.reducedMotion || self.batteryFriendly,
                                   landmarks: display.configuration.scene(for: display.desktop).props.map { Float($0.x * display.desktop.size.width) })
            display.lights.advance(now: now, wind: display.renderer.simulation.wind, cursor: pointer,
                                   reducedMotion: self.policy.reducedMotion || self.batteryFriendly) { point in
                snapshot.bodies.contains { $0.contains(point) } || isCoveredByOwnWindow(point)
            }
            if now - display.lastLightSnowUpdate >= 0.1 {
                display.lastLightSnowUpdate = now
                let supports = display.lights.snowSurfaces(occluders: display.renderer.simulation.collisionBodies, catchFraction: display.lightSnowCatch)
                if supports != display.lightSnowSurfaces { self.applyScene(for: display) }
            }
            if display.decorations.advance(cursor: pointer, now: now,
                                           reducedMotion: self.policy.reducedMotion, occluders: snapshot.bodies,
                                           isCoveredByOwnWindow: isCoveredByOwnWindow) {
                self.applyScene(for: display)
            }
        }
        renderer.onFailure = { [weak self] in
            self?.failed = true
            self?.updateState()
        }
        displays.append(display)
        // Order the transparent panel once to establish its native Space membership.
        // Keep it ordered while inactive so WindowServer can animate its last frame.
        panel.orderFrontRegardless()
    }

    private var desktopAvailable: Bool { screensAwake && sessionActive && !failed && !policy.suspended }
    private var running: Bool { !paused && desktopAvailable }
    private var followsObjects: Bool {
        activeDisplays.contains { $0.lights.followsWidgets || (tracker.includesDesktopIcons && $0.lights.followsIcons) }
    }
    private var needsDesktopScene: Bool {
        desktopAvailable && (!paused || editorVisible || activeDisplays.contains { $0.configuration.hasContent || !$0.friend.isEmpty })
    }

    private func updateIconTracking() {
        let needed = activeDisplays.contains { $0.configuration.includesDesktopIcons }
            && (editorVisible || activeDisplays.contains { $0.lights.followsIcons })
        guard needed != tracker.includesDesktopIcons else { return }
        tracker.includesDesktopIcons = needed
        refreshMetadata()
    }

    private func configureDecorations(for display: Display) {
        let desktop = display.desktop
        let scene = display.configuration.scene(for: desktop)
        display.decorations.updateDock(desktop.dock)
        display.decorations.configure(props: scene.props)
        display.lights.updateDesktop(desktop, animate: running && display.panel.isOnActiveSpace && !policy.reducedMotion && !batteryFriendly && !display.fullscreen)
        display.lights.configure(scene.lights)
    }

    private func buildSnowman(at x: Double, on display: Display) {
        var scene = display.configuration.scene(for: display.desktop)
        guard scene.props.count < DecorationScene.maxProps else { return }
        let pixelX = CGFloat(x) * display.desktop.size.width
        let onDock = display.desktop.dock.map { pixelX >= $0.minX && pixelX <= $0.maxX } ?? false
        scene.props.append(PlacedDecoration(assetID: "Snowman", x: min(1, max(0, x)), scale: 1.1,
                                            pushes: true, support: onDock ? .dock : .floor))
        display.configuration.scenes[display.geometry.id] = scene
        display.configuration.usesCustomScenes = true
        display.followsFactoryVillageLayout = false
        configureDecorations(for: display)
        applyScene(for: display)
        onStateChange?()
    }

    private func applyScene(for display: Display) {
        guard let snapshot = display.snapshot else { return }
        let simulation = display.renderer.simulation
        let scene = display.decorations.scene(with: snapshot, budget: simulation.budget)
        let wires = display.lights.snowSurfaces(occluders: scene.bodies, catchFraction: display.lightSnowCatch)
        display.lightSnowSurfaces = wires
        let maximum = min(simulation.budget.surfaces, simulation.budget.cells / 5)
        let wireCount = min(wires.count, max(0, maximum - snapshot.surfaces.count))
        let surfaces = Array(scene.surfaces.prefix(max(0, maximum - wireCount))) + wires.prefix(wireCount)
        simulation.updateScene(surfaces: surfaces, bodies: scene.bodies)
    }

    private func updateState() {
        guard !reconfiguring, !stopping, !updatingState else { return }
        updatingState = true
        defer { updatingState = false }
        let totalArea = max(1, activeDisplays.reduce(CGFloat(0)) {
            $0 + $1.geometry.bounds.width * $1.geometry.bounds.height + $1.renderer.spotlightOverlay.logicalArea
        })
        // Across every display, limit drawable area as well as particle/mesh counts.
        let pixelBudgetScale = sqrt(6_000_000 / totalArea)
        for display in displays {
            // Seed airborne flakes only after the first body snapshot, never inside unknown windows.
            let visibleDesktop = desktopAvailable && display.geometryReady && !display.fullscreen
            let showSnow = running && visibleDesktop
            let showDecorations = visibleDesktop && (!display.decorations.isEmpty || !display.lights.isEmpty || !display.friend.isEmpty)
            let active = display.wasActive
            display.renderer.view.isHidden = !showSnow
            display.decorations.view.isHidden = !showDecorations
            display.lights.view.isHidden = !showDecorations
            display.friend.view.isHidden = !showDecorations
            display.playground.view.isHidden = !visibleDesktop || self.paused
            display.gusts.view.isHidden = !visibleDesktop || self.paused || batteryFriendly || policy.reducedMotion
            let scale = min(display.nativeScale, min(CGFloat(policy.renderScale), pixelBudgetScale))
            // Full-display transparent Finder/widget containers can mark a desktop panel occluded.
            // Use explicit scene/lifecycle gates; that bounding-box signal is not reliable here.
            display.renderer.apply(policy: policy, scale: scale, paused: !showSnow || !active,
                                   retainingLastFrame: showSnow && !active)
            display.renderer.spotlightOverlay.apply(show: showSnow && active, scale: scale)
        }
        if desktopAvailable && (running || editorVisible || followsObjects) && !activeDisplays.isEmpty {
            if metadataTimer == nil {
                let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refreshMetadata() }
                }
                timer.tolerance = 0.10
                RunLoop.main.add(timer, forMode: .common)
                metadataTimer = timer
                refreshMetadata()
            }
        } else {
            metadataTimer?.invalidate()
            metadataTimer = nil
            if needsDesktopScene {
                // A paused desktop needs only a one-shot snapshot after a Space
                // or display change. Its static art requires no render clock.
                if activeDisplays.contains(where: { !$0.geometryReady }) { refreshMetadata() }
            } else {
                tracker.invalidate()
            }
        }
        onStateChange?()
    }

    private func refreshMetadata(dragging: Bool? = nil) {
        let targets = activeDisplays
        guard needsDesktopScene, !targets.isEmpty else { return }
        let idleInterval: TimeInterval = targets.allSatisfy(\.fullscreen) ? 1 : 0.5
        let now = CACurrentMediaTime()
        if now - lastDockGeometryRead >= idleInterval {
            // visibleFrame follows the currently occupied Dock screen and auto-hide
            // state. Re-read it at metadata cadence, without rebuilding renderers.
            dockBottomInsets.removeAll(keepingCapacity: true)
            for screen in NSScreen.screens.prefix(6) {
                guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
                let frame = screen.frame
                dockBottomInsets[id.uint32Value] = Float(max(0, screen.visibleFrame.minY - frame.minY))
            }
            lastDockGeometryRead = now
        }
        let geometry = targets.map { display in
            DisplayGeometry(id: display.geometry.id, bounds: display.geometry.bounds,
                            menuInset: display.geometry.menuInset,
                            dockBottomInset: dockBottomInsets[display.geometry.id] ?? 0)
        }
        tracker.refreshIfNeeded(displays: geometry, now: now,
                                dragging: dragging ?? (NSEvent.pressedMouseButtons != 0), idleInterval: idleInterval) { [weak self] snapshots in
            guard let self, self.needsDesktopScene else { return }
            guard let snapshots else {
                self.refreshMetadata()
                return
            }
            let previousDesktops = self.editorDesktops
            for snapshot in snapshots {
                guard let display = targets.first(where: { $0.geometry.id == snapshot.id }),
                      self.displays.contains(where: { $0 === display }),
                      display.panel.isOnActiveSpace else { continue }
                let previousSnapshot = display.snapshot
                let previousDesktop = display.desktop
                display.snapshot = snapshot
                let desktopChanged = display.desktop != previousDesktop
                if display.followsFactoryVillageLayout, display.desktop.dock != previousDesktop.dock {
                    // The Dock arrives with the first native snapshot, after the panel is created.
                    // Reflow factory props then; explicit scene edits and saved presets keep their placements.
                    let factory = DesktopVibe.cozyVillage.decorations(in: display.desktop, fallback: display.configuration)
                    var scene = display.configuration.scene(for: display.desktop)
                    scene.props = factory.scene(for: display.desktop).props
                    display.configuration.scenes[display.geometry.id] = scene
                }
                if desktopChanged { self.configureDecorations(for: display) }
                if desktopChanged || previousSnapshot?.surfaces != snapshot.surfaces
                    || previousSnapshot?.bodies != snapshot.bodies {
                    self.applyScene(for: display)
                }
                let shaken = display.shakeDetector.update(bodies: snapshot.bodies, now: CACurrentMediaTime(),
                                                          dragging: NSEvent.pressedMouseButtons != 0)
                for id in shaken { display.renderer.simulation.shakeSnow(fromSurfaceID: id) }
                display.renderer.spotlightOverlay.update(supports: snapshot.spotlightSupports,
                                                        displayBounds: display.geometry.bounds, primaryTop: self.primaryTop)
                display.fullscreen = snapshot.fullscreen
                display.geometryReady = true
            }
            let newDesktops = self.editorDesktops
            if newDesktops != previousDesktops { self.onDesktopGeometryChange?(newDesktops) }
            self.updateState()
        }
    }
}
