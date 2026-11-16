// LockDown — Omarchy's own bar, with its layout-editing gestures held behind a
// switch.
//
// Nothing of Omarchy's bar is copied here. This mounts the bar the running
// Omarchy ships (`$OMARCHY_PATH/shell/plugins/bar/Bar.qml`) and hands it a
// guarded shell, so `omarchy update` brings new bar work into this plugin with
// nothing to regenerate, re-anchor or merge.
//
// The lock uses Omarchy's own proposed spelling for it — the flag path, the
// click-vs-chord split and the widget guard all come from omacom/omarchy#18082,
// "Add config-lock guards for bar, workspaces, and dock", by @Da1NOnlyCheezIt:
// while `~/.local/state/omarchy/toggles/config-lock` exists, pointer-driven
// layout edits are declined. When that guard lands in the shell, this bar plugin
// can be removed and the flag alone keeps working.
//
// Two of the bar's gestures go through `shell.mutateShellConfig`: moving the bar
// to another edge, and dragging a widget to reorder or remove it. While locked
// the bar is handed a shell object with no `mutateShellConfig` at all, which is
// how the bar itself asks "may I persist this?" — so a widget drag never starts
// (no ghost, no spacer, no removal) and a bar move that lands is put back.
// Two more are commands the bar spawns for itself, which a plugin cannot
// intercept (QML methods are read-only, so `bar.run` cannot be wrapped):
//   - double-click the bar -> cycles its background
//   - clicking the active workspace -> cycles the layout (guarded in
//     Workspaces.qml, which this plugin also ships)
// The background is held from this side instead: while locked the bar is handed
// the background it had when it locked, and a change that lands in shell.json is
// written back. The screen does not change, and shell.json keeps saying what the
// screen shows.
//
// A locked drag on empty bar space still draws the bar's edge highlight before
// the release is undone: that preview lives inside the bar.

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
  id: wrapper

  // The properties the omarchy-shell host injects into a bar plugin. Declaring
  // the same names the built-in bar declares is what makes this a drop-in
  // replacement: the host fills them in, the loaded bar reads them.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var barConfig: ({})
  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null

  // Upstream's flag for this lock. Present = locked.
  readonly property string lockFlag: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/toggles/config-lock"
  readonly property string shellConfigPath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omarchy/shell.json"
  property bool locked: true

  FileView {
    path: wrapper.lockFlag
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: wrapper.locked = true
    onLoadFailed: wrapper.locked = false
  }

  // ---- the bar background, held while locked -------------------------------
  //
  // Double-clicking the bar runs `omarchy-bar background cycle`, which writes
  // shell.json. The write is not interceptable, so it is undone: the value the
  // bar shows at lock time is remembered, the loaded bar is handed that value,
  // and a different one arriving in shell.json is written back.

  property string heldBackground: ""
  property bool revertingBackground: false

  readonly property string currentBackground: barConfig && barConfig.background ? String(barConfig.background) : ""

  // Captured the first time a background is known while locked, and dropped when
  // the bar unlocks. `barConfig` arrives after the plugin mounts, so this watches
  // it rather than only reacting to the lock flag.
  onCurrentBackgroundChanged: if (locked && heldBackground === "") heldBackground = currentBackground

  onLockedChanged: {
    if (locked) {
      if (heldBackground === "") heldBackground = currentBackground
      if (heldPosition === "") heldPosition = currentPosition
    } else {
      heldBackground = ""
      revertingBackground = false
      revertAttempts = 0
      heldPosition = ""
    }
    applyShell()
  }

  // ---- the bar's edge, held while locked ------------------------------------
  //
  // The bar has only one way to say "the shell will not persist this": it sets
  // its own `position` property instead of writing the config. So a locked drag
  // that lands has to be put back, or the bar would sit on another edge until
  // the next config reload.

  property string heldPosition: ""
  readonly property string currentPosition: barConfig && barConfig.position ? String(barConfig.position) : ""

  onCurrentPositionChanged: if (locked && heldPosition === "") heldPosition = currentPosition

  Connections {
    target: barLoader.item
    ignoreUnknownSignals: true

    function onPositionChanged() {
      var bar = barLoader.item
      if (!bar) return
      if (!wrapper.locked) {
        wrapper.heldPosition = String(bar.position)
        return
      }
      if (wrapper.heldPosition && String(bar.position) !== wrapper.heldPosition)
        bar.position = wrapper.heldPosition
    }
  }

  // The config the loaded bar renders: identical to the host's, except that a
  // locked bar keeps the background it locked with.
  readonly property var effectiveBarConfig: {
    var cfg = wrapper.barConfig
    if (!wrapper.locked || !wrapper.heldBackground || !cfg || !cfg.background) return cfg
    if (String(cfg.background) === wrapper.heldBackground) return cfg
    var copy = JSON.parse(JSON.stringify(cfg))
    copy.background = wrapper.heldBackground
    return copy
  }

  FileView {
    id: shellConfigFile

    path: wrapper.shellConfigPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: wrapper.checkBackground(text())
  }

  // The writer of shell.json and this revert can interleave, so a revert that
  // loses the race is retried a few times rather than assumed to have won.
  property int revertAttempts: 0

  function checkBackground(text) {
    if (!wrapper.locked || !wrapper.heldBackground) return
    var seen = ""
    try {
      var cfg = JSON.parse(text || "{}")
      seen = cfg && cfg.bar && cfg.bar.background ? String(cfg.bar.background) : ""
    } catch (e) {
      return
    }
    if (!seen || seen === wrapper.heldBackground) {
      revertAttempts = 0
      revertingBackground = false
      return
    }
    if (revertingBackground || revertAttempts >= 5) return
    // Only the three shapes Omarchy writes, so nothing else can ride along.
    if (!/^(opaque|glassy|none)$/.test(wrapper.heldBackground)) return
    revertAttempts++
    revertingBackground = true
    Quickshell.execDetached(["bash", "-lc", "omarchy-bar background " + wrapper.heldBackground])
    revertTimer.restart()
  }

  Timer {
    id: revertTimer
    interval: 400
    onTriggered: {
      wrapper.revertingBackground = false
      shellConfigFile.reload()
    }
  }

  // ---- the shell the bar is handed ----------------------------------------
  //
  // The bar persists its layout edits through `shell.mutateShellConfig` and, in
  // three places, asks whether that method exists:
  //   - `canReorder` (widget drag: reorder, remove)      -> drag never starts
  //   - `setBarPosition` (drag the bar to another edge)  -> position reset below
  //   - inline widget settings
  // While unlocked it gets the real shell. While locked it gets one with no
  // mutateShellConfig at all, so a widget drag does not begin: nothing is
  // ghosted, dragged or removed. Declining the call instead would still let the
  // bar run its whole drag preview before the write went nowhere.

  readonly property QtObject openShell: QtObject {
    function mutateShellConfig(mutator) {
      return wrapper.shell && typeof wrapper.shell.mutateShellConfig === "function"
        ? wrapper.shell.mutateShellConfig(mutator) : false
    }

    function pluginShellForBarEntry(ownerId, moduleName) {
      return wrapper.shell && typeof wrapper.shell.pluginShellForBarEntry === "function"
        ? wrapper.shell.pluginShellForBarEntry(ownerId, moduleName) : null
    }

    function pluginShellForId(moduleName) {
      return wrapper.shell && typeof wrapper.shell.pluginShellForId === "function"
        ? wrapper.shell.pluginShellForId(moduleName) : null
    }
  }

  readonly property QtObject lockedShell: QtObject {
    function pluginShellForBarEntry(ownerId, moduleName) {
      return wrapper.shell && typeof wrapper.shell.pluginShellForBarEntry === "function"
        ? wrapper.shell.pluginShellForBarEntry(ownerId, moduleName) : null
    }

    function pluginShellForId(moduleName) {
      return wrapper.shell && typeof wrapper.shell.pluginShellForId === "function"
        ? wrapper.shell.pluginShellForId(moduleName) : null
    }
  }

  function applyShell() {
    if (barLoader.item) barLoader.item.shell = wrapper.locked ? wrapper.lockedShell : wrapper.openShell
  }

  Loader {
    id: barLoader

    anchors.fill: parent
    source: wrapper.omarchyPath + "/shell/plugins/bar/Bar.qml"

    onLoaded: {
      var bar = item
      if (!bar) return

      // Bindings, not values: a shell.json reload has to reach the bar.
      bar.omarchyPath = Qt.binding(function() { return wrapper.omarchyPath })
      bar.barConfig = Qt.binding(function() { return wrapper.effectiveBarConfig })
      bar.barWidgetRegistry = Qt.binding(function() { return wrapper.barWidgetRegistry })
      bar.pluginRegistry = Qt.binding(function() { return wrapper.pluginRegistry })
      bar.manifest = Qt.binding(function() { return wrapper.manifest })
      wrapper.applyShell()
    }

    onStatusChanged: {
      if (status === Loader.Error)
        console.warn("LockDown: could not mount " + source + " — is OMARCHY_PATH right?")
    }
  }
}
