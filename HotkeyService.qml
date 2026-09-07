pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "HotkeyModel.js" as HK

// Registers the launcher's Hyprland keybinding at runtime, shared by the
// overlay and the bar widget so both show the same state.
//
// Nothing under ~/.config/hypr is written. The bind lives in the running
// compositor (`hyprctl eval`), comes back after `hyprctl reload`, and is
// removed when the plugin is disabled or removed. The preferred key and the
// on/off switch live in a small plugin-owned settings file.
Scope {
  id: service

  readonly property string pluginId: "io.github.decadentsavant.bookmark-everything"
  readonly property string home: Quickshell.env("HOME")
  readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
  readonly property string settingsPath: home + "/.config/omarchy/bookmark-everything.settings.json"
  readonly property string command: "omarchy-shell shell toggle " + pluginId

  property string hotkey: HK.DEFAULT_HOTKEY   // the key the user wants
  property bool enabled: true
  property string noticed: ""                 // last fallback we notified about
  property string active: ""                  // the key actually registered right now
  property string preferredOwner: ""          // what holds `hotkey` when we fell back
  property var binds: []                      // last parse of `hyprctl binds`
  property bool ready: false                  // settings read and first scan finished
  property int retained: 0
  property int applyAttempts: 0
  property bool settingsLoaded: false

  readonly property string summary: HK.summary(active, hotkey, preferredOwner, enabled)
  readonly property string prettyActive: active ? HK.pretty(active) : ""

  function pretty(combo) { return HK.pretty(combo) }
  function statusOf(combo) { return HK.status(binds, combo) }

  // The overlay and each bar widget hold a reference while loaded; the bind
  // is released when the last one goes away (plugin disabled or removed).
  function retain() {
    retained++
    if (retained === 1) start()
  }

  function release() {
    retained = Math.max(0, retained - 1)
    if (retained === 0) releaseBind()
  }

  function start() {
    settingsFile.reload()
  }

  function applySettings(text) {
    var s = HK.parseSettings(text)
    hotkey = s.hotkey
    enabled = s.enabled
    noticed = s.noticed
    settingsLoaded = true
    scan()
  }

  function save() {
    settingsFile.setText(HK.serializeSettings({ hotkey: hotkey, enabled: enabled, noticed: noticed }))
  }

  // Re-reads `hyprctl binds` and reconciles. Safe to call any time.
  function scan() {
    if (bindsProc.running) { bindsProc.rerun = true; return }
    bindsProc.running = true
  }

  function reconcile() {
    if (!settingsLoaded) return
    var script = ""
    // The singleton outlives the overlay and the bar widget, and a watcher
    // (settings file, Hyprland reload) can still wake it after the plugin is
    // disabled or removed. With nothing retaining it, only ever let go.
    if (retained <= 0) {
      script = HK.releaseScript(binds)
      active = ""
      preferredOwner = ""
      if (script) Quickshell.execDetached(["hyprctl", "eval", script])
      return
    }
    if (!enabled) {
      script = HK.releaseScript(binds)
      active = ""
      preferredOwner = ""
    } else {
      var r = HK.resolve(binds, hotkey)
      script = HK.applyScript(binds, r.target, command)
      active = r.target
      preferredOwner = r.fallback ? r.preferredOwner : ""
      noticeIfNeeded(r)
    }
    ready = true
    if (!script) { applyAttempts = 0; return }
    if (applyAttempts >= 2) {
      console.warn("Bookmark Everything: hyprctl eval did not take effect: " + script)
      applyAttempts = 0
      return
    }
    applyAttempts++
    Quickshell.execDetached(["hyprctl", "eval", script])
    verifyTimer.restart()
  }

  // Tell the user once when their preferred key was taken and we used another,
  // or when nothing was free. Remembered in the settings file so it does not
  // repeat at every login.
  function noticeIfNeeded(r) {
    if (!r.fallback) { if (noticed) { noticed = ""; save() }; return }
    var key = r.preferred + " -> " + r.target
    if (key === noticed) return
    noticed = key
    save()
    var body
    if (r.target)
      body = "Opens with " + HK.pretty(r.target) + ". " + HK.pretty(r.preferred) + " was already used" + (r.preferredOwner ? " for “" + r.preferredOwner + "”" : "") + ". Click the bookmark icon in the bar to change it."
    else
      body = HK.pretty(r.preferred) + " and every fallback key are taken. Open the launcher from the bookmark icon in the bar and choose another."
    Quickshell.execDetached([omarchyPath + "/bin/omarchy-notification-send", "Bookmark Everything", body])
  }

  // "" on success, otherwise a message for the user. A key something else
  // already holds is refused rather than silently falling back, so the CLI
  // and the chooser agree.
  function setHotkey(combo) {
    var p = HK.parseCombo(combo)
    if (p.error) return p.error
    var st = HK.status(binds, p.combo)
    if (st.state === "taken") return HK.pretty(p.combo) + " is already used for “" + st.owner + "”"
    hotkey = p.combo
    enabled = true
    noticed = ""
    save()
    scan()
    return ""
  }

  function setEnabled(value) {
    enabled = value === true
    if (enabled) noticed = ""
    save()
    scan()
  }

  function releaseBind() {
    var script = HK.releaseScript(binds)
    if (script) Quickshell.execDetached(["hyprctl", "eval", script])
    active = ""
  }

  FileView {
    id: settingsFile
    path: service.settingsPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: service.applySettings(text())
    onLoadFailed: service.applySettings("")
    onFileChanged: reload()
  }

  Process {
    id: bindsProc
    property bool rerun: false
    command: ["hyprctl", "binds"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        service.binds = HK.parseBinds(text)
        service.reconcile()
        if (bindsProc.rerun) { bindsProc.rerun = false; Qt.callLater(service.scan) }
      }
    }
  }

  // Confirms a bind or unbind landed. If it did, the next reconcile is a no-op.
  Timer {
    id: verifyTimer
    interval: 400
    repeat: false
    onTriggered: service.scan()
  }

  // A config reload rebuilds Hyprland's binds from the Lua config and drops
  // runtime ones, so put ours back.
  Timer {
    id: reloadTimer
    interval: 600
    repeat: false
    onTriggered: service.scan()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && String(event.name) === "configreloaded") reloadTimer.restart()
    }
  }
}
