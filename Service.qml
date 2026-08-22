import QtQuick
import Quickshell
import Quickshell.Io

// Headless singleton behind the Noisebox plugin.
//
// The synthesiser is a separate long-running process (`noisebox daemon`) that
// owns the audio stream, so sound survives a shell reload and there is exactly
// one generator no matter how many monitors mount a widget.
//
// This service holds a persistent unix-socket connection to it rather than
// shelling out per action, because the panel's sliders emit on every frame of
// a drag: a socket write is a few dozen bytes, a process spawn is milliseconds
// and a scheduler round trip. The daemon pushes state back on the same
// connection, so the bar stays in sync with `noisebox` used from a terminal.
Item {
  id: root

  // Injected by the shell.
  property var shell: null
  property var settings: ({})
  property var manifest: null

  // The synthesiser ships inside this plugin, so it has to be found relative to
  // wherever the plugin was installed rather than at a fixed path in $HOME —
  // `omarchy plugin add` clones to a directory named after the manifest id, and
  // nothing is ever copied into ~/.local/bin. The shell stamps the install
  // directory onto the manifest; Qt.resolvedUrl covers the case where it has
  // not been injected yet.
  readonly property string sourceDir: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir) : ""
  readonly property string bin: sourceDir
    ? sourceDir + "/bin/noisebox"
    : localPath(Qt.resolvedUrl("bin/noisebox"))

  function localPath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) value = value.slice(7)
    try {
      return decodeURIComponent(value)
    } catch (error) {
      return value
    }
  }
  readonly property string sockPath: {
    var dir = Quickshell.env("XDG_RUNTIME_DIR")
    return (dir && dir !== "" ? dir : "/tmp") + "/noisebox.sock"
  }

  // ---------------------------------------------------------------------------
  // View model, pushed by the daemon
  // ---------------------------------------------------------------------------

  property var view: ({})
  property bool ready: false

  readonly property bool   playing:        view.playing === true
  readonly property string mode:           view.mode || "rain"
  readonly property string modeLabel:      view.modeLabel || "Rain"
  readonly property real   volume:         num(view.volume, 0.45)
  readonly property real   muffle:         num(view.muffle, 0.15)
  readonly property real   stereoWidth:    num(view.width, 0.80)
  readonly property int    sleepMinutes:   Number(view.sleepMinutes) || 0
  readonly property int    sleepRemaining: Number(view.sleepRemaining) || 0
  readonly property var    order:          view.order || ["rain", "ocean", "wind", "stream", "fan", "noise"]
  readonly property var    params:         view.params || ({})

  function num(v, fallback) {
    return (v === undefined || v === null || isNaN(Number(v))) ? fallback : Number(v)
  }

  function labelFor(name) {
    var m = view.labels || {}
    return m[name] || name
  }

  // [{key, label}] for the sliders a given sound exposes.
  function schemaFor(name) {
    var m = view.schema || {}
    return m[name] || []
  }

  function paramValue(key, fallback) {
    var v = params[key]
    return num(v, fallback === undefined ? 0.5 : fallback)
  }

  // Nerd Font glyphs, all verified present in JetBrainsMono Nerd Font.
  function glyphFor(name) {
    switch (name) {
      case "rain":   return "󰖗"   // weather-pouring
      case "ocean":  return "󰞍"   // waves
      case "wind":   return "󰖝"   // weather-windy
      case "stream": return "󰖌"   // water
      case "fan":    return "󰈐"   // fan
      case "noise":  return "󰥛"   // sine-wave
    }
    return "󰝚"
  }

  // ---------------------------------------------------------------------------
  // Transport
  // ---------------------------------------------------------------------------

  // A failed QLocalSocket does not reliably re-attempt when `connected` is
  // re-asserted, and at login the first attempt always loses the race against
  // `ensure` starting the daemon. So each retry builds a brand-new Socket
  // instead: unambiguous, and cheap at this interval.
  Loader {
    id: sockLoader
    active: false
    sourceComponent: socketComponent
  }

  Component {
    id: socketComponent

    Socket {
      path: root.sockPath
      connected: true

      parser: SplitParser {
        splitMarker: "\n"
        onRead: function (line) { root.handleLine(line) }
      }

      onConnectionStateChanged: {
        if (connected) write('{"cmd":"subscribe"}\n')
        else root.ready = false
      }
    }
  }

  function handleLine(line) {
    var raw = String(line || "").trim()
    if (raw === "") return
    try {
      root.view = JSON.parse(raw)
      root.ready = true
    } catch (e) {
      // A partial frame is not worth surfacing; the next push is whole.
    }
  }

  // Stops itself once state actually arrives, and restarts if the daemon goes
  // away. The guard is `ready` rather than the socket's own flag because a
  // socket that never opened can still report itself connected.
  Timer {
    interval: 2500
    running: !root.ready
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (!ensureProc.running) ensureProc.running = true
      sockLoader.active = false
      sockLoader.active = true
    }
  }

  Process {
    id: ensureProc
    command: [root.bin, "ensure"]
    running: false
  }

  // The countdown is pushed only when something else changes, so tick it
  // locally to keep the bar's sleep timer honest between updates.
  Timer {
    interval: 1000
    running: root.playing && root.sleepRemaining > 0
    repeat: true
    onTriggered: {
      var v = root.view
      if (!v || !v.sleepRemaining) return
      v.sleepRemaining = Math.max(0, Number(v.sleepRemaining) - 1)
      root.view = v
      root.viewChanged()
    }
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  // Falls back to the CLI when the socket is not up yet, because the CLI starts
  // the daemon on demand — so a click always does something, even the first one
  // after a reboot.
  function send(obj) {
    var live = sockLoader.item
    if (root.ready && live && live.connected) {
      live.write(JSON.stringify(obj) + "\n")
      return
    }
    if (fallbackProc.running) fallbackProc.running = false
    fallbackProc.command = [root.bin, "cmd", JSON.stringify(obj)]
    fallbackProc.running = true
  }

  Process {
    id: fallbackProc
    running: false
  }

  function toggle()          { send({ cmd: "toggle" }) }
  function play()            { send({ cmd: "play" }) }
  function stop()            { send({ cmd: "stop" }) }
  function setMode(name)     { send({ cmd: "mode", name: name, play: true }) }
  function setSleep(minutes) { send({ cmd: "set", params: { sleep: minutes } }) }

  function setParam(key, value) {
    var p = {}
    p[key] = value
    send({ cmd: "set", params: p })
  }

  // Optimistic local echo: the daemon coalesces its state pushes, so without
  // this the bar's volume readout would lag a scroll by up to 120 ms.
  function setVolume(v) {
    var clamped = Math.max(0, Math.min(1, v))
    var m = root.view
    m.volume = clamped
    root.view = m
    root.viewChanged()
    setParam("volume", clamped)
  }

  function nudgeVolume(delta) { setVolume(root.volume + delta) }

  function cycleMode(step) {
    var list = root.order
    var i = list.indexOf(root.mode)
    if (i < 0) i = 0
    setMode(list[(i + step + list.length) % list.length])
  }
}
