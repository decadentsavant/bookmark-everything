pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "." as Local

// Tells the user when a newer version of the plugin is on origin, and can
// install it. Omarchy keeps installed plugins as git checkouts under
// ~/.config/omarchy/plugins and updates them only when asked
// (`omarchy plugin update <id>`), so nothing else would ever mention it.
//
// The check is `git ls-remote origin HEAD` against the local HEAD: read-only
// on the checkout, quiet when offline or when this is not a git checkout.
// Installing runs Omarchy's own update command, which fast-forwards and
// validates. The launcher is keepLoaded, which a plugin rescan leaves alone,
// so the new code only runs after a shell restart: the Options button does
// that restart, an automatic update waits for the next one.
Scope {
  id: service

  readonly property string pluginId: "io.github.decadentsavant.bookmark-everything"
  readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
  readonly property string pluginDir: decodeURIComponent(String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, ""))

  property string localHead: ""       // HEAD of the installed checkout
  property string remoteHead: ""      // HEAD of origin, "" until a check succeeds
  property bool checking: false
  property bool updating: false
  property double lastCheck: 0        // ms since epoch, 0 = never
  property int retained: 0

  readonly property bool available: remoteHead !== "" && localHead !== "" && remoteHead !== localHead
  readonly property string status: {
    if (updating) return "Updating…"
    if (checking) return "Checking for updates…"
    if (available) return "Update available"
    if (remoteHead) return "Up to date"
    return ""
  }

  // The overlay and the bar widget hold a reference while loaded; the timers
  // only run while something does, so a disabled plugin never phones home.
  function retain() {
    retained++
    if (retained === 1) { firstCheck.start(); poll.start() }
  }

  function release() {
    retained = Math.max(0, retained - 1)
    if (retained === 0) { firstCheck.stop(); poll.stop() }
  }

  // Throttled unless forced, so opening Options is cheap. Settings load
  // asynchronously, and "updateCheck": false in the file must win, so
  // nothing runs before they have.
  function check(force) {
    if (checking || updating || retained <= 0) return
    if (!Local.HotkeyService.settingsLoaded || !Local.HotkeyService.updateCheck) return
    if (!force && lastCheck && Date.now() - lastCheck < 10 * 60 * 1000) return
    checking = true
    checkProc.running = true
  }

  function handleCheck(text) {
    checking = false
    lastCheck = Date.now()
    var lines = String(text || "").trim().split("\n")
    if (lines.length < 2) return   // offline, no remote, or not a git checkout
    var local = lines[0].trim()
    var remote = lines[1].trim().split(/\s+/)[0]
    if (!/^[0-9a-f]{40}$/.test(local) || !/^[0-9a-f]{40}$/.test(remote)) return
    localHead = local
    remoteHead = remote
    if (!available || !Local.HotkeyService.settingsLoaded) return
    if (Local.HotkeyService.autoUpdate) { update(false); return }
    // One notification per new remote commit, remembered in the settings
    // file so it does not repeat at every login.
    if (Local.HotkeyService.noticedUpdate === remote) return
    Local.HotkeyService.setNoticedUpdate(remote)
    notify("A new version is available. Open Options from the bookmark icon to update, or run: omarchy plugin update " + pluginId)
  }

  // Runs detached: a successful update reloads this plugin mid-flight, so
  // nothing here can wait for the result. The script reports either way.
  function update(restartShell) {
    if (updating) return
    updating = true
    updatingReset.restart()
    Quickshell.execDetached(["sh", "-c", updateScript, "sh", pluginId, pluginDir, omarchyPath, restartShell === true ? "restart" : ""])
  }

  readonly property string updateScript: 'PATH="$3/bin:$PATH"; export PATH; ' +
    'if out=$("$3/bin/omarchy-plugin-update" "$1" --yes 2>&1); then ' +
    '  v=$(jq -r .version "$2/manifest.json" 2>/dev/null); ' +
    '  if [ "$4" = restart ]; then ' +
    '    "$3/bin/omarchy-notification-send" "Bookmark Everything" "Updated to v${v:-?}. Restarting the shell to load it."; ' +
    '    sleep 1; "$3/bin/omarchy-restart-shell"; ' +
    '  else ' +
    '    "$3/bin/omarchy-notification-send" "Bookmark Everything" "Updated to v${v:-?}. It loads at the next login, or now with: omarchy restart shell"; ' +
    '  fi; ' +
    'else ' +
    '  "$3/bin/omarchy-notification-send" "Bookmark Everything" "Update failed: $(printf %s "$out" | tail -n 1)"; ' +
    'fi'

  function notify(body) {
    Quickshell.execDetached([omarchyPath + "/bin/omarchy-notification-send", "Bookmark Everything", body])
  }

  Process {
    id: checkProc
    command: ["sh", "-c",
      'cd "$1" && git rev-parse HEAD && ' +
      'GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -oBatchMode=yes" timeout 20 git ls-remote --quiet origin HEAD',
      "sh", service.pluginDir]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: service.handleCheck(text)
    }
  }

  // Shortly after login, then every six hours (the same cadence as the
  // system-update widget in the bar).
  Timer { id: firstCheck; interval: 60 * 1000; repeat: false; onTriggered: service.check(true) }
  Timer { id: poll; interval: 6 * 60 * 60 * 1000; repeat: true; onTriggered: service.check(true) }
  // If the update failed the plugin was not reloaded; let the button come back.
  Timer { id: updatingReset; interval: 90 * 1000; repeat: false; onTriggered: service.updating = false }
}
