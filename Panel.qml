import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Settings live in ~/.config/omarchy/bg-tint.conf (owned by bin/bg-tint) so the
// CLI and this panel share one source of truth.
Panel {
  id: root
  moduleName: "io.github.satas20.bg-tint"
  ipcTarget: "io.github.satas20.bg-tint"

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property string ff: bar ? bar.fontFamily : Style.font.family
  readonly property string home: Quickshell.env("HOME")
  readonly property string bin: home + "/.config/omarchy/plugins/io.github.satas20.bg-tint/bin/bg-tint"

  property var state: Model.parseState("")
  property var cfg: ({})
  property int sourceIndex: 0
  property string previewPath: ""
  property bool previewDirty: false
  property string status: ""
  property string error: ""

  readonly property var selected: Model.selectedKeys(cfg, state.colors)
  readonly property string sourcePath: state.sources.length ? state.sources[Math.min(sourceIndex, state.sources.length - 1)] : ""
  readonly property bool generating: genProc.running

  function refresh() {
    if (!stateProc.running) stateProc.running = true
  }

  function setCfg(patch) {
    root.cfg = Object.assign({}, root.cfg, patch)
    root.requestPreview()
  }

  function requestPreview() {
    if (previewProc.running) { previewDirty = true; return }
    previewDirty = false
    var argv = [root.bin, root.sourcePath]
    for (var k in root.cfg) argv.push(k, String(root.cfg[k]))
    previewProc.command = ["bash", "-c", 'b=$1; s=$2; shift 2; "$b" config "$@" && "$b" preview "$s"', "bg-tint"].concat(argv)
    previewProc.running = true
  }

  function cycleSource(delta) {
    var n = state.sources.length
    if (!n) return
    sourceIndex = (sourceIndex + delta + n) % n
    requestPreview()
  }

  function generate() {
    if (genProc.running) return
    root.error = ""
    root.status = "Starting…"
    genProc.command = [root.bin, "generate", "--set"]
    genProc.running = true
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function setBackground(path) {
    Util.execArgv(["omarchy-theme-bg-set", path])
    root.state = Object.assign({}, root.state, { current: path })
  }

  onOpenedChanged: if (opened) refresh()

  Process {
    id: stateProc
    command: [root.bin, "state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var s = Model.parseState(text)
        var themeChanged = s.theme !== root.state.theme
        root.state = s
        root.cfg = s.cfg
        if (root.opened && (themeChanged || !root.previewPath)) root.requestPreview()
      }
    }
  }

  Process {
    id: previewProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var p = String(text || "").trim()
        if (p) root.previewPath = p
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.error = String(text || "").trim()
    }
    onExited: if (root.previewDirty) root.requestPreview()
  }

  Process {
    id: genProc
    stdout: SplitParser { onRead: function(line) { root.status = line } }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.error = String(text || "").trim()
    }
    onExited: function(code) {
      if (code !== 0 && !root.error) root.error = "generate failed (" + code + ")"
      root.refresh()
    }
  }

  // One instance per monitor; only the primary screen's retints on theme switch.
  readonly property var hostWindow: QsWindow.window
  readonly property bool isLeader: {
    var screens = Quickshell.screens
    if (!hostWindow || !hostWindow.screen || screens.length === 0) return true
    return hostWindow.screen.name === screens[0].name
  }

  FileView {
    path: root.home + "/.local/state/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onFileChanged: { reload(); themeSettle.restart() }
  }

  // theme.name flips before omarchy-theme-set finishes setting its own background.
  Timer {
    id: themeSettle
    interval: 2000
    onTriggered: {
      if (root.isLeader && !genProc.running) {
        root.error = ""
        genProc.command = [root.bin, "generate", "--auto"]
        genProc.running = true
      } else {
        root.refresh()
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: String.fromCodePoint(0xF0E09)
    tooltipText: "Background tint"
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { if (dx !== 0) root.cycleSource(dx) }
      onActivateRequested: root.generate()
      onCloseRequested: root.close()

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        Column {
          width: parent.width
          spacing: Style.space(2)
          Text {
            text: "Background Tint"
            color: root.fg
            font.family: root.ff
            font.pixelSize: Style.font.title
            font.bold: true
          }
          Text {
            text: (root.state.theme + " · " + root.state.sources.length + " source images").toUpperCase()
            color: root.dim
            font.family: root.ff
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
          }
        }

        // Live preview of the current source with the current settings.
        Item {
          width: parent.width
          height: Math.round(width * 9 / 16)

          Rectangle {
            anchors.fill: parent
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
            radius: Style.cornerRadius
          }
          Image {
            anchors.fill: parent
            source: Util.fileUrl(root.previewPath)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
          }
          Text {
            anchors.centerIn: parent
            visible: !root.previewPath
            text: root.state.sources.length ? "Rendering…" : "No images in " + (root.cfg.SRC || "")
            color: root.dim
            font.family: root.ff
            font.pixelSize: Style.font.body
          }
          Rectangle {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: Style.space(8)
            width: previewLabel.implicitWidth + Style.space(16)
            height: previewLabel.implicitHeight + Style.space(8)
            radius: height / 2
            color: Qt.rgba(0, 0, 0, 0.55)
            visible: root.state.sources.length > 0
            Text {
              id: previewLabel
              anchors.centerIn: parent
              text: (previewProc.running ? "⋯ " : "") + Model.baseName(root.sourcePath)
                + "  " + (root.sourceIndex + 1) + "/" + root.state.sources.length
              color: "white"
              font.family: root.ff
              font.pixelSize: Style.font.caption
            }
          }
          Row {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Style.space(8)
            spacing: Style.space(4)
            visible: root.state.sources.length > 1
            Button { text: "‹"; foreground: "white"; background: Qt.rgba(0, 0, 0, 0.55); onClicked: root.cycleSource(-1) }
            Button { text: "›"; foreground: "white"; background: Qt.rgba(0, 0, 0, 0.55); onClicked: root.cycleSource(1) }
          }
        }

        PanelSectionHeader {
          text: "PALETTE  ·  " + root.selected.length + "/" + root.state.colors.length
          foreground: root.fg
          fontFamily: root.ff
        }

        Flow {
          width: parent.width
          spacing: Style.space(8)
          Repeater {
            model: root.state.colors
            Rectangle {
              required property var modelData
              readonly property bool on: root.selected.indexOf(modelData.key) >= 0
              width: Style.space(32)
              height: width
              radius: Style.cornerRadius > 0 ? width / 2 : 0
              color: modelData.hex
              opacity: on ? 1 : 0.25
              border.width: on ? Math.max(2, Style.space(2)) : 1
              border.color: on ? root.fg : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.3)
              Behavior on opacity { NumberAnimation { duration: 120 } }
              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  var next = Model.toggleKey(root.cfg, root.state.colors, parent.modelData.key)
                  if (next === null) root.error = "Keep at least 2 colours"
                  else { root.error = ""; root.setCfg({ COLORS: next }) }
                }
              }
            }
          }
          Button {
            text: "All"
            bordered: true
            foreground: root.fg
            fontSize: Style.font.bodySmall
            onClicked: root.setCfg({ COLORS: "" })
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(4)
          PanelSectionHeader {
            text: "STRENGTH  ·  " + (root.cfg.STRENGTH || 0) + "%"
            foreground: root.fg
            fontFamily: root.ff
          }
          PanelSlider {
            bar: root.bar
            width: parent.width
            minimum: 0
            maximum: 100
            step: 5
            integer: true
            value: Number(root.cfg.STRENGTH || 0)
            onReleased: function(v) { root.setCfg({ STRENGTH: Math.round(v) }) }
          }
        }

        Toggle {
          width: parent.width
          label: "Keep original brightness"
          description: "Recolour hue only; stars and nebula glow stay as bright as the photo"
          checked: root.cfg.PRESERVE === "1"
          foreground: root.fg
          fontFamily: root.ff
          onClicked: root.setCfg({ PRESERVE: checked ? "0" : "1" })
        }

        Toggle {
          width: parent.width
          label: "Apply on theme switch"
          description: "Retint for the new theme and set it as the background"
          checked: root.cfg.AUTO_SET === "1"
          foreground: root.fg
          fontFamily: root.ff
          onClicked: root.setCfg({ AUTO_SET: checked ? "0" : "1" })
        }

        Column {
          width: parent.width
          spacing: Style.space(4)
          PanelSectionHeader {
            text: "SOURCE FOLDER"
            foreground: root.fg
            fontFamily: root.ff
          }
          TextField {
            width: parent.width
            text: root.cfg.SRC || ""
            foreground: root.fg
            font.family: root.ff
            onEditingFinished: if (text !== root.cfg.SRC) {
              root.cfg = Object.assign({}, root.cfg, { SRC: text })
              root.sourceIndex = 0
              root.previewPath = ""
              Util.execArgv([root.bin, "config", "SRC", text])
              refreshAfterSrc.restart()
            }
          }
          Timer { id: refreshAfterSrc; interval: 300; onTriggered: root.refresh() }
        }

        PanelSectionHeader {
          visible: root.state.outs.length > 0
          text: "GENERATED  ·  CLICK TO USE"
          foreground: root.fg
          fontFamily: root.ff
        }

        Flickable {
          id: outScroll
          visible: root.state.outs.length > 0
          width: parent.width
          readonly property real rowHeight: Math.round(outGrid.cell * 9 / 16) + outGrid.spacing
          // 2 rows visible, peek of the 3rd hints more below
          height: Math.min(outGrid.implicitHeight, rowHeight * 2.4)
          contentHeight: outGrid.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          ScrollBar.vertical: ScrollBar { policy: outGrid.implicitHeight > outScroll.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }

        Grid {
          id: outGrid
          width: outScroll.width
          columns: 3
          spacing: Style.space(6)
          readonly property real cell: (width - spacing * (columns - 1)) / columns
          Repeater {
            model: root.state.outs
            Item {
              required property string modelData
              width: outGrid.cell
              height: Math.round(width * 9 / 16)
              Image {
                anchors.fill: parent
                source: Util.fileUrl(parent.modelData)
                sourceSize.width: 320
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
              }
              Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: root.state.current === parent.modelData ? Math.max(2, Style.space(2)) : 0
                border.color: Color.accent
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setBackground(parent.modelData)
              }
            }
          }
        }
        }

        Item {
          width: parent.width
          height: genButton.implicitHeight
          Text {
            anchors.left: parent.left
            anchors.right: genButton.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            text: root.error || root.status
            color: root.error ? Color.urgent : root.dim
            font.family: root.ff
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
          Button {
            id: genButton
            anchors.right: parent.right
            text: root.generating ? "Generating…" : "Generate & apply"
            bordered: true
            foreground: root.fg
            iconSpinning: root.generating
            onClicked: root.generate()
          }
        }
      }
    }
  }
}
