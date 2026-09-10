import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "." as Local

// A bookmark icon in the bar: the way in that never depends on remembering a
// key. Hover shows the current hotkey; click opens; right-click opens options.
BarWidget {
  id: root
  moduleName: "io.github.decadentsavant.bookmark-everything"
  // Hidden from Options: the bar gives an invisible widget no width, so the
  // entry can stay in the layout and the plugin stays loaded.
  visible: !Local.HotkeyService.iconHidden
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function run(command) { if (root.bar) root.bar.run(command) }

  Component.onCompleted: Local.HotkeyService.retain()
  Component.onDestruction: Local.HotkeyService.release()

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰃀" // nf-md-bookmark, U+F00C0
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    tooltipText: "Bookmark Everything\nOpen: " + (Local.HotkeyService.enabled && Local.HotkeyService.prettyActive ? Local.HotkeyService.prettyActive : "click this icon") + " | Options: Right-click"

    onPressed: function(b) {
      if (b === Qt.RightButton) root.run("omarchy-shell shell summon " + root.moduleName + " '{\"options\":true}'")
      else root.run("omarchy-shell shell toggle " + root.moduleName + " '{}'")
    }
  }
}
