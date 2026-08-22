import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// The Noisebox pill.
//
// Ambience is a background thing, so the widget is deliberately quiet: an icon
// for the sound that is loaded, tinted only while it is actually running. The
// one exception is an armed sleep timer, which gets the minutes remaining,
// because that is the single piece of state you cannot infer from listening.
//
// Left click opens the mixer, right click starts or stops, middle click steps
// to the next sound, scroll changes the volume.
BarWidget {
  id: root
  moduleName: "wyatt.noisebox"

  readonly property var noise: bar && bar.shell ? bar.shell.serviceFor("wyatt.noisebox") : null

  readonly property bool showLabel:    setting("showLabel", false) === true
  readonly property bool showSleep:    setting("showSleep", true) === true
  readonly property bool scrollVolume: setting("scrollVolume", true) === true
  readonly property real volumeStep:   Math.max(1, Math.min(20, Number(setting("volumeStep", 5)) || 5)) / 100

  readonly property bool playing: noise ? noise.playing : false
  readonly property string glyph: noise ? noise.glyphFor(noise.mode) : "󰝚"

  readonly property color defaultForeground: bar ? bar.foreground : Color.foreground
  readonly property color stateColor: playing ? Color.accent : defaultForeground

  readonly property string sleepText: {
    if (!showSleep || !noise || !playing) return ""
    var left = noise.sleepRemaining
    if (left <= 0) return ""
    var m = Math.ceil(left / 60)
    return m >= 60 ? Math.floor(m / 60) + "h" + (m % 60 ? (m % 60) + "m" : "") : m + "m"
  }

  readonly property string metaText: {
    var parts = []
    if (showLabel && noise) parts.push(noise.modeLabel)
    if (sleepText !== "") parts.push("󰤄" + sleepText)
    return parts.join("  ")
  }

  readonly property string tooltipText: {
    if (!noise || !noise.ready) return "Noisebox"
    var lines = []
    lines.push(noise.modeLabel + (playing ? "  ·  playing" : "  ·  stopped"))
    lines.push("Volume " + Math.round(noise.volume * 100) + "%")
    var schema = noise.schemaFor(noise.mode)
    if (schema.length > 0) {
      var bits = []
      for (var i = 0; i < schema.length; i++)
        bits.push(schema[i].label + " " + Math.round(noise.paramValue(schema[i].key) * 100) + "%")
      lines.push(bits.join("  ·  "))
    }
    if (playing && noise.sleepRemaining > 0)
      lines.push("Sleeping in " + Math.ceil(noise.sleepRemaining / 60) + " min")
    lines.push("")
    lines.push("Left: mixer  ·  Right: play/stop  ·  Middle: next sound"
               + (scrollVolume ? "  ·  Scroll: volume" : ""))
    return lines.join("\n")
  }

  // ---- Panel plumbing. The bar identifies a panel by the widget mounted in
  //      its slot, so open/close/opened have to live on this root rather than
  //      on the nested panel.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open()  { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target)        target.bar = root.bar
    if ("settings" in target)   target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = root
    if ("hostWidget" in target) target.hostWidget = root
    if ("noise" in target)      target.noise = root.noise
  }

  implicitWidth: vertical ? barSize : row.implicitWidth + Style.space(14)
  implicitHeight: vertical ? column.implicitHeight + Style.space(8) : barSize

  onBarChanged:      injectPanel()
  onSettingsChanged: injectPanel()
  onNoiseChanged:    injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  Row {
    id: row
    visible: !root.vertical
    anchors.centerIn: parent
    spacing: Style.space(6)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.glyph
      color: root.stateColor
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.bar.iconFont
      Behavior on color {
        enabled: !root.bar || root.bar.foregroundAnimationEnabled
        ColorAnimation { duration: 160 }
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.metaText !== ""
      text: root.metaText
      color: Qt.rgba(root.defaultForeground.r, root.defaultForeground.g,
                     root.defaultForeground.b, 0.62)
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
    }
  }

  Column {
    id: column
    visible: root.vertical
    anchors.centerIn: parent
    spacing: Style.space(2)

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.glyph
      color: root.stateColor
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.bar.iconFont
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: root.sleepText !== ""
      text: root.sleepText
      color: Qt.rgba(root.defaultForeground.r, root.defaultForeground.g,
                     root.defaultForeground.b, 0.7)
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Math.max(8, Style.font.body - 3)
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    onClicked: function (mouse) {
      if (!root.noise) return
      if (mouse.button === Qt.RightButton)       root.noise.toggle()
      else if (mouse.button === Qt.MiddleButton) root.noise.cycleMode(1)
      else                                       root.togglePanel()
    }

    onWheel: function (wheel) {
      if (!root.scrollVolume || !root.noise) { wheel.accepted = false; return }
      root.noise.nudgeVolume(wheel.angleDelta.y > 0 ? root.volumeStep : -root.volumeStep)
      wheel.accepted = true
    }

    onEntered: if (root.bar) root.bar.showTooltip(root, root.tooltipText)
    onExited:  if (root.bar) root.bar.hideTooltip(root)
  }

  // Lets a keybind drive the widget: `omarchy-shell wyatt.noisebox <method>`
  IpcHandler {
    target: "wyatt.noisebox"

    function toggle(): void  { if (root.noise) root.noise.toggle() }
    function next(): void    { if (root.noise) root.noise.cycleMode(1) }
    function prev(): void    { if (root.noise) root.noise.cycleMode(-1) }
    function mixer(): void   { root.togglePanel() }
    function louder(): void  { if (root.noise) root.noise.nudgeVolume(root.volumeStep) }
    function quieter(): void { if (root.noise) root.noise.nudgeVolume(-root.volumeStep) }
  }
}
