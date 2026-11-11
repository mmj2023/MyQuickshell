pragma Singleton

import QtCore
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Common
import "WallpaperShortcutConfig.js" as ShortcutConfig

Singleton {
  id: root

  signal fileChooserFallback(string operation, var screen, string scope)

  property var items: []
  property var directoryGroups: []
  property string error: ""
  property string overlayMode: ""
  property var overlayScreen: null
  property var scanCommand: []
  property bool scanPending: false
  property var mediaController: null
  property var mediaResolutions: ({})
  property var mediaResolverProcesses: ({})
  property int mediaResolveGeneration: 0
  property var audioWaveforms: ({})
  property var audioWaveformProcesses: ({})
  property int audioWaveformGeneration: 0
  property string switcherApplyScope: "global"
  readonly property var toplevels: Hyprland.toplevels?.values || []
  readonly property string videoResolution: SettingsData.wallpaperVideoResolution
  readonly property var videoResolutionOptions: [
    { label: qsTr("Best available"), value: "best" },
    { label: qsTr("Up to 2160p"), value: "2160" },
    { label: qsTr("Up to 1440p"), value: "1440" },
    { label: qsTr("Up to 1080p"), value: "1080" },
    { label: qsTr("Up to 720p"), value: "720" },
    { label: qsTr("Up to 480p"), value: "480" }
  ]
  property var appWindows: []
  property var appWindow: null
  property string appWindowTitle: ""
  property bool appPreviewPaused: false
  property bool mediaMuted: false
  property real mediaVolume: 0.45
  property bool shortcutCaptureActive: false
  property bool shortcutCheckPending: false
  property bool shortcutApplyPending: false
  property string pendingShortcut: SettingsData.wallpaperShortcut || "SUPER + ALT + E"
  property string requestedShortcut: ""
  property string activeShortcut: ""
  property bool compositorShortcutConflict: false
  property string shortcutStatus: qsTr("Apply a shortcut to check for conflicts and enable it.")
  property bool shortcutStatusIsError: false

  readonly property string hyprlandConfigPath:
    StandardPaths.writableLocation(StandardPaths.ConfigLocation) + "/hypr"
  readonly property string source: SettingsData.wallpaperSource
  readonly property string type: SettingsData.wallpaperType
  readonly property var directories: SettingsData.wallpaperDirectories
  function refreshDirectoryGroups() {
    const paths = root.directories
      .map(path => root.pathFromUrl(path).trim().replace(/\/+$/, ""))
      .filter(path => path.length > 0)
    root.directoryGroups = paths.map(directory => {
      const nestedDirectories = paths.filter(candidate =>
        candidate !== directory && root.isPathWithinDirectory(candidate, directory)
      )
      const groupItems = root.items.filter(item => {
        const path = root.pathFromUrl(item)
        return root.isPathWithinDirectory(path, directory)
          && !nestedDirectories.some(nested =>
            root.isPathWithinDirectory(path, nested)
          )
      })
      return { path: directory, items: groupItems }
    })
  }
  readonly property bool mediaHasAudio: root.mediaController
    ? root.mediaController.hasAudio : false
  readonly property bool mediaIsPlaying: root.mediaController
    ? root.mediaController.isPlaying : false
  readonly property bool mediaSeekable: root.mediaController
    ? root.mediaController.seekable : false
  readonly property int mediaPosition: root.mediaController
    ? root.mediaController.position : 0
  readonly property int mediaDuration: root.mediaController
    ? root.mediaController.duration : 0

  Component.onCompleted: {
    Qt.callLater(scanDirectories)
    Qt.callLater(root.restoreConfiguredShortcut)
    Qt.callLater(root.restoreAppWindow)
    Qt.callLater(root.restoreMediaSource)
  }

  Component.onDestruction: {
    if (root.activeShortcut)
      root.unbindShortcut(root.activeShortcut)
  }

  Connections {
    target: SettingsData
    function onSettingsApplied() {
      root.restoreConfiguredShortcut()
      root.restoreAppWindow()
      root.restoreMediaSource()
    }
  }

  Connections {
    target: SettingsData
    function onWallpaperDirectoriesChanged() {
      root.scanDirectories()
    }
  }

  Connections {
    target: root.appWindow
    ignoreUnknownSignals: true
    function onDestroyed() {
      root.appWindow = null
      root.appWindowTitle = ""
      root.appPreviewPaused = false
    }
  }

  function isPathWithinDirectory(path, directory) {
    const value = String(path)
    const base = String(directory).replace(/\/+$/, "")
    if (base === "")
      return value.startsWith("/")
    return value === base || value.startsWith(base + "/")
  }

  Process {
    id: scanProcess
    command: root.scanCommand

    stdout: StdioCollector {
      id: scanOutput
      waitForEnd: true
    }

    stderr: StdioCollector {
      id: scanError
      waitForEnd: true
    }

    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.error = scanError.text.trim() || qsTr("Could not scan wallpaper folders.")
      } else {
        root.error = ""
        root.items = scanOutput.text.split("\n")
          .filter(path => path.length > 0)
          .sort((a, b) => a.localeCompare(b))
          .filter((path, index, paths) => index === 0 || path !== paths[index - 1])
          .map(path => root.urlForPath(path))
        root.refreshDirectoryGroups()
      }

      if (root.scanPending) {
        root.scanPending = false
        root.scanDirectories()
      }
    }
  }

  Process {
    id: bindCheckProcess
    command: ["hyprctl", "binds", "-j"]

    stdout: StdioCollector {
      id: bindCheckOutput
      waitForEnd: true
    }

    stderr: StdioCollector {
      id: bindCheckError
      waitForEnd: true
    }

    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.shortcutCheckPending = false
        const detail = bindCheckError.text.trim()
        const message = qsTr("Couldn't check Hyprland shortcuts. Check your config; no change was made.")
        root.setShortcutStatus(
          detail ? message + " " + detail : message,
          true
        )
        return
      }

      const result = root.inspectBindings(bindCheckOutput.text, root.requestedShortcut)
      if (!result.valid) {
        root.shortcutCheckPending = false
        root.setShortcutStatus(
          qsTr("Couldn't verify Hyprland shortcuts. Check your config; no change was made."),
          true
        )
      } else {
        root.compositorShortcutConflict = result.conflict
        root.setShortcutStatus(qsTr("Checking Hyprland Lua config…"), false)
        configBindCheckProcess.running = true
      }
    }
  }

  Process {
    id: configBindCheckProcess
    command: [
      "find", "-L", root.hyprlandConfigPath, "-type", "f", "-name", "*.lua",
      "-exec", "sh", "-c",
      "for file do printf '\\n__MYQUICKSHELL_LUA_FILE__\\n' || exit 1; cat \"$file\" || exit 1; printf '\\n' || exit 1; done",
      "sh", "{}", "+"
    ]

    stdout: StdioCollector {
      id: configBindCheckOutput
      waitForEnd: true
    }

    stderr: StdioCollector {
      id: configBindCheckError
      waitForEnd: true
    }

    onExited: function(exitCode) {
      root.shortcutCheckPending = false
      if (exitCode !== 0) {
        const detail = configBindCheckError.text.trim()
        const message = qsTr("Couldn't read the Hyprland Lua config; no change was made.")
        root.setShortcutStatus(detail ? message + " " + detail : message, true)
        return
      }

      const result = ShortcutConfig.inspectBindings(
        configBindCheckOutput.text,
        root.requestedShortcut,
        root.canonicalShortcut
      )
      if (!result.valid) {
        root.setShortcutStatus(
          qsTr("Couldn't fully parse Hyprland Lua binds; no change was made."),
          true
        )
      } else if (root.compositorShortcutConflict || result.conflict) {
        root.setShortcutStatus(
          qsTr("That shortcut is already in use. Choose another chord; no change was made."),
          true
        )
      } else {
        root.activateRequestedShortcut()
      }
    }
  }

  Component {
    id: mediaResolverProcessComponent

    Process {
      id: mediaResolverProcessInstance
      property string requestSource: ""
      property int requestGeneration: 0
      command: []

      stdout: StdioCollector {
        id: mediaResolverOutput
        waitForEnd: true
      }

      stderr: StdioCollector {
        id: mediaResolverError
        waitForEnd: true
      }

      onExited: function(exitCode) {
        root.finishMediaResolution(
          mediaResolverProcessInstance,
          requestSource,
          requestGeneration,
          exitCode,
          mediaResolverOutput.text,
          mediaResolverError.text
        )
      }
    }
  }

  Component {
    id: audioWaveformProcessComponent

    Process {
      id: audioWaveformProcessInstance
      property string requestSource: ""
      property int requestGeneration: 0
      command: []

      stdout: StdioCollector {
        id: audioWaveformOutput
        waitForEnd: true
      }

      stderr: StdioCollector {
        id: audioWaveformError
        waitForEnd: true
      }

      onExited: function(exitCode) {
        root.finishAudioWaveform(
          audioWaveformProcessInstance,
          requestSource,
          requestGeneration,
          exitCode,
          audioWaveformOutput.text,
          audioWaveformError.text
        )
      }
    }
  }

  Component {
    id: wallpaperChooserProcess

    Process {
      property var request: ({})
      command: []

      stdout: StdioCollector {
        id: chooserOutput
        waitForEnd: true
      }

      stderr: StdioCollector {
        id: chooserError
        waitForEnd: true
      }

      onExited: function(exitCode) {
        root.handleChooserResult(
          request, exitCode, chooserOutput.text, chooserError.text
        )
        destroy()
      }
    }
  }

  Timer {
    interval: Math.max(1, SettingsData.wallpaperIntervalMinutes) * 60000
    repeat: true
    running: SettingsData.wallpaperCycleEnabled && root.items.length > 1
    onTriggered: root.nextWallpaper("global")
  }

  function urlForPath(path) {
    const value = String(path)
    if (value.startsWith("file://"))
      return value
    return "file://" + value.split("/").map(part => encodeURIComponent(part)).join("/")
  }

  function pathFromUrl(url) {
    const value = String(url)
    if (!value.startsWith("file://"))
      return value
    return decodeURIComponent(value.replace(/^file:\/\//, ""))
  }

  function typeForSource(source) {
    const path = String(source).toLowerCase().split(/[?#]/)[0]
    if (/^https?:\/\//.test(path) && !/\.[a-z0-9]+$/.test(path))
      return "video"
    if (/\.qml$/.test(path))
      return "scene"
    if (/\.(glb|gltf|mesh)$/.test(path))
      return "model3d"
    if (/\.(mp3|m4a|aac|ogg|opus|flac|wav|wma|aiff|alac)$/.test(path))
      return "audio"
    if (/\.(mp4|m4v|webm|mov|mkv|avi|av1|m3u8|mpd)$/.test(path))
      return "video"
    return "image"
  }

  function workspaceKeyForScreen(screen) {
    const monitor = String(screen?.name || "")
    if (!monitor)
      return ""
    const workspaceName = WorkspacesService.activeWorkspaceName(monitor)
      || String(WorkspacesService.activeWorkspaceId(monitor) || "")
    return workspaceName ? monitor + "::" + workspaceName : ""
  }

  function workspaceLabelForScreen(screen) {
    const monitor = String(screen?.name || "")
    if (!monitor)
      return qsTr("No active workspace")
    const workspace = WorkspacesService.activeWorkspaceName(monitor)
      || String(WorkspacesService.activeWorkspaceId(monitor) || "")
    return workspace ? monitor + " · " + workspace : qsTr("No active workspace")
  }

  function overrideForScreen(screen) {
    const key = root.workspaceKeyForScreen(screen)
    const overrides = SettingsData.wallpaperWorkspaceOverrides || ({})
    return key ? overrides[key] || null : null
  }

  function hasWorkspaceOverrideForScreen(screen) {
    const override = root.overrideForScreen(screen)
    return !!(override && override.source)
  }

  function clearWorkspaceOverride(screen) {
    const key = root.workspaceKeyForScreen(screen)
    if (!key || !root.hasWorkspaceOverrideForScreen(screen))
      return false
    const overrides = Object.assign({}, SettingsData.wallpaperWorkspaceOverrides || ({}))
    delete overrides[key]
    if (!SettingsData.setMany({ wallpaperWorkspaceOverrides: overrides })) {
      root.error = qsTr("Wallpaper settings are not ready yet.")
      return false
    }
    root.error = ""
    return true
  }

  function sourceForTarget(scope, screen) {
    const override = scope === "workspace" ? root.overrideForScreen(screen) : null
    return override?.source || root.source
  }

  function typeForTarget(scope, screen) {
    const override = scope === "workspace" ? root.overrideForScreen(screen) : null
    return override?.type || root.type
  }

  function isMediaAudioOwner(screen) {
    const owner = Array.from(Quickshell.screens || []).find(candidate => {
      const type = root.typeForTarget("workspace", candidate)
      return type === "video" || type === "audio"
    })
    return !!owner && owner === screen
  }

  function setDefaultApplyScope(scope) {
    if (scope !== "global" && scope !== "workspace")
      return false
    if (scope === "workspace" && !root.workspaceKeyForScreen(root.overlayScreen)) {
      root.error = qsTr("There is no active workspace on this monitor.")
      return false
    }
    if (!SettingsData.setMany({ wallpaperApplyScope: scope })) {
      root.error = qsTr("Wallpaper settings are not ready yet.")
      return false
    }
    root.error = ""
    return true
  }

  function setSwitcherApplyScope(scope) {
    if (scope !== "global" && scope !== "workspace")
      return false
    if (scope === "workspace" && !root.workspaceKeyForScreen(root.overlayScreen)) {
      root.error = qsTr("There is no active workspace on this monitor.")
      return false
    }
    root.switcherApplyScope = scope
    root.error = ""
    return true
  }

  function toggleSwitcherApplyScope() {
    const next = root.switcherApplyScope === "global" ? "workspace" : "global"
    return root.setSwitcherApplyScope(next)
  }

  function requiresYouTubeExtraction(source) {
    return /^https?:\/\/(?:(?:www|m|music)\.)?(?:youtube\.com|youtu\.be|youtube-nocookie\.com)(?:\/|$)/i
      .test(String(source))
  }

  function setVideoResolution(value) {
    const option = root.videoResolutionOptions.find(item => item.value === value)
    if (!option) {
      root.error = qsTr("Choose a supported video resolution.")
      return false
    }
    if (!SettingsData.setMany({ wallpaperVideoResolution: option.value })) {
      root.error = qsTr("Wallpaper settings are not ready yet.")
      return false
    }
    const sources = Object.keys(root.mediaResolutions)
      .map(key => root.mediaResolutions[key]?.source || "")
      .filter(source => source.length > 0)
    if (root.requiresYouTubeExtraction(root.source))
      sources.push(root.source)
    sources.filter((source, index) => sources.indexOf(source) === index)
      .forEach(source => root.resolveMediaSource(source, "video", true))
    return true
  }

  function youtubeFormatForResolution() {
    const formats = {
      "best": "bestvideo+bestaudio/best",
      "2160": "bestvideo[height<=2160]+bestaudio/best[height<=2160]",
      "1440": "bestvideo[height<=1440]+bestaudio/best[height<=1440]",
      "1080": "bestvideo[height<=1080]+bestaudio/best[height<=1080]",
      "720": "bestvideo[height<=720]+bestaudio/best[height<=720]",
      "480": "bestvideo[height<=480]+bestaudio/best[height<=480]"
    }
    return formats[root.videoResolution] || formats.best
  }

  function restoreMediaSource() {
    if (root.type === "video" || root.type === "audio")
      root.resolveMediaSource(root.source, root.type, false)
  }

  function mediaResolutionKey(source) {
    return "$" + String(source)
  }

  function mediaResolutionFor(source) {
    return root.mediaResolutions[root.mediaResolutionKey(source)] || null
  }

  function updateMediaResolution(key, resolution) {
    const resolutions = Object.assign({}, root.mediaResolutions)
    resolutions[key] = resolution
    root.mediaResolutions = resolutions
  }

  function mediaVideoSourceFor(source) {
    const value = String(source || "")
    if (!root.requiresYouTubeExtraction(value))
      return value
    return root.mediaResolutionFor(value)?.videoSource || ""
  }

  function mediaAudioSourceFor(source) {
    return root.mediaResolutionFor(source)?.audioSource || ""
  }

  function audioWaveformKey(source) {
    return "$" + String(source)
  }

  function audioWaveformFor(source) {
    return root.audioWaveforms[root.audioWaveformKey(source)] || null
  }

  function updateAudioWaveform(key, waveform) {
    const waveforms = Object.assign({}, root.audioWaveforms)
    waveforms[key] = waveform
    root.audioWaveforms = waveforms
  }

  function ensureAudioWaveform(source) {
    const value = String(source || "").trim()
    if (!value)
      return
    const key = root.audioWaveformKey(value)
    const current = root.audioWaveformFor(value)
    if (current && current.attempted)
      return

    const generation = ++root.audioWaveformGeneration
    root.updateAudioWaveform(key, {
      source: value,
      attempted: true,
      pending: true,
      generation: generation,
      samples: []
    })
    const process = audioWaveformProcessComponent.createObject(root, {
      requestSource: value,
      requestGeneration: generation,
      command: [
        "python3",
        Quickshell.shellDir + "/Services/WallpaperAudioWaveform.py",
        root.pathFromUrl(value)
      ]
    })
    if (!process) {
      root.updateAudioWaveform(key, {
        source: value,
        attempted: true,
        pending: false,
        generation: generation,
        samples: []
      })
      root.error = qsTr("Could not start audio waveform analysis.")
      return
    }

    const processes = Object.assign({}, root.audioWaveformProcesses)
    processes[key] = process
    root.audioWaveformProcesses = processes
    process.running = true
  }

  function finishAudioWaveform(process, source, generation, exitCode, output, errorOutput) {
    const key = root.audioWaveformKey(source)
    const processes = Object.assign({}, root.audioWaveformProcesses)
    if (processes[key] === process) {
      delete processes[key]
      root.audioWaveformProcesses = processes
    }
    const current = root.audioWaveformFor(source)
    if (!current || generation !== current.generation) {
      process.destroy()
      return
    }

    let result = null
    if (exitCode === 0) {
      try {
        result = JSON.parse(String(output || ""))
      } catch (error) {
        result = null
      }
    }
    const samples = result && Array.isArray(result.samples)
      ? result.samples.map(value => Math.max(0, Math.min(1, Number(value))))
        .filter(value => Number.isFinite(value))
      : []
    if (exitCode !== 0 || samples.length < 2) {
      const detail = String(errorOutput || "").trim()
      root.error = detail
        ? qsTr("Could not analyze this audio wallpaper: %1").arg(detail)
        : qsTr("Could not analyze this audio wallpaper. Install optional Python 3, ffmpeg, and ffprobe.")
      root.updateAudioWaveform(key, {
        source: source,
        attempted: true,
        pending: false,
        generation: generation,
        samples: []
      })
      process.destroy()
      return
    }

    root.updateAudioWaveform(key, {
      source: source,
      attempted: true,
      pending: false,
      generation: generation,
      duration: Number(result && result.duration) || 0,
      samples: samples
    })
    root.error = ""
    process.destroy()
  }

  function stopMediaResolver(key) {
    const processes = Object.assign({}, root.mediaResolverProcesses)
    const process = processes[key]
    if (process) {
      delete processes[key]
      root.mediaResolverProcesses = processes
      if (process.running)
        process.running = false
    }
  }

  function resolveMediaSource(source, sourceType, force) {
    const value = String(source || "").trim()
    if (!value || (sourceType !== "video" && sourceType !== "audio")
        || !root.requiresYouTubeExtraction(value))
      return
    const key = root.mediaResolutionKey(value)
    const current = root.mediaResolutionFor(value)
    if (!force && current?.attempted)
      return

    root.stopMediaResolver(key)
    const generation = ++root.mediaResolveGeneration
    root.updateMediaResolution(key, {
      source: value,
      attempted: true,
      pending: true,
      generation: generation,
      videoSource: "",
      audioSource: ""
    })
    root.error = ""

    const process = mediaResolverProcessComponent.createObject(root, {
      requestSource: value,
      requestGeneration: generation,
      command: [
        "yt-dlp",
        "--no-warnings",
        "--no-playlist",
        "--format", root.youtubeFormatForResolution(),
        "--get-url",
        value
      ]
    })
    if (!process) {
      root.updateMediaResolution(key, {
        source: value,
        attempted: true,
        pending: false,
        generation: generation,
        videoSource: "",
        audioSource: ""
      })
      root.error = qsTr("Could not start the optional yt-dlp stream resolver.")
      return
    }

    const processes = Object.assign({}, root.mediaResolverProcesses)
    processes[key] = process
    root.mediaResolverProcesses = processes
    process.running = true
  }

  function finishMediaResolution(process, source, generation, exitCode, output, errorOutput) {
    const key = root.mediaResolutionKey(source)
    const processes = Object.assign({}, root.mediaResolverProcesses)
    if (processes[key] === process) {
      delete processes[key]
      root.mediaResolverProcesses = processes
    }
    const current = root.mediaResolutionFor(source)
    if (!current || generation !== current.generation) {
      process.destroy()
      return
    }

    const urls = String(output || "").split(/\r?\n/)
      .map(value => value.trim())
      .filter(value => value.length > 0)
    if (exitCode !== 0
        || (urls.length !== 1 && urls.length !== 2)
        || urls.some(url => !/^https?:\/\//i.test(url))) {
      const detail = String(errorOutput || "").trim()
      root.error = detail
        ? qsTr("Could not resolve this YouTube video: %1").arg(detail)
        : qsTr("Could not resolve this YouTube video. Install or update optional yt-dlp.")
      root.updateMediaResolution(key, {
        source: source,
        attempted: true,
        pending: false,
        generation: generation,
        videoSource: "",
        audioSource: ""
      })
      process.destroy()
      return
    }

    root.updateMediaResolution(key, {
      source: source,
      attempted: true,
      pending: false,
      generation: generation,
      videoSource: urls[0],
      audioSource: urls.length === 2 ? urls[1] : ""
    })
    root.error = ""
    process.destroy()
  }

  function refreshAppWindows() {
    root.appWindows = Array.from(root.toplevels)
      .filter(window => !!window.address && !!window.wayland)
      .map(window => ({
        address: String(window.address).toLowerCase(),
        appId: String(window.wayland.appId || ""),
        title: String(window.wayland.title || window.title
          || window.wayland.appId || qsTr("Application")),
        window: window.wayland
      }))
      .sort((first, second) => first.title.localeCompare(second.title))
  }

  function setAppWindow(item, scope, screen) {
    if (!item?.window || !item.address) {
      root.error = qsTr("Choose an available app window.")
      return false
    }
    if (!root.setSource(String(item.address).toLowerCase(), "app", scope, screen))
      return false

    if (scope !== "workspace") {
      root.appWindow = item.window
      root.appWindowTitle = String(item.title || qsTr("Application"))
      root.appPreviewPaused = false
    }
    return true
  }

  function appWindowForSource(source) {
    const address = String(source || "").toLowerCase()
    if (!address)
      return null
    if (root.type === "app" && root.source.toLowerCase() === address && root.appWindow)
      return root.appWindow
    const match = root.toplevels.find(
      window => String(window.address || "").toLowerCase() === address && !!window.wayland
    )
    return match?.wayland || null
  }

  function appWindowTitleForSource(source) {
    const address = String(source || "").toLowerCase()
    if (root.type === "app" && root.source.toLowerCase() === address
        && root.appWindowTitle)
      return root.appWindowTitle
    const match = root.toplevels.find(
      window => String(window.address || "").toLowerCase() === address && !!window.wayland
    )
    return match
      ? String(match.wayland.title || match.title || match.wayland.appId || qsTr("Application"))
      : ""
  }

  function restoreAppWindow() {
    if (root.type !== "app" || root.appWindow || !root.source)
      return

    const address = String(root.source).toLowerCase()
    const match = root.toplevels.find(
      window => String(window.address || "").toLowerCase() === address && !!window.wayland
    )
    if (!match)
      return

    root.appWindow = match.wayland
    root.appWindowTitle = String(match.wayland.title || match.title
      || match.wayland.appId || qsTr("Application"))
  }

  function setSource(source, type, scope, screen) {
    const value = String(source || "").trim()
    if (!value) {
      root.error = qsTr("Choose a wallpaper source first.")
      return false
    }

    const nextType = type || root.typeForSource(value)
    const targetScope = scope === "workspace" ? "workspace" : "global"
    let updated = false
    if (targetScope === "workspace") {
      const key = root.workspaceKeyForScreen(screen || root.overlayScreen)
      if (!key) {
        root.error = qsTr("There is no active workspace on this monitor.")
        return false
      }
      const overrides = Object.assign({}, SettingsData.wallpaperWorkspaceOverrides || ({}))
      overrides[key] = { source: value, type: nextType }
      updated = SettingsData.setMany({ wallpaperWorkspaceOverrides: overrides })
    } else {
      updated = SettingsData.setMany({
        wallpaperSource: value,
        wallpaperType: nextType
      })
    }
    if (!updated) {
      root.error = qsTr("Wallpaper settings are not ready yet.")
      return false
    }
    root.error = ""
    if (nextType === "video" || nextType === "audio")
      root.resolveMediaSource(value, nextType, true)
    if (nextType === "audio")
      root.ensureAudioWaveform(value)
    if (targetScope === "global" && nextType !== "app") {
      root.appWindow = null
      root.appWindowTitle = ""
      root.appPreviewPaused = false
    }
    return true
  }

  function setColor(color, scope, screen) {
    const value = String(color || "").trim()
    if (!/^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.test(value)) {
      root.error = qsTr("Enter a color as #RGB or #RRGGBB.")
      return false
    }
    return root.setSource(value, "color", scope, screen)
  }

  function addDirectory(url) {
    const path = root.pathFromUrl(url).trim().replace(/\/+$/, "")
    if (!path) {
      root.error = qsTr("Choose a valid wallpaper folder.")
      return
    }
    const paths = SettingsData.wallpaperDirectories.slice()
    if (paths.some(existing =>
      root.pathFromUrl(existing).trim().replace(/\/+$/, "") === path
    ))
      return
    paths.push(path)
    SettingsData.set("wallpaperDirectories", paths)
  }

  function removeDirectory(directory) {
    const target = root.pathFromUrl(directory || "").trim().replace(/\/+$/, "")
    if (!target)
      return false
    const paths = SettingsData.wallpaperDirectories.slice()
    const index = paths.findIndex(path =>
      root.pathFromUrl(path).trim().replace(/\/+$/, "") === target
    )
    if (index < 0 || index >= paths.length)
      return false
    paths.splice(index, 1)
    if (!SettingsData.setMany({ wallpaperDirectories: paths })) {
      root.error = qsTr("Could not remove this wallpaper folder.")
      return false
    }
    root.error = ""
    return true
  }

  function scanDirectories() {
    const paths = SettingsData.wallpaperDirectories
      .map(path => root.pathFromUrl(path).trim())
      .filter(path => path.length > 0)
    if (scanProcess.running) {
      root.scanPending = true
      return
    }
    if (paths.length === 0) {
      root.items = []
      root.directoryGroups = []
      root.error = ""
      return
    }

    const fileTypes = [
      "*.png", "-o", "-iname", "*.jpg", "-o", "-iname", "*.jpeg", "-o",
      "-iname", "*.webp", "-o", "-iname", "*.bmp", "-o", "-iname", "*.gif", "-o",
      "-iname", "*.mp3", "-o", "-iname", "*.m4a", "-o", "-iname", "*.aac", "-o",
      "-iname", "*.ogg", "-o", "-iname", "*.opus", "-o", "-iname", "*.flac", "-o",
      "-iname", "*.wav", "-o", "-iname", "*.wma", "-o", "-iname", "*.aiff", "-o",
      "-iname", "*.alac", "-o",
      "-iname", "*.mp4", "-o", "-iname", "*.m4v", "-o", "-iname", "*.webm", "-o",
      "-iname", "*.mov", "-o", "-iname", "*.mkv", "-o", "-iname", "*.avi", "-o",
      "-iname", "*.av1", "-o", "-iname", "*.avif", "-o",
      "-iname", "*.m3u8", "-o", "-iname", "*.mpd", "-o", "-iname", "*.qml", "-o",
      "-iname", "*.glb", "-o", "-iname", "*.gltf", "-o", "-iname", "*.mesh"
    ]
    root.scanCommand = ["find"].concat(
      paths,
      ["-mindepth", "1", "-maxdepth", "1", "-xtype", "f", "(", "-iname"]
        .concat(fileTypes, [")", "-print"])
    )
    root.error = ""
    scanProcess.running = true
  }

  function applyItem(index, scope, screen) {
    if (index < 0 || index >= root.items.length)
      return false
    const source = root.items[index]
    return root.setSource(source, root.typeForSource(source), scope, screen)
  }

  function applySwitcherItem(index, scope, screen) {
    const targetScope = scope || root.switcherApplyScope
    const targetScreen = screen || root.overlayScreen
    if (index < 0 || index >= root.switcherItemCount(targetScope, targetScreen))
      return false
    const source = root.switcherItemAt(index, targetScope, targetScreen)
    return root.setSource(source, root.typeForSwitcherItem(
      source, targetScope, targetScreen
    ), targetScope, targetScreen)
  }

  function typeForSwitcherItem(source, scope, screen) {
    if (source === root.sourceForTarget(scope || "global", screen || root.overlayScreen))
      return root.typeForTarget(scope || "global", screen || root.overlayScreen)
    return String(source).startsWith("#") ? "color" : root.typeForSource(source)
  }

  function currentSwitcherIndex(scope, screen) {
    const source = root.sourceForTarget(scope || "global", screen || root.overlayScreen)
    const index = root.items.indexOf(source)
    return index < 0 ? 0 : index
  }

  function switcherItemCount(scope, screen) {
    const source = root.sourceForTarget(scope || "global", screen || root.overlayScreen)
    const sourceIndex = root.items.indexOf(source)
    return root.items.length + (source && sourceIndex < 0 ? 1 : 0)
  }

  function switcherItemAt(index, scope, screen) {
    const source = root.sourceForTarget(scope || "global", screen || root.overlayScreen)
    const sourceIndex = root.items.indexOf(source)
    if (source && sourceIndex < 0)
      return index === 0 ? source : root.items[index - 1]
    return root.items[index]
  }

  function switcherPreviewItems(startIndex, limit, scope, screen) {
    const source = root.sourceForTarget(scope || "global", screen || root.overlayScreen)
    const sourceIndex = root.items.indexOf(source)
    const injectSource = source && sourceIndex < 0
    const count = root.items.length + (injectSource ? 1 : 0)
    if (count === 0)
      return []

    const start = ((startIndex % count) + count) % count
    const result = []
    for (let offset = 0; offset < Math.min(limit, count); offset++) {
      const index = (start + offset) % count
      result.push(injectSource
        ? index === 0 ? source : root.items[index - 1]
        : root.items[index])
    }
    return result
  }

  function registerMediaController(controller) {
    root.mediaController = controller
  }

  function unregisterMediaController(controller) {
    if (root.mediaController === controller)
      root.mediaController = null
  }

  function toggleMediaPlayback() {
    if (root.mediaController)
      root.mediaController.togglePlayback()
  }

  function seekMedia(position) {
    if (root.mediaController && root.mediaSeekable)
      root.mediaController.seekTo(position)
  }

  function setMediaVolume(value) {
    root.mediaVolume = Math.max(0, Math.min(1, Number(value)))
  }

  function formatMediaTime(milliseconds) {
    if (!Number.isFinite(milliseconds) || milliseconds <= 0)
      return "0:00"
    const totalSeconds = Math.floor(milliseconds / 1000)
    const seconds = String(totalSeconds % 60).padStart(2, "0")
    const minutes = Math.floor(totalSeconds / 60)
    return minutes >= 60
      ? Math.floor(minutes / 60) + ":" + String(minutes % 60).padStart(2, "0") + ":" + seconds
      : minutes + ":" + seconds
  }

  function rotateWallpaper(amount, scope, screen) {
    const targetScope = scope || "global"
    const targetScreen = screen || root.overlayScreen
    const count = root.switcherItemCount(targetScope, targetScreen)
    if (count === 0)
      return false
    const next = (root.currentSwitcherIndex(targetScope, targetScreen)
      + amount % count + count) % count
    return root.applySwitcherItem(next, targetScope, targetScreen)
  }

  function nextWallpaper(scope, screen) {
    return root.rotateWallpaper(1, scope, screen)
  }

  function previousWallpaper(scope, screen) {
    return root.rotateWallpaper(-1, scope, screen)
  }

  function openOverview(screen) {
    if (root.shortcutCaptureActive)
      root.cancelShortcutCapture()
    root.overlayScreen = screen || Quickshell.screens[0] || null
    root.overlayMode = "overview"
  }

  function openSwitcher(screen) {
    if (root.shortcutCaptureActive)
      root.cancelShortcutCapture()
    root.overlayScreen = screen || Quickshell.screens[0] || null
    root.switcherApplyScope = SettingsData.wallpaperApplyScope === "workspace"
      && root.workspaceKeyForScreen(root.overlayScreen)
      ? "workspace" : "global"
    root.overlayMode = "switcher"
  }

  function toggleSwitcher(screen) {
    const target = screen || Quickshell.screens[0] || null
    if (root.overlayMode === "switcher" && root.overlayScreen === target)
      root.closeOverlay()
    else
      root.openSwitcher(target)
  }

  function closeOverlay() {
    root.overlayMode = ""
    root.cancelShortcutCapture()
  }

  function chooseMediaFile(screen, scope) {
    root.beginChooser("media", screen, scope)
  }

  function chooseDirectory(screen) {
    root.beginChooser("directory", screen)
  }

  function beginChooser(operation, screen, scope) {
    const target = screen || root.overlayScreen || Quickshell.screens[0] || null
    const targetScope = scope === "workspace" ? "workspace" : "global"
    root.overlayScreen = target
    root.closeOverlay()
    Qt.callLater(function() {
      if (!root.startChooserProcess(operation, "portal", target, targetScope)) {
        root.openOverview(target)
        root.fileChooserFallback(operation, target, targetScope)
      }
    })
  }

  function startChooserProcess(operation, stage, screen, scope) {
    const process = wallpaperChooserProcess.createObject(root, {
      request: { operation: operation, stage: stage, screen: screen, scope: scope }
    })
    if (!process)
      return false

    const command = stage === "portal"
      ? ["env", "GTK_USE_PORTAL=1", "zenity", "--file-selection"]
      : ["zenity", "--file-selection"]
    if (operation === "directory")
      command.push("--directory")
    command.push("--title=" + (operation === "media"
      ? qsTr("Choose wallpaper media")
      : qsTr("Add a wallpaper folder")))
    if (operation === "media") {
      command.push(
        "--filename=" + StandardPaths.writableLocation(StandardPaths.PicturesLocation) + "/",
        "--file-filter=" + qsTr("Wallpapers and media")
          + " | *.png *.jpg *.jpeg *.webp *.bmp *.gif *.avif *.mp3 *.m4a *.aac *.ogg *.opus *.flac *.wav *.wma *.aiff *.alac *.mp4 *.m4v *.webm *.mov *.mkv *.avi *.av1 *.m3u8 *.mpd *.qml *.glb *.gltf *.mesh",
        "--file-filter=" + qsTr("All files") + " | *"
      )
    }
    process.command = command
    process.running = true
    return true
  }

  function handleChooserResult(request, exitCode, output, errorOutput) {
    const selectedPath = String(output || "").trim()
    if (exitCode === 0 && selectedPath.length > 0) {
      const path = root.pathFromUrl(selectedPath)
      if (request.operation === "media")
        root.setSource(root.urlForPath(path), root.typeForSource(path),
          request.scope, request.screen)
      else
        root.addDirectory(path)
      root.openOverview(request.screen)
      return
    }

    if (exitCode === 1 && String(errorOutput || "").trim() === "") {
      root.openOverview(request.screen)
      return
    }

    if (request.stage === "portal"
        && root.startChooserProcess(request.operation, "gtk", request.screen, request.scope))
      return

    root.error = qsTr("Desktop chooser failed; opening the built-in picker. %1")
      .arg(String(errorOutput || "").trim())
    root.openOverview(request.screen)
    root.fileChooserFallback(request.operation, request.screen, request.scope)
  }

  function setShortcutStatus(message, isError) {
    root.shortcutStatus = message
    root.shortcutStatusIsError = isError
  }

  function restoreConfiguredShortcut() {
    if (root.activeShortcut || !SettingsData.wallpaperShortcut
        || WorkspacesService.backend !== "hyprland")
      return

    const shortcut = root.canonicalShortcut(SettingsData.wallpaperShortcut)
    if (!shortcut) {
      root.setShortcutStatus(
        qsTr("The saved wallpaper shortcut is invalid. Choose and apply a new one."),
        true
      )
      return
    }

    root.bindShortcut(shortcut)
    root.activeShortcut = shortcut
  }

  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  function luaString(value) {
    return JSON.stringify(String(value))
  }

  function dispatchLua(statement) {
    Hyprland.dispatch("function() " + statement + " end")
  }

  function bindShortcut(shortcut) {
    const command = "qs -p " + root.shellQuote(Quickshell.shellDir)
      + " ipc call wallpaper switcher"
    root.dispatchLua("hl.bind("
      + root.luaString(shortcut)
      + ", hl.dsp.exec_cmd(" + root.luaString(command) + ")"
      + ", { description = "
      + root.luaString("MyQuickshell wallpaper switcher") + " })")
  }

  function unbindShortcut(shortcut) {
    root.dispatchLua("hl.unbind(" + root.luaString(shortcut) + ")")
  }

  function activateRequestedShortcut() {
    const previousShortcut = root.activeShortcut
    root.shortcutApplyPending = true
    root.setShortcutStatus(qsTr("Shortcut is available. Applying…"), false)

    root.bindShortcut(root.requestedShortcut)
    if (previousShortcut)
      root.unbindShortcut(previousShortcut)

    if (!SettingsData.setMany({ wallpaperShortcut: root.requestedShortcut })) {
      root.unbindShortcut(root.requestedShortcut)
      if (previousShortcut)
        root.bindShortcut(previousShortcut)
      root.shortcutApplyPending = false
      root.setShortcutStatus(
        qsTr("The shortcut could not be saved; the previous bind was restored."),
        true
      )
      return
    }

    root.activeShortcut = root.requestedShortcut
    root.pendingShortcut = root.requestedShortcut
    root.shortcutApplyPending = false
    root.setShortcutStatus(
      qsTr("Shortcut applied: %1").arg(root.requestedShortcut),
      false
    )
  }

  function beginShortcutCapture() {
    if (root.shortcutCheckPending || root.shortcutApplyPending)
      return
    root.shortcutCaptureActive = true
    root.setShortcutStatus(qsTr("Press a modifier and a letter, number, or F1–F12. Esc cancels."), false)
  }

  function cancelShortcutCapture() {
    root.shortcutCaptureActive = false
    root.setShortcutStatus(qsTr("Shortcut capture canceled."), false)
  }

  function captureShortcut(key, modifiers) {
    if (!root.shortcutCaptureActive)
      return false

    if (key === Qt.Key_Escape) {
      root.cancelShortcutCapture()
      return true
    }

    let keyName = ""
    if (key >= Qt.Key_A && key <= Qt.Key_Z)
      keyName = String.fromCharCode(key)
    else if (key >= Qt.Key_0 && key <= Qt.Key_9)
      keyName = String.fromCharCode(key)
    else if (key >= Qt.Key_F1 && key <= Qt.Key_F12)
      keyName = "F" + (key - Qt.Key_F1 + 1)

    if (!keyName)
      return true

    const parts = []
    if ((modifiers & Qt.MetaModifier) !== 0) parts.push("SUPER")
    if ((modifiers & Qt.ControlModifier) !== 0) parts.push("CTRL")
    if ((modifiers & Qt.AltModifier) !== 0) parts.push("ALT")
    if ((modifiers & Qt.ShiftModifier) !== 0) parts.push("SHIFT")
    if (parts.length === 0) {
      root.setShortcutStatus(qsTr("Include at least one modifier key."), true)
      return true
    }

    parts.push(keyName)
    root.pendingShortcut = parts.join(" + ")
    root.shortcutCaptureActive = false
    root.setShortcutStatus(
      qsTr("Captured %1. Apply it to check for conflicts.").arg(root.pendingShortcut),
      false
    )
    return true
  }

  function canonicalShortcut(value) {
    const parts = String(value || "").trim().toUpperCase().split(/\s*\+\s*/)
    if (parts.length < 2 || parts.length > 5)
      return ""

    const key = parts.pop()
    if (!/^(?:[A-Z]|[0-9]|F(?:[1-9]|1[0-2]))$/.test(key))
      return ""

    const supported = ["SUPER", "CTRL", "ALT", "SHIFT"]
    const modifiers = []
    for (const part of parts) {
      if (supported.indexOf(part) === -1 || modifiers.indexOf(part) !== -1)
        return ""
      modifiers.push(part)
    }
    if (modifiers.length === 0)
      return ""

    const ordered = supported.filter(modifier => modifiers.indexOf(modifier) !== -1)
    ordered.push(key)
    return ordered.join(" + ")
  }

  function inspectBindings(output, shortcut) {
    let bindings
    try {
      bindings = JSON.parse(output)
    } catch (error) {
      return { valid: false, conflict: false }
    }
    if (!Array.isArray(bindings))
      return { valid: false, conflict: false }

    const parts = shortcut.split(" + ")
    const key = parts.pop()
    const masks = { SHIFT: 1, CTRL: 4, ALT: 8, SUPER: 64 }
    let mask = 0
    for (const modifier of parts)
      mask |= masks[modifier]

    for (const binding of bindings) {
      if (!binding || typeof binding.key !== "string"
          || typeof binding.modmask !== "number"
          || !Number.isInteger(binding.modmask)) {
        return { valid: false, conflict: false }
      }
      if (binding.key.toUpperCase() === key && binding.modmask === mask)
        return { valid: true, conflict: true }
    }
    return { valid: true, conflict: false }
  }

  function applyShortcut() {
    if (root.shortcutCaptureActive) {
      root.setShortcutStatus(qsTr("Finish or cancel shortcut capture first."), true)
      return false
    }
    if (root.shortcutCheckPending || root.shortcutApplyPending)
      return false

    const shortcut = root.canonicalShortcut(root.pendingShortcut)
    if (!shortcut) {
      root.setShortcutStatus(qsTr("Choose a supported shortcut with at least one modifier."), true)
      return false
    }
    if (shortcut === SettingsData.wallpaperShortcut
        && shortcut === root.activeShortcut) {
      root.setShortcutStatus(qsTr("That shortcut is already configured."), false)
      return true
    }

    if (WorkspacesService.backend !== "hyprland") {
      root.setShortcutStatus(
        qsTr("Wallpaper shortcuts require a Hyprland session."),
        true
      )
      return false
    }

    root.requestedShortcut = shortcut
    root.shortcutCheckPending = true
    root.setShortcutStatus(qsTr("Checking Hyprland shortcuts…"), false)
    bindCheckProcess.running = true
    return true
  }
}
