import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// The Noisebox mixer.
//
// Ordered by how often you touch it: pick a sound, set how loud it is, then
// shape it. The per-sound sliders are built from the schema the daemon
// publishes rather than hard-coded here, so adding a parameter to the
// synthesiser makes it appear in this panel with no QML change.
Panel {
  id: root
  moduleName: "wyatt.noisebox"
  ipcTarget: ""
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var noise: null

  // The bar tracks the widget mounted in its slot, not this nested panel, so
  // everything the popout coordinator compares against has to be that widget.
  readonly property var barIdentity: hostWidget || root

  readonly property color fg: bar ? bar.foreground : Color.popups.text
  readonly property string ff: bar ? bar.fontFamily : Style.font.family

  function dim(alpha) { return Qt.rgba(fg.r, fg.g, fg.b, alpha) }
  function pct(v) { return Math.round(v * 100) + "%" }

  readonly property bool live: noise !== null && noise !== undefined && noise.ready

  function open() { root.controller.show() }

  // One row of the mixer: name, track, readout. Used for both the global
  // controls and the per-sound ones so they line up down the panel.
  component SliderRow: Item {
    id: srow

    property string label: ""
    property real value: 0.5
    property string hint: ""
    signal moved(real v)

    width: parent ? parent.width : 0
    implicitHeight: Math.max(slider.implicitHeight, name.implicitHeight)

    Text {
      id: name
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(86)
      text: srow.label
      color: root.dim(0.78)
      font.family: root.ff
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    PanelSlider {
      id: slider
      bar: root.bar
      anchors.left: name.right
      anchors.right: readout.left
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      minimum: 0
      maximum: 1
      step: 0.01
      value: srow.value
      onMoved: function (v) { srow.moved(v) }
    }

    Text {
      id: readout
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(38)
      horizontalAlignment: Text.AlignRight
      text: root.pct(slider.liveValue)
      color: root.dim(0.5)
      font.family: root.ff
      font.pixelSize: Style.font.caption
    }
  }

  PopupCard {
    id: card
    anchorItem: root.anchorItem
    bar: root.bar
    owner: root.barIdentity
    open: root.opened
    contentWidth: card.fittedContentWidth(Style.space(430))
    contentHeight: card.fittedContentHeight(content.implicitHeight, Style.space(700))

    Column {
      id: content
      width: parent.width
      spacing: Style.space(10)

      // ------------------------------------------------------------- header
      //
      // Anchored rather than a Row so the status line has a real width to work
      // with: the "install python-numpy" message is far longer than "stopped"
      // and has to wrap inside the space left by the transport button instead
      // of sliding underneath it.
      Item {
        width: parent.width
        implicitHeight: Math.max(headGlyph.implicitHeight,
                                 headText.implicitHeight,
                                 transport.implicitHeight)

        Text {
          id: headGlyph
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: root.noise ? root.noise.glyphFor(root.noise.mode) : "󰝚"
          color: root.noise && root.noise.playing ? Color.accent : root.dim(0.8)
          font.family: root.ff
          font.pixelSize: Style.font.icon
        }

        Column {
          id: headText
          anchors.left: headGlyph.right
          anchors.leftMargin: Style.space(8)
          anchors.right: transport.left
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(1)

          Text {
            width: parent.width
            elide: Text.ElideRight
            text: root.noise ? root.noise.modeLabel : "Noisebox"
            color: root.fg
            font.family: root.ff
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.noise && root.noise.stalled
                   ? "synthesiser will not start — install python-numpy"
                 : !root.live ? "starting the synthesiser…"
                 : root.noise.playing
                   ? (root.noise.sleepRemaining > 0
                      ? "playing · stops in " + Math.ceil(root.noise.sleepRemaining / 60) + " min"
                      : "playing")
                   : "stopped"
            color: root.noise && root.noise.stalled ? Color.urgent : root.dim(0.5)
            font.family: root.ff
            font.pixelSize: Style.font.caption
          }
        }

        Button {
          id: transport
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          foreground: root.fg
          background: root.bar ? root.bar.background : Color.background
          fontFamily: root.ff
          bordered: true
          selected: root.noise ? root.noise.playing : false
          iconText: root.noise && root.noise.playing ? "󰓛" : "󰐊"
          text: root.noise && root.noise.playing ? "Stop" : "Play"
          onClicked: if (root.noise) root.noise.toggle()
        }
      }

      PanelSeparator { width: parent.width; foreground: root.fg }

      // -------------------------------------------------------------- sound
      PanelSectionHeader {
        text: "SOUND"
        foreground: root.fg
        fontFamily: root.ff
      }

      Grid {
        width: parent.width
        columns: 3
        columnSpacing: Style.space(6)
        rowSpacing: Style.space(6)

        readonly property real cellWidth:
          (width - columnSpacing * (columns - 1)) / columns

        Repeater {
          model: root.noise ? root.noise.order : []

          Button {
            required property var modelData
            width: parent.cellWidth
            foreground: root.fg
            background: root.bar ? root.bar.background : Color.background
            fontFamily: root.ff
            bordered: true
            selected: root.noise && root.noise.mode === modelData
            iconText: root.noise ? root.noise.glyphFor(modelData) : ""
            text: root.noise ? root.noise.labelFor(modelData) : ""
            onClicked: if (root.noise) root.noise.setMode(modelData)
          }
        }
      }

      PanelSeparator { width: parent.width; foreground: root.fg }

      // ---------------------------------------------------------------- mix
      PanelSectionHeader {
        text: "MIX"
        foreground: root.fg
        fontFamily: root.ff
      }

      SliderRow {
        label: "Volume"
        value: root.noise ? root.noise.volume : 0.45
        onMoved: function (v) { if (root.noise) root.noise.setVolume(v) }
      }

      SliderRow {
        label: "Muffle"
        value: root.noise ? root.noise.muffle : 0.15
        onMoved: function (v) { if (root.noise) root.noise.setParam("muffle", v) }
      }

      SliderRow {
        label: "Width"
        value: root.noise ? root.noise.stereoWidth : 0.8
        onMoved: function (v) { if (root.noise) root.noise.setParam("width", v) }
      }

      PanelSeparator { width: parent.width; foreground: root.fg }

      // ------------------------------------------------------- shape (live)
      PanelSectionHeader {
        text: root.noise ? root.noise.modeLabel.toUpperCase() : "SHAPE"
        foreground: root.fg
        fontFamily: root.ff
      }

      Column {
        width: parent.width
        spacing: Style.space(10)

        Repeater {
          model: root.noise ? root.noise.schemaFor(root.noise.mode) : []

          SliderRow {
            required property var modelData
            label: modelData.label
            value: root.noise ? root.noise.paramValue(modelData.key) : 0.5
            onMoved: function (v) {
              if (root.noise) root.noise.setParam(modelData.key, v)
            }
          }
        }
      }

      PanelSeparator { width: parent.width; foreground: root.fg }

      // --------------------------------------------------------------- timer
      PanelSectionHeader {
        text: "SLEEP TIMER"
        foreground: root.fg
        fontFamily: root.ff
      }

      ButtonGroup {
        width: parent.width
        foreground: root.fg
        background: root.bar ? root.bar.background : Color.background
        fontFamily: root.ff
        focusable: false
        options: [
          { value: "0",   label: "Off" },
          { value: "15",  label: "15m" },
          { value: "30",  label: "30m" },
          { value: "60",  label: "1h" },
          { value: "120", label: "2h" }
        ]
        value: root.noise ? String(root.noise.sleepMinutes) : "0"
        onChanged: function (v) { if (root.noise) root.noise.setSleep(parseInt(v, 10)) }
      }

      Text {
        width: parent.width
        visible: root.noise && root.noise.sleepMinutes > 0
        text: root.noise && root.noise.playing && root.noise.sleepRemaining > 0
              ? "Fades out over the last 90 seconds."
              : "The timer starts when you press play."
        color: root.dim(0.45)
        font.family: root.ff
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }
  }
}
