import SwiftUI
import SnowCore

struct VibesView: View {
    @Bindable var settings: DecorationSettings
    var openEditor: () -> Void
    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Desktop Vibes").font(.largeTitle.weight(.semibold))
                    Text("Give each desktop its own weather, village and friends.")
                        .foregroundStyle(.secondary)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(settings.vibe.rawValue).font(.title2.weight(.semibold))
                                Text("Changes below apply to the desktop you are using.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Edit Village…", action: openEditor).buttonStyle(WinterSettingsButtonStyle(prominent: true))
                        }
                        Divider()
                        choiceMenu("Preset", selection: $settings.vibe, values: DesktopVibe.allCases) { $0.rawValue }
                        choiceMenu("Snowfall", selection: $settings.snowfall, values: Snowfall.allCases) { $0.rawValue }
                        HStack {
                            Text("Wind strength").frame(width: 105, alignment: .leading)
                            Slider(value: $settings.windStrength, in: 0...1)
                            Text(settings.windStrength, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit().frame(width: 44, alignment: .trailing)
                        }
                        HStack {
                            Text("Wind direction").frame(width: 105, alignment: .leading)
                            Slider(value: $settings.windHeading, in: 0...360, step: 5)
                            Text("\(Int(settings.windHeading))°").monospacedDigit().frame(width: 44, alignment: .trailing)
                        }
                        HStack {
                            Text("Snow on lights").frame(width: 105, alignment: .leading)
                            Slider(value: $settings.lightSnowCatch, in: 0...1, step: 0.05)
                                .accessibilityLabel("Snow caught by hanging lights")
                            Text(settings.lightSnowCatch, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit().frame(width: 44, alignment: .trailing)
                        }
                        Text("The share of falling flakes that sticks to hanging lights. The rest falls through.")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 22) {
                            choiceMenu("Friends", selection: $settings.friendKind, values: WinterFriendKind.allCases) { $0.rawValue }
                            HStack(spacing: 9) {
                                Button("−") { settings.friendCount -= 1 }
                                    .disabled(settings.friendCount <= 1 || settings.friendKind == .none)
                                Text("\(settings.friendCount)").monospacedDigit().frame(width: 14)
                                Button("+") { settings.friendCount += 1 }
                                    .disabled(settings.friendCount >= 5 || settings.friendKind == .none)
                            }.buttonStyle(WinterSettingsButtonStyle())
                        }
                        choiceMenu("Cursor tool", selection: $settings.tool, values: SnowTool.allCases) { $0.rawValue }
                        HStack {
                            Button("Clear Snow") { settings.onClearSnow?() }
                            Button("Reset Village Positions") { settings.onResetPositions?() }
                        }.buttonStyle(WinterSettingsButtonStyle())
                        if settings.tool == .snowball || settings.tool == .snowman {
                            Text(settings.tool == .snowball
                                 ? "Hold Option on empty desktop, flick the pointer, then release Option to throw."
                                 : "Hold Option on empty desktop for a little over a second, then release to build.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text("Friends greet each other, explore open village paths and notice your pointer.")
                            .font(.caption).foregroundStyle(.secondary)
                        Divider()
                        HStack {
                            Button("Save Changes to Preset") {
                                settings.notice = settings.onSaveVibe?() == true ? "Saved \(settings.vibe.rawValue)." : "Could not save the preset."
                            }
                            Button("Reset Preset") { settings.onResetVibe?(); settings.notice = "Restored the original preset." }
                            Spacer()
                            if !settings.notice.isEmpty { Text(settings.notice).font(.caption).foregroundStyle(.secondary) }
                        }.buttonStyle(WinterSettingsButtonStyle())
                        Text("Saved presets keep your scene, weather and friend choices after restarting Snowy.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(8)
                }
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(DesktopVibe.allCases.filter { $0 != .custom }, id: \.self) { vibe in
                        Button { settings.vibe = vibe } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                DecorationThumbnail(pieces: previewPieces(for: vibe))
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(vibe.rawValue).font(.headline)
                                        Spacer()
                                        if settings.vibe == vibe { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                                    }
                                    Text(settings.savedPresetAssets[vibe.rawValue] == nil ? vibe.detail : "Your saved scene and settings.").font(.caption).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
                                }.padding(12)
                            }
                            .background(.background)
                            .clipShape(.rect(cornerRadius: 9))
                            .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(settings.vibe == vibe ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: settings.vibe == vibe ? 2 : 1) }
                        }.buttonStyle(.plain)
                    }
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 7) {
                        Toggle("Battery-Friendly Mode", isOn: $settings.batteryFriendly)
                        Text("Keep your village and settled snow, with falling flakes and wandering paused. Applies to all desktops.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(8)
                }
            }
            .groupBoxStyle(WinterSettingsGroupStyle())
            .padding(26)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private func choiceMenu<Value: Hashable>(_ title: String, selection: Binding<Value>, values: [Value],
                                             label: @escaping (Value) -> String) -> some View {
        HStack {
            Text(title).frame(width: 105, alignment: .leading)
            Menu {
                ForEach(values, id: \.self) { value in
                    Button(label(value)) { selection.wrappedValue = value }
                }
            } label: {
                HStack {
                    Text(label(selection.wrappedValue)).lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .accessibilityLabel(title)
            .accessibilityValue(label(selection.wrappedValue))
        }
    }

    private func previewPieces(for vibe: DesktopVibe) -> [DecorationPiece] {
        guard let assets = settings.savedPresetAssets[vibe.rawValue] else { return vibe.previewPieces }
        var seen = Set<String>()
        return assets.compactMap { seen.insert($0).inserted ? DecorationCatalog.piece($0) : nil }
    }
}

private struct WinterSettingsGroupStyle: GroupBoxStyle {
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            configuration.label
            configuration.content
        }
        .padding(10)
        .background(scheme == .dark ? Color(red: 0.13, green: 0.15, blue: 0.18) : Color(red: 0.97, green: 0.98, blue: 0.99),
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.1)) }
    }
}

private struct WinterSettingsButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.medium)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(prominent ? Color.accentColor : Color.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: 6))
            .opacity(!enabled ? 0.35 : (configuration.isPressed ? 0.7 : 1))
    }
}
