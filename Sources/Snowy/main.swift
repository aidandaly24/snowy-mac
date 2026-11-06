import AppKit

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
#if DEBUG
if let previewPath = ProcessInfo.processInfo.environment["SNOWY_VILLAGE_PREVIEW_PATH"] {
    try renderVillagePreview(to: previewPath)
    exit(0)
}
if let previewPath = ProcessInfo.processInfo.environment["SNOWY_SETTINGS_PREVIEW_PATH"] {
    try renderSettingsPreview(to: previewPath)
    exit(0)
}
#endif
let delegate = AppDelegate()
application.delegate = delegate
application.run()
