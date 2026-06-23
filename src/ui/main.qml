import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia

ApplicationWindow {
    id: window
    visible: true
    width: 960
    height: 540
    minimumWidth: 600
    minimumHeight: 400
    title: originalTitle
    color: "#1a1a1a"

    property bool isVideoPlaying: false
    property string currentTrack: ""
    property string originalTitle: "Doda Media Player"

    Item {
        id: videoContainer
        anchors.fill: parent
        anchors.topMargin: (topBar.visible ? topBar.height : 0) + (topRow.visible ? topRow.height : 0)
        anchors.bottomMargin: (bottomBar.visible ? bottomBar.height : 0) + (eqVisible && (!isFullscreen || controlsShown) ? 120 : 0)
        anchors.rightMargin: playlistVisible && playlistItems.length > 0 && (!isFullscreen || controlsShown) ? 280 : 0

        VideoOutput {
            id: videoOutput
            objectName: "videoOutput"
            anchors.fill: parent
        }

        Rectangle {
            id: audioArtBg
            anchors.fill: parent
            visible: app && app.isAudioSource && !pipMode
            z: 1
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#1a1a2e" }
                GradientStop { position: 0.4; color: "#16213e" }
                GradientStop { position: 1.0; color: "#0f3460" }
            }

            Image {
                id: albumArtImg
                anchors.centerIn: parent
                width: Math.min(parent.width, parent.height) * 0.5
                height: width
                fillMode: Image.PreserveAspectFit
                source: app && app.albumArt && app.albumArt.toString().length > 0 ? app.albumArt : ""
                visible: status === Image.Ready

                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    border.color: Qt.rgba(255, 255, 255, 0.08)
                    border.width: 1
                    radius: 8
                }
            }

            Image {
                anchors.centerIn: parent
                width: 80
                height: 80
                source: "icons/visualizer.svg"
                fillMode: Image.PreserveAspectFit
                opacity: 0.2
                visible: !albumArtImg.visible
            }
        }

        Text {
            id: subtitleLabel
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16 + (eqVisible && (!isFullscreen || controlsShown) ? 120 : 0)
            width: parent.width * 0.85
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: "#fff"
            font.pixelSize: 18
            font.bold: true
            visible: false
            z: 10
            style: Text.Outline
            styleColor: "#000"
        }

        Button {
            id: pipCloseBtn
            anchors.top: parent.top
            anchors.topMargin: 4
            anchors.right: parent.right
            anchors.rightMargin: 4
            flat: true
            implicitWidth: 24
            implicitHeight: 24
            visible: pipMode
            z: 100
            contentItem: Text {
                color: "#fff"
                font.pixelSize: 14
                font.bold: true
                text: "X"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle {
                color: parent.hovered ? "#c00" : Qt.rgba(0,0,0,0.5)
                radius: 3
            }
            onClicked: togglePip()
        }

        MouseArea {
            id: pipClickArea
            anchors.fill: parent
            visible: pipMode
            z: 90
            onClicked: {
                app.playPause()
            }
        }
    }

    property var visData: []
    property int visualizerMode: 0
    property bool visualizerVisible: true
    readonly property var visModeNames: ["Bars", "Wave", "Circle", "Mirror", "Glow", "Fire", "Rings", "Bubbles", "VU Meter", "Pinwheel", "Meteor", "Waves", "Water", "Stairs", "Orbit", "X-Ray"]
    property bool isFullscreen: false
    property bool eqVisible: false
    property bool playlistVisible: false
    property var playlistItems: []
    property var eqGains: [1,1,1,1,1,1,1,1,1,1]
    readonly property var eqPresetNames: ["Flat", "Rock", "Pop", "Classical", "Dance"]
    property var repeatModeNames: ["None", "One", "All"]
    property int playlistCurrentIndex: -1
    property double playbackSpeed: 1.0
    readonly property var speedPresets: [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    property bool mediaInfoVisible: false
    property bool alwaysOnTop: false
    property bool pipMode: false
    property int savedPipX: 0
    property int savedPipY: 0
    property int savedPipW: 960
    property int savedPipH: 540
    property real seekHoverRatio: -1
    property real seekHoverPos: -1

    Connections {
        target: app
        function onPlaybackStateChanged(newState) {
            if (newState === 1) {
                isVideoPlaying = true
                controlsTimer.restart()
                if (app) app.trackPlayStart(app.playlist.currentPath())
                if (app && app.subtitleVisible) subtitleTimer.start()
                positionSaver.start()
                visPollTimer.start()
            } else if (newState === 0) {
                isVideoPlaying = false
                controlsTimer.stop()
                subtitleTimer.stop()
                positionSaver.stop()
                visPollTimer.stop()
                subtitleLabel.text = ""
                if (app) app.trackPlayStop(app.playlist.currentPath())
            } else if (newState === 2) {
                isVideoPlaying = false
                controlsTimer.stop()
                subtitleTimer.stop()
                positionSaver.stop()
                visPollTimer.stop()
                if (app) app.trackPlayStop(app.playlist.currentPath())
            }
        }
        function onErrorOccurred(error, errorString) {
            errorLabel.text = "Error: " + errorString
            errorLabel.visible = true
        }
        function onSourceChanged() {
            errorLabel.visible = false
        }
    }

    Canvas {
        id: visCanvas
        anchors.fill: videoContainer
        z: 5
        visible: visualizerVisible && isVideoPlaying && app ? (app.visualizerActive && app.isAudioSource) : false

        function poll() {
            if (!app || !app.visualizerActive) return
            if (!isVideoPlaying) return
            var data = app.getSpectrum(app.position)
            if (data && data.length > 0) {
                visData = data
                requestPaint()
            }
        }

        function rainbowGrad(ctx, x, y, w, h) {
            if (w <= 0) w = 1
            var g = ctx.createLinearGradient(x, y, x + w, y)
            g.addColorStop(0.0, "#ff006e"); g.addColorStop(0.17, "#8338ec")
            g.addColorStop(0.33, "#3a86ff"); g.addColorStop(0.5, "#06d6a0")
            g.addColorStop(0.67, "#ffbe0b"); g.addColorStop(0.83, "#fb5607")
            g.addColorStop(1.0, "#ff006e")
            return g
        }

        function drawBars(ctx, w, h) {
            var n = visData.length, gap = 2
            var barW = Math.max(2, (w * 0.8 - gap * (n - 1)) / n)
            var totalW = barW * n + gap * (n - 1)
            var startX = (w - totalW) / 2
            var grad = rainbowGrad(ctx, startX, 0, totalW, 0)
            for (var i = 0; i < n; i++) {
                var barH = Math.max(2, Math.max(0.02, visData[i]) * h * 0.6)
                ctx.fillStyle = grad
                ctx.fillRect(startX + i * (barW + gap), h - barH, barW, barH)
            }
        }

        function drawWave(ctx, w, h) {
            var n = visData.length, step = w / (n - 1), maxH = h * 0.35
            var grad = rainbowGrad(ctx, 0, 0, w, 0)
            ctx.beginPath()
            ctx.moveTo(0, h/2 + (0.5 - visData[0]) * maxH)
            for (var i = 1; i < n; i++) {
                ctx.lineTo(i * step, h/2 + (0.5 - visData[i]) * maxH)
            }
            ctx.strokeStyle = grad
            ctx.lineWidth = 3
            ctx.stroke()
            ctx.lineTo(w, h); ctx.lineTo(0, h); ctx.closePath()
            var fillGrad = ctx.createLinearGradient(0, h/2 - maxH, 0, h)
            fillGrad.addColorStop(0, "rgba(255,0,110,0.3)")
            fillGrad.addColorStop(0.5, "rgba(6,214,160,0.15)")
            fillGrad.addColorStop(1, "rgba(17,17,24,0)")
            ctx.fillStyle = fillGrad; ctx.fill()
        }

        function drawCircle(ctx, w, h) {
            var cx = w/2, cy = h/2, n = visData.length
            ctx.save(); ctx.translate(cx, cy)
            ctx.lineWidth = 3
            for (var i = 0; i < n; i++) {
                var angle = i / n * Math.PI * 2 - Math.PI/2
                var len = 8 + Math.max(0.02, visData[i]) * Math.min(w, h) * 0.35
                var hue = i / n * 360
                ctx.strokeStyle = "hsl(" + hue + ", 100%, 60%)"
                ctx.beginPath()
                ctx.moveTo(Math.cos(angle) * 6, Math.sin(angle) * 6)
                ctx.lineTo(Math.cos(angle) * len, Math.sin(angle) * len)
                ctx.stroke()
            }
            ctx.restore()
        }

        function drawMirror(ctx, w, h) {
            var n = visData.length, half = Math.floor(n / 2), gap = 2
            var barW = Math.max(2, (w * 0.8 - gap * half) / half)
            var cx = w / 2
            var grad = rainbowGrad(ctx, 0, 0, w, 0)
            for (var i = 0; i < half; i++) {
                var val = Math.max(0.02, visData[i * 2])
                var barH = Math.max(2, val * h * 0.6)
                ctx.fillStyle = grad
                ctx.fillRect(cx - (i + 1) * (barW + gap), h - barH, barW, barH)
                ctx.fillRect(cx + i * (barW + gap), h - barH, barW, barH)
            }
        }

        function drawGlow(ctx, w, h) {
            var n = visData.length, gap = 2
            var barW = Math.max(2, (w * 0.9 - gap * (n - 1)) / n)
            var startX = (w - (barW * n + gap * (n - 1))) / 2
            var grad = rainbowGrad(ctx, startX, 0, barW * n + gap * (n - 1), 0)
            for (var i = 0; i < n; i++) {
                var val = Math.max(0.02, visData[i])
                var barH = Math.max(2, val * h * 0.6)
                var x = startX + i * (barW + gap), y = h - barH
                ctx.globalAlpha = 0.15
                ctx.fillStyle = grad
                ctx.fillRect(x - 4, y - 4, barW + 8, barH + 8)
                ctx.globalAlpha = 0.4
                ctx.fillRect(x - 2, y - 2, barW + 4, barH + 4)
                ctx.globalAlpha = 1.0
                ctx.fillStyle = grad
                ctx.fillRect(x, y, barW, barH)
            }
            ctx.globalAlpha = 1.0
        }

        function drawFire(ctx, w, h) {
            var n = visData.length, gap = 1
            var barW = Math.max(3, (w * 0.85 - gap * (n - 1)) / n)
            var totalW = barW * n + gap * (n - 1)
            var startX = (w - totalW) / 2
            for (var i = 0; i < n; i++) {
                var val = Math.max(0.02, visData[i])
                var barH = Math.max(4, val * h * 0.7)
                var x = startX + i * (barW + gap)
                var grad = ctx.createLinearGradient(x, h, x, h - barH)
                grad.addColorStop(0, "#4a0000")
                grad.addColorStop(0.3, "#cc0000")
                grad.addColorStop(0.55, "#ff6600")
                grad.addColorStop(0.8, "#ffaa00")
                grad.addColorStop(1, "#ffee44")
                ctx.fillStyle = grad
                ctx.beginPath()
                ctx.moveTo(x, h)
                ctx.lineTo(x + barW, h)
                ctx.lineTo(x + barW/2, h - barH)
                ctx.closePath()
                ctx.fill()
            }
        }

        function drawRings(ctx, w, h) {
            var cx = w/2, cy = h/2, n = visData.length
            var numRings = 8, groups = Math.floor(n / numRings)
            var maxR = Math.min(w, h) * 0.45
            var colors = ["#ff006e", "#8338ec", "#3a86ff", "#06d6a0", "#ffbe0b", "#fb5607", "#ff006e", "#8338ec"]
            ctx.lineWidth = 4
            for (var r = 0; r < numRings; r++) {
                var sum = 0
                for (var j = 0; j < groups; j++) sum += visData[r * groups + j] || 0
                var avg = sum / groups
                var radius = maxR * (r + 1) / numRings * (0.25 + avg * 0.75)
                ctx.strokeStyle = colors[r % colors.length]
                ctx.beginPath()
                ctx.arc(cx, cy, Math.max(4, radius), 0, Math.PI * 2)
                ctx.stroke()
            }
        }

        function drawBubbles(ctx, w, h) {
            var n = visData.length, cols = 8, rows = 4
            var spacingX = w / (cols + 1), spacingY = h / (rows + 1)
            var maxR = Math.min(spacingX, spacingY) * 0.4
            for (var i = 0; i < n; i++) {
                var val = Math.max(0.02, visData[i])
                var row = Math.floor(i / cols), col = i % cols
                var x = (col + 1) * spacingX, y = (row + 1) * spacingY
                var r = Math.max(2, val * maxR)
                var hue = i / n * 360
                ctx.fillStyle = "hsl(" + hue + ", 100%, 60%)"
                ctx.globalAlpha = 0.8
                ctx.beginPath()
                ctx.arc(x, y, r, 0, Math.PI * 2)
                ctx.fill()
                ctx.globalAlpha = 0.3
                ctx.fillStyle = "hsl(" + hue + ", 100%, 80%)"
                ctx.beginPath()
                ctx.arc(x, y, r * 0.6, 0, Math.PI * 2)
                ctx.fill()
            }
            ctx.globalAlpha = 1.0
        }

        function drawVUMeter(ctx, w, h) {
            var n = visData.length, gap = 2
            var barW = Math.max(2, (w * 0.8 - gap * (n - 1)) / n)
            var totalW = barW * n + gap * (n - 1)
            var startX = (w - totalW) / 2
            var segs = 8
            for (var i = 0; i < n; i++) {
                var val = Math.max(0.02, visData[i])
                var barH = val * h * 0.7
                var x = startX + i * (barW + gap)
                var segH = Math.max(3, (h * 0.7) / segs)
                var lit = Math.ceil(val * segs)
                for (var s = 0; s < lit; s++) {
                    var sy = h - (s + 1) * segH
                    var ratio = s / segs
                    if (ratio < 0.5) ctx.fillStyle = "#22c55e"
                    else if (ratio < 0.75) ctx.fillStyle = "#eab308"
                    else ctx.fillStyle = "#ef4444"
                    ctx.fillRect(x, sy, barW, segH - 1)
                }
            }
        }

        function drawPinwheel(ctx, w, h) {
            var cx = w/2, cy = h/2, n = visData.length
            ctx.save(); ctx.translate(cx, cy)
            var spokes = 12
            var groups = Math.floor(n / spokes)
            for (var s = 0; s < spokes; s++) {
                var sum = 0
                for (var j = 0; j < groups; j++) sum += visData[s * groups + j] || 0
                var avg = sum / groups
                var angle = s / spokes * Math.PI * 2 - Math.PI/2
                var len = 6 + avg * Math.min(w, h) * 0.4
                var hue = (s / spokes * 360 + new Date().getTime() * 0.05) % 360
                ctx.strokeStyle = "hsl(" + hue + ", 100%, 60%)"
                ctx.lineWidth = 4
                ctx.beginPath()
                ctx.moveTo(0, 0)
                ctx.lineTo(Math.cos(angle) * len, Math.sin(angle) * len)
                ctx.stroke()
            }
            ctx.restore()
        }

        function drawMeteor(ctx, w, h) {
            var n = visData.length, gap = 1
            var barW = Math.max(3, (w * 0.85 - gap * (n - 1)) / n)
            var totalW = barW * n + gap * (n - 1)
            var startX = (w - totalW) / 2
            var t = new Date().getTime() * 0.003
            for (var i = 0; i < n; i++) {
                var val = Math.max(0.02, visData[i])
                var barH = Math.max(3, val * h * 0.65)
                var x = startX + i * (barW + gap)
                var y = h - barH
                var offset = Math.sin(t + i * 0.5) * 3
                var grad = ctx.createLinearGradient(x, y + offset, x + barW, y + offset)
                grad.addColorStop(0, Qt.rgba(255, 255, 255, 0))
                grad.addColorStop(0.3, Qt.hsla(i / n, 1.0, 0.7, 1.0))
                grad.addColorStop(1, Qt.rgba(255, 255, 255, 0))
                ctx.fillStyle = grad
                ctx.fillRect(x, y + offset, barW, barH)
                ctx.fillStyle = "hsl(" + (i / n * 360) + ", 100%, 50%)"
                ctx.globalAlpha = 0.3
                ctx.fillRect(x - 1, y + offset - 1, barW + 2, barH + 2)
                ctx.globalAlpha = 1.0
            }
        }

        function drawWaves(ctx, w, h) {
            var n = visData.length, step = w / (n - 1)
            var maxH = h * 0.3
            for (var layer = 0; layer < 3; layer++) {
                ctx.beginPath()
                var offset = layer * 10
                ctx.moveTo(0, h/2 + (0.5 - visData[0]) * maxH * (1 - layer * 0.25) + offset)
                for (var i = 1; i < n; i++) {
                    var v = visData[Math.max(0, Math.min(n - 1, i - layer * 2))] || 0
                    ctx.lineTo(i * step, h/2 + (0.5 - v) * maxH * (1 - layer * 0.25) + offset)
                }
                ctx.strokeStyle = "hsla(" + (layer * 120) + ", 100%, 60%, 0.5)"
                ctx.lineWidth = 3 - layer
                ctx.stroke()
            }
        }

        function drawWater(ctx, w, h) {
            var n = visData.length, gap = 0
            var barW = Math.max(4, (w - gap * n) / n)
            var t = new Date().getTime() * 0.002
            for (var i = 0; i < n; i++) {
                var val = Math.max(0.02, visData[i])
                var barH = val * h * 0.6
                var x = i * (barW + gap)
                var wave = Math.sin(t + i * 0.3) * 5
                var grad = ctx.createLinearGradient(x, h - barH + wave, x, h)
                grad.addColorStop(0, Qt.hsla(0.556, 1.0, 0.7, 1.0))
                grad.addColorStop(1, Qt.hsla(0.611, 0.8, 0.3, 1.0))
                ctx.globalAlpha = 0.85
                ctx.fillStyle = grad
                ctx.beginPath()
                ctx.moveTo(x, h)
                ctx.lineTo(x, h - barH + wave)
                ctx.quadraticCurveTo(x + barW/2, h - barH - 4 + wave, x + barW, h - barH + wave)
                ctx.lineTo(x + barW, h)
                ctx.closePath()
                ctx.fill()
            }
            ctx.globalAlpha = 1.0
        }

        function drawStairs(ctx, w, h) {
            var n = visData.length, gap = 1
            var barW = Math.max(2, (w * 0.8 - gap * (n - 1)) / n)
            var totalW = barW * n + gap * (n - 1)
            var startX = (w - totalW) / 2
            var grad = rainbowGrad(ctx, startX, 0, totalW, 0)
            for (var i = 0; i < n; i++) {
                var val = Math.max(0.02, visData[i])
                var segments = Math.ceil(val * 8)
                var segH = Math.max(4, (h * 0.5) / 8)
                for (var s = 0; s < segments; s++) {
                    var sy = h - (s + 1) * segH
                    var sw = barW * (1 - s * 0.1)
                    var sx = startX + i * (barW + gap) + (barW - sw) / 2
                    ctx.fillStyle = grad
                    ctx.globalAlpha = 0.5 + s / segments * 0.5
                    ctx.fillRect(sx, sy, sw, segH - 1)
                }
            }
            ctx.globalAlpha = 1.0
        }

        function drawOrbit(ctx, w, h) {
            var cx = w/2, cy = h/2, n = visData.length
            var t = new Date().getTime() * 0.001
            for (var i = 0; i < n; i++) {
                var val = Math.max(0.02, visData[i])
                var angle = i / n * Math.PI * 2 + t * (0.5 + val * 0.5)
                var radius = 10 + val * Math.min(w, h) * 0.35
                var x = cx + Math.cos(angle) * radius
                var y = cy + Math.sin(angle) * radius
                var hue = (angle * 180 / Math.PI + t * 20) % 360
                ctx.fillStyle = "hsl(" + hue + ", 100%, 60%)"
                ctx.globalAlpha = 0.8
                ctx.beginPath()
                ctx.arc(x, y, 2 + val * 6, 0, Math.PI * 2)
                ctx.fill()
            }
            ctx.globalAlpha = 1.0
        }

        function drawXRay(ctx, w, h) {
            var n = visData.length, step = w / (n - 1), maxH = h * 0.45
            ctx.clearRect(0, 0, w, h)
            for (var i = 0; i < n - 1; i++) {
                var v1 = Math.max(0.02, visData[i])
                var v2 = Math.max(0.02, visData[i + 1])
                var x1 = i * step, x2 = (i + 1) * step
                var y1 = h/2 + (0.5 - v1) * maxH
                var y2 = h/2 + (0.5 - v2) * maxH
                ctx.strokeStyle = "rgba(0, 255, 100, 0.4)"
                ctx.lineWidth = 0.5
                ctx.beginPath()
                ctx.moveTo(x1, y1)
                ctx.lineTo(x2, y2)
                ctx.stroke()
                ctx.strokeStyle = "rgba(0, 200, 255, 0.2)"
                ctx.beginPath()
                ctx.moveTo(x1, h - y1)
                ctx.lineTo(x2, h - y2)
                ctx.stroke()
            }
            ctx.strokeStyle = "rgba(0, 255, 100, 0.6)"
            ctx.lineWidth = 2
            ctx.beginPath()
            ctx.moveTo(0, h/2 + (0.5 - visData[0]) * maxH)
            for (var i = 1; i < n; i++) {
                ctx.lineTo(i * step, h/2 + (0.5 - visData[i]) * maxH)
            }
            ctx.stroke()
            ctx.fillStyle = "rgba(0, 255, 100, 0.05)"
            ctx.lineTo(w, h); ctx.lineTo(0, h); ctx.closePath()
            ctx.fill()
        }

        onPaint: {
            var ctx = getContext("2d")
            var w = width, h = height
            if (w <= 0 || h <= 0) return
            if (!visData || visData.length < 2) return
            ctx.clearRect(0, 0, w, h)
            switch (visualizerMode) {
                case 0: drawBars(ctx, w, h); break
                case 1: drawWave(ctx, w, h); break
                case 2: drawCircle(ctx, w, h); break
                case 3: drawMirror(ctx, w, h); break
                case 4: drawGlow(ctx, w, h); break
                case 5: drawFire(ctx, w, h); break
                case 6: drawRings(ctx, w, h); break
                case 7: drawBubbles(ctx, w, h); break
                case 8: drawVUMeter(ctx, w, h); break
                case 9: drawPinwheel(ctx, w, h); break
                case 10: drawMeteor(ctx, w, h); break
                case 11: drawWaves(ctx, w, h); break
                case 12: drawWater(ctx, w, h); break
                case 13: drawStairs(ctx, w, h); break
                case 14: drawOrbit(ctx, w, h); break
                case 15: drawXRay(ctx, w, h); break
            }
        }
    }

    Rectangle {
        id: infoPanel
        anchors.top: videoContainer.top
        anchors.topMargin: 8
        anchors.left: videoContainer.left
        anchors.leftMargin: 8
        width: 300
        height: childrenRect.height + 16
        color: Qt.rgba(0, 0, 0, 0.82)
        radius: 6
        visible: mediaInfoVisible && app && app.mediaInfo && app.mediaInfo.filename
        z: 60

        Column {
            x: 8; y: 8
            spacing: 4
            width: parent.width - 16

            Repeater {
                model: app && app.mediaInfo ? Object.keys(app.mediaInfo) : []

                Row {
                    width: parent.width
                    spacing: 8

                    Text {
                        width: 100
                        color: "#888"
                        font.pixelSize: 11
                        text: {
                            var k = modelData
                            if (k === "filename") return "File"
                            if (k === "duration") return "Duration"
                            if (k === "format") return "Format"
                            if (k === "video_codec") return "Video Codec"
                            if (k === "resolution") return "Resolution"
                            if (k === "frame_rate") return "Frame Rate"
                            if (k === "video_bitrate") return "Video Bitrate"
                            if (k === "audio_codec") return "Audio Codec"
                            if (k === "sample_rate") return "Sample Rate"
                            if (k === "channels") return "Channels"
                            if (k === "audio_bitrate") return "Audio Bitrate"
                            return k
                        }
                    }

                    Text {
                        width: parent.width - 108
                        color: "#ddd"
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        text: {
                            var k = modelData
                            var v = app.mediaInfo[k]
                            if (k === "duration") {
                                var totalSec = Math.floor(v)
                                var h = Math.floor(totalSec / 3600)
                                var m = Math.floor((totalSec % 3600) / 60)
                                var s = totalSec % 60
                                var pad = function(n) { return n < 10 ? "0" + n : n }
                                return h > 0 ? h + ":" + pad(m) + ":" + pad(s) : pad(m) + ":" + pad(s)
                            }
                            return String(v)
                        }
                    }
                }
            }
        }

        Button {
            id: copyInfoBtn
            anchors.top: parent.top; anchors.topMargin: 4
            anchors.right: closeInfoBtn.left; anchors.rightMargin: 4
            flat: true; text: "Copy"; font.pixelSize: 10
            implicitWidth: 36; implicitHeight: 18
            background: Rectangle { color: parent.hovered ? "#555" : "transparent"; radius: 3 }
            onClicked: {
                var keys = app ? Object.keys(app.mediaInfo) : []
                var lines = []
                for (var i = 0; i < keys.length; i++) {
                    var k = keys[i], v = app.mediaInfo[k]
                    if (k === "duration") {
                        var totalSec = Math.floor(v)
                        var h = Math.floor(totalSec / 3600)
                        var m = Math.floor((totalSec % 3600) / 60)
                        var s = totalSec % 60
                        var pad = function(n) { return n < 10 ? "0" + n : n }
                        v = h > 0 ? h + ":" + pad(m) + ":" + pad(s) : pad(m) + ":" + pad(s)
                    }
                    lines.push(k + ": " + String(v))
                }
                app.copyText(lines.join("\n"))
                copyInfoBtn.text = "Copied!"
                copyInfoRestorer.restart()
            }
            Timer { id: copyInfoRestorer; interval: 1500; onTriggered: copyInfoBtn.text = "Copy" }
        }

        Button {
            id: closeInfoBtn
            anchors.top: parent.top; anchors.topMargin: 4
            anchors.right: parent.right; anchors.rightMargin: 4
            flat: true; text: "✕"; font.pixelSize: 11
            implicitWidth: 18; implicitHeight: 18
            background: Rectangle { color: parent.hovered ? "#666" : "transparent"; radius: 3 }
            onClicked: mediaInfoVisible = false
        }
    }

    MenuBar {
        id: topBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        z: 100
        visible: !pipMode && (!isFullscreen || controlsShown)

        Menu {
            title: "File"
            MenuItem { text: "Open File...         O"; onTriggered: app.openFile() }
            MenuItem { text: "Open URL...         Ctrl+U"; onTriggered: app.openUrl() }
            MenuItem { text: "Add to Playlist..."; onTriggered: app.playlistAddFile() }
            MenuSeparator {}
            MenuItem { text: "Save Playlist"; onTriggered: app.savePlaylist() }
            MenuItem { text: "Load Playlist"; onTriggered: app.loadPlaylist() }
            MenuSeparator {}
            MenuItem { text: "Open Subtitle File..."; onTriggered: app.openSubtitleFile() }
            MenuSeparator {}
            Menu {
                title: "Download"
                enabled: app && app.currentUrl && app.currentUrl.length > 0
                MenuItem { text: "Download MP4 (Video)"; onTriggered: app.downloadCurrentMedia("mp4") }
                MenuItem { text: "Download MP3 (Audio)"; onTriggered: app.downloadCurrentMedia("mp3") }
            }
            MenuSeparator {}
            MenuItem { text: "Quit                Ctrl+Q"; onTriggered: Qt.quit() }
        }

        Menu {
            title: "Playback"
            MenuItem {
                text: "Play/Pause          Space"
                enabled: true
                onTriggered: {
                    app.playPause()
                }
            }
            MenuItem {
                text: "Mute/Unmute            M"
                enabled: true
                onTriggered: { app.muted = !app.muted }
            }
            MenuSeparator {}
            Menu {
                title: "Visualizer            V"
                MenuItem {
                    text: "Bars"; checkable: true; checked: visualizerMode === 0
                    onTriggered: visualizerMode = 0
                }
                MenuItem {
                    text: "Wave"; checkable: true; checked: visualizerMode === 1
                    onTriggered: visualizerMode = 1
                }
                MenuItem {
                    text: "Circle"; checkable: true; checked: visualizerMode === 2
                    onTriggered: visualizerMode = 2
                }
                MenuItem {
                    text: "Mirror"; checkable: true; checked: visualizerMode === 3
                    onTriggered: visualizerMode = 3
                }
                MenuItem {
                    text: "Glow"; checkable: true; checked: visualizerMode === 4
                    onTriggered: visualizerMode = 4
                }
                MenuItem {
                    text: "Fire"; checkable: true; checked: visualizerMode === 5
                    onTriggered: visualizerMode = 5
                }
                MenuItem {
                    text: "Rings"; checkable: true; checked: visualizerMode === 6
                    onTriggered: visualizerMode = 6
                }
                MenuItem {
                    text: "Bubbles"; checkable: true; checked: visualizerMode === 7
                    onTriggered: visualizerMode = 7
                }
                MenuItem {
                    text: "VU Meter"; checkable: true; checked: visualizerMode === 8
                    onTriggered: visualizerMode = 8
                }
                MenuItem {
                    text: "Pinwheel"; checkable: true; checked: visualizerMode === 9
                    onTriggered: visualizerMode = 9
                }
                MenuItem {
                    text: "Meteor"; checkable: true; checked: visualizerMode === 10
                    onTriggered: visualizerMode = 10
                }
                MenuItem {
                    text: "Waves"; checkable: true; checked: visualizerMode === 11
                    onTriggered: visualizerMode = 11
                }
                MenuItem {
                    text: "Water"; checkable: true; checked: visualizerMode === 12
                    onTriggered: visualizerMode = 12
                }
                MenuItem {
                    text: "Stairs"; checkable: true; checked: visualizerMode === 13
                    onTriggered: visualizerMode = 13
                }
                MenuItem {
                    text: "Orbit"; checkable: true; checked: visualizerMode === 14
                    onTriggered: visualizerMode = 14
                }
                MenuItem {
                    text: "X-Ray"; checkable: true; checked: visualizerMode === 15
                    onTriggered: visualizerMode = 15
                }
            }
            MenuSeparator {}
            Menu {
                title: "Speed            Z"
                Repeater {
                    model: speedPresets
                    MenuItem {
                        text: modelData.toFixed(2).replace(/\.?0+$/, "") + "x"
                        checkable: true
                        checked: playbackSpeed === modelData
                        onTriggered: {
                            playbackSpeed = modelData
                            app.playbackRate = playbackSpeed
                        }
                    }
                }
            }
        }

        Menu {
            title: "View"
            MenuItem { text: "Fullscreen             F"; onTriggered: window.toggleFullscreen() }
            MenuItem { text: "Picture-in-Picture"; checkable: true; checked: pipMode; onTriggered: togglePip() }
            MenuSeparator {}
            MenuItem { text: "Always on Top"; checkable: true; checked: alwaysOnTop; onTriggered: window.toggleAlwaysOnTop() }
            MenuSeparator {}
            MenuItem { text: "Visualizer On"; checkable: true; checked: visualizerVisible; onTriggered: visualizerVisible = !visualizerVisible }
            MenuItem { text: "Equalizer             E"; checkable: true; checked: eqVisible; onTriggered: eqVisible = !eqVisible }
            MenuItem { text: "Media Info            I"; checkable: true; checked: mediaInfoVisible; onTriggered: mediaInfoVisible = !mediaInfoVisible }
            Menu {
                title: "Subtitles          Y"
                MenuItem { text: "None"; checkable: true; checked: app && app.activeSubtitleIndex < 0; onTriggered: if (app) { app.setActiveSubtitle(-1); app.setSubtitleVisible(false); subtitleTimer.stop(); subtitleLabel.text = "" } }
                MenuSeparator {}
                Repeater {
                    model: app ? app.subtitleTrackNames : []
                    MenuItem {
                        text: modelData
                        checkable: true
                        checked: app && app.activeSubtitleIndex === index
                        onTriggered: {
                            if (app) {
                                app.setActiveSubtitle(index)
                                app.setSubtitleVisible(true)
                                subtitleTimer.start()
                            }
                        }
                    }
                }
            }
            Menu {
                title: "EQ Preset"
                Repeater {
                    model: eqPresetNames
                    MenuItem {
                        text: modelData
                        onTriggered: {
                            if (app) app.applyEqPreset(index)
                            var gains = app ? app.eqGains : []
                            for (var i = 0; i < gains.length && i < eqGains.length; i++)
                                eqGains[i] = gains[i]
                        }
                    }
                }
            }
        }

        Menu {
            title: "Tools"
            MenuItem { text: "Settings...        Ctrl+T"; onTriggered: settingsDialog.open() }
        }

        Menu {
            title: "Help"
            MenuItem { text: "Documentation"; onTriggered: Qt.openUrlExternally("https://docs.dodatech.com/") }
            MenuItem { text: "Donate"; onTriggered: Qt.openUrlExternally("https://dodatech.com/donate/") }
            MenuSeparator {}
            MenuItem { text: "About"; onTriggered: aboutDialog.open() }
        }
    }

    Dialog {
        id: aboutDialog
        title: "About Doda Media Player"
        modal: true
        standardButtons: Dialog.Close
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: 360
        height: 280

        background: Rectangle {
            color: "#1e1e2e"
            radius: 8
        }

        contentItem: Item {
            Column {
                anchors.centerIn: parent
                spacing: 12

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: "#cdd6f4"
                    font.pixelSize: 22
                    font.bold: true
                    text: "Doda Media Player"
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: "#a6e3a1"
                    font.pixelSize: 14
                    text: "Version 1.0.0"
                }

                Rectangle {
                    width: 240; height: 1; color: "#313244"; anchors.horizontalCenter: parent.horizontalCenter
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: "#bac2de"
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    text: "A cross-platform media player with visualizer, equalizer, and subtitle support."
                    width: 280
                    wrapMode: Text.WordWrap
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: "#6c7086"
                    font.pixelSize: 11
                    text: "Made with love by DodaTech"
                }

                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    flat: true
                    implicitHeight: 28
                    contentItem: Text {
                        color: parent.hovered ? "#89b4fa" : "#74c7ec"
                        font.pixelSize: 11
                        text: "dodatech.com"
                    }
                    background: Rectangle { color: "transparent" }
                    onClicked: Qt.openUrlExternally("https://dodatech.com/")
                }
            }
        }
    }

    function fmtTime(ms) {
        if (ms <= 0) return "0s"
        var s = Math.floor(ms / 1000)
        var m = Math.floor(s / 60)
        var h = Math.floor(m / 60)
        s = s % 60; m = m % 60
        var parts = []
        if (h > 0) parts.push(h + "h")
        if (m > 0) parts.push(m + "m")
        parts.push(s + "s")
        return parts.join(" ")
    }

    Dialog {
        id: settingsDialog
        title: "Settings"
        modal: true
        standardButtons: Dialog.Close
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: 600
        height: 500

        background: Rectangle {
            color: "#1e1e2e"
            radius: 10
            border.color: "#333"
            border.width: 1
        }

        header: Rectangle {
            height: 40
            color: "#181825"
            radius: 10

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1; color: "#333"
            }

            Text {
                anchors.left: parent.left; anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                color: "#cdd6f4"
                font.pixelSize: 15
                font.bold: true
                text: "Settings"
            }
        }

        contentItem: Item {
            implicitWidth: 600
            implicitHeight: 460
            clip: true

                Flickable {
                anchors.fill: parent
                anchors.margins: 24
                contentHeight: settingsCol.height
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 6 }

                Column {
                    id: settingsCol
                    spacing: 20
                    width: parent.width

                    Text {
                        color: "#cdd6f4"
                        font.pixelSize: 15
                        font.bold: true
                        text: "Statistics"
                    }

                    Rectangle {
                        color: "#181825"
                        radius: 8
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: statsRow.height + 24

                        Row {
                            id: statsRow
                            spacing: 14
                            anchors.left: parent.left; anchors.leftMargin: 14
                            anchors.right: parent.right; anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter

                            Column {
                                spacing: 6
                                width: parent.width - 70
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    color: "#cdd6f4"
                                    font.pixelSize: 14
                                    text: "Enable watch time statistics"
                                }
                                Text {
                                    color: "#6c7086"
                                    font.pixelSize: 12
                                    text: "Tracks play count and total time per file. Stored locally only."
                                    wrapMode: Text.WordWrap
                                    width: parent.width
                                }
                            }

                            Switch {
                                id: statsSwitch
                                anchors.verticalCenter: parent.verticalCenter
                                checked: app ? app.statsEnabled : false
                                onToggled: {
                                    if (app) app.setStatsEnabled(checked)
                                }
                            }
                        }
                    }

                    Rectangle {
                        color: "#313244"
                        height: 1
                        anchors.left: parent.left
                        anchors.right: parent.right
                    }

                    Text {
                        color: "#585b70"
                        font.pixelSize: 13
                        text: "Your stats will appear here after you play some media."
                        visible: !statsSwitch.checked || !app || !app.statsEnabled
                    }

                    Column {
                        spacing: 12
                        visible: statsSwitch.checked && app && app.statsEnabled
                        anchors.left: parent.left
                        anchors.right: parent.right

                        Rectangle {
                            color: "#181825"
                            radius: 8
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: summaryCol.height + 28

                            Column {
                                id: summaryCol
                                spacing: 10
                                anchors.left: parent.left; anchors.leftMargin: 16
                                anchors.right: parent.right; anchors.rightMargin: 16
                                anchors.top: parent.top; anchors.topMargin: 14

                                StatsRow { label: "Total"; value: fmtTime(app && app.statsEnabled ? app.statsData.total_ms || 0 : 0) }
                                StatsRow { label: "Today"; value: fmtTime(app && app.statsEnabled ? app.statsData.today_ms || 0 : 0) }
                                StatsRow { label: "Session"; value: fmtTime(app && app.statsEnabled ? app.statsData.session_ms || 0 : 0) }
                            }
                        }

                        Rectangle {
                            color: "#313244"
                            height: 1
                            anchors.left: parent.left
                            anchors.right: parent.right
                            visible: (app && app.statsEnabled ? app.statsData.top_files || [] : []).length > 0
                        }

                        Text {
                            color: "#cdd6f4"
                            font.pixelSize: 14
                            font.bold: true
                            text: "Most Played"
                            visible: (app && app.statsEnabled ? app.statsData.top_files || [] : []).length > 0
                        }

                        Rectangle {
                            color: "#181825"
                            radius: 8
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: filesCol.height + 24
                            visible: app && app.statsEnabled

                            Column {
                                id: filesCol
                                spacing: 8
                                anchors.left: parent.left; anchors.leftMargin: 16
                                anchors.right: parent.right; anchors.rightMargin: 16
                                anchors.top: parent.top; anchors.topMargin: 12

                                Repeater {
                                    model: app && app.statsEnabled ? app.statsData.top_files || [] : []

                                    Row {
                                        spacing: 10
                                        width: filesCol.width
                                        height: 22

                                        Text {
                                            color: "#cdd6f4"
                                            font.pixelSize: 13
                                            text: modelData.name
                                            elide: Text.ElideRight
                                            width: parent.width - 220
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Text {
                                            color: "#a6adc8"
                                            font.pixelSize: 12
                                            text: (modelData.count || 0) + " plays"
                                            width: 80
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Text {
                                            color: "#89b4fa"
                                            font.pixelSize: 13
                                            text: fmtTime(modelData.total_ms || 0)
                                            width: 100
                                            horizontalAlignment: Text.AlignRight
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }

                                Text {
                                    color: "#585b70"
                                    font.pixelSize: 12
                                    text: "No file data yet."
                                    visible: (app && app.statsEnabled ? app.statsData.top_files || [] : []).length === 0
                                }
                            }
                        }

                        Button {
                            text: "Reset All Data"
                            anchors.horizontalCenter: parent.horizontalCenter
                            flat: true
                            onClicked: {
                                if (app) app.resetStats()
                            }
                            contentItem: Text {
                                text: "Reset All Data"
                                color: "#f38ba8"
                                font.pixelSize: 13
                            }
                            background: Rectangle {
                                color: "transparent"
                                border.color: "#f38ba8"
                                border.width: 1
                                radius: 6
                                implicitWidth: 130
                                implicitHeight: 32
                            }
                        }
                    }
                }
            }
        }
    }

    component StatsRow: Row {
        property string label: ""
        property string value: ""
        spacing: 10

        Text {
            color: "#6c7086"
            font.pixelSize: 14
            text: parent.label
            width: 90
        }
        Text {
            color: "#a6e3a1"
            font.pixelSize: 14
            font.bold: true
            text: parent.value
        }
    }

    Rectangle {
        id: topRow
        anchors.top: topBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 32
        color: Qt.rgba(0, 0, 0, 0.85)
        visible: !pipMode && (!isFullscreen || controlsShown)

        Button {
            id: openBtn
            anchors.left: parent.left
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            flat: true
            implicitWidth: 32
            implicitHeight: 26

            contentItem: FolderIcon { width: 16; height: 16 }

            background: Rectangle {
                color: parent.hovered ? "#444" : "transparent"
                radius: 3
            }

            onClicked: {
                keyHandler.forceActiveFocus()
                app.openFile()
            }

            ToolTip.visible: hovered
            ToolTip.text: "Open media file"
            ToolTip.delay: 400
        }

        Button {
            id: urlBtn
            anchors.left: openBtn.right
            anchors.leftMargin: 2
            anchors.verticalCenter: parent.verticalCenter
            flat: true
            implicitWidth: 32
            implicitHeight: 26

            contentItem: Image {
                source: "icons/url.svg"
                sourceSize.width: 16
                sourceSize.height: 16
                fillMode: Image.PreserveAspectFit
                smooth: true
                opacity: parent.hovered ? 1.0 : 0.65
            }

            background: Rectangle {
                color: parent.hovered ? "#444" : "transparent"
                radius: 3
            }

            onClicked: {
                keyHandler.forceActiveFocus()
                app.openUrl()
            }

            ToolTip.visible: hovered
            ToolTip.text: "Open URL (YouTube, etc.)"
            ToolTip.delay: 400
        }

        Text {
            id: trackLabel
            anchors.left: urlBtn.right
            anchors.leftMargin: 12
            anchors.right: dlBtn.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            color: "#ccc"
            font.pixelSize: 12
            elide: Text.ElideMiddle
            text: currentTrack
            visible: currentTrack.length > 0
        }

        Button {
            id: dlBtn
            anchors.right: closeBtn.left
            anchors.rightMargin: 2
            anchors.verticalCenter: parent.verticalCenter
            flat: true
            implicitWidth: 28
            implicitHeight: 26
            visible: app && app.currentUrl && app.currentUrl.length > 0

            contentItem: Image {
                source: "icons/download.svg"
                sourceSize.width: 16
                sourceSize.height: 16
                fillMode: Image.PreserveAspectFit
                smooth: true
                opacity: parent.hovered ? 1.0 : 0.65
            }

            background: Rectangle {
                color: parent.hovered ? "#444" : "transparent"
                radius: 3
            }

            onClicked: {
                keyHandler.forceActiveFocus()
                dlPopup.popup(dlBtn, 0, dlBtn.height)
            }

            ToolTip.visible: hovered
            ToolTip.text: "Download current video"
            ToolTip.delay: 400
        }

        Button {
            id: closeBtn
            anchors.right: quitBtn.left
            anchors.rightMargin: 2
            anchors.verticalCenter: parent.verticalCenter
            flat: true
            implicitWidth: 28
            implicitHeight: 26

            contentItem: Image {
                source: "icons/close.svg"
                sourceSize.width: 16
                sourceSize.height: 16
                fillMode: Image.PreserveAspectFit
                smooth: true
                opacity: parent.hovered ? 1.0 : 0.65
            }

            background: Rectangle {
                color: parent.hovered ? "#c0392b" : "transparent"
                radius: 3
            }

            onClicked: {
                app.closeMedia()
                currentTrack = ""
                originalTitle = "Doda Media Player"
                if (app) { app.playlist.clear() }
            }

            ToolTip.visible: hovered
            ToolTip.text: "Close media"
            ToolTip.delay: 400
        }

        Button {
            id: quitBtn
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            flat: true
            implicitWidth: 28
            implicitHeight: 26

            contentItem: Image {
                source: "icons/power.svg"
                sourceSize.width: 14
                sourceSize.height: 14
                fillMode: Image.PreserveAspectFit
                smooth: true
                opacity: parent.hovered ? 1.0 : 0.65
            }

            background: Rectangle {
                color: parent.hovered ? "#c0392b" : "transparent"
                radius: 3
            }

            onClicked: Qt.quit()

            ToolTip.visible: hovered
            ToolTip.text: "Quit"
            ToolTip.delay: 400
        }
    }

    Rectangle {
        id: eqPanel
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: bottomBar.top
        height: 120
        color: Qt.rgba(20, 20, 30, 0.95)
        visible: eqVisible && (!isFullscreen || controlsShown)

        Row {
            anchors.centerIn: parent
            spacing: 4
            Repeater {
                model: 10
                Column {
                    spacing: 2; width: 60
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: "#888"; font.pixelSize: 10
                        text: app ? app.eqBandLabels[index] : ""
                    }
                    Slider {
                        from: 0; to: 4; value: eqGains[index]
                        orientation: Qt.Vertical
                        implicitWidth: 30; implicitHeight: 70
                        onMoved: {
                            eqGains[index] = value
                            if (app) app.setEqGain(index, value)
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: "#aaa"; font.pixelSize: 10
                        text: Math.round((eqGains[index] - 1) * 12) + " dB"
                    }
                }
            }
        }

        Button {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: 8
            flat: true
            text: "↺"
            font.pixelSize: 18
            implicitWidth: 32; implicitHeight: 32
            onClicked: {
                if (app) app.resetEq()
                for (var i = 0; i < eqGains.length; i++) eqGains[i] = 1.0
            }
            ToolTip.visible: hovered; ToolTip.text: "Reset EQ"; ToolTip.delay: 400
        }
    }

    Rectangle {
        id: playlistPanel
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: bottomBar.top
        width: 280
        color: Qt.rgba(15, 15, 25, 0.92)
        visible: playlistVisible && playlistItems.length > 0 && (!isFullscreen || controlsShown)

        Rectangle {
            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
            height: 32; color: Qt.rgba(30, 30, 45, 0.9)
            Text {
                anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter
                color: "#aaa"; font.pixelSize: 12; text: "Playlist"
            }
            Button {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.rightMargin: 4
                flat: true; text: "✕"; font.pixelSize: 14
                implicitWidth: 24; implicitHeight: 24
                onClicked: playlistVisible = false
            }
        }

        ListView {
            anchors.top: parent.top; anchors.topMargin: 32
            anchors.left: parent.left; anchors.right: parent.right
            anchors.bottom: parent.bottom
            clip: true
            model: playlistItems
            delegate: Rectangle {
                width: parent.width; height: 36
                color: model.index === playlistCurrentIndex ? Qt.rgba(29, 185, 84, 0.2) : "transparent"

                Text {
                    anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter
                    anchors.right: removeBtn.left; anchors.rightMargin: 4
                    color: model.index === playlistCurrentIndex ? "#1db954" : "#ccc"
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    text: modelData.replace(/^.*[/\\]/, "")
                }

                Button {
                    id: removeBtn
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.rightMargin: 4
                    flat: true; text: "✕"; font.pixelSize: 10
                    implicitWidth: 20; implicitHeight: 20
                    onClicked: { if (app) app.playlist.remove(model.index) }
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: function(mouse) {
                        if (mouse.button === Qt.LeftButton) {
                            if (app) app.playlist._current = model.index
                        } else {
                            contextMenu.popup()
                        }
                    }

                    Menu {
                        id: contextMenu
                        MenuItem { text: "Remove"; onTriggered: { if (app) app.playlist.remove(model.index) } }
                        MenuItem { text: "Clear"; onTriggered: { if (app) app.playlist.clear() } }
                    }
                }
            }
        }
    }

    Rectangle {
        id: bottomBar
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 80
        color: Qt.rgba(0, 0, 0, 0.85)
        visible: !pipMode && (!isFullscreen || controlsShown)

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onPositionChanged: {
                if (!controlsShown) {
                    controlsShown = true
                } else {
                    controlsTimer.restart()
                }
            }
            onPressed: keyHandler.forceActiveFocus()
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    color: "#aaa"
                    font.pixelSize: 11
                    text: formatTime(app ? app.position : 0)
                    verticalAlignment: Text.AlignVCenter
                }

                Item {
                    Layout.fillWidth: true
                    height: 24

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 4
                        radius: 2
                        color: "#444"

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: app && app.duration > 0
                                ? (parent.width * Math.min(app.position / app.duration, 1.0))
                                : 0
                            height: 4
                            radius: 2
                            color: "#1db954"
                            Behavior on width { NumberAnimation { duration: 200 } }
                        }
                    }

                    Text {
                        y: -20
                        x: Math.max(0, Math.min(parent.width - width, seekHoverRatio * parent.width - width / 2))
                        color: "#fff"
                        font.pixelSize: 11
                        font.bold: true
                        text: seekHoverRatio >= 0 && app.duration > 0
                            ? formatTime(seekHoverRatio * app.duration) : ""
                        visible: seekHoverRatio >= 0
                        style: Text.Outline
                        styleColor: "#000"
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onPressed: function(mouse) {
                            if (!app || app.duration <= 0) return
                            var ratio = Math.max(0, Math.min(1, mouse.x / width))
                            app.position = ratio * app.duration
                        }
                        onPositionChanged: function(mouse) {
                            var r = Math.max(0, Math.min(1, mouse.x / width))
                            seekHoverRatio = r
                        }
                        onExited: {
                            seekHoverRatio = -1
                        }
                    }
                }

                Text {
                    color: "#666"
                    font.pixelSize: 11
                    text: formatTime(app ? app.duration : 0)
                    verticalAlignment: Text.AlignVCenter
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                Item { Layout.fillWidth: true }

                Row {
                    spacing: 4
                    Layout.alignment: Qt.AlignHCenter

                    SeekBtn {
                        iconSource: "icons/previous.svg"
                        tooltipText: "Previous    (P)"
                        onClicked: { if (app) app.playPrevious() }
                    }

                    SeekBtn {
                        iconSource: "icons/rewind.svg"
                        tooltipText: "Back 10s"
                        onClicked: { app.position = Math.max(0, app.position - 10000) }
                    }

                    PlayPauseBtn {}

                    SeekBtn {
                        iconSource: "icons/forward.svg"
                        tooltipText: "Forward 10s"
                        onClicked: { app.position = app.position + 10000 }
                    }

                    SeekBtn {
                        iconSource: "icons/next.svg"
                        tooltipText: "Next    (N)"
                        onClicked: { if (app) app.playNext() }
                    }
                }

                Item { Layout.fillWidth: true }

                Row {
                    spacing: 4
                    Layout.alignment: Qt.AlignRight

                    SeekBtn {
                        iconSource: app && app.muted ? "icons/mute.svg" : "icons/volume.svg"
                        tooltipText: app && app.muted ? "Unmute" : "Mute"
                        onClicked: { if (app) app.muted = !app.muted }
                    }

                    Slider {
                        id: volumeSlider
                        from: 0
                        to: 100
                        value: app ? Math.round(app.volume * 100) : 50
                        implicitWidth: 80
                        implicitHeight: 20
                        onMoved: { app.volume = value / 100.0 }
                    }

                    Text {
                        color: "#666"; font.pixelSize: 10
                        text: playlistItems.length + " items"
                        visible: playlistItems.length > 0
                        verticalAlignment: Text.AlignVCenter
                    }

                    SeekBtn {
                        iconSource: "icons/playlist.svg"
                        tooltipText: "Playlist    (L)"
                        onClicked: playlistVisible = !playlistVisible
                    }

                    SeekBtn {
                        iconSource: "icons/visualizer.svg"
                        tooltipText: (visualizerVisible ? "Hide" : "Show") + " Visualizer (H)"
                        onClicked: {
                            if (visualizerVisible)
                                visualizerVisible = false
                            else {
                                visualizerVisible = true
                                visualizerMode = (visualizerMode + 1) % 16
                            }
                        }
                    }

                    SeekBtn {
                        iconSource: "icons/equalizer.svg"
                        tooltipText: "Equalizer    (E)"
                        onClicked: eqVisible = !eqVisible
                    }

                    Button {
                        flat: true
                        implicitWidth: 28
                        implicitHeight: 32
                        contentItem: Text {
                            color: parent.hovered ? "#fff" : "#aaa"
                            font.pixelSize: 13
                            font.bold: true
                            text: "i"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            color: parent.hovered ? "#444" : "transparent"
                            radius: 3
                        }
                        onClicked: mediaInfoVisible = !mediaInfoVisible
                        hoverEnabled: true
                        ToolTip.visible: hovered
                        ToolTip.text: "Media Info    (I)"
                        ToolTip.delay: 400
                    }

                    Button {
                        flat: true
                        implicitWidth: 32
                        implicitHeight: 32
                        contentItem: Text {
                            color: app && app.subtitleVisible ? "#1db954" : (parent.hovered ? "#fff" : "#aaa")
                            font.pixelSize: 12
                            font.bold: true
                            text: "CC"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            color: parent.hovered ? "#444" : "transparent"
                            radius: 3
                        }
                        onClicked: {
                            if (app) {
                                if (app.subtitleVisible) {
                                    app.setSubtitleVisible(false)
                                    subtitleTimer.stop()
                                    subtitleLabel.text = ""
                                    subtitleLabel.visible = false
                                } else if (app.subtitleTrackNames.length > 0) {
                                    app.setActiveSubtitle(0)
                                    app.setSubtitleVisible(true)
                                    subtitleTimer.start()
                                }
                            }
                        }
                        hoverEnabled: true
                        ToolTip.visible: hovered
                        ToolTip.text: "Subtitles    (Y)"
                        ToolTip.delay: 400
                    }

                    SeekBtn {
                        iconSource: "icons/shuffle.svg"
                        tooltipText: "Shuffle    (S)"
                        onClicked: {
                            if (app) app.playlist.shuffle = !app.playlist.shuffle
                        }
                    }

                    SeekBtn {
                        iconSource: "icons/repeat.svg"
                        tooltipText: "Repeat    (R)"
                        onClicked: {
                            if (app) app.playlist.repeatMode = (app.playlist.repeatMode + 1) % 3
                        }
                    }

                    Button {
                        flat: true
                        implicitWidth: 44
                        implicitHeight: 32
                        enabled: true

                        contentItem: Text {
                            color: parent.hovered ? "#fff" : "#aaa"
                            font.pixelSize: 11
                            font.bold: true
                            text: playbackSpeed.toFixed(2).replace(/\.?0+$/, "") + "x"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        background: Rectangle {
                            color: parent.hovered ? "#444" : "transparent"
                            radius: 3
                        }

                        onClicked: {
                            var idx = speedPresets.indexOf(playbackSpeed)
                            idx = (idx + 1) % speedPresets.length
                            playbackSpeed = speedPresets[idx]
                            app.playbackRate = playbackSpeed
                        }

                        hoverEnabled: true
                        ToolTip.visible: hovered
                        ToolTip.text: "Speed: " + playbackSpeed.toFixed(2).replace(/\.?0+$/, "") + "x  (Z)"
                        ToolTip.delay: 400
                    }

                    SeekBtn {
                        iconSource: "icons/fullscreen.svg"
                        tooltipText: "Fullscreen"
                        onClicked: window.toggleFullscreen()
                    }

                    Button {
                        flat: true
                        implicitWidth: 32
                        implicitHeight: 32
                        contentItem: Text {
                            color: pipMode ? "#89b4fa" : (parent.hovered ? "#fff" : "#aaa")
                            font.pixelSize: 10
                            font.bold: true
                            text: "PiP"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            color: parent.hovered ? "#444" : "transparent"
                            radius: 3
                        }
                        onClicked: togglePip()
                        hoverEnabled: true
                        ToolTip.visible: hovered
                        ToolTip.text: pipMode ? "Exit Picture-in-Picture" : "Picture-in-Picture"
                        ToolTip.delay: 400
                    }

                }
            }
        }
    }

    component PlayPauseBtn: Button {
        flat: true
        implicitWidth: 40
        implicitHeight: 36
        contentItem: Image {
            source: isVideoPlaying ? "icons/pause.svg" : "icons/play.svg"
            sourceSize.width: 24
            sourceSize.height: 24
            fillMode: Image.PreserveAspectFit
            smooth: true
            opacity: parent.hovered ? 1.0 : 0.65
        }
        background: Rectangle {
            color: parent.hovered ? "#555" : "transparent"; radius: 4
        }

        onClicked: {
            app.playPause()
        }

        hoverEnabled: true
        ToolTip.visible: hovered
        ToolTip.text: isVideoPlaying ? "Pause" : "Play"
        ToolTip.delay: 400
    }

    component SeekBtn: Button {
        flat: true
        implicitWidth: 32
        implicitHeight: 32
        property string iconSource: ""
        property string tooltipText: ""
        contentItem: Image {
            source: parent.iconSource
            sourceSize.width: 20
            sourceSize.height: 20
            fillMode: Image.PreserveAspectFit
            smooth: true
            opacity: parent.hovered ? 1.0 : 0.65
        }
        background: Rectangle {
            color: parent.hovered ? "#444" : "transparent"; radius: 3
        }
        hoverEnabled: true
        ToolTip.visible: hovered && tooltipText.length > 0
        ToolTip.text: tooltipText
        ToolTip.delay: 400

        WheelHandler {
            onWheel: function(event) {
                if (app) {
                    var step = event.angleDelta.y > 0 ? 0.05 : -0.05
                    var v = Math.max(0, Math.min(1, app.volume + step))
                    app.volume = v
                    if (volumeSlider) volumeSlider.value = Math.round(v * 100)
                }
            }
        }
    }

    component FolderIcon: Image {
        source: "icons/folder.svg"
        sourceSize.width: width
        sourceSize.height: height
        fillMode: Image.PreserveAspectFit
        smooth: true
    }

    Text {
        id: errorLabel
        anchors.centerIn: parent
        color: "#ff6b6b"
        font.pixelSize: 16
        visible: false
        z: 10
    }

    property bool controlsShown: true

    function formatTime(ms) {
        if (ms < 0 || isNaN(ms)) return "00:00"
        var totalSec = Math.floor(ms / 1000)
        var hours = Math.floor(totalSec / 3600)
        var minutes = Math.floor((totalSec % 3600) / 60)
        var secs = totalSec % 60
        var pad = function(n) { return n < 10 ? "0" + n : n }
        return hours > 0 ? hours + ":" + pad(minutes) + ":" + pad(secs) : pad(minutes) + ":" + pad(secs)
    }

    function cycleSpeed() {
        var idx = speedPresets.indexOf(playbackSpeed)
        idx = (idx + 1) % speedPresets.length
        playbackSpeed = speedPresets[idx]
        app.playbackRate = playbackSpeed
    }

    function toggleFullscreen() {
        isFullscreen = !isFullscreen
        if (isFullscreen)
            window.showFullScreen()
        else
            window.showNormal()
        controlsTimer.stop()
        controlsShown = true
        controlsTimer.restart()
    }

    function toggleAlwaysOnTop() {
        alwaysOnTop = !alwaysOnTop
        if (app) app.setAlwaysOnTop(alwaysOnTop)
    }

    function togglePip() {
        pipMode = !pipMode
        if (pipMode) {
            if (isFullscreen) toggleFullscreen()
            savedPipX = window.x
            savedPipY = window.y
            savedPipW = window.width
            savedPipH = window.height
            window.width = 360
            window.height = 200
            if (app) app.setAlwaysOnTop(true)
            alwaysOnTop = true
        } else {
            window.width = savedPipW
            window.height = savedPipH
            window.setPosition(savedPipX, savedPipY)
            if (!alwaysOnTop && app) app.setAlwaysOnTop(false)
            if (app) {
                app.saveConfig("window_x", savedPipX)
                app.saveConfig("window_y", savedPipY)
                app.saveConfig("window_width", savedPipW)
                app.saveConfig("window_height", savedPipH)
            }
        }
    }

    Timer {
        id: visPollTimer
        interval: 50
        repeat: true
        running: false
        onTriggered: visCanvas.poll()
    }

    Timer {
        id: controlsTimer
        interval: 3000
        onTriggered: {
            if (app.playbackState === 1)
                controlsShown = false
        }
    }

    Timer {
        id: subtitleTimer
        interval: 100
        repeat: true
        running: false
        onTriggered: {
            if (app && app.subtitleVisible) {
                var pos = app ? app.position : 0
                var txt = app.getSubtitleText(pos)
                if (subtitleLabel.text !== txt) {
                    subtitleLabel.text = txt
                    subtitleLabel.visible = txt.length > 0
                }
            } else if (!app || !app.subtitleVisible) {
                if (subtitleLabel.text.length > 0 || subtitleLabel.visible) {
                    subtitleLabel.text = ""
                    subtitleLabel.visible = false
                }
            }
        }
    }

    Timer {
        id: positionSaver
        interval: 10000
        repeat: true
        running: false
        onTriggered: {
            if (app && app.position > 30000) {
                var path = app.playlist.currentPath()
                if (path) {
                    var positions = app.loadConfig("resume_positions", {})
                    positions[path] = app.position
                    app.saveConfig("resume_positions", positions)
                }
            }
        }
    }

    MouseArea {
        id: videoMouseArea
        anchors.fill: parent
        anchors.topMargin: (topBar.visible ? topBar.height : 0) + (topRow.visible ? topRow.height : 0)
        anchors.bottomMargin: (bottomBar.visible ? bottomBar.height : 0) + (eqVisible && (!isFullscreen || controlsShown) ? 120 : 0)
        anchors.rightMargin: playlistVisible && playlistItems.length > 0 && (!isFullscreen || controlsShown) ? 280 : 0
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onPositionChanged: {
            if (!controlsShown) {
                controlsShown = true
                controlsTimer.restart()
            } else {
                controlsTimer.restart()
            }
        }

        onPressed: keyHandler.forceActiveFocus()

        onClicked: function(mouse) {
            if (mouse.button === Qt.LeftButton) {
                if (controlsShown) {
                    controlsTimer.stop()
                    controlsShown = false
                } else {
                    controlsShown = true
                    controlsTimer.restart()
                }
            }
            if (mouse.button === Qt.RightButton) {
                contextMenu.popup()
            }
        }

        onDoubleClicked: window.toggleFullscreen()
    }

    Menu {
        id: dlPopup
        enabled: app && app.currentUrl && app.currentUrl.length > 0
        MenuItem { text: "Download MP4 (Video)"; onTriggered: app.downloadCurrentMedia("mp4") }
        MenuItem { text: "Download MP3 (Audio)"; onTriggered: app.downloadCurrentMedia("mp3") }
    }

    Menu {
        id: contextMenu
        MenuItem {
            text: "Play/Pause  (Space)"
            enabled: true
            onTriggered: {
                app.playPause()
            }
        }
        MenuItem {
            text: "Mute/Unmute  (M)"
            enabled: true
            onTriggered: { app.muted = !app.muted }
        }
        MenuSeparator {}
        MenuItem { text: "Previous  (P)"; onTriggered: if (app) app.playPrevious() }
        MenuItem { text: "Next  (N)"; onTriggered: if (app) app.playNext() }
        MenuSeparator {}
        MenuItem { text: "Open File...  (O)"; onTriggered: app.openFile() }
        MenuItem { text: "Fullscreen  (F)"; onTriggered: window.toggleFullscreen() }
        MenuItem {
            text: "Visualizer: " + visModeNames[visualizerMode] + "  (V)"
            onTriggered: visualizerMode = (visualizerMode + 1) % 16
        }
        Menu {
            title: "Speed"
            Repeater {
                model: speedPresets
                MenuItem {
                    text: modelData.toFixed(2).replace(/\.?0+$/, "") + "x"
                    onTriggered: {
                        playbackSpeed = modelData
                        app.playbackRate = playbackSpeed
                    }
                }
            }
        }
        MenuSeparator {}
        MenuItem { text: "Picture-in-Picture"; onTriggered: togglePip() }
        MenuSeparator {}
        Menu {
            title: "Download"
            enabled: app && app.currentUrl && app.currentUrl.length > 0
            MenuItem { text: "Download MP4 (Video)"; onTriggered: app.downloadCurrentMedia("mp4") }
            MenuItem { text: "Download MP3 (Audio)"; onTriggered: app.downloadCurrentMedia("mp3") }
        }
        MenuSeparator {}
        MenuItem { text: "Subtitles  (Y)"; onTriggered: { if (!app) return; if (app.subtitleVisible) { app.setSubtitleVisible(false); subtitleTimer.stop(); subtitleLabel.text = "" } else if (app.subtitleTrackNames.length > 0) { app.setActiveSubtitle(0); app.setSubtitleVisible(true); subtitleTimer.start() } } }
        MenuSeparator {}
        MenuItem { text: "Save Playlist"; onTriggered: app.savePlaylist() }
        MenuItem { text: "Load Playlist"; onTriggered: app.loadPlaylist() }
        MenuSeparator {}
        MenuItem { text: "Quit  (Ctrl+Q)"; onTriggered: Qt.quit() }
    }

    DropArea {
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: function(drop) {
            if (drop.urls.length > 0) {
                for (var u = 0; u < drop.urls.length; u++) {
                    var path = drop.urls[u]
                    if (path.toString().startsWith("file://"))
                        path = path.toString().substring(7)
                    if (app) app.playlist.add(path)
                }
            }
        }
    }

    Item {
        id: keyHandler
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(event) {
            switch (event.key) {
                case Qt.Key_Space:
                    app.playPause()
                    event.accepted = true
                    break
                case Qt.Key_Left:
                    app.position = app.position - 5000
                    event.accepted = true
                    break
                case Qt.Key_Right:
                    app.position = app.position + 5000
                    event.accepted = true
                    break
                case Qt.Key_Up:
                    app.volume = Math.min(1.0, app.volume + 0.1)
                    event.accepted = true
                    break
                case Qt.Key_Down:
                    app.volume = Math.max(0.0, app.volume - 0.1)
                    event.accepted = true
                    break
            }
        }
    }

    Shortcut { sequence: "F"; context: Qt.ApplicationShortcut; onActivated: window.toggleFullscreen() }
    Shortcut { sequence: "O"; context: Qt.ApplicationShortcut; onActivated: app.openFile() }
    Shortcut { sequence: "Ctrl+U"; context: Qt.ApplicationShortcut; onActivated: app.openUrl() }
    Shortcut { sequence: "Ctrl+Q"; context: Qt.ApplicationShortcut; onActivated: Qt.quit() }
    Shortcut { sequence: "E"; context: Qt.ApplicationShortcut; onActivated: eqVisible = !eqVisible }
    Shortcut { sequence: "L"; context: Qt.ApplicationShortcut; onActivated: playlistVisible = !playlistVisible }
    Shortcut { sequence: "N"; context: Qt.ApplicationShortcut; onActivated: if (app) app.playNext() }
    Shortcut { sequence: "P"; context: Qt.ApplicationShortcut; onActivated: if (app) app.playPrevious() }
    Shortcut { sequence: "S"; context: Qt.ApplicationShortcut; onActivated: if (app) app.playlist.shuffle = !app.playlist.shuffle }
    Shortcut { sequence: "R"; context: Qt.ApplicationShortcut; onActivated: if (app) app.playlist.repeatMode = (app.playlist.repeatMode + 1) % 3 }
    Shortcut { sequence: "M"; context: Qt.ApplicationShortcut; onActivated: app.muted = !app.muted }
    Shortcut { sequence: "H"; context: Qt.ApplicationShortcut; onActivated: visualizerVisible = !visualizerVisible }
    Shortcut { sequence: "V"; context: Qt.ApplicationShortcut; onActivated: { visualizerVisible = true; visualizerMode = (visualizerMode + 1) % 16 } }
    Shortcut { sequence: "Z"; context: Qt.ApplicationShortcut; onActivated: cycleSpeed() }
    Shortcut { sequence: "I"; context: Qt.ApplicationShortcut; onActivated: mediaInfoVisible = !mediaInfoVisible }
    Shortcut { sequence: "Y"; context: Qt.ApplicationShortcut; onActivated: { if (!app) return; if (app.subtitleVisible) { app.setSubtitleVisible(false); subtitleTimer.stop(); subtitleLabel.text = "" } else if (app.subtitleTrackNames.length > 0) { app.setActiveSubtitle(0); app.setSubtitleVisible(true); subtitleTimer.start() } } }
    Shortcut { sequence: "Ctrl+T"; context: Qt.ApplicationShortcut; onActivated: settingsDialog.open() }
    Shortcut { sequence: "Ctrl+P"; context: Qt.ApplicationShortcut; onActivated: togglePip() }
    Shortcut {
        sequence: "Escape"
        context: Qt.ApplicationShortcut
        onActivated: {
            if (window.visibility === ApplicationWindow.FullScreen)
                window.toggleFullscreen()
        }
    }

    Connections {
        target: app
        function onEqChanged() {
            var gains = app ? app.eqGains : []
            for (var i = 0; i < gains.length && i < eqGains.length; i++)
                eqGains[i] = gains[i]
        }
        function onPlaylistIndexChanged(idx) {
            playlistCurrentIndex = idx
            if (app) playlistItems = app.playlist.items
        }
    }

    Connections {
        target: app ? app.playlist : null
        function onItemsChanged() {
            if (app) {
                playlistItems = app.playlist.items
                playlistCurrentIndex = app.playlist.currentIndex
            }
        }
    }

    Connections {
        target: app
        function onFileOpened(path) {
            var name = path.replace(/^.*[/\\]/, "")
            name = name.replace(/\.\w{2,4}$/, "")
            currentTrack = name
            originalTitle = "Doda Media Player - " + name
        }
    }

    Component.onCompleted: {
        var gains = app ? app.eqGains : []
        for (var i = 0; i < gains.length && i < eqGains.length; i++)
            eqGains[i] = gains[i]
        if (app) {
            playlistItems = app.playlist.items
            playlistCurrentIndex = app.playlist.currentIndex
        }
        var wx = app ? app.loadConfig("window_x", -1) : -1
        var wy = app ? app.loadConfig("window_y", -1) : -1
        var ww = app ? app.loadConfig("window_width", 960) : 960
        var wh = app ? app.loadConfig("window_height", 540) : 540
        if (wx > 0 && wy > 0) window.setPosition(wx, wy)
        window.width = ww
        window.height = wh
    }

    onClosing: function(event) {
        if (app) {
            app.savePlaylist()
            app.saveConfig("window_x", window.x)
            app.saveConfig("window_y", window.y)
            app.saveConfig("window_width", window.width)
            app.saveConfig("window_height", window.height)
            if (app.position > 30000) {
                var path = app.playlist.currentPath()
                if (path) {
                    var positions = app.loadConfig("resume_positions", {})
                    positions[path] = app.position
                    app.saveConfig("resume_positions", positions)
                }
            }
        }
    }
}
