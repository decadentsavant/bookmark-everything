import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "BookmarkModel.js" as Model
import "HotkeyModel.js" as HK
import "." as Local

// Bookmark Everything — keyboard-first launcher for URLs, files, folders, and
// applications. Summoned through the shell:
//   omarchy-shell shell toggle io.github.decadentsavant.bookmark-everything '{}'
//   omarchy-shell shell summon io.github.decadentsavant.bookmark-everything '{"mode":"search"}'
// Extra IPC methods (omarchy-shell shell call io.github.decadentsavant.bookmark-everything <method> <arg>):
//   addBookmark <target>, addFromClipboard, importFrom <path>, exportTo <path>
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginId: (root.manifest && root.manifest.id) || "io.github.decadentsavant.bookmark-everything"
  readonly property string pluginDir: decodeURIComponent(String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, ""))
  readonly property string helpPath: root.pluginDir + "/help.html"
  property string storePath: root.home + "/.config/omarchy/bookmark-everything.json"

  // Inline settings on this plugin's entry in ~/.config/omarchy/shell.json:
  //   { "id": "io.github.decadentsavant.bookmark-everything", "openMode": "hints" | "search" }
  readonly property var pluginSettings: {
    var cfg = root.shell ? root.shell.shellConfig : null
    var list = cfg && Array.isArray(cfg.plugins) ? cfg.plugins : []
    for (var i = 0; i < list.length; i++)
      if (list[i] && list[i].id === root.pluginId) return list[i]
    return ({})
  }
  readonly property string configuredOpenMode: root.pluginSettings.openMode === "search" ? "search" : "hints"

  // The hotkey itself is registered by HotkeyService, shared with the bar
  // widget. Retaining it here keeps the bind alive for as long as the overlay
  // is loaded, and releasing it on unload removes the bind.
  Component.onCompleted: Local.HotkeyService.retain()
  Component.onDestruction: Local.HotkeyService.release()

  property bool opened: false
  property string view: "list"        // list | form | apps | prompt | options
  property string mode: "hints"       // hints | search
  property string openMode: "hints"   // mode the launcher opened in (Esc target)
  property string hintBuffer: ""
  property string filterText: ""
  property var entries: []            // user bookmarks, normalized
  property var displayEntries: []     // rows currently shown, in order
  property int selectedIndex: 0
  property bool cursorActive: true
  property bool storeLoaded: false
  property string notice: ""

  // Delete confirmation + row action sheet (mouse overflow menu).
  property bool deleteConfirmOpen: false
  property var deleteTarget: null
  property bool actionsOpen: false
  property int actionsIndex: 0
  property var actionsEntry: null   // pinned when the sheet opens

  // Add / edit form.
  property string formMode: "add"     // add | edit
  property string formId: ""
  property string formType: "url"     // url | path | app  (path saves as file or folder)
  property string formAppName: ""
  property int formFocus: 1           // 0 type, 1 name, 2 target, 3 tags, 4 notes, 5 hint
  property string formError: ""
  property string formDefaultHint: ""   // code the entry had (edit) or was auto-assigned (add)
  property bool formSaving: false
  readonly property var typeOptions: ["url", "path", "app"]

  // Path completion for the Target field (file/folder). pathDir is the
  // directory part as typed (may start with ~/), pathPrefix the partial name.
  property string pathDir: ""
  property string pathPrefix: ""
  property var pathNames: []          // every entry of pathDir from ls
  property var pathCandidates: []     // pathNames filtered by pathPrefix
  property int pathCandidateIndex: -1
  property bool pendingTabComplete: false   // Tab pressed before the listing arrived
  readonly property bool pathListVisible: root.view === "form" && root.formFocus === 2 && root.formType !== "app" && root.pathCandidates.length > 0

  // Places picker: folders and files the user already uses, gathered from
  // the Files sidebar bookmarks, zoxide, and GTK recent files.
  property var places: []
  property string placesFilter: ""
  property int placesIndex: 0
  property bool placesLoading: false

  // Application picker. appsSelected is a set of desktop ids for bulk add.
  property string appsFilter: ""
  property int appsIndex: 0
  property var appsSelected: ({})
  property int appsSelectedCount: 0
  property bool appsBulkMode: false

  // Import / export path prompt.
  property string promptKind: "import"
  property bool importPending: false

  // --------------------------------------------------------- options view
  property string hotkeyInput: ""
  readonly property int listFooterHeight: Style.space(26)
  // What the typed combination means right now, against the live bind list.
  readonly property var hotkeyCheck: {
    var binds = Local.HotkeyService.binds
    var p = HK.parseCombo(root.hotkeyInput)
    if (p.error) return { ok: false, message: p.error, combo: "" }
    var st = HK.status(binds, p.combo)
    if (st.state === "taken") return { ok: false, message: HK.pretty(p.combo) + " is already used for “" + st.owner + "”. Choose another, or free it in ~/.config/hypr/bindings.lua.", combo: p.combo }
    if (p.combo === Local.HotkeyService.active) return { ok: true, message: "This is the current hotkey.", combo: p.combo }
    return { ok: true, message: HK.pretty(p.combo) + " is free. Enter to use it.", combo: p.combo }
  }
  // The line to paste into bindings.lua when the built-in hotkey is off.
  readonly property string bindingSnippet: HK.luaBindUser(Local.HotkeyService.hotkey || HK.DEFAULT_HOTKEY, root.pluginId)
  // Whether the bar icon is in the bar layout right now.
  readonly property bool iconInBar: {
    var cfg = root.shell ? root.shell.shellConfig : null
    var layout = cfg && cfg.bar && cfg.bar.layout ? cfg.bar.layout : null
    if (!layout) return false
    var sections = ["left", "center", "right"]
    for (var s = 0; s < sections.length; s++) {
      var arr = layout[sections[s]] || []
      for (var i = 0; i < arr.length; i++) if (arr[i] && arr[i].id === root.pluginId) return true
    }
    return false
  }

  // Shares the [menu] surface tokens so themes that style the Omarchy menu
  // style this launcher too.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color selectedBorder: Color.menu.selectedBorder
  property var selectedBorderSpec: Border.surfaceSpec("menu", "selected-border", selectedBorder, 0)
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md
  property int rowHeight: Math.max(Style.space(46), Style.font.heading + Style.font.bodySmall + Style.space(14))
  property int rowSpacing: Style.spacing.xs
  property int maxVisibleRows: 12
  property int hintColumnWidth: Style.space(34)
  property int iconColumnWidth: Style.space(30)
  property int formLabelWidth: Style.space(66)
  property int formRowHeight: Style.spacing.controlHeight + Style.spacing.lg
  property int cardWidth: Math.min(Style.space(640), panel.width - Style.gapsOut * 2)
  readonly property bool showEmptyHint: root.view === "list" && root.entries.length === 0
  readonly property int listRows: Math.max(3, Math.min(displayModel.count, root.maxVisibleRows)) + (root.showEmptyHint ? 1 : 0)
  readonly property int bodyHeight: {
    if (root.view === "form") return root.formRowHeight * 6 + Style.space(30) + Style.spacing.controlHeight + Style.spacing.lg * 2 + Style.space(16)
    if (root.view === "apps") return Math.max(4, Math.min(appsModel.count, 10)) * (root.rowHeight + root.rowSpacing) + Style.space(22)
    if (root.view === "places") return Math.max(4, Math.min(placesModel.count, 10)) * (root.rowHeight + root.rowSpacing) + Style.space(22)
    if (root.view === "prompt") return Style.spacing.controlHeight + Style.space(30)
    if (root.view === "options") return optionsColumn.implicitHeight + Style.space(8)
    return root.listRows * (root.rowHeight + root.rowSpacing) + root.listFooterHeight
  }
  property int cardHeight: Math.min(contentMargin * 2 + headerHeight + contentSpacing + bodyHeight, panel.height - Style.gapsOut * 2)

  // ------------------------------------------------------------ lifecycle

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    var requested = payload.mode === "search" || payload.mode === "hints" ? payload.mode : root.configuredOpenMode
    root.openMode = requested
    root.mode = requested
    root.view = "list"
    root.hintBuffer = ""
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.notice = ""
    root.deleteConfirmOpen = false
    root.actionsOpen = false
    root.opened = true
    panel.cardTop = -1
    root.disarmPointer()
    if (root.shell && root.shell.appLibrary && typeof root.shell.appLibrary.refreshIcons === "function")
      root.shell.appLibrary.refreshIcons()
    root.refreshDecorations()
    if (root.seedPending) root.seedDefaults()   // index still empty: seed without the app sample
    root.rebuildDisplay()
    if (payload.add !== undefined) root.openAdd(String(payload.add || ""))
    else if (payload.options || payload.hotkey) root.openOptions()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.deleteConfirmOpen = false
    root.actionsOpen = false
    root.opened = false
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function ensureOpen() {
    if (!root.opened) root.open("{}")
  }

  // IPC: omarchy-shell shell call io.github.decadentsavant.bookmark-everything addBookmark <target>
  function addBookmark(target) {
    root.ensureOpen()
    root.openAdd(String(target || ""))
    return "ok"
  }

  // IPC: omarchy-shell shell call io.github.decadentsavant.bookmark-everything pickApplications ''
  // Opens the application picker in bulk mode: Space selects, Ctrl+A selects
  // all, Enter adds every selected application as its own bookmark.
  function pickApplications() {
    root.ensureOpen()
    root.deleteConfirmOpen = false
    root.actionsOpen = false
    root.appsBulkMode = true
    root.openAppsPicker("")
    return "ok"
  }

  // IPC: omarchy-shell shell call io.github.decadentsavant.bookmark-everything addFromClipboard ''
  function addFromClipboard() {
    root.ensureOpen()
    clipProc.running = false
    clipProc.running = true
    return "ok"
  }

  // IPC: omarchy-shell shell call io.github.decadentsavant.bookmark-everything importFrom <path>
  function importFrom(path) {
    var p = Model.expandPath(path, root.home)
    if (!p) return "error"
    root.importPending = true
    importFile.path = p
    importFile.reload()
    return "ok"
  }

  // IPC: omarchy-shell shell call io.github.decadentsavant.bookmark-everything exportTo <path>
  function exportTo(path) {
    var p = Model.expandPath(path, root.home)
    if (!p) return "error"
    exportFile.path = p
    exportFile.setText(Model.serialize(root.entries))
    root.showNotice("Exported " + root.entries.length + " bookmarks")
    root.notify("Bookmarks exported", root.entries.length + " bookmarks written to " + Model.compactPath(p, root.home))
    return "ok"
  }

  // IPC: omarchy-shell shell call <id> openHotkeySettings ''
  function openHotkeySettings() {
    root.ensureOpen()
    root.openOptions()
    return "ok"
  }

  // IPC: omarchy-shell shell call <id> setIconInBar false
  // Adds or removes the bar icon. The plugin stays enabled either way through
  // an entry in shell.json's `plugins` list, so the hotkey keeps working.
  function setIconInBar(value) {
    var show = String(value) !== "false"
    if (!root.shell || typeof root.shell.persistShellConfig !== "function") return "error: shell config unavailable"
    var cfg = JSON.parse(JSON.stringify(root.shell.shellConfig || {}))
    if (!cfg.bar || typeof cfg.bar !== "object") cfg.bar = {}
    if (!cfg.bar.layout || typeof cfg.bar.layout !== "object") cfg.bar.layout = { left: [], center: [], right: [] }
    if (!Array.isArray(cfg.plugins)) cfg.plugins = []
    var sections = ["left", "center", "right"]
    for (var s = 0; s < sections.length; s++) {
      var arr = Array.isArray(cfg.bar.layout[sections[s]]) ? cfg.bar.layout[sections[s]] : []
      cfg.bar.layout[sections[s]] = arr.filter(function(e) { return !(e && e.id === root.pluginId) })
    }
    var pluginIndex = -1
    for (var i = 0; i < cfg.plugins.length; i++) if (cfg.plugins[i] && cfg.plugins[i].id === root.pluginId) pluginIndex = i
    if (show) {
      var right = cfg.bar.layout.right
      right.splice(Math.min(1, right.length), 0, { id: root.pluginId })
      // A bare plugins entry only existed to keep the overlay loaded while the
      // icon was hidden; drop it so `omarchy plugin disable` works in one go.
      if (pluginIndex !== -1 && Object.keys(cfg.plugins[pluginIndex]).length === 1) cfg.plugins.splice(pluginIndex, 1)
    } else if (pluginIndex === -1) {
      cfg.plugins.push({ id: root.pluginId })
    }
    root.shell.persistShellConfig(cfg)
    return "ok"
  }

  // IPC: omarchy-shell shell call <id> setHotkey 'SUPER + ALT + B'
  function setHotkey(combo) {
    var err = Local.HotkeyService.setHotkey(String(combo || ""))
    return err ? "error: " + err : "ok"
  }

  // IPC: omarchy-shell shell call <id> setHotkeyEnabled false
  function setHotkeyEnabled(value) {
    Local.HotkeyService.setEnabled(String(value) !== "false")
    return "ok"
  }

  // IPC: omarchy-shell shell call <id> hotkeyStatus ''
  function hotkeyStatus() { return Local.HotkeyService.summary }

  // IPC: omarchy-shell shell call <id> version '' — confirms which code is loaded.
  readonly property string codeVersion: "1.1.0"
  function version() { return root.codeVersion }

  // IPC: omarchy-shell shell call <id> resolveApp <target> — shows which desktop
  // entry a target resolves to ("" when none). Handy for troubleshooting.
  function resolveApp(target) {
    var de = root.lookupApp(target)
    return de ? String(de.id || "") : ""
  }

  // Re-resolve application names, icons, and canonical ids. The desktop
  // entry index may not be populated when the store first loads at shell
  // startup, so this runs again when the index changes and on every open.
  function refreshDecorations() {
    if (root.seedPending && root.appsIndexReady()) { root.seedDefaults(); return }
    if (!root.storeLoaded || root.entries.length === 0) return
    root.entries = root.decorate(root.entries)
    if (root.decorateRepaired) root.saveStore()
    root.checkPaths()
    if (root.opened) root.rebuildDisplay()
  }

  // Paths whose file or folder no longer exists, keyed by expanded path.
  // Filled asynchronously by pathCheckProc so rows can be flagged "missing".
  property var missingPaths: ({})

  function checkPaths() {
    var args = []
    for (var i = 0; i < root.entries.length; i++) {
      var e = root.entries[i]
      if (e.type === "file" || e.type === "folder") args.push(Model.expandPath(e.target, root.home))
    }
    if (args.length === 0) { root.missingPaths = ({}); return }
    pathCheckProc.running = false
    pathCheckProc.command = ["bash", "-c", 'for p in "$@"; do [ -e "$p" ] || printf "%s\\n" "$p"; done', "bash"].concat(args)
    pathCheckProc.running = true
  }

  function applyMissingPaths(raw) {
    var next = ({})
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) if (lines[i]) next[lines[i]] = true
    root.missingPaths = next
    if (root.opened) root.rebuildDisplay()
  }

  function entryMissing(e) {
    if (!e) return false
    if (e.type === "app") return e.missing === true
    if (e.type === "file" || e.type === "folder") return root.missingPaths[Model.expandPath(e.target, root.home)] === true
    return false
  }

  function missingLabel(e) {
    if (e.type === "app") return "not installed"
    return e.type === "folder" ? "folder missing" : "file missing"
  }

  function notify(title, body) {
    Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-notification-send", title, body])
  }

  function showNotice(text) {
    root.notice = text
    noticeTimer.restart()
  }

  // ---------------------------------------------------------------- store

  // First run (no bookmarks file yet): seed a few examples covering every
  // type so the launcher is not empty. The application is the first of a
  // preference list that is installed. Never runs when a file exists.
  property bool seedPending: false
  readonly property var seedApps: [
    { target: "obsidian", name: "Obsidian", tag: "notes" },
    { target: "localsend", name: "LocalSend", tag: "share" },
    { target: "org.gnome.Nautilus", name: "Files", tag: "files" }
  ]

  function appsIndexReady() {
    try { return (DesktopEntries.applications.values || []).length > 0 } catch (e) { return false }
  }

  function seedDefaults() {
    root.seedPending = false
    var list = [
      { type: "folder", name: "Home folder", target: "~/", tags: ["home", "folder"], notes: "Your home folder. Edit or delete these starter bookmarks freely." },
      { type: "folder", name: "Downloads folder", target: "~/Downloads", tags: ["downloads", "folder"], notes: "" },
      { type: "url", name: "Bookmark Everything on GitHub", target: "https://github.com/decadentsavant/bookmark-everything", tags: ["docs", "github"], notes: "Source, issues, and updates for this plugin" },
      { type: "url", name: "Baton on GitHub", target: "https://github.com/decadentsavant/baton", tags: ["plugin", "github"], notes: "Wave at a random Omarchy user. Another plugin by the same author." },
      { type: "url", name: "decadentsavant on X", target: "https://x.com/decadentsavant", tags: ["author", "social"], notes: "The plugin's author" }
    ]
    for (var i = 0; i < root.seedApps.length; i++) {
      var de = root.lookupApp(root.seedApps[i].target)
      if (de) {
        list.push({ type: "app", name: String(de.name || root.seedApps[i].name), target: String(de.id || root.seedApps[i].target), tags: ["app", root.seedApps[i].tag], notes: String(de.comment || "") })
        break
      }
    }
    var result = Model.parseBookmarks(JSON.stringify(list))
    root.entries = root.decorate(result.entries)
    root.storeLoaded = true
    root.saveStore()
    root.checkPaths()
    root.rebuildDisplay()
  }

  // Called when the bookmarks file does not exist yet.
  function handleMissingStore() {
    if (root.appsIndexReady()) { root.seedDefaults(); return }
    // The desktop-entry index fills in shortly after shell startup; seed
    // once it is there so the application sample can be resolved.
    root.seedPending = true
    root.entries = []
    root.storeLoaded = true
    root.rebuildDisplay()
  }

  function loadStore(raw) {
    var result = Model.parseBookmarks(raw)
    if (result.error) {
      console.warn("bookmarks: " + result.error)
      root.showNotice("bookmark-everything.json is not valid JSON")
      root.notify("Bookmarks", "Could not parse " + Model.compactPath(root.storePath, root.home) + ": " + result.error)
      if (!root.storeLoaded) root.entries = []
      root.storeLoaded = true
      root.rebuildDisplay()
      return
    }
    root.entries = root.decorate(result.entries)
    root.storeLoaded = true
    if (result.changed || root.decorateRepaired) root.saveStore()
    root.rebuildDisplay()
  }

  function saveStore() {
    storeFile.setText(Model.serialize(root.entries))
  }

  // Set by decorate() when an application target was rewritten to its
  // canonical desktop id (e.g. "nautilus" → "org.gnome.Nautilus"), so the
  // caller knows the store needs saving.
  property bool decorateRepaired: false

  function decorate(list) {
    root.decorateRepaired = false
    for (var i = 0; i < list.length; i++) {
      var e = list[i]
      if (e.type === "app") {
        var de = root.lookupApp(e.target)
        if (de && de.id && String(de.id) !== e.target) {
          e.target = String(de.id)
          root.decorateRepaired = true
        }
        e.appName = de ? String(de.name || "") : ""
        e.appIcon = de ? root.appIconSource(de.icon) : ""
        e.missing = !de
      } else {
        e.appName = ""
        e.appIcon = ""
        e.missing = false
      }
    }
    Model.prepareSearch(list)
    return list
  }

  function lookupApp(id) {
    var value = String(id || "").trim()
    if (!value) return null
    var found = null
    try { found = DesktopEntries.byId(value) } catch (e) { found = null }
    if (!found && value.slice(-8) === ".desktop") {
      try { found = DesktopEntries.byId(value.slice(0, -8)) } catch (e2) { found = null }
    }
    if (!found) {
      try { found = DesktopEntries.heuristicLookup(value) } catch (e3) { found = null }
    }
    if (!found) found = root.fuzzyLookupApp(value)
    return found
  }

  // Quickshell's heuristicLookup does not map "nautilus" to
  // org.gnome.Nautilus. Match, in order: the id case-insensitively, the last
  // dot-component of the id, the display name, then the executable's name.
  function fuzzyLookupApp(value) {
    var t = String(value || "").trim().toLowerCase().replace(/\.desktop$/, "")
    if (!t) return null
    var values = []
    try { values = DesktopEntries.applications.values || [] } catch (e) { values = [] }
    // Each tier is only trusted when it matches exactly one entry; an
    // ambiguous tier is skipped rather than guessed at.
    var tiers = [[], [], [], []]   // id, id tail, name, executable
    for (var i = 0; i < values.length; i++) {
      var de = values[i]
      if (!de) continue
      var idLower = String(de.id || "").toLowerCase()
      if (idLower === t) tiers[0].push(de)
      if (de.noDisplay) continue
      if (idLower.split(".").pop() === t) tiers[1].push(de)
      if (String(de.name || "").toLowerCase() === t) tiers[2].push(de)
      var cmd = ""
      try { cmd = de.command && de.command.length ? String(de.command[0]) : String(de.execString || "").split(/\s+/)[0] } catch (e2) { cmd = "" }
      if (cmd && cmd.split("/").pop().toLowerCase() === t) tiers[3].push(de)
    }
    for (var k = 0; k < tiers.length; k++) if (tiers[k].length === 1) return tiers[k][0]
    return null
  }

  function appIconSource(icon) {
    if (root.shell && root.shell.appLibrary) return root.shell.appLibrary.iconSource(icon)
    var themed = Quickshell.iconPath(String(icon || ""), true)
    return themed || ""
  }

  function entryDetail(e) {
    var target = e.type === "app" ? (e.appName ? e.appName + " · " + e.target : e.target) : Model.compactPath(e.target, root.home)
    var tags = (e.tags || []).length ? "  #" + e.tags.join(" #") : ""
    var flag = root.entryMissing(e) ? root.missingLabel(e) + "  ·  " : ""
    return flag + target + tags
  }

  // -------------------------------------------------------------- display

  function rebuildDisplay() {
    var help = Model.helpEntry(root.helpPath)
    help.appName = ""
    help.appIcon = ""
    var all = Model.sortByHint(root.entries).concat([help])
    var rows = root.mode === "hints"
      ? Model.hintFilter(all, root.hintBuffer)
      : Model.search(all, root.filterText, 300)
    root.displayEntries = rows

    displayModel.clear()
    for (var i = 0; i < rows.length; i++) {
      var e = rows[i]
      displayModel.append({
        entryId: e.id,
        hint: e.hint || "",
        type: e.type,
        name: e.name,
        detail: root.entryDetail(e),
        glyph: Model.typeIcon(e.type),
        appIcon: e.appIcon || "",
        builtin: e.builtin === true,
        missing: root.entryMissing(e)
      })
    }

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function select(delta) {
    if (displayModel.count === 0) return
    root.disarmPointer()
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count
    }
    resultList.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function selectAbsolute(index) {
    if (displayModel.count === 0) return
    root.disarmPointer()
    root.cursorActive = true
    root.selectedIndex = Math.max(0, Math.min(index, displayModel.count - 1))
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function selectEntryId(id) {
    for (var i = 0; i < root.displayEntries.length; i++) {
      if (root.displayEntries[i].id === id) { root.selectAbsolute(i); return }
    }
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    root.cursorActive = true
    root.selectedIndex = index
  }

  function selectedEntry() {
    if (root.selectedIndex < 0 || root.selectedIndex >= root.displayEntries.length) return null
    return root.displayEntries[root.selectedIndex]
  }

  function switchMode(next) {
    root.mode = next
    root.hintBuffer = ""
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.rebuildDisplay()
  }

  function setFilter(next) {
    panel.freezeCardTop()
    root.filterText = next
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.rebuildDisplay()
  }

  function setHintBuffer(next) {
    panel.freezeCardTop()
    root.hintBuffer = next
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.rebuildDisplay()
  }

  function typeHint(letter) {
    var next = root.hintBuffer + letter
    if (next.length >= 2) {
      var hit = Model.findByHint(root.displayEntries, next)
      if (hit) { root.launch(hit); return }
      root.showNotice("No bookmark " + next)
      root.setHintBuffer("")
      return
    }
    root.setHintBuffer(next)
    if (displayModel.count === 0) {
      root.showNotice("No bookmark starts with " + next)
      root.setHintBuffer("")
    }
  }

  // --------------------------------------------------------------- launch

  function activateIndex(index) {
    if (index < 0 || index >= root.displayEntries.length) return
    root.launch(root.displayEntries[index])
  }

  function launch(e) {
    if (!e) return
    root.dismiss()
    if (e.type === "app") {
      // gtk-launch needs the desktop file's real id; resolve heuristically so
      // a hand-written target like "nautilus" still launches org.gnome.Nautilus.
      var de = root.lookupApp(e.target)
      if (!de) {
        root.notify("Bookmark Everything", "No installed application matches “" + e.target + "”")
        return
      }
      var appId = String(de.id || e.target)
      if (root.shell && root.shell.appLibrary && typeof root.shell.appLibrary.launch === "function") {
        root.shell.appLibrary.launch(appId, e.name)
      } else {
        Util.execArgv(["uwsm-app", "--", "gtk-launch", appId + ".desktop"])
      }
      return
    }
    var target = e.type === "url" ? e.target : Model.expandPath(e.target, root.home)
    if (e.type !== "url" && root.missingPaths[target] === true) {
      root.notify("Bookmark Everything", root.missingLabel(e) + ": " + Model.compactPath(target, root.home))
      return
    }
    // uwsm-app puts the opened application in its own scope instead of
    // parenting it to the shell process.
    Util.execArgv(["uwsm-app", "--", "xdg-open", target])
  }

  function openHelp() {
    root.launch(Model.helpEntry(root.helpPath))
  }

  // ---------------------------------------------------------- add / edit

  function openAdd(target) {
    root.deleteConfirmOpen = false
    root.actionsOpen = false
    root.formMode = "add"
    root.formId = ""
    root.formType = "url"
    root.formAppName = ""
    root.formError = ""
    root.formSaving = false
    root.clearPathCompletion()
    nameField.text = ""
    targetField.text = ""
    tagsField.text = ""
    notesField.text = ""
    root.formDefaultHint = Model.nextFreeHint(root.entries, "")
    hintField.text = root.formDefaultHint
    hintField.placeholderText = root.formDefaultHint || "none free"
    root.view = "form"
    var t = String(target || "").trim()
    if (t) {
      targetField.text = t
      root.detectTargetType(t)
      root.formFocus = 1     // target known: start on Name
    } else {
      root.formFocus = 0     // start on the Type row
    }
    Qt.callLater(root.focusFormField)
  }

  function openEdit(e) {
    if (!e || e.builtin) { root.showNotice("The help entry cannot be edited"); return }
    root.deleteConfirmOpen = false
    root.actionsOpen = false
    root.formMode = "edit"
    root.formId = e.id
    root.formType = (e.type === "file" || e.type === "folder") ? "path" : e.type
    root.formAppName = e.appName || ""
    root.formError = ""
    root.formSaving = false
    root.clearPathCompletion()
    nameField.text = e.name
    targetField.text = e.target
    tagsField.text = (e.tags || []).join(", ")
    notesField.text = e.notes || ""
    root.formDefaultHint = e.hint || Model.nextFreeHint(root.entries, e.id)
    hintField.text = root.formDefaultHint
    hintField.placeholderText = root.formDefaultHint
    root.view = "form"
    root.formFocus = 1
    Qt.callLater(root.focusFormField)
  }

  function closeForm() {
    root.view = "list"
    root.formSaving = false
    root.clearPathCompletion()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function focusFormField() {
    if (root.view !== "form") return
    switch (root.formFocus) {
      case 1: nameField.forceActiveFocus(); nameField.cursorPosition = nameField.text.length; break
      case 2:
        if (root.formType === "app") keyCatcher.forceActiveFocus()
        else { targetField.forceActiveFocus(); targetField.cursorPosition = targetField.text.length }
        break
      case 3: tagsField.forceActiveFocus(); tagsField.cursorPosition = tagsField.text.length; break
      case 4: notesField.forceActiveFocus(); notesField.cursorPosition = notesField.text.length; break
      case 5: hintField.forceActiveFocus(); hintField.cursorPosition = hintField.text.length; break
      default: keyCatcher.forceActiveFocus()
    }
  }

  function moveFormFocus(delta) {
    root.formFocus = (root.formFocus + delta + 6) % 6
    root.focusFormField()
  }

  function setFormType(type) {
    if (root.typeOptions.indexOf(type) === -1) return
    root.formType = type
    root.formError = ""
    if (type !== "app") root.formAppName = ""
    if (root.formFocus === 2) root.focusFormField()
  }

  function cycleFormType(delta) {
    var idx = root.typeOptions.indexOf(root.formType)
    root.setFormType(root.typeOptions[(idx + delta + 3) % 3])
  }

  // Called on user edits of the target field: a URL selects URL, a local
  // path selects "File or folder". Whether it is a file or a folder is
  // decided at save time, never while typing.
  function detectTargetType(text) {
    var kind = Model.detectTarget(text)
    if (kind === "url") {
      if (root.formType !== "url") root.setFormType("url")
      root.clearPathCompletion()
    } else if (kind === "path") {
      if (root.formType === "url") root.setFormType("path")
      completeTimer.restart()
    } else {
      root.clearPathCompletion()
    }
  }

  // Who currently owns the hint typed into the form, excluding the entry
  // being edited. Returns null when the code is free.
  function formHintOwner() {
    var hint = hintField.text.trim().toLowerCase()
    if (!Model.isValidHint(hint)) return null
    var owner = Model.findByHint(root.entries, hint)
    return owner && owner.id !== root.formId ? owner : null
  }

  function formHintStatus() {
    var hint = hintField.text.trim().toLowerCase()
    if (!hint) return "Auto-assigned: " + (root.formDefaultHint || "none free")
    if (hint.length < 2) return "Two letters, aa–zy"
    if (hint === "zz") return "zz is reserved for the help page"
    if (!Model.isValidHint(hint)) return "Two lowercase letters, aa–zy"
    var owner = root.formHintOwner()
    if (owner) return "Swaps with " + owner.name + "  (" + owner.name + " becomes " + (root.formDefaultHint || Model.nextFreeHint(root.entries, root.formId)) + ")"
    if (hint === root.formDefaultHint) return root.formMode === "edit" ? "Current code" : "Auto-assigned"
    return "Free"
  }

  function resetFormHint() {
    hintField.text = root.formDefaultHint
    root.formError = ""
  }

  // ---------------------------------------------------- path completion

  // Split the typed target into directory part + partial name, and list the
  // directory with ls. Called (debounced) on every edit of a path-like target.
  function requestPathCompletion() {
    if (root.formType === "app") { root.clearPathCompletion(); return }
    var text = targetField.text
    if (text === "~") text = "~/"
    if (!Model.looksLikePath(text)) { root.clearPathCompletion(); return }
    var idx = text.lastIndexOf("/")
    if (idx < 0) { root.clearPathCompletion(); return }
    var dir = text.slice(0, idx + 1)
    var prefix = text.slice(idx + 1)
    root.pathPrefix = prefix
    if (dir === root.pathDir && root.pathNames.length > 0) {
      root.filterPathCandidates()
      return
    }
    root.pathDir = dir
    root.pathNames = []
    root.pathCandidates = []
    root.pathCandidateIndex = -1
    var expanded = Model.expandPath(dir, root.home)
    listDirProc.running = false
    listDirProc.requestedDir = dir
    listDirProc.command = ["ls", "-1Ap", "--", expanded]
    listDirProc.running = true
  }

  function applyPathListing(dir, raw) {
    if (dir !== root.pathDir) return   // stale answer
    var names = String(raw || "").split("\n").filter(function(x) { return x.length > 0 })
    root.pathNames = names
    root.filterPathCandidates()
    if (root.pendingTabComplete) {
      root.pendingTabComplete = false
      if (root.pathCandidates.length > 0 && root.pathPrefix) root.tabCompletePath(1)
    }
  }

  function filterPathCandidates() {
    var prefix = root.pathPrefix
    var showHidden = prefix.charAt(0) === "."
    var out = []
    for (var i = 0; i < root.pathNames.length; i++) {
      var name = root.pathNames[i]
      if (!showHidden && name.charAt(0) === ".") continue
      if (name.indexOf(prefix) === 0) out.push(name)
    }
    if (out.length === 0 && prefix) {
      var lower = prefix.toLowerCase()
      for (var j = 0; j < root.pathNames.length; j++) {
        var nm = root.pathNames[j]
        if (!showHidden && nm.charAt(0) === ".") continue
        if (nm.toLowerCase().indexOf(lower) === 0) out.push(nm)
      }
    }
    // Folders first, then files, alphabetical within each.
    out.sort(function(a, b) {
      var ad = a.slice(-1) === "/", bd = b.slice(-1) === "/"
      if (ad !== bd) return ad ? -1 : 1
      return a.toLowerCase() < b.toLowerCase() ? -1 : 1
    })
    root.pathCandidates = out
    root.pathCandidateIndex = -1
  }

  function clearPathCompletion() {
    root.pendingTabComplete = false
    root.pathDir = ""
    root.pathPrefix = ""
    root.pathNames = []
    root.pathCandidates = []
    root.pathCandidateIndex = -1
    completeTimer.stop()
  }

  function commonPrefix(list) {
    if (list.length === 0) return ""
    var acc = list[0]
    for (var i = 1; i < list.length && acc.length > 0; i++) {
      var other = list[i]
      var k = 0
      while (k < acc.length && k < other.length && acc.charAt(k) === other.charAt(k)) k++
      acc = acc.slice(0, k)
    }
    return acc
  }

  // Put dir + name into the field. A folder (trailing /) immediately lists
  // its contents so the next Tab keeps descending.
  function setTargetPath(text, relist) {
    targetField.text = text
    targetField.cursorPosition = text.length
    root.detectTargetType(text)
    if (relist) { completeTimer.stop(); root.requestPathCompletion() }
  }

  function applyPathCandidate(index) {
    if (index < 0 || index >= root.pathCandidates.length) return
    var name = root.pathCandidates[index]
    root.setTargetPath(root.pathDir + name, name.slice(-1) === "/")
    if (name.slice(-1) !== "/") root.pathCandidates = []
  }

  // Shell-style Tab: extend to the common prefix when that adds letters,
  // otherwise cycle through the candidates.
  function tabCompletePath(direction) {
    var list = root.pathCandidates
    if (list.length === 0) return false
    if (list.length === 1) { root.applyPathCandidate(0); return true }
    var common = root.commonPrefix(list)
    if (common.length > root.pathPrefix.length) {
      root.setTargetPath(root.pathDir + common, common.slice(-1) === "/")
      root.pathPrefix = common
      root.filterPathCandidates()
      return true
    }
    var next = root.pathCandidateIndex < 0
      ? (direction < 0 ? list.length - 1 : 0)
      : (root.pathCandidateIndex + direction + list.length) % list.length
    root.pathCandidateIndex = next
    var name = list[next]
    targetField.text = root.pathDir + name
    targetField.cursorPosition = targetField.text.length
    pathList.positionViewAtIndex(next, ListView.Contain)
    return true
  }

  function movePathCandidate(delta) {
    var list = root.pathCandidates
    if (list.length === 0) return
    var next = root.pathCandidateIndex < 0 ? (delta < 0 ? list.length - 1 : 0) : Math.max(0, Math.min(list.length - 1, root.pathCandidateIndex + delta))
    root.pathCandidateIndex = next
    pathList.positionViewAtIndex(next, ListView.Contain)
  }

  // Enter in the Target field: accept the highlighted candidate, otherwise save.
  function targetAccepted() {
    if (root.pathListVisible && root.pathCandidateIndex >= 0) {
      var name = root.pathCandidates[root.pathCandidateIndex]
      root.applyPathCandidate(root.pathCandidateIndex)
      if (name.slice(-1) === "/") return
      root.pathCandidates = []
      return
    }
    root.saveForm()
  }

  // ---------------------------------------------------------- places

  function openPlacesPicker() {
    root.placesFilter = ""
    root.placesIndex = 0
    root.view = "places"
    root.rebuildPlaces()
    if (root.places.length === 0 || !root.placesLoading) root.loadPlaces()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function loadPlaces() {
    root.placesLoading = true
    placesProc.running = false
    placesProc.running = true
  }

  function applyPlaces(raw) {
    root.placesLoading = false
    var lines = String(raw || "").split("\n")
    var out = []
    for (var i = 0; i < lines.length; i++) {
      var parts = lines[i].split("\t")
      if (parts.length < 3) continue
      var path = parts[2]
      var base = path.replace(/\/+$/, "").split("/").pop() || "/"
      out.push({ kind: parts[0], source: parts[1], path: path, label: parts[3] || "", name: parts[3] || base, compact: Model.compactPath(path, root.home) })
    }
    root.places = out
    if (root.view === "places") root.rebuildPlaces()
  }

  function rebuildPlaces() {
    placesModel.clear()
    var terms = root.placesFilter.trim().toLowerCase().split(/\s+/).filter(function(x) { return x.length > 0 })
    for (var i = 0; i < root.places.length; i++) {
      var pl = root.places[i]
      var hay = (pl.name + " " + pl.compact + " " + pl.source).toLowerCase()
      var ok = true
      for (var t = 0; t < terms.length; t++) if (hay.indexOf(terms[t]) === -1) { ok = false; break }
      if (!ok) continue
      placesModel.append({ kind: pl.kind, source: pl.source, path: pl.path, placeName: pl.name, compact: pl.compact })
      if (placesModel.count >= 200) break
    }
    if (root.placesIndex >= placesModel.count) root.placesIndex = Math.max(0, placesModel.count - 1)
    Qt.callLater(function() {
      if (placesModel.count > 0) placesList.positionViewAtIndex(root.placesIndex, ListView.Contain)
    })
  }

  function setPlacesFilter(next) {
    placesPointerGate.reset()
    root.placesFilter = next
    root.placesIndex = 0
    root.rebuildPlaces()
  }

  function selectPlace(delta) {
    if (placesModel.count === 0) return
    placesPointerGate.reset()
    root.placesIndex = (root.placesIndex + delta + placesModel.count) % placesModel.count
    placesList.positionViewAtIndex(root.placesIndex, ListView.Contain)
  }

  function choosePlace(index) {
    if (index < 0 || index >= placesModel.count) return
    var row = placesModel.get(index)
    root.formType = "path"
    targetField.text = row.compact
    if (!nameField.text.trim()) nameField.text = row.placeName
    root.formError = ""
    root.clearPathCompletion()
    root.view = "form"
    root.formFocus = 3
    Qt.callLater(root.focusFormField)
  }

  function closePlacesPicker() {
    root.view = "form"
    root.formFocus = 2
    Qt.callLater(root.focusFormField)
  }

  function sourceLabel(source) {
    if (source === "sidebar") return "Files sidebar"
    if (source === "frequent") return "frequent (zoxide)"
    if (source === "recent") return "recent"
    return source
  }

  function defaultName(type, target, appName) {
    if (type === "app") return appName || target
    if (type === "url") {
      var m = String(target).match(/^[a-z][a-z0-9+.-]*:\/\/([^\/?#]+)/i)
      return m ? m[1].replace(/^www\./, "") : target
    }
    var parts = String(target).replace(/\/+$/, "").split("/")
    return parts[parts.length - 1] || target
  }

  function saveForm() {
    if (root.view !== "form" || root.formSaving) return
    root.formError = ""
    var target = targetField.text.trim()
    var hint = hintField.text.trim().toLowerCase()
    if (!target) { root.formError = "Target is required"; root.formFocus = 2; root.focusFormField(); return }
    if (hint && !Model.isValidHint(hint)) {
      root.formError = hint === "zz" ? "zz is reserved for the help page" : "Hint must be two lowercase letters, aa–zy"
      root.formFocus = 5
      root.focusFormField()
      return
    }
    var type = root.formType
    var appName = ""

    if (type === "url") {
      target = Model.normalizeUrl(target)
      if (!Model.looksLikeUrl(target)) { root.formError = "That does not look like a URL"; return }
    } else if (type === "app") {
      var de = root.lookupApp(target)
      if (!de) { root.formError = "No installed application matches “" + target + "”"; return }
      target = String(de.id || target)
      appName = String(de.name || "")
    } else {
      // "path": stat decides file vs folder.
      target = Model.expandPath(target, root.home)
      if (target.charAt(0) !== "/") { root.formError = "Use an absolute path (or ~/…)"; return }
      root.formSaving = true
      saveStatProc.running = false
      saveStatProc.command = ["bash", "-c", 'if [ -d "$0" ]; then echo dir; elif [ -e "$0" ]; then echo file; else echo missing; fi', target]
      saveStatProc.pendingTarget = target
      saveStatProc.running = true
      return
    }
    root.commitForm(type, target, appName)
  }

  function finishPathSave(kind) {
    root.formSaving = false
    if (root.view !== "form") return
    var target = saveStatProc.pendingTarget
    if (kind === "missing") { root.formError = "Path does not exist: " + Model.compactPath(target, root.home); return }
    root.commitForm(kind === "dir" ? "folder" : "file", target, "")
  }

  function commitForm(type, target, appName) {
    var name = nameField.text.trim() || root.defaultName(type, target, appName)
    var hint = hintField.text.trim().toLowerCase() || root.formDefaultHint || Model.nextFreeHint(root.entries, root.formId)
    var id = root.formMode === "edit" && root.formId ? root.formId : Model.uniqueId(root.entries, Model.slugify(name), "")
    var entry = {
      id: id,
      hint: hint,
      type: type,
      name: name,
      target: target,
      tags: Model.normalizeTags(tagsField.text),
      notes: notesField.text.trim()
    }
    var result = Model.upsert(root.entries, entry, root.formDefaultHint)
    root.entries = root.decorate(result.entries)
    root.saveStore()
    root.checkPaths()
    root.view = "list"
    root.rebuildDisplay()
    root.selectEntryId(id)
    var summary = (root.formMode === "edit" ? "Saved " : "Added ") + name + (hint ? "  (" + hint + ")" : "")
    if (result.swapped) summary += "  ·  " + result.swapped.name + " is now " + result.swapped.hint
    root.showNotice(summary)
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  // --------------------------------------------------------------- delete

  function requestDelete(e) {
    if (!e) return
    if (e.builtin) { root.showNotice("The help entry cannot be deleted"); return }
    root.actionsOpen = false
    root.deleteTarget = e
    deleteConfirm.selectedIndex = 1
    root.deleteConfirmOpen = true
  }

  function cancelDelete() {
    root.deleteConfirmOpen = false
    root.deleteTarget = null
    root.disarmPointer()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function confirmDelete() {
    var e = root.deleteTarget
    root.deleteConfirmOpen = false
    root.deleteTarget = null
    if (e) {
      root.entries = root.decorate(Model.removeById(root.entries, e.id))
      root.saveStore()
      root.showNotice("Deleted " + e.name)
    }
    if (root.selectedIndex >= displayModel.count - 1) root.selectedIndex = Math.max(0, displayModel.count - 2)
    root.disarmPointer()
    root.rebuildDisplay()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  // -------------------------------------------------------- action sheet

  function openActions(index) {
    root.selectAbsolute(index)
    root.actionsEntry = root.selectedEntry()
    root.actionsIndex = 0
    root.actionsOpen = true
  }

  function runAction(which) {
    var e = root.actionsEntry || root.selectedEntry()
    root.actionsEntry = null
    root.actionsOpen = false
    root.disarmPointer()
    if (which === "edit") root.openEdit(e)
    else if (which === "delete") root.requestDelete(e)
    else if (which === "launch") root.launch(e)
    else Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  // ------------------------------------------------------ application list

  function openAppsPicker(initialFilter) {
    appsPointerGate.reset()
    root.appsFilter = String(initialFilter || "")
    root.appsIndex = 0
    root.appsSelected = ({})
    root.appsSelectedCount = 0
    root.view = "apps"
    root.rebuildApps()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function rebuildApps() {
    appsModel.clear()
    var rows = []
    if (root.shell && root.shell.appLibrary && typeof root.shell.appLibrary.sortedEntries === "function") {
      var sorted = root.shell.appLibrary.sortedEntries(root.appsFilter)
      for (var i = 0; i < sorted.length && i < 100; i++) rows.push(sorted[i].entry)
    } else {
      var values = DesktopEntries.applications.values || []
      var q = root.appsFilter.toLowerCase()
      for (var j = 0; j < values.length; j++) {
        var v = values[j]
        if (!v || v.noDisplay) continue
        if (q && String(v.name || "").toLowerCase().indexOf(q) === -1) continue
        rows.push(v)
        if (rows.length >= 100) break
      }
    }
    // Compare canonical desktop ids so an entry saved as "nautilus" still
    // marks org.gnome.Nautilus as bookmarked.
    var bookmarked = ({})
    for (var b = 0; b < root.entries.length; b++) {
      if (root.entries[b].type !== "app") continue
      bookmarked[root.entries[b].target] = true
      var known = root.lookupApp(root.entries[b].target)
      if (known && known.id) bookmarked[String(known.id)] = true
    }
    for (var k = 0; k < rows.length; k++) {
      var de = rows[k]
      var id = String(de.id || "")
      appsModel.append({
        appId: id,
        appName: String(de.name || ""),
        appSubtext: String(de.comment || de.genericName || ""),
        appIcon: root.appIconSource(de.icon),
        appSelected: root.appsSelected[id] === true,
        appBookmarked: bookmarked[id] === true
      })
    }
    if (root.appsIndex >= appsModel.count) root.appsIndex = Math.max(0, appsModel.count - 1)
    Qt.callLater(function() {
      if (appsModel.count > 0) appsList.positionViewAtIndex(root.appsIndex, ListView.Contain)
    })
  }

  function setAppsFilter(next) {
    appsPointerGate.reset()
    root.appsFilter = next
    root.appsIndex = 0
    root.rebuildApps()
  }

  function selectApp(delta) {
    if (appsModel.count === 0) return
    appsPointerGate.reset()
    root.appsIndex = (root.appsIndex + delta + appsModel.count) % appsModel.count
    appsList.positionViewAtIndex(root.appsIndex, ListView.Contain)
  }

  function toggleAppSelection(index) {
    if (index < 0 || index >= appsModel.count) return
    var row = appsModel.get(index)
    var next = ({})
    for (var k in root.appsSelected) next[k] = true
    if (next[row.appId]) delete next[row.appId]
    else next[row.appId] = true
    root.appsSelected = next
    root.appsSelectedCount = Object.keys(next).length
    appsModel.setProperty(index, "appSelected", next[row.appId] === true)
  }

  // Select every application currently listed (respects the filter).
  function selectAllApps() {
    var next = ({})
    for (var i = 0; i < appsModel.count; i++) {
      var row = appsModel.get(i)
      next[row.appId] = true
      appsModel.setProperty(i, "appSelected", true)
    }
    root.appsSelected = next
    root.appsSelectedCount = Object.keys(next).length
  }

  function clearAppSelection() {
    root.appsSelected = ({})
    root.appsSelectedCount = 0
    for (var i = 0; i < appsModel.count; i++) appsModel.setProperty(i, "appSelected", false)
  }

  // Add every selected application as its own bookmark. Applications that
  // are already bookmarked are skipped so repeated bulk adds stay idempotent.
  function addSelectedApps() {
    var ids = Object.keys(root.appsSelected)
    if (ids.length === 0) return
    var list = root.entries.slice()
    var added = 0, skipped = 0
    for (var i = 0; i < ids.length; i++) {
      var de = root.lookupApp(ids[i])
      if (!de) { skipped++; continue }
      var target = String(de.id || ids[i])
      var exists = false
      for (var j = 0; j < list.length; j++) {
        if (list[j].type !== "app") continue
        if (list[j].target === target) { exists = true; break }
        var other = root.lookupApp(list[j].target)
        if (other && String(other.id) === target) { exists = true; break }
      }
      if (exists) { skipped++; continue }
      var name = String(de.name || target)
      list = Model.upsert(list, {
        id: Model.uniqueId(list, Model.slugify(name), ""),
        hint: Model.nextFreeHint(list, ""),
        type: "app",
        name: name,
        target: target,
        tags: ["app"],
        notes: String(de.comment || "")
      }, "").entries
      added++
    }
    root.entries = root.decorate(list)
    root.saveStore()
    root.appsBulkMode = false
    root.formSaving = false
    root.view = "list"
    root.rebuildDisplay()
    root.showNotice("Added " + added + " application" + (added === 1 ? "" : "s") + (skipped ? ", " + skipped + " already bookmarked" : ""))
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function chooseApp(index) {
    if (root.appsSelectedCount > 0) { root.addSelectedApps(); return }
    if (root.appsBulkMode) { root.toggleAppSelection(index); return }
    if (index < 0 || index >= appsModel.count) return
    var row = appsModel.get(index)
    root.formType = "app"
    root.formAppName = row.appName
    targetField.text = row.appId
    if (!nameField.text.trim()) nameField.text = row.appName
    root.formError = ""
    root.view = "form"
    root.formFocus = 3
    Qt.callLater(root.focusFormField)
  }

  function closeAppsPicker() {
    if (root.appsBulkMode) {
      root.appsBulkMode = false
      root.view = "list"
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
      return
    }
    root.view = "form"
    root.formFocus = 2
    Qt.callLater(root.focusFormField)
  }

  // ------------------------------------------------------ import / export

  function openPrompt(kind) {
    root.actionsOpen = false
    root.promptKind = kind
    root.view = "prompt"
    if (kind === "export") {
      var d = new Date()
      var stamp = d.getFullYear() + ("0" + (d.getMonth() + 1)).slice(-2) + ("0" + d.getDate()).slice(-2)
      promptField.text = "~/bookmark-everything-export-" + stamp + ".json"
    } else {
      promptField.text = "~/"
    }
    Qt.callLater(function() {
      promptField.forceActiveFocus()
      promptField.cursorPosition = promptField.text.length
    })
  }

  function closePrompt() {
    root.view = "list"
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function runPrompt() {
    var p = promptField.text.trim()
    if (!p) return
    var kind = root.promptKind
    root.closePrompt()
    if (kind === "export") root.exportTo(p)
    else root.importFrom(p)
  }

  function handleImportText(raw) {
    if (!root.importPending) return
    root.importPending = false
    var result = Model.parseBookmarks(raw)
    if (result.error) {
      root.showNotice("Import failed")
      root.notify("Bookmarks import failed", result.error)
      return
    }
    if (result.entries.length === 0) {
      root.showNotice("Nothing to import")
      return
    }
    var unresolved = []
    for (var u = 0; u < result.entries.length; u++) {
      var ie = result.entries[u]
      if (ie.type === "app" && !root.lookupApp(ie.target)) unresolved.push(ie.name + " (" + ie.target + ")")
    }
    backupProc.unresolved = unresolved
    backupProc.imported = result.entries
    backupProc.running = false
    backupProc.command = ["bash", "-c", 'if [ -e "$0" ]; then cp -a "$0" "$1"; fi', root.storePath, root.storePath + ".bak-" + root.timestamp()]
    backupProc.running = true
  }

  function finishImport() {
    var imported = backupProc.imported || []
    backupProc.imported = []
    var merged = Model.mergeImport(root.entries, imported)
    root.entries = root.decorate(merged.entries)
    root.saveStore()
    root.rebuildDisplay()
    root.checkPaths()
    var summary = merged.added + " added, " + merged.updated + " updated"
    var unresolved = backupProc.unresolved || []
    backupProc.unresolved = []
    var body = summary + ". Previous file backed up next to bookmark-everything.json."
    if (unresolved.length) {
      summary += ", " + unresolved.length + " app" + (unresolved.length === 1 ? "" : "s") + " not installed"
      body += "\nNot installed: " + unresolved.join(", ") + ". They are kept and flagged in the list."
    }
    root.showNotice("Imported: " + summary)
    root.notify("Bookmarks imported", body)
  }

  function timestamp() {
    var d = new Date()
    function two(n) { return ("0" + n).slice(-2) }
    return d.getFullYear() + two(d.getMonth() + 1) + two(d.getDate()) + "-" + two(d.getHours()) + two(d.getMinutes()) + two(d.getSeconds())
  }

  function handleClipboard(raw) {
    var text = String(raw || "").trim()
    var kind = Model.detectTarget(text)
    if (!kind) {
      root.openAdd("")
      root.showNotice("Clipboard has no URL or path")
      return
    }
    root.openAdd(text)
  }

  // ------------------------------------------------------------ key input

  function isPrintable(event) {
    return event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127
      && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
  }

  function handleListKey(event) {
    var ctrl = (event.modifiers & Qt.ControlModifier) && !(event.modifiers & (Qt.AltModifier | Qt.MetaModifier))
    if (ctrl && event.key === Qt.Key_N) { root.openAdd(""); return true }
    if (ctrl && event.key === Qt.Key_E) { root.openEdit(root.selectedEntry()); return true }
    if (ctrl && event.key === Qt.Key_V) { root.addFromClipboard(); return true }
    if (ctrl && event.key === Qt.Key_I) { root.openPrompt("import"); return true }
    if (ctrl && event.key === Qt.Key_O) { root.openPrompt("export"); return true }
    if (ctrl && event.key === Qt.Key_D) { root.requestDelete(root.selectedEntry()); return true }
    if (ctrl && event.key === Qt.Key_A) { root.pickApplications(); return true }
    if (ctrl && event.key === Qt.Key_K) { root.openOptions(); return true }
    if (event.key === Qt.Key_Delete) { root.requestDelete(root.selectedEntry()); return true }
    // Backspace deletes too (Mac keyboards have no Delete key), but only in
    // Hint mode with no half-typed code; in Search mode it edits the query.
    if (event.key === Qt.Key_Backspace && root.mode === "hints" && !root.hintBuffer) {
      root.requestDelete(root.selectedEntry())
      return true
    }
    if (event.key === Qt.Key_F1) { root.openHelp(); return true }

    if (event.key === Qt.Key_Escape) {
      if (root.mode === "hints") {
        if (root.hintBuffer) root.setHintBuffer("")
        else root.dismiss()
      } else {
        if (root.filterText) root.setFilter("")
        else if (root.openMode === "search") root.dismiss()
        else root.switchMode("hints")
      }
      return true
    }
    if (event.key === Qt.Key_Up) { root.select(-1); return true }
    if (event.key === Qt.Key_Down) { root.select(1); return true }
    if (event.key === Qt.Key_PageUp) { root.select(-6); return true }
    if (event.key === Qt.Key_PageDown) { root.select(6); return true }
    if (event.key === Qt.Key_Home && (root.mode === "hints" || !root.filterText)) { root.selectAbsolute(0); return true }
    if (event.key === Qt.Key_End && (root.mode === "hints" || !root.filterText)) { root.selectAbsolute(displayModel.count - 1); return true }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (root.cursorActive) root.activateIndex(root.selectedIndex)
      else if (displayModel.count > 0) root.cursorActive = true
      return true
    }
    if (event.key === Qt.Key_Tab) {
      root.switchMode(root.mode === "hints" ? "search" : "hints")
      return true
    }

    if (root.mode === "hints") {
      if (event.text === "/") { root.switchMode("search"); return true }
      if (event.text === "+") { root.openAdd(""); return true }
      if (event.text === "?") { root.openHelp(); return true }
      if (event.key === Qt.Key_Backspace) { root.setHintBuffer(root.hintBuffer.slice(0, -1)); return true }
      if (root.isPrintable(event) && /^[a-zA-Z]$/.test(event.text)) { root.typeHint(event.text.toLowerCase()); return true }
      return false
    }

    if (Util.editsFilter(event, root.filterText)) { root.setFilter(Util.editedFilter(event, root.filterText)); return true }
    if (root.isPrintable(event)) { root.setFilter(root.filterText + event.text); return true }
    return false
  }

  function handleFormKey(event) {
    var ctrl = (event.modifiers & Qt.ControlModifier) && !(event.modifiers & (Qt.AltModifier | Qt.MetaModifier))
    // Target field with a path: Tab completes, arrows browse candidates,
    // Ctrl+Space opens Places.
    if (root.formFocus === 2 && root.formType !== "app") {
      if (ctrl && event.key === Qt.Key_Space) { root.openPlacesPicker(); return true }
      if (event.key === Qt.Key_Tab && root.formType === "path" && !targetField.text.trim()) {
        root.setTargetPath("~/", true)   // start browsing from home
        return true
      }
      if (root.pathListVisible) {
        if (event.key === Qt.Key_Tab) { root.tabCompletePath(1); return true }
        if (event.key === Qt.Key_Backtab) { root.tabCompletePath(-1); return true }
        if (event.key === Qt.Key_Down) { root.movePathCandidate(1); return true }
        if (event.key === Qt.Key_Up) { root.movePathCandidate(-1); return true }
        if (event.key === Qt.Key_Escape) { root.pathCandidates = []; root.pathCandidateIndex = -1; return true }
      } else if (event.key === Qt.Key_Tab && Model.looksLikePath(targetField.text) && root.pathNames.length === 0 && targetField.text.indexOf("/") !== -1) {
        // Nothing listed yet (typed fast): fetch now and complete when it arrives.
        completeTimer.stop()
        root.pendingTabComplete = true
        root.requestPathCompletion()
        return true
      }
    }
    if (event.key === Qt.Key_Escape) {
      if (root.view === "form") root.closeForm()
      return true
    }
    if (ctrl && event.key === Qt.Key_S) { root.saveForm(); return true }
    if (ctrl && event.key === Qt.Key_R) { root.resetFormHint(); return true }
    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Down) { root.moveFormFocus(1); return true }
    if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Up) { root.moveFormFocus(-1); return true }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (root.formFocus === 2 && root.formType === "app") root.openAppsPicker("")
      else root.saveForm()
      return true
    }
    if (root.formFocus === 0) {
      if (event.key === Qt.Key_Left) { root.cycleFormType(-1); return true }
      if (event.key === Qt.Key_Right || event.key === Qt.Key_Space) { root.cycleFormType(1); return true }
      if (event.text === "1") { root.setFormType("url"); return true }
      if (event.text === "2") { root.setFormType("path"); return true }
      if (event.text === "3") { root.setFormType("app"); return true }
      return false
    }
    if (root.formFocus === 2 && root.formType === "app") {
      if (event.key === Qt.Key_Space) { root.openAppsPicker(""); return true }
      if (ctrl && event.key === Qt.Key_Space) { root.openAppsPicker(""); return true }
      if (root.isPrintable(event)) { root.openAppsPicker(event.text); return true }
      if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) { targetField.text = ""; root.formAppName = ""; return true }
      return false
    }
    return false
  }

  function handleAppsKey(event) {
    var ctrl = (event.modifiers & Qt.ControlModifier) && !(event.modifiers & (Qt.AltModifier | Qt.MetaModifier))
    if (event.key === Qt.Key_Escape) {
      if (root.appsSelectedCount > 0) root.clearAppSelection()
      else if (root.appsFilter) root.setAppsFilter("")
      else root.closeAppsPicker()
      return true
    }
    if (event.key === Qt.Key_Space) { root.toggleAppSelection(root.appsIndex); return true }
    if (ctrl && event.key === Qt.Key_A) {
      if (event.modifiers & Qt.ShiftModifier) root.clearAppSelection()
      else root.selectAllApps()
      return true
    }
    if (ctrl && event.key === Qt.Key_D) { root.clearAppSelection(); return true }
    if (event.key === Qt.Key_Up) { root.selectApp(-1); return true }
    if (event.key === Qt.Key_Down) { root.selectApp(1); return true }
    if (event.key === Qt.Key_PageUp) { root.selectApp(-6); return true }
    if (event.key === Qt.Key_PageDown) { root.selectApp(6); return true }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Tab) { root.chooseApp(root.appsIndex); return true }
    if (Util.editsFilter(event, root.appsFilter)) { root.setAppsFilter(Util.editedFilter(event, root.appsFilter)); return true }
    if (root.isPrintable(event)) { root.setAppsFilter(root.appsFilter + event.text); return true }
    return false
  }

  function handlePlacesKey(event) {
    if (event.key === Qt.Key_Escape) {
      if (root.placesFilter) root.setPlacesFilter("")
      else root.closePlacesPicker()
      return true
    }
    if (event.key === Qt.Key_Up) { root.selectPlace(-1); return true }
    if (event.key === Qt.Key_Down) { root.selectPlace(1); return true }
    if (event.key === Qt.Key_PageUp) { root.selectPlace(-6); return true }
    if (event.key === Qt.Key_PageDown) { root.selectPlace(6); return true }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Tab) { root.choosePlace(root.placesIndex); return true }
    if (Util.editsFilter(event, root.placesFilter)) { root.setPlacesFilter(Util.editedFilter(event, root.placesFilter)); return true }
    if (root.isPrintable(event)) { root.setPlacesFilter(root.placesFilter + event.text); return true }
    return false
  }

  function handlePromptKey(event) {
    if (event.key === Qt.Key_Escape) { root.closePrompt(); return true }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.runPrompt(); return true }
    return false
  }

  // -------------------------------------------------------------- options
  // The hotkey is typed, never captured from a key press: Hyprland acts on a
  // bound combination before the overlay could see it, so "press the keys
  // you want" would launch whatever holds them.

  function openOptions() {
    root.actionsOpen = false
    root.deleteConfirmOpen = false
    root.view = "options"
    hotkeyField.text = Local.HotkeyService.hotkey
    Local.HotkeyService.scan()
    Qt.callLater(function() { hotkeyField.forceActiveFocus(); hotkeyField.selectAll() })
  }

  function closeOptions() {
    root.view = "list"
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function applyHotkey() {
    var check = root.hotkeyCheck
    if (!check.ok) { root.showNotice(check.message); return }
    var err = Local.HotkeyService.setHotkey(check.combo)
    if (err) { root.showNotice(err); return }
    root.showNotice("Opens with " + HK.pretty(check.combo))
  }

  function toggleHotkeyEnabled() {
    Local.HotkeyService.setEnabled(!Local.HotkeyService.enabled)
    root.showNotice(Local.HotkeyService.enabled ? "Built-in hotkey on" : "Built-in hotkey off")
  }

  function toggleIconInBar() {
    var show = !root.iconInBar
    var result = root.setIconInBar(show)
    if (result !== "ok") { root.showNotice(result); return }
    root.showNotice(show ? "Icon added to the bar" : "Icon removed from the bar")
  }

  function handleOptionsKey(event) {
    if (event.key === Qt.Key_Escape) { root.closeOptions(); return true }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.applyHotkey(); return true }
    return false
  }

  function handleActionsKey(event) {
    if (event.key === Qt.Key_Escape) { root.runAction("cancel"); return true }
    if (event.key === Qt.Key_Left || event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) { root.actionsIndex = (root.actionsIndex + 2) % 3; return true }
    if (event.key === Qt.Key_Right || event.key === Qt.Key_Down || event.key === Qt.Key_Tab) { root.actionsIndex = (root.actionsIndex + 1) % 3; return true }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.runAction(["launch", "edit", "delete"][root.actionsIndex])
      return true
    }
    return true
  }

  // ------------------------------------------------------------ resources

  ListModel { id: displayModel }
  ListModel { id: appsModel }
  ListModel { id: placesModel }

  PointerMoveGate {
    id: placesPointerGate
    referenceItem: card
  }

  Timer {
    id: completeTimer
    interval: 120
    repeat: false
    onTriggered: root.requestPathCompletion()
  }

  // Lists a directory for Tab completion. Plain ls: no extra packages.
  Process {
    id: listDirProc
    property string requestedDir: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyPathListing(listDirProc.requestedDir, text)
    }
  }

  // Gathers places from the Files sidebar bookmarks, zoxide, and GTK recent
  // files via places.sh. Every source is optional; no extra packages.
  Process {
    id: placesProc
    command: ["bash", root.pluginDir + "/places.sh"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyPlaces(text)
    }
  }

  Connections {
    target: root.shell && root.shell.appLibrary ? root.shell.appLibrary : null
    ignoreUnknownSignals: true
    function onAppsChanged() { root.refreshDecorations() }
  }

  Connections {
    target: DesktopEntries.applications
    ignoreUnknownSignals: true
    function onValuesChanged() { root.refreshDecorations() }
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  PointerMoveGate {
    id: appsPointerGate
    referenceItem: card
  }

  Timer {
    id: noticeTimer
    interval: 3000
    repeat: false
    onTriggered: root.notice = ""
  }

  FileView {
    id: storeFile
    path: root.storePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadStore(text())
    onLoadFailed: root.handleMissingStore()
    onFileChanged: reload()
    onSaveFailed: {
      root.showNotice("Could not write bookmark-everything.json")
      root.notify("Bookmarks", "Could not write " + Model.compactPath(root.storePath, root.home))
    }
  }

  FileView {
    id: importFile
    path: ""
    printErrors: false
    onLoaded: root.handleImportText(text())
    onLoadFailed: {
      if (!root.importPending) return
      root.importPending = false
      root.showNotice("Could not read import file")
      root.notify("Bookmarks import failed", "Could not read " + Model.compactPath(importFile.path, root.home))
    }
  }

  FileView {
    id: exportFile
    path: ""
    atomicWrites: true
    printErrors: false
    onSaveFailed: {
      root.showNotice("Export failed")
      root.notify("Bookmarks export failed", "Could not write " + Model.compactPath(exportFile.path, root.home))
    }
  }

  Process {
    id: clipProc
    command: ["wl-paste", "-n", "-t", "text"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleClipboard(text)
    }
  }

  Process {
    id: saveStatProc
    property string pendingTarget: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.finishPathSave(String(text).trim())
    }
  }

  Process {
    id: pathCheckProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyMissingPaths(text)
    }
  }

  Process {
    id: backupProc
    property var imported: []
    property var unresolved: []
    onExited: root.finishImport()
  }

  // --------------------------------------------------------------- window

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-bookmark-everything"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    // Like the Omarchy menu: the card opens centered, and the first keystroke
    // freezes the top edge so the card grows and shrinks downward instead of
    // re-centering on every filter change.
    property int cardTop: -1
    readonly property int centeredTop: Math.max(Style.gapsOut, Math.round((height - root.cardHeight) / 2))
    readonly property int effectiveCardTop: root.view === "list" && cardTop >= 0 ? cardTop : centeredTop
    function freezeCardTop() {
      if (visible && cardTop < 0) cardTop = effectiveCardTop
    }
    onVisibleChanged: if (!visible) cardTop = -1

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: Math.min(root.cardHeight, panel.height - Style.gapsOut - panel.effectiveCardTop)
      radius: root.cornerRadius
      anchors.horizontalCenter: parent.horizontalCenter
      y: panel.effectiveCardTop
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.deleteConfirmOpen) {
            if (deleteConfirm.handleKey(event)) event.accepted = true
            return
          }
          if (root.actionsOpen) {
            if (root.handleActionsKey(event)) event.accepted = true
            return
          }
          var handled = false
          if (root.view === "form") handled = root.handleFormKey(event)
          else if (root.view === "apps") handled = root.handleAppsKey(event)
          else if (root.view === "places") handled = root.handlePlacesKey(event)
          else if (root.view === "prompt") handled = root.handlePromptKey(event)
          else if (root.view === "options") handled = root.handleOptionsKey(event)
          else handled = root.handleListKey(event)
          if (handled) event.accepted = true
        }

        Column {
          id: content
          anchors.fill: parent
          anchors.topMargin: card.contentTopInset
          anchors.rightMargin: card.contentRightInset
          anchors.bottomMargin: card.contentBottomInset
          anchors.leftMargin: card.contentLeftInset
          spacing: root.contentSpacing

          // ------------------------------------------------------ header
          Item {
            width: parent.width
            height: root.headerHeight

            Text {
              id: headerText
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.right: headerTrail.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              text: {
                if (root.view === "form") return root.formMode === "edit" ? "Edit bookmark" : "Add bookmark"
                if (root.view === "apps") return root.appsFilter || (root.appsBulkMode ? "Add applications…" : "Search applications…")
                if (root.view === "places") return root.placesFilter || "Places you use…"
                if (root.view === "prompt") return root.promptKind === "export" ? "Export bookmarks to file" : "Import bookmarks from file"
                if (root.view === "options") return "Options"
                if (root.mode === "search") return root.filterText || "Search bookmarks…"
                return root.hintBuffer ? root.hintBuffer + "_" : "/ to search"
              }
              color: (root.view === "list" && root.mode === "hints" && root.hintBuffer) ? root.selectedText : root.foreground
              opacity: {
                if (root.view === "form" || root.view === "prompt" || root.view === "options") return 1
                if (root.view === "apps") return root.appsFilter ? 1 : 0.58
                if (root.view === "places") return root.placesFilter ? 1 : 0.58
                if (root.mode === "search") return root.filterText ? 1 : 0.58
                return root.hintBuffer ? 1 : 0.58
              }
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              elide: Text.ElideRight
            }

            Row {
              id: headerTrail
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(10)

              Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                visible: root.view === "apps" && root.appsSelectedCount > 0
                text: root.appsSelectedCount + " selected  ·  Enter adds"
                color: root.selectedText
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                visible: root.notice.length > 0
                text: root.notice
                color: root.selectedText
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                width: Math.min(implicitWidth, Style.space(260))
              }

              // Mode badge — click to switch between Hints and Search.
              BorderSurface {
                visible: root.view === "list"
                anchors.verticalCenter: parent.verticalCenter
                width: modeLabel.implicitWidth + Style.space(14)
                height: Style.space(22)
                radius: root.cornerRadius
                color: "transparent"
                borderSpec: Border.flat(Util.alpha(root.foreground, 0.32), Style.normalBorderWidth)

                Text {
                  id: modeLabel
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: root.mode === "hints" ? "HINTS" : "SEARCH"
                  color: root.foreground
                  opacity: 0.62
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.switchMode(root.mode === "hints" ? "search" : "hints")
                }
              }

              // Add button.
              Rectangle {
                visible: root.view === "list"
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(26)
                height: Style.space(26)
                radius: root.cornerRadius
                color: addHover.containsMouse ? root.selectedBackground : "transparent"

                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: "+"
                  color: addHover.containsMouse ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                  font.weight: Font.Light
                }

                MouseArea {
                  id: addHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openAdd("")
                }
              }
            }
          }

          // -------------------------------------------------------- body
          Item {
            id: body
            width: parent.width
            height: parent.height - root.headerHeight - root.contentSpacing
            clip: true

            // ================================================ list view
            Item {
              anchors.fill: parent
              visible: root.view === "list"

              Text {
                id: emptyHint
                textFormat: Text.PlainText
                visible: root.showEmptyHint
                height: visible ? root.rowHeight + root.rowSpacing : 0
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                text: "No bookmarks yet. Press + or Ctrl+N to add one, Ctrl+V to add whatever is on the clipboard, or type zz for help."
                color: root.foreground
                opacity: 0.62
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
                verticalAlignment: Text.AlignVCenter
              }

              // Footer: a gear for the options screen.
              Item {
                id: listFooter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: root.listFooterHeight

                Rectangle {
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  width: Style.space(26)
                  height: Style.space(26)
                  radius: root.cornerRadius
                  color: gearHover.containsMouse ? root.selectedBackground : "transparent"

                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: "󰒓" // nf-md-cog, U+F0493
                    color: gearHover.containsMouse ? root.selectedText : root.foreground
                    opacity: gearHover.containsMouse ? 1 : 0.55
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  MouseArea {
                    id: gearHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.view === "options" ? root.closeOptions() : root.openOptions()
                  }
                }
              }

              ListView {
                id: resultList
                anchors.fill: parent
                anchors.topMargin: emptyHint.visible ? emptyHint.height : 0
                anchors.bottomMargin: listFooter.height
                model: displayModel
                clip: true
                spacing: root.rowSpacing
                boundsBehavior: Flickable.StopAtBounds

                delegate: BorderSurface {
                  id: row
                  required property int index
                  required property string entryId
                  required property string hint
                  required property string type
                  required property string name
                  required property string detail
                  required property string glyph
                  required property string appIcon
                  required property bool builtin
                  required property bool missing

                  readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex
                  readonly property bool hintMatch: root.mode === "hints" && root.hintBuffer.length > 0 && hint.indexOf(root.hintBuffer) === 0

                  width: ListView.view.width
                  height: root.rowHeight
                  radius: root.cornerRadius
                  color: hasCursor ? root.selectedBackground : "transparent"
                  borderSpec: hasCursor ? root.selectedBorderSpec : Border.none()

                  // Hint code column — quiet, monospace-ish, highlighted while typing.
                  Text {
                    id: hintText
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.hintColumnWidth
                    text: row.hint
                    color: row.hintMatch ? root.selectedText : (row.hasCursor ? root.selectedText : root.foreground)
                    opacity: row.hintMatch || row.hasCursor ? 0.95 : 0.42
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.subtitle
                    font.weight: row.hintMatch ? Font.DemiBold : Font.Normal
                    horizontalAlignment: Text.AlignLeft
                  }

                  Item {
                    id: iconSlot
                    anchors.left: hintText.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.iconColumnWidth
                    height: Style.font.iconLarge + Style.space(4)

                    Text {
                      textFormat: Text.PlainText
                      visible: row.type !== "app" || row.appIcon.length === 0
                      anchors.centerIn: parent
                      text: row.glyph
                      color: row.hasCursor ? root.selectedText : root.foreground
                      opacity: row.missing ? 0.35 : (row.hasCursor ? 1 : 0.75)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.iconLarge
                    }

                    Image {
                      visible: row.type === "app" && row.appIcon.length > 0
                      anchors.centerIn: parent
                      width: Style.font.iconLarge
                      height: Style.font.iconLarge
                      fillMode: Image.PreserveAspectFit
                      sourceSize.width: width * Screen.devicePixelRatio
                      sourceSize.height: height * Screen.devicePixelRatio
                      source: visible ? row.appIcon : ""
                      asynchronous: true
                    }
                  }

                  Column {
                    anchors.left: iconSlot.right
                    anchors.leftMargin: Style.space(8)
                    anchors.right: overflow.left
                    anchors.rightMargin: Style.space(6)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(2)

                    Text {
                      textFormat: Text.PlainText
                      width: parent.width
                      text: row.name
                      color: row.hasCursor ? root.selectedText : root.foreground
                      opacity: row.missing ? 0.45 : 1
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.heading
                      font.weight: Font.Medium
                      font.strikeout: row.missing
                      elide: Text.ElideRight
                    }

                    Text {
                      textFormat: Text.PlainText
                      width: parent.width
                      text: row.detail
                      color: row.missing ? Color.urgent : root.foreground
                      opacity: row.missing ? 0.85 : (row.hasCursor ? 0.7 : 0.48)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      elide: Text.ElideMiddle
                    }
                  }

                  // Overflow menu (mouse): edit / delete.
                  Rectangle {
                    id: overflow
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(26)
                    height: Style.space(26)
                    radius: root.cornerRadius
                    visible: (row.hasCursor || overflowHover.containsMouse) && !row.builtin
                    color: overflowHover.containsMouse ? Util.alpha(root.foreground, 0.12) : "transparent"

                    Text {
                      textFormat: Text.PlainText
                      anchors.centerIn: parent
                      text: "⋯"
                      color: row.hasCursor ? root.selectedText : root.foreground
                      opacity: 0.8
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.heading
                    }

                    MouseArea {
                      id: overflowHover
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.openActions(row.index)
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    anchors.rightMargin: overflow.visible ? overflow.width + Style.space(8) : 0
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onPositionChanged: function(mouse) { root.selectFromPointer(row.index, row, mouse) }
                    onClicked: function(mouse) {
                      root.cursorActive = true
                      root.selectedIndex = row.index
                      if (mouse.button === Qt.RightButton) root.openActions(row.index)
                      else root.activateIndex(row.index)
                    }
                  }
                }
              }

              Column {
                anchors.centerIn: parent
                spacing: Style.space(8)
                visible: displayModel.count === 0
                width: parent.width - Style.space(40)

                Text {
                  text: "󰃀"
                  color: root.selectedText
                  opacity: 0.8
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.displayLarge
                  horizontalAlignment: Text.AlignHCenter
                  width: parent.width
                }

                Text {
                  textFormat: Text.PlainText
                  text: root.mode === "hints"
                    ? "No hint starts with “" + root.hintBuffer + "”"
                    : "No matches for “" + root.filterText + "”"
                  color: root.foreground
                  opacity: 0.7
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  horizontalAlignment: Text.AlignHCenter
                  wrapMode: Text.WordWrap
                  width: parent.width
                }
              }
            }

            // ================================================ form view
            Item {
              anchors.fill: parent
              visible: root.view === "form"

              Column {
                id: form
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: Style.spacing.lg

                // Type row.
                Row {
                  width: parent.width
                  height: Style.spacing.controlHeight
                  spacing: Style.spacing.controlGap

                  Text {
                    textFormat: Text.PlainText
                    width: root.formLabelWidth
                    height: parent.height
                    text: "Type"
                    color: root.formFocus === 0 ? root.selectedText : root.foreground
                    opacity: root.formFocus === 0 ? 1 : 0.7
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    verticalAlignment: Text.AlignVCenter
                  }

                  Repeater {
                    model: root.typeOptions

                    BorderSurface {
                      required property int index
                      required property string modelData
                      readonly property bool selected: root.formType === modelData
                      readonly property bool focused: root.formFocus === 0

                      width: chipLabel.implicitWidth + Style.space(22)
                      height: Style.spacing.controlHeight
                      radius: root.cornerRadius
                      color: selected ? root.selectedBackground : (chipHover.containsMouse ? Util.alpha(root.foreground, 0.05) : "transparent")
                      borderSpec: Border.flat(selected ? (focused ? root.selectedText : Util.alpha(root.selectedText, 0.6)) : Util.alpha(root.foreground, 0.3), Style.normalBorderWidth)

                      Text {
                        id: chipLabel
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: Model.typeIcon(modelData) + "  " + Model.typeLabel(modelData)
                        color: selected ? root.selectedText : root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                      }

                      MouseArea {
                        id: chipHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          root.formFocus = 0
                          root.setFormType(modelData)
                          keyCatcher.forceActiveFocus()
                          if (modelData === "app" && !targetField.text.trim()) root.openAppsPicker("")
                          else if (modelData === "path") { root.formFocus = 2; root.focusFormField() }
                        }
                      }
                    }
                  }
                }

                // Name.
                Row {
                  width: parent.width
                  spacing: Style.spacing.controlGap

                  Text {
                    textFormat: Text.PlainText
                    width: root.formLabelWidth
                    height: nameField.height
                    text: "Name"
                    color: root.formFocus === 1 ? root.selectedText : root.foreground
                    opacity: root.formFocus === 1 ? 1 : 0.7
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    verticalAlignment: Text.AlignVCenter
                  }

                  TextField {
                    id: nameField
                    width: parent.width - root.formLabelWidth - parent.spacing
                    placeholderText: "Defaults to the site, file, or app name"
                    foreground: root.foreground
                    accent: root.selectedText
                    font.family: root.fontFamily
                    onActiveFocusChanged: if (activeFocus) root.formFocus = 1
                    // Accept Enter here: QQC2 TextField emits accepted() but leaves the
                    // key event unaccepted, and the overlay's handler would treat the
                    // same press as "launch the highlighted bookmark" after the save.
                    Keys.onPressed: function(event) {
                      // Tab/Shift+Tab: Qt's focus chain would only visit text fields and skip
                      // the Type row, so route them through the form's own focus handling.
                      if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) { event.accepted = true; root.handleFormKey(event); return }
                      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { event.accepted = true; root.saveForm() }
                    }
                  }
                }

                // Target.
                Row {
                  id: targetRow
                  width: parent.width
                  spacing: Style.spacing.controlGap

                  Text {
                    textFormat: Text.PlainText
                    width: root.formLabelWidth
                    height: targetField.height
                    text: "Target"
                    color: root.formFocus === 2 ? root.selectedText : root.foreground
                    opacity: root.formFocus === 2 ? 1 : 0.7
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    verticalAlignment: Text.AlignVCenter
                  }

                  TextField {
                    id: targetField
                    width: parent.width - root.formLabelWidth - parent.spacing - (placesButton.visible ? placesButton.width + parent.spacing : 0)
                    visible: root.formType !== "app"
                    placeholderText: root.formType === "url" ? "https://…" : "~/folder or ~/file   ·   Tab to browse"
                    foreground: root.foreground
                    accent: root.selectedText
                    font.family: root.fontFamily
                    onActiveFocusChanged: {
                      if (activeFocus) root.formFocus = 2
                      else { root.pathCandidates = []; root.pathCandidateIndex = -1 }
                    }
                    onTextEdited: root.detectTargetType(text)
                    // Accept Enter here: QQC2 TextField emits accepted() but leaves the
                    // key event unaccepted, and the overlay's handler would treat the
                    // same press as "launch the highlighted bookmark" after the save.
                    Keys.onPressed: function(event) {
                      // Tab/Shift+Tab: Qt's focus chain would only visit text fields and skip
                      // the Type row, so route them through the form's own focus handling.
                      if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) { event.accepted = true; root.handleFormKey(event); return }
                      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { event.accepted = true; root.targetAccepted() }
                    }
                  }

                  // Places picker (file/folder only). Also Ctrl+Space.
                  BorderSurface {
                    id: placesButton
                    visible: root.formType === "path"
                    width: placesLabel.implicitWidth + Style.space(18)
                    height: targetField.height
                    radius: root.cornerRadius
                    color: placesHover.containsMouse ? root.selectedBackground : "transparent"
                    borderSpec: Border.flat(placesHover.containsMouse ? root.selectedText : Util.alpha(root.foreground, 0.3), Style.normalBorderWidth)

                    Text {
                      id: placesLabel
                      textFormat: Text.PlainText
                      anchors.centerIn: parent
                      text: "󰉋  Places"
                      color: placesHover.containsMouse ? root.selectedText : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }

                    MouseArea {
                      id: placesHover
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.openPlacesPicker()
                    }
                  }

                  // Application target: a picker button instead of free text.
                  BorderSurface {
                    id: appTargetButton
                    visible: root.formType === "app"
                    width: parent.width - root.formLabelWidth - parent.spacing
                    height: targetField.height
                    radius: root.cornerRadius
                    color: Style.controlFill(root.formFocus === 2, appTargetHover.containsMouse, root.foreground, root.selectedText)
                    borderSpec: Border.controlSpec(root.formFocus === 2 ? "focus" : (appTargetHover.containsMouse ? "hover-cursor" : "normal"), root.foreground, root.selectedText)

                    Text {
                      textFormat: Text.PlainText
                      anchors.left: parent.left
                      anchors.leftMargin: Style.spacing.controlPaddingX
                      anchors.right: parent.right
                      anchors.rightMargin: Style.spacing.controlPaddingX
                      anchors.verticalCenter: parent.verticalCenter
                      text: targetField.text.trim()
                        ? (root.formAppName ? root.formAppName + "   " + targetField.text.trim() : targetField.text.trim())
                        : "Choose an application…  (Enter or start typing)"
                      color: root.foreground
                      opacity: targetField.text.trim() ? 1 : 0.55
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                    }

                    MouseArea {
                      id: appTargetHover
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: { root.formFocus = 2; root.openAppsPicker("") }
                    }
                  }
                }

                // Tags.
                Row {
                  width: parent.width
                  spacing: Style.spacing.controlGap

                  Text {
                    textFormat: Text.PlainText
                    width: root.formLabelWidth
                    height: tagsField.height
                    text: "Tags"
                    color: root.formFocus === 3 ? root.selectedText : root.foreground
                    opacity: root.formFocus === 3 ? 1 : 0.7
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    verticalAlignment: Text.AlignVCenter
                  }

                  TextField {
                    id: tagsField
                    width: parent.width - root.formLabelWidth - parent.spacing
                    placeholderText: "comma or space separated"
                    foreground: root.foreground
                    accent: root.selectedText
                    font.family: root.fontFamily
                    onActiveFocusChanged: if (activeFocus) root.formFocus = 3
                    // Accept Enter here: QQC2 TextField emits accepted() but leaves the
                    // key event unaccepted, and the overlay's handler would treat the
                    // same press as "launch the highlighted bookmark" after the save.
                    Keys.onPressed: function(event) {
                      // Tab/Shift+Tab: Qt's focus chain would only visit text fields and skip
                      // the Type row, so route them through the form's own focus handling.
                      if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) { event.accepted = true; root.handleFormKey(event); return }
                      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { event.accepted = true; root.saveForm() }
                    }
                  }
                }

                // Notes.
                Row {
                  width: parent.width
                  spacing: Style.spacing.controlGap

                  Text {
                    textFormat: Text.PlainText
                    width: root.formLabelWidth
                    height: notesField.height
                    text: "Notes"
                    color: root.formFocus === 4 ? root.selectedText : root.foreground
                    opacity: root.formFocus === 4 ? 1 : 0.7
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    verticalAlignment: Text.AlignVCenter
                  }

                  TextField {
                    id: notesField
                    width: parent.width - root.formLabelWidth - parent.spacing
                    placeholderText: "optional, searchable"
                    foreground: root.foreground
                    accent: root.selectedText
                    font.family: root.fontFamily
                    onActiveFocusChanged: if (activeFocus) root.formFocus = 4
                    // Accept Enter here: QQC2 TextField emits accepted() but leaves the
                    // key event unaccepted, and the overlay's handler would treat the
                    // same press as "launch the highlighted bookmark" after the save.
                    Keys.onPressed: function(event) {
                      // Tab/Shift+Tab: Qt's focus chain would only visit text fields and skip
                      // the Type row, so route them through the form's own focus handling.
                      if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) { event.accepted = true; root.handleFormKey(event); return }
                      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { event.accepted = true; root.saveForm() }
                    }
                  }
                }

                // Hint.
                Row {
                  width: parent.width
                  spacing: Style.spacing.controlGap

                  Text {
                    textFormat: Text.PlainText
                    width: root.formLabelWidth
                    height: hintField.height
                    text: "Hint"
                    color: root.formFocus === 5 ? root.selectedText : root.foreground
                    opacity: root.formFocus === 5 ? 1 : 0.7
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    verticalAlignment: Text.AlignVCenter
                  }

                  TextField {
                    id: hintField
                    width: Style.space(72)
                    maximumLength: 2
                    placeholderText: "aa"
                    foreground: root.foreground
                    accent: root.selectedText
                    font.family: root.fontFamily
                    onActiveFocusChanged: if (activeFocus) root.formFocus = 5
                    onTextEdited: text = text.toLowerCase().replace(/[^a-z]/g, "")
                    // Accept Enter here: QQC2 TextField emits accepted() but leaves the
                    // key event unaccepted, and the overlay's handler would treat the
                    // same press as "launch the highlighted bookmark" after the save.
                    Keys.onPressed: function(event) {
                      // Tab/Shift+Tab: Qt's focus chain would only visit text fields and skip
                      // the Type row, so route them through the form's own focus handling.
                      if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) { event.accepted = true; root.handleFormKey(event); return }
                      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { event.accepted = true; root.saveForm() }
                    }
                  }

                  // Reset to the default code (current one when editing, next
                  // free one when adding). Also Ctrl+R.
                  Rectangle {
                    id: hintReset
                    width: Style.spacing.controlHeight
                    height: hintField.height
                    radius: root.cornerRadius
                    visible: hintField.text.trim().toLowerCase() !== root.formDefaultHint
                    color: hintResetHover.containsMouse ? root.selectedBackground : "transparent"

                    Text {
                      textFormat: Text.PlainText
                      anchors.centerIn: parent
                      text: "󰑐"
                      color: hintResetHover.containsMouse ? root.selectedText : root.foreground
                      opacity: hintResetHover.containsMouse ? 1 : 0.7
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.iconLarge
                    }

                    MouseArea {
                      id: hintResetHover
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.resetFormHint()
                    }
                  }

                  Text {
                    textFormat: Text.PlainText
                    height: hintField.height
                    // Re-evaluates as the field changes because it reads hintField.text.
                    text: hintField.text.length >= 0 ? root.formHintStatus() : ""
                    color: root.formHintOwner() ? root.selectedText : root.foreground
                    opacity: root.formHintOwner() ? 0.95 : 0.55
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    width: parent.width - root.formLabelWidth - hintField.width - (hintReset.visible ? hintReset.width + parent.spacing : 0) - parent.spacing * 2
                  }
                }

                // Error / status line.
                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  height: Style.space(18)
                  text: root.formError || (root.formSaving ? "Checking path…" : "")
                  color: root.formError ? Color.urgent : root.foreground
                  opacity: root.formError ? 1 : 0.6
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  verticalAlignment: Text.AlignVCenter
                }

                // Footer: key legend + buttons.
                Item {
                  width: parent.width
                  height: Style.spacing.controlHeight

                  Text {
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.right: formButtons.left
                    anchors.rightMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.formType === "path" ? "Tab browses / completes the path  ·  Ctrl+Space places  ·  Enter save  ·  Esc cancel" : "Enter save  ·  Tab next field  ·  Ctrl+R reset hint  ·  Esc cancel"
                    color: root.foreground
                    opacity: 0.45
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }

                  Row {
                    id: formButtons
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.spacing.controlGap

                    Button {
                      text: "Cancel"
                      bordered: true
                      foreground: root.foreground
                      accent: root.selectedText
                      fontFamily: root.fontFamily
                      onClicked: root.closeForm()
                    }

                    Button {
                      text: root.formMode === "edit" ? "Save" : "Add"
                      bordered: true
                      selected: true
                      foreground: root.foreground
                      accent: root.selectedText
                      fontFamily: root.fontFamily
                      onClicked: root.saveForm()
                    }
                  }
                }
              }
            }

            // Path completion candidates, floating under the Target field.
            BorderSurface {
              id: pathPopup
              visible: root.pathListVisible
              z: 5
              x: root.formLabelWidth + Style.spacing.controlGap
              y: targetRow.y + targetRow.height + Style.space(4)
              width: targetField.width
              height: Math.min(root.pathCandidates.length, 6) * pathList.rowHeight + Style.space(8)
              radius: root.cornerRadius
              color: root.background
              borderSpec: Border.flat(Util.alpha(root.foreground, 0.35), Style.normalBorderWidth)
              padding: Style.space(4)

              ListView {
                id: pathList
                readonly property int rowHeight: Style.space(24)
                anchors.fill: parent
                anchors.margins: Style.space(4)
                model: root.pathCandidates
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                  required property int index
                  required property string modelData
                  readonly property bool isDir: modelData.slice(-1) === "/"
                  readonly property bool highlighted: index === root.pathCandidateIndex

                  width: ListView.view.width
                  height: pathList.rowHeight
                  radius: root.cornerRadius
                  color: highlighted ? root.selectedBackground : "transparent"

                  Row {
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(8)
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(8)

                    Text {
                      textFormat: Text.PlainText
                      text: isDir ? "󰉋" : "󰈔"
                      color: highlighted ? root.selectedText : root.foreground
                      opacity: 0.8
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: modelData
                      color: highlighted ? root.selectedText : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideMiddle
                      width: parent.width - Style.space(24)
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.pathCandidateIndex = index
                    onClicked: {
                      root.applyPathCandidate(index)
                      targetField.forceActiveFocus()
                    }
                  }
                }
              }
            }

            // ============================================== places view
            Item {
              anchors.fill: parent
              visible: root.view === "places"

              ListView {
                id: placesList
                anchors.fill: parent
                anchors.bottomMargin: placesLegend.height
                model: placesModel
                clip: true
                spacing: root.rowSpacing
                boundsBehavior: Flickable.StopAtBounds

                delegate: BorderSurface {
                  id: placeRow
                  required property int index
                  required property string kind
                  required property string source
                  required property string path
                  required property string placeName
                  required property string compact

                  readonly property bool hasCursor: index === root.placesIndex

                  width: ListView.view.width
                  height: root.rowHeight
                  radius: root.cornerRadius
                  color: hasCursor ? root.selectedBackground : "transparent"
                  borderSpec: hasCursor ? root.selectedBorderSpec : Border.none()

                  Text {
                    id: placeIcon
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(12)
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.iconColumnWidth
                    text: placeRow.kind === "folder" ? "󰉋" : "󰈔"
                    color: placeRow.hasCursor ? root.selectedText : root.foreground
                    opacity: placeRow.hasCursor ? 1 : 0.75
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.iconLarge
                    horizontalAlignment: Text.AlignHCenter
                  }

                  Column {
                    anchors.left: placeIcon.right
                    anchors.leftMargin: Style.space(8)
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(12)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(2)

                    Text {
                      textFormat: Text.PlainText
                      width: parent.width
                      text: placeRow.placeName
                      color: placeRow.hasCursor ? root.selectedText : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.heading
                      font.weight: Font.Medium
                      elide: Text.ElideRight
                    }

                    Text {
                      textFormat: Text.PlainText
                      width: parent.width
                      text: placeRow.compact + "  ·  " + root.sourceLabel(placeRow.source)
                      color: root.foreground
                      opacity: 0.5
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      elide: Text.ElideMiddle
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: function(mouse) {
                      if (placesPointerGate.moved(placeRow, mouse)) root.placesIndex = placeRow.index
                    }
                    onClicked: root.choosePlace(placeRow.index)
                  }
                }
              }

              Text {
                id: placesLegend
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: Style.space(22)
                text: "Type to filter  ·  Enter choose  ·  Esc back    (Files sidebar · zoxide · recent files)"
                color: root.foreground
                opacity: 0.45
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                verticalAlignment: Text.AlignBottom
                elide: Text.ElideRight
              }

              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                visible: placesModel.count === 0
                text: root.placesLoading ? "Looking around…" : (root.placesFilter ? "No places match “" + root.placesFilter + "”" : "No places found yet")
                color: root.foreground
                opacity: 0.7
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
              }
            }

            // ================================================ apps view
            Item {
              anchors.fill: parent
              visible: root.view === "apps"

              ListView {
                id: appsList
                anchors.fill: parent
                anchors.bottomMargin: appsLegend.height
                model: appsModel
                clip: true
                spacing: root.rowSpacing
                boundsBehavior: Flickable.StopAtBounds

                delegate: BorderSurface {
                  id: appRow
                  required property int index
                  required property string appId
                  required property string appName
                  required property string appSubtext
                  required property string appIcon
                  required property bool appSelected
                  required property bool appBookmarked

                  readonly property bool hasCursor: index === root.appsIndex

                  width: ListView.view.width
                  height: root.rowHeight
                  radius: root.cornerRadius
                  color: hasCursor ? root.selectedBackground : "transparent"
                  borderSpec: hasCursor ? root.selectedBorderSpec : Border.none()

                  // Selection checkbox for bulk add.
                  Text {
                    id: appCheck
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(24)
                    text: appRow.appSelected ? "󰄲" : "󰄱"
                    color: appRow.appSelected ? root.selectedText : root.foreground
                    opacity: appRow.appSelected ? 1 : (appRow.hasCursor ? 0.7 : 0.35)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.iconLarge
                    horizontalAlignment: Text.AlignHCenter

                    MouseArea {
                      anchors.fill: parent
                      anchors.margins: -Style.space(4)
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.toggleAppSelection(appRow.index)
                    }
                  }

                  Image {
                    id: appRowIcon
                    anchors.left: appCheck.right
                    anchors.leftMargin: Style.space(6)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.font.iconLarge
                    height: Style.font.iconLarge
                    fillMode: Image.PreserveAspectFit
                    sourceSize.width: width * Screen.devicePixelRatio
                    sourceSize.height: height * Screen.devicePixelRatio
                    source: appRow.appIcon
                    asynchronous: true
                  }

                  Column {
                    anchors.left: appRowIcon.right
                    anchors.leftMargin: Style.space(10)
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(12)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(2)

                    Text {
                      textFormat: Text.PlainText
                      width: parent.width
                      text: appRow.appName
                      color: appRow.hasCursor ? root.selectedText : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.heading
                      font.weight: Font.Medium
                      elide: Text.ElideRight
                    }

                    Text {
                      textFormat: Text.PlainText
                      width: parent.width
                      text: (appRow.appBookmarked ? "already bookmarked  ·  " : "") + (appRow.appSubtext ? appRow.appSubtext + "  ·  " + appRow.appId : appRow.appId)
                      color: root.foreground
                      opacity: 0.5
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      elide: Text.ElideRight
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    anchors.leftMargin: appCheck.width + Style.space(14)
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onPositionChanged: function(mouse) {
                      if (appsPointerGate.moved(appRow, mouse)) root.appsIndex = appRow.index
                    }
                    onClicked: function(mouse) {
                      root.appsIndex = appRow.index
                      if (mouse.button === Qt.RightButton || root.appsSelectedCount > 0 || root.appsBulkMode) root.toggleAppSelection(appRow.index)
                      else root.chooseApp(appRow.index)
                    }
                  }
                }
              }

              Text {
                id: appsLegend
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: Style.space(22)
                text: root.appsSelectedCount > 0
                  ? "Enter add " + root.appsSelectedCount + "  ·  Space toggle  ·  Ctrl+A all  ·  Esc clear selection"
                  : (root.appsBulkMode
                    ? "Space or click to select  ·  Ctrl+A select all listed  ·  Enter add  ·  Esc back"
                    : "Enter choose  ·  Space select several  ·  Ctrl+A select all listed  ·  Esc back")
                color: root.foreground
                opacity: 0.45
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                verticalAlignment: Text.AlignBottom
                elide: Text.ElideRight
              }

              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                visible: appsModel.count === 0
                text: "No applications match “" + root.appsFilter + "”"
                color: root.foreground
                opacity: 0.7
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
              }
            }

            // ============================================== prompt view
            Item {
              anchors.fill: parent
              visible: root.view === "prompt"

              Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: Style.spacing.md

                TextField {
                  id: promptField
                  width: parent.width
                  placeholderText: "~/path/to/bookmark-everything.json"
                  foreground: root.foreground
                  accent: root.selectedText
                  font.family: root.fontFamily
                  // Accept Enter here: QQC2 TextField emits accepted() but leaves the
                  // key event unaccepted, and the overlay's handler would treat the
                  // same press as "launch the highlighted bookmark" after the save.
                  Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { event.accepted = true; root.runPrompt() }
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: root.promptKind === "export"
                    ? "Writes every bookmark as JSON. Enter to export, Esc to cancel."
                    : "Merges a JSON export into your bookmarks (same id updates, new ids are added). The current file is backed up first. Enter to import, Esc to cancel."
                  color: root.foreground
                  opacity: 0.55
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }
            }

            // ============================================== options view
            Item {
              anchors.fill: parent
              visible: root.view === "options"

              Column {
                id: optionsColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: Style.spacing.md

                // What opens the launcher right now.
                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: {
                    if (!Local.HotkeyService.enabled) return "Built-in hotkey is off"
                    if (!Local.HotkeyService.prettyActive) return "No key registered: every choice is in use"
                    return "Opens with " + Local.HotkeyService.prettyActive
                  }
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  elide: Text.ElideRight
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  visible: Local.HotkeyService.enabled && Local.HotkeyService.preferredOwner !== ""
                  text: Local.HotkeyService.pretty(Local.HotkeyService.hotkey) + " is already used for “" + Local.HotkeyService.preferredOwner + "”, so a free key was picked instead."
                  color: root.foreground
                  opacity: 0.62
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }

                // Change it: type a combination, Enter or the button applies.
                Row {
                  width: parent.width
                  spacing: Style.spacing.controlGap

                  TextField {
                    id: hotkeyField
                    width: parent.width - useKeyButton.width - parent.spacing
                    placeholderText: "SUPER + B"
                    foreground: root.foreground
                    accent: root.selectedText
                    font.family: root.fontFamily
                    onTextChanged: root.hotkeyInput = text
                    // Enter is accepted here so the overlay handler does not see
                    // the same press again after the field loses focus.
                    Keys.onPressed: function(event) {
                      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { event.accepted = true; root.applyHotkey() }
                    }
                  }

                  Button {
                    id: useKeyButton
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Use this key"
                    bordered: true
                    selected: true
                    foreground: root.foreground
                    accent: root.selectedText
                    fontFamily: root.fontFamily
                    onClicked: root.applyHotkey()
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: root.hotkeyCheck.message
                  color: root.hotkeyCheck.ok ? root.foreground : Color.urgent
                  opacity: root.hotkeyCheck.ok ? 0.62 : 1
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }

                Toggle {
                  width: parent.width
                  label: "Built-in hotkey"
                  description: Local.HotkeyService.enabled
                    ? "The plugin registers the key itself. Nothing in bindings.lua is touched."
                    : "Off. To bind it yourself, add this line to ~/.config/hypr/bindings.lua:"
                  checked: Local.HotkeyService.enabled
                  foreground: root.foreground
                  accent: root.selectedText
                  fontFamily: root.fontFamily
                  onClicked: root.toggleHotkeyEnabled()
                }

                BorderSurface {
                  visible: !Local.HotkeyService.enabled
                  width: parent.width
                  height: snippetText.implicitHeight + Style.space(16)
                  radius: root.cornerRadius
                  color: Util.alpha(root.foreground, 0.06)
                  borderSpec: Border.flat(Util.alpha(root.foreground, 0.2), Style.normalBorderWidth)

                  Text {
                    id: snippetText
                    textFormat: Text.PlainText
                    anchors.fill: parent
                    anchors.margins: Style.space(8)
                    text: root.bindingSnippet
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WrapAnywhere
                  }
                }

                Toggle {
                  width: parent.width
                  label: "Icon in the bar"
                  description: root.iconInBar
                    ? "Click it to open the launcher. Hover it to see the hotkey."
                    : "Hidden. You will need to remember the hotkey" + (Local.HotkeyService.enabled && Local.HotkeyService.prettyActive ? " (" + Local.HotkeyService.prettyActive + ")" : "") + " to get here."
                  checked: root.iconInBar
                  foreground: root.foreground
                  accent: root.selectedText
                  fontFamily: root.fontFamily
                  onClicked: root.toggleIconInBar()
                }

                // Footer: legend + button.
                Item {
                  width: parent.width
                  height: Style.spacing.controlHeight

                  Text {
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.right: doneButton.left
                    anchors.rightMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Enter use key  ·  Esc back"
                    color: root.foreground
                    opacity: 0.45
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }

                  Button {
                    id: doneButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Done"
                    bordered: true
                    foreground: root.foreground
                    accent: root.selectedText
                    fontFamily: root.fontFamily
                    onClicked: root.closeOptions()
                  }
                }
              }
            }
          }
        }

        // ------------------------------------------------ action sheet
        Rectangle {
          anchors.fill: parent
          visible: root.actionsOpen
          z: 10
          color: root.scrim

          // hoverEnabled so pointer motion over the scrim does not reach the
          // rows underneath and move the selection while the sheet is open.
          MouseArea { anchors.fill: parent; hoverEnabled: true; onClicked: root.runAction("cancel") }

          BorderSurface {
            id: actionsCard
            width: Math.min(parent.width - Style.space(32), Style.space(360))
            height: actionsCard.contentTopInset + actionsCard.contentBottomInset + actionsTitle.implicitHeight + Style.space(16) + Style.space(34)
            anchors.centerIn: parent
            color: root.background
            borderSpec: Border.flat(root.selectedText, Style.normalBorderWidth)
            padding: Style.space(18)
            radius: root.cornerRadius

            MouseArea { anchors.fill: parent; onClicked: {} }

            Item {
              anchors.fill: parent
              anchors.topMargin: actionsCard.contentTopInset
              anchors.rightMargin: actionsCard.contentRightInset
              anchors.bottomMargin: actionsCard.contentBottomInset
              anchors.leftMargin: actionsCard.contentLeftInset

              Text {
                id: actionsTitle
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                text: root.actionsEntry ? root.actionsEntry.name : (root.selectedEntry() ? root.selectedEntry().name : "")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                elide: Text.ElideRight
              }

              Row {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                spacing: Style.space(10)

                Repeater {
                  model: ["Open", "Edit", "Delete"]

                  BorderSurface {
                    required property int index
                    required property string modelData
                    readonly property bool selected: root.actionsIndex === index
                    readonly property bool destructive: index === 2

                    width: Style.space(88)
                    height: Style.space(34)
                    radius: 0
                    color: selected ? (destructive ? Util.alpha(Color.urgent, 0.22) : root.selectedBackground) : "transparent"
                    borderSpec: Border.flat(destructive
                      ? (selected ? Color.urgent : Util.alpha(Color.urgent, 0.56))
                      : (selected ? root.selectedText : Util.alpha(root.foreground, 0.38)), Style.normalBorderWidth)

                    Text {
                      textFormat: Text.PlainText
                      anchors.centerIn: parent
                      text: modelData
                      color: destructive ? (selected ? Color.urgent : root.foreground) : (selected ? root.selectedText : root.foreground)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onEntered: root.actionsIndex = index
                      onClicked: root.runAction(["launch", "edit", "delete"][index])
                    }
                  }
                }
              }
            }
          }
        }

        // The shared ConfirmDialog's scrim does not block hover, so shield
        // the rows underneath while it is open.
        MouseArea {
          anchors.fill: parent
          visible: root.deleteConfirmOpen
          z: 15
          hoverEnabled: true
          onClicked: {}
        }

        ConfirmDialog {
          id: deleteConfirm
          anchors.fill: parent
          opened: root.deleteConfirmOpen
          z: 20
          message: root.deleteTarget ? "Delete “" + root.deleteTarget.name + "”?" : "Delete bookmark?"
          confirmText: "Delete"
          background: root.background
          foreground: root.foreground
          scrim: root.scrim
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          cornerRadius: root.cornerRadius
          onCanceled: root.cancelDelete()
          onConfirmed: root.confirmDelete()
        }
      }
    }
  }
}
