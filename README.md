# Snowy ❄️

Snow for your desktop. A native Mac app that lets winter settle on your windows, widgets, and bottom Dock.

Sweep a pile with your pointer. Pick up a shovel. Make a little mess.

![An illustrated Snowy desktop with snow resting on overlapping windows and a bottom Dock](docs/snowy.svg)

## Get it

Download the latest [Apple Silicon DMG](https://github.com/soloiaros/snowy-mac/releases/latest/download/Snowy-macOS-arm64.dmg), open it, and drag **Snowy.app** onto **Applications**. Eject the disk image, then open Snowy from Applications. On a fresh setup, three quick pages show how to sweep snow, adjust wind, and find the menu-bar controls. Skip or close the walkthrough at any time; it won’t reopen on later launches.

Requires **macOS 14 or later**. The current download is for Apple Silicon. Intel Macs can build from source. The 0.10.0 beta is signed locally and can trigger Gatekeeper’s malware-verification warning. If macOS blocks the copy you downloaded here, go to **System Settings → Privacy & Security → Open Anyway** after trying to open it.

When a compatible release is available, **Update** appears in blue near the bottom of the snowflake menu. Click it to download, install, and reopen Snowy. To upgrade from 0.9.1 or earlier, quit Snowy and replace it in Applications using the DMG once.

## Let it snow

Click the snowflake in your menu bar to make yourself comfortable:

- Choose **Light**, **Steady**, or **Flurry**.
- Brush snow away with the **Glove**, or choose **Shovel** for a proper clear-out.
- Open **Wind…** and stretch or rotate the arrow to change its strength and direction.
- **Pause** the weather or **Clear Settled Snow** whenever you like.

Snow collects on window tops, widgets, Spotlight, and a bottom-positioned Dock. Moving windows push it around; closing Spotlight lets its uncovered snow fall. Side-positioned Docks are intentionally left out.

Choose **Open Snowy…** in the snowflake menu to apply a wallpaper, select a pixel-art preset, or build your own desktop scene. Props catch snow and can slide when swept. In **Edit Scene**, place individual pieces and attach string lights to the desktop edges and widgets. Finder icon anchors are optional and require Accessibility access. The **Guide** includes **Replay Walkthrough**.

The desktop stays clickable. Snowy reads public window bounds for snow and widgets. Finder icon anchors use Accessibility only when enabled. Snowy keeps your settings and imported wallpapers on your Mac and checks GitHub for signed updates.

## Build it yourself

You’ll need **Xcode 16 or later**, its Metal toolchain, and a Mac.

```sh
git clone https://github.com/soloiaros/snowy-mac.git
cd snowy-mac
./scripts/build-app.sh
open build/Snowy.app
```

The build script compiles the app and shaders, adds a local signature, and leaves the app in `build/`. It does not launch or install anything. If Xcode reports a missing Metal toolchain, install it from Xcode’s component settings first.

## Working on this fork

This checkout uses `origin` for `aidandaly24/snowy-mac` and `upstream` for the
original `soloiaros/snowy-mac` repository. Local edits start on the
`local-customizations` branch. Automatic checks of the original app's release
feed are disabled in `App/Info.plist` for this fork.

Open `Package.swift` in Xcode to edit the app. After saving changes, run:

```sh
./scripts/dev.sh
```

This builds a locally signed `build/Snowy.app`, closes the running copy from this
checkout, and opens the new build. A failed build leaves the running app alone.
`Sources/Snowy/` contains the interface and rendering; `Sources/SnowCore/` contains
the snow simulation. Run `swift test` after changing the simulation.

This fork keeps a separate snow simulation and decoration layer for each visited
macOS desktop. Swiping away pauses that desktop; returning resumes its existing
snow and prop positions. Up to eight desktops per physical display are retained
while the app runs. Quitting or changing the physical screen layout clears that
transient snow state.

For a native desktop round-trip check, launch with an absolute local log path:

```sh
SNOWY_SPACE_DIAGNOSTICS_PATH=/tmp/snowy-space-state.log ./scripts/dev.sh
```

Brush a pile, switch desktops, and return. A panel's `resume` state fingerprint
should match its preceding `suspend` fingerprint. This records only Snowy's own
panel identifiers and simulation fingerprints, without desktop content.

## Personal winter features

Choose **Open Snowy… → Vibes** for the main controls. The settings window moves
to your current desktop when opened. Pick a preset, adjust snowfall and wind,
choose a friend mix and group size, select a cursor tool, or enable battery mode.
**Edit Village…** opens the asset and string-light editor. **Save Changes to
Preset** stores the current scene, weather and friends locally for later use;
**Reset Preset** restores its original design. The menu bar controls stay in sync.

Eight built-in presets cover the original village asset collection: Cozy Village,
Blizzard, City Snowfall, Christmas Morning, Winter Market, Alpine Retreat,
Lantern Garden, and Gingerbread Lane. Both Cozy Village and Blizzard have houses.
Cozy Village continues across the bottom, with cottages around a café, chalkboard,
streetlamp and bench above the Dock. Factory scenery fits actual sprite widths
to each display. Explicit scene edits and saved presets retain their placements.
The donation menu item has been removed in this personal fork.

A desktop starts with three mixed friends. Choose one to five penguins, foxes or
snowmen, or None. They wander in front of the village, greet nearby friends,
visit landmarks, notice your pointer, and leave fading tracks. Sprite-sized walking
clearances keep mixed groups apart. Blocked residents wait or recover to free
ground; walking animation stops while idle, and centered cursor movement has a
facing deadband. Inactive desktops
pause; each retains its own scene and play state while Snowy runs.

- **Snowball:** on empty desktop, hold Option, flick the pointer, then release
  Option. No click is needed. Snowballs collide with windows and the floor.
- **Build Snowman:** hold Option over empty desktop for about 1.2 seconds, then
  release. It appears at the desktop edge or on the Dock below.
- Shake a dragged window rapidly side to side to shed its attached snow.
- **Battery-Friendly Mode:** keeps settled snow and decorations, stops ambient
  flakes, gust streaks and wandering, and skips unchanged snow redraws. Interactive
  polling is capped at 10 Hz. This toggle is remembered across app launches.

Blizzard flakes enter through upwind boundaries over the screen's full height,
as well as through the top. Eight subtle gust streaks make the wind visible.
Strong storm wind slowly transfers exposed settled snow into the bounded granular
field; material that cannot fit stays on its support. Hanging light wires now
have curved, thin snow supports that follow the moving strings and release snow
when removed. The Vibes **Snow on lights** slider sets their capture chance,
defaulting to 20%; the remaining flakes pass through to lower surfaces. Both
visible flake contacts and ambient accumulation respect the percentage. The
setting is stored with each saved preset, and older presets default to 20%.

The scene cache keeps up to eight desktops per physical screen. Each has at most
five friends, 72 fading tracks, eight snowballs, and 16 placed props. Curved wire
supports share the existing surface and mesh budgets. New effects use the existing
frame clock. Saved preset definitions persist across restarts; macOS desktop
assignments and transient snow/play state currently remain in memory only.

`swift test` covers weather budgets, walking and social pauses, projectile
contacts, shake detection and conservation, idle battery meshes, upwind inflow,
wind erosion and exhausted storage, and snow landing on/removing curved wires.
Debug builds can render the settings window offscreen with
`SNOWY_SETTINGS_PREVIEW_PATH=/tmp/snowy-settings.png`; this also smoke-checks all
preset asset references, preset serialization, and native friend groups of sizes
one through five. `SNOWY_VILLAGE_PREVIEW_PATH=/tmp/snowy-village.png` checks Cozy
prop spacing and renders native scenery and friends at two display widths.
The native Guide explains the controls too.

## A desktop in your browser


The [website](https://snowy.aauburn.com) has its own movable windows, a bottom Dock, and snow you can push around. There may also be someone thawing out for December. Downloads are pay what you want, including $0; optional support uses [Polar hosted checkout](website/docs/payments.md).

Run it locally with **Node.js 22 or later**. No packages need installing.

```sh
npm --prefix website run dev
```

Open the address printed by the server. To make the static site, run `npm --prefix website run build`; the result goes into `website/dist/`. See the [Cloudflare deployment guide](website/docs/deployment.md) to publish it.

## A few rough edges

Window corners and some Dock bounds are estimates because macOS doesn’t expose every visible outline. Custom window shapes and system updates can need adjustments. The app has bounded simulation and rendering budgets, respects Low Power Mode and Reduced Motion, and pauses for sleep or fullscreen content. These are design choices, not a battery-life claim.

If something behaves oddly, [open an issue](https://github.com/soloiaros/snowy-mac/issues) with your macOS version, screen setup, Dock position, and steps to reproduce it.

## Contributing

```sh
swift test
npm --prefix website ci --ignore-scripts
npm --prefix website test
npm --prefix website run build
```

The tests run headlessly. They don’t open the app, inspect your desktop, or run benchmarks. See [CONTRIBUTING.md](CONTRIBUTING.md) for the project layout and release steps, and [the architecture notes](docs/architecture.md) for the physics and resource limits.

## Credits and license

The readable, personal repository style was inspired by [Window Sweaters](https://github.com/saragordic/window-sweaters). Snowy has its own implementation and artwork; it does not include Window Sweaters or JankyBorders code.

Code and original artwork use the [MIT license](LICENSE). The user-provided sound clip is excluded from that license.
