import AppKit
import SwiftUI

@MainActor
final class SnowyWindowController: NSWindowController {
    private var sceneEditor: SceneEditorWindowController?

    init(settings: DecorationSettings, resetDecorations: @escaping () -> Void,
         replayWalkthrough: @escaping () -> Void) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 760),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Snowy"
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.contentMinSize = NSSize(width: 820, height: 620)
        super.init(window: window)

        let hosting = NSHostingController(rootView: SnowyWindowView(
            settings: settings, resetDecorations: resetDecorations, replayWalkthrough: replayWalkthrough,
            openEditor: { [weak self] in self?.openSceneEditor(settings: settings) }
        ))
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.center()
        window.setFrameAutosaveName("Snowy Settings")
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        showWindow(nil)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func openSceneEditor(settings: DecorationSettings) {
        if sceneEditor == nil {
            sceneEditor = SceneEditorWindowController(settings: settings, screen: window?.screen) { [weak self] in
                self?.sceneEditor = nil
            }
        }
        sceneEditor?.present()
    }
}

struct SnowyWindowView: View {
    private enum Page: String, CaseIterable, Identifiable {
        case vibes = "Vibes"
        case wallpapers = "Wallpapers"
        case decorations = "Decorations"
        case guide = "Guide"

        var id: Self { self }
        var symbol: String {
            switch self {
            case .vibes: "sparkles"
            case .wallpapers: "photo.on.rectangle"
            case .decorations: "tree"
            case .guide: "book"
            }
        }
    }

    var settings: DecorationSettings
    var resetDecorations: () -> Void
    var replayWalkthrough: () -> Void
    var openEditor: () -> Void
    @State private var page: Page? = .vibes

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: $page) { item in
                Label(item.rawValue, systemImage: item.symbol)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 182, max: 210)
        } detail: {
            switch page ?? .vibes {
            case .vibes:
                VibesView(settings: settings, openEditor: openEditor)
            case .wallpapers:
                WallpapersView()
            case .decorations:
                DecorationsView(settings: settings, resetDecorations: resetDecorations, openEditor: openEditor)
            case .guide:
                SnowyGuideView(replayWalkthrough: replayWalkthrough)
            }
        }
    }
}

private struct SnowyGuideView: View {
    var replayWalkthrough: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Guide").font(.largeTitle.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Replay Walkthrough", action: replayWalkthrough)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 15) {
                        ForEach(WelcomeStep.allCases, id: \.self) { step in
                            if step != .desktop { Divider() }
                            guideRow(step.title, symbol: step.symbol, detail: step.detail,
                                     note: step.secondaryDetail)
                        }
                    }
                    .padding(8)
                } label: {
                    Text("Snow controls")
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 15) {
                        guideRow("Give each desktop a vibe", symbol: "square.stack.3d.up",
                                 detail: "Open Vibes to browse eight presets, adjust weather and friends, and edit the village. Save Changes to Preset keeps your edits after restarting. Each desktop keeps its current selection while Snowy stays open.")
                        Divider()
                        guideRow("Meet your winter village", symbol: "pawprint",
                                 detail: "In Vibes, choose a Village Mix or a single species and set one to five friends. They wander in front of the village, greet each other, visit landmarks, and notice a nearby pointer.")
                        Divider()
                        guideRow("Set a wallpaper", symbol: "photo.on.rectangle",
                                 detail: "Choose an image in Wallpapers or import your own, then apply it to your display.")
                        Divider()
                        guideRow("Decorate the desktop", symbol: "tree",
                                 detail: "Choose a preset or open Edit Scene to place props and hang lights. Enable Push with Cursor to slide a prop, and use Reset Positions to put the scene back.")
                    }
                    .padding(8)
                } label: {
                    Text("Make it yours")
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 15) {
                        guideRow("Throw a snowball", symbol: "snowflake",
                                 detail: "Choose Cursor Tool → Snowball. On an empty part of the desktop, hold Option, flick the pointer, then release Option. No mouse click is needed. Snowballs splash against windows and the ground.")
                        Divider()
                        guideRow("Build a snowman", symbol: "figure.stand",
                                 detail: "Choose Cursor Tool → Build Snowman. Hold Option over empty desktop for a little over a second, then release. A snowman appears at the bottom edge below your pointer.")
                        Divider()
                        guideRow("Shake off a snowy window", symbol: "rectangle.on.rectangle",
                                 detail: "Drag a window back and forth a few times quickly. Its snow cap falls off the sides.")
                        Divider()
                        guideRow("Keep it quiet on battery", symbol: "battery.75percent",
                                 detail: "Battery-Friendly Mode keeps settled snow and decorations, stops falling flakes and wandering friends, and redraws the snow only when something changes. You can still sweep and play.")
                    }
                    .padding(8)
                } label: { Text("Play and power") }
            }
            .padding(26)
            .frame(maxWidth: 740, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private func guideRow(_ title: String, symbol: String, detail: String, note: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
                if let note { Text(note).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
