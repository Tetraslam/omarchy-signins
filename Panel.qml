import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// A quiet key in the bar while one of your sign-ins has lapsed, nothing at
// all otherwise. The panel lists what's signed out with the command that
// fixes it; ignored sign-ins never bring the key back.
Panel {
  id: root
  moduleName: "tetraslam.signins"
  ipcTarget: "tetraslam.signins"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int checkMinutes: Math.max(5, Number(setting("checkMinutes", 10)))
  readonly property bool notifyLapses: setting("notify", false) === true
  readonly property var ignored: {
    var value = setting("ignored", [])
    return Array.isArray(value) ? value : []
  }
  readonly property string scriptPath: String(Qt.resolvedUrl("signins.py")).replace("file://", "")

  property var checks: []
  readonly property var lapsed: checks.filter(function(c) { return !c.ok && root.ignored.indexOf(c.id) < 0 })
  readonly property var ignoredLapsed: checks.filter(function(c) { return !c.ok && root.ignored.indexOf(c.id) >= 0 })
  property var notified: ({})
  property int cursor: 0

  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  function check() {
    if (!probe.running) probe.running = true
  }

  // Several lapsed checks can share one fix (gcloud's user and application
  // default credentials both come back with one login).
  function fixes(list) {
    list = list || lapsed
    var seen = {}
    var out = []
    for (var i = 0; i < list.length; i++) {
      var c = list[i]
      if (seen[c.fix]) { seen[c.fix].names.push(c.name); seen[c.fix].ids.push(c.id); continue }
      var entry = { fix: c.fix, names: [c.name], ids: [c.id], detail: c.detail, account: c.account }
      seen[c.fix] = entry
      out.push(entry)
    }
    return out
  }

  // Ignoring is remembered in shell.json, like any other widget setting.
  function toggleIgnored(entry) {
    if (!entry) return
    var next = ignored.slice()
    var wasIgnored = next.indexOf(entry.ids[0]) >= 0
    for (var i = 0; i < entry.ids.length; i++) {
      var at = next.indexOf(entry.ids[i])
      if (wasIgnored && at >= 0) next.splice(at, 1)
      else if (!wasIgnored && at < 0) next.push(entry.ids[i])
    }
    Quickshell.execDetached(["omarchy", "bar", "set", "tetraslam.signins", "ignored", JSON.stringify(next), "--json"])
  }

  readonly property var rows: fixes(lapsed).concat(fixes(ignoredLapsed).map(function(e) { e.ignored = true; return e }))

  function runFix(entry) {
    if (!entry) return
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", entry.fix])
    close()
    recheckAfterFix.restart()
  }

  Process {
    id: probe
    command: ["python3", "-I", root.scriptPath]
    stdout: StdioCollector {
      onStreamFinished: {
        var parsed = null
        try { parsed = JSON.parse(text) } catch (error) { return }
        root.checks = parsed.checks || []
        root.announce()
      }
    }
  }

  // One notification when a sign-in lapses, none while it stays lapsed.
  function announce() {
    var next = {}
    for (var i = 0; i < lapsed.length; i++) {
      var c = lapsed[i]
      next[c.id] = true
      if (!notified[c.id] && notifyLapses)
        Quickshell.execDetached(["notify-send", "-a", "Sign-ins", "-i", "dialog-password", c.name + " is signed out", c.detail || c.fix])
    }
    notified = next
  }

  Timer {
    interval: root.checkMinutes * 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.check()
  }

  // Logins finish in a browser; look again a little later, and once more.
  Timer {
    id: recheckAfterFix
    interval: 20000
    repeat: true
    property int remaining: 6
    onRunningChanged: if (running) remaining = 6
    onTriggered: {
      root.check()
      if (--remaining <= 0 || root.lapsed.length === 0) stop()
    }
  }

  onOpenedChanged: if (opened) {
    cursor = 0
    check()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function check(): string { root.check(); return "ok" }
    function state(): string { return JSON.stringify(root.checks) }
  }

  visible: lapsed.length > 0
  implicitWidth: visible ? barRow.implicitWidth : 0
  implicitHeight: barRow.implicitHeight

  Row {
    id: barRow
    anchors.fill: parent

    BarIconButton {
      id: button
      bar: root.bar
      text: "󰌆"
      tooltipText: root.lapsed.map(function(c) { return c.name }).join(" · ") + " signed out"
      onPressed: function(buttonCode) {
        if (buttonCode === Qt.RightButton) root.runFix(root.fixes()[0])
        else root.toggle()
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        var n = root.rows.length
        if (n > 0 && dy !== 0) root.cursor = Math.max(0, Math.min(n - 1, root.cursor + dy))
      }
      onActivateRequested: root.runFix(root.rows[root.cursor])
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.check()
        else if (t === "i" || t === "I") root.toggleIgnored(root.rows[root.cursor])
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: root.lapsed.length > 0 ? "Signed out" : "All signed in"
          meta: root.lapsed.length > 0 ? root.lapsed.length + " of " + root.checks.length + " sign-ins" : root.checks.length + " sign-ins"
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            Text {
              text: "󰌆"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        Repeater {
          model: root.rows

          Rectangle {
            id: fixRow
            required property var modelData
            required property int index
            readonly property bool selected: root.cursor === index
            width: column.width
            implicitHeight: fixColumn.implicitHeight + Style.space(20)
            radius: Style.space(8)
            opacity: modelData.ignored ? 0.55 : 1
            color: selected ? root.alpha(root.foreground, 0.10) : root.alpha(root.foreground, 0.04)

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: root.cursor = fixRow.index
              onClicked: root.runFix(fixRow.modelData)
            }

            Column {
              id: fixColumn
              x: Style.space(12)
              y: Style.space(10)
              width: parent.width - Style.space(24)
              spacing: Style.space(4)

              Text {
                width: parent.width
                text: fixRow.modelData.names.join(" + ") + (fixRow.modelData.ignored ? "  · ignored" : "")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                wrapMode: Text.WordWrap
              }

              Text {
                width: parent.width
                visible: text !== ""
                text: [fixRow.modelData.account, fixRow.modelData.detail].filter(function(s) { return s }).join(" · ")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              Text {
                width: parent.width
                text: "↵  " + fixRow.modelData.fix
                color: fixRow.selected ? root.foreground : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }
          }
        }

        Text {
          width: parent.width
          text: "Enter signs in · i ignore · r check again"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
