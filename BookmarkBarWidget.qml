import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "." as Local

// A bookmark icon in the bar: the way in that never depends on remembering a
// key. Hover shows the current hotkey; right-click shows options.
BarWidget {
  id: root
  moduleName: "io.github.decadentsavant.bookmark-everything"
  property bool optionsOpen: false
  readonly property string helpPath: decodeURIComponent(String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")) + "/help.html"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function close() { optionsOpen = false }
  function run(command) { if (root.bar) root.bar.run(command) }
  function openLauncher(payload) { run("omarchy-shell shell summon " + moduleName + " '" + payload + "'") }

  Component.onCompleted: Local.HotkeyService.retain()
  Component.onDestruction: Local.HotkeyService.release()

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰃀" // nf-md-bookmark, U+F00C0
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    tooltipText: "Bookmark Everything · " + Local.HotkeyService.summary + "\nClick: open · Middle-click: search · Right-click: options"

    onPressed: function(b) {
      if (b === Qt.RightButton) root.optionsOpen = !root.optionsOpen
      else if (b === Qt.MiddleButton) root.openLauncher('{"mode":"search"}')
      else root.run("omarchy-shell shell toggle " + root.moduleName + " '{}'")
    }
  }

  PopupCard {
    id: optionsPopup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.optionsOpen
    contentWidth: optionsPopup.fittedContentWidth(Style.space(340))
    contentHeight: optionsPopup.fittedContentHeight(optionsColumn.implicitHeight)

    Column {
      id: optionsColumn
      width: parent.width
      spacing: Style.space(10)

      Text {
        text: "Bookmark Everything"
        color: root.bar ? root.bar.barForeground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Text {
        width: parent.width
        text: {
          if (!Local.HotkeyService.enabled) return "The built-in hotkey is off."
          if (!Local.HotkeyService.active) return "No key is registered: " + Local.HotkeyService.pretty(Local.HotkeyService.hotkey) + " and every fallback are in use."
          return "Opens with " + Local.HotkeyService.prettyActive + "."
        }
        color: root.bar ? root.bar.barForeground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
      }

      Text {
        width: parent.width
        visible: Local.HotkeyService.enabled && Local.HotkeyService.preferredOwner !== ""
        text: Local.HotkeyService.pretty(Local.HotkeyService.hotkey) + " is already used for “" + Local.HotkeyService.preferredOwner + "”, so a free key was picked instead."
        color: root.bar ? root.bar.barForeground : Color.foreground
        opacity: 0.7
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Toggle {
        width: parent.width
        label: "Built-in hotkey"
        description: Local.HotkeyService.enabled ? "The plugin registers the key itself. Nothing in bindings.lua is touched." : "Bind it yourself in ~/.config/hypr/bindings.lua, or turn this back on."
        checked: Local.HotkeyService.enabled
        foreground: root.bar ? root.bar.barForeground : Color.foreground
        accent: root.bar ? root.bar.urgent : Color.accent
        onClicked: Local.HotkeyService.setEnabled(!Local.HotkeyService.enabled)
      }

      Row {
        spacing: Style.spacing.controlGap

        Button {
          text: "Change hotkey…"
          bordered: true
          selected: true
          foreground: root.bar ? root.bar.barForeground : Color.foreground
          accent: root.bar ? root.bar.urgent : Color.accent
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          onClicked: { root.close(); root.openLauncher('{"hotkey":true}') }
        }

        Button {
          text: "Open"
          bordered: true
          foreground: root.bar ? root.bar.barForeground : Color.foreground
          accent: root.bar ? root.bar.urgent : Color.accent
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          onClicked: { root.close(); root.openLauncher('{}') }
        }

        Button {
          text: "Help"
          bordered: true
          foreground: root.bar ? root.bar.barForeground : Color.foreground
          accent: root.bar ? root.bar.urgent : Color.accent
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          onClicked: { root.close(); Util.execArgv(["xdg-open", root.helpPath]) }
        }
      }
    }
  }
}
