pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: root

  property var player: null
  readonly property string trackKey: player ? JSON.stringify([
    player.trackTitle || "",
    player.trackArtist || "",
    player.trackAlbum || "",
    player.metadata ? player.metadata["xesam:url"] || "" : ""
  ]) : ""
  property string state: "idle"
  property var lines: []
  property var plainLines: []
  property bool synced: false
  readonly property bool hasLyrics: state === "ready" &&
    (lines.length > 0 || plainLines.some(line => String(line).trim() !== ""))
  property real currentPosition: 0
  property int activeWordIndex: -1
  property string attributionName: ""
  property string attributionUrl: ""
  property int activeIndex: -1
  property int serial: 0
  property int fetchSerial: 0

  onTrackKeyChanged: {
    root.serial++
    lookupDelay.restart()
    root.clearLyrics()
  }

  Process {
    id: lyricsFetcher
    running: false
    command: []
    stdout: StdioCollector {
      onStreamFinished: root.receiveLookup(text, root.fetchSerial)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.state === "loading" && root.fetchSerial === root.serial)
        root.useEmbeddedLyrics("error")
      else if (root.fetchSerial !== root.serial)
        lookupDelay.restart()
    }
  }

  Timer {
    id: lookupDelay
    interval: 300
    repeat: false
    onTriggered: root.lookup()
  }

  Timer {
    interval: 150
    repeat: true
    running: root.synced && root.state === "ready"
    onTriggered: root.updateActiveIndex()
  }

  function setPlayer(value) {
    if (root.player === value)
      return
    root.player = value
  }

  function retry() {
    root.serial++
    root.clearLyrics()
    lookupDelay.restart()
  }

  function clearLyrics() {
    root.state = "idle"
    root.lines = []
    root.plainLines = []
    root.synced = false
    root.attributionName = ""
    root.attributionUrl = ""
    root.activeIndex = -1
    root.activeWordIndex = -1
  }

  function embeddedLyrics() {
    const metadata = root.player ? root.player.metadata : null
    if (!metadata)
      return ""
    return String(metadata["xesam:asText"] || metadata["xesam:lyrics"] || "")
  }

  function lookup() {
    if (!root.player || !root.player.trackTitle) {
      root.state = "none"
      return
    }
    if (lyricsFetcher.running) {
      lookupDelay.restart()
      return
    }
    root.state = "loading"
    root.fetchSerial = root.serial
    const title = root.searchTrackTitle(root.player.trackTitle)
    const artist = root.searchArtistName(root.player.trackArtist)
    const args = [
      "curl", "-fsS", "--max-time", "12", "--get",
      "--data-urlencode", "track_name=" + title,
      "https://lrclib.net/api/search"
    ]
    if (artist !== "")
      args.splice(7, 0, "--data-urlencode", "artist_name=" + artist)
    lyricsFetcher.command = args
    lyricsFetcher.running = true
  }

  function searchTrackTitle(value) {
    return String(value || "")
      .replace(/\([^)]*\)|\[[^\]]*\]/g, " ")
      .replace(/\b(official(\s+(music|lyric))?\s+video|lyrics?\s+video|visualizer)\b/ig, " ")
      .replace(/\s+/g, " ")
      .trim()
  }

  function searchArtistName(value) {
    return String(value || "").split(/\s+(?:and|&|feat\.?|ft\.?|with)\s+|[,;]/i)[0].trim()
  }

  function receiveLookup(text, token) {
    if (token !== root.serial)
      return
    let results
    try {
      results = JSON.parse(text.trim())
    } catch (error) {
      console.warn("LyricsService: invalid LRCLIB response:", error)
      root.useEmbeddedLyrics("error")
      return
    }
    if (!Array.isArray(results) || results.length === 0) {
      root.useEmbeddedLyrics("none")
      return
    }
    const targetTitle = root.normalizeTrackText(root.searchTrackTitle(root.player.trackTitle))
    const targetArtist = root.normalizeArtistText(root.player.trackArtist || "")
    const duration = Number(root.player.length) || 0
    results.sort((a, b) => root.matchScore(b, targetTitle, targetArtist, duration) -
      root.matchScore(a, targetTitle, targetArtist, duration))
    const match = results[0]
    if (!match || (!match.plainLyrics && !match.syncedLyrics && !match.instrumental)) {
      root.useEmbeddedLyrics("none")
      return
    }
    root.applyResult({
      found: true,
      instrumental: match.instrumental === true,
      plain: match.plainLyrics || "",
      synced: root.parseLrc(match.syncedLyrics || ""),
      attribution: { name: "LRCLIB", url: "https://lrclib.net" }
    })
  }

  function normalizeTrackText(value) {
    return String(value || "").toLowerCase().replace(/\([^)]*\)|\[[^\]]*\]/g, "")
      .replace(/[^a-z0-9]+/g, " ").trim()
  }

  function normalizeArtistText(value) {
    return root.normalizeTrackText(value).replace(/\b(and|with|feat|ft|featuring)\b/g, " ")
      .replace(/\s+/g, " ").trim()
  }

  function matchScore(result, title, artist, duration) {
    const candidateTitle = root.normalizeTrackText(result.trackName)
    const candidateArtist = root.normalizeArtistText(result.artistName)
    const titleScore = candidateTitle === title ? 100 : candidateTitle.includes(title) || title.includes(candidateTitle) ? 50 : 0
    const artistScore = !artist || candidateArtist === artist ? 30 : candidateArtist.includes(artist) || artist.includes(candidateArtist) ? 15 : 0
    const lengthDifference = duration > 0 && Number(result.duration) > 0
      ? Math.abs(duration - Number(result.duration)) : 0
    return titleScore + artistScore - Math.min(30, lengthDifference / 2)
  }

  function parseLrc(text) {
    const lines = []
    const timestamp = /^\[(\d+):(\d+(?:\.\d+)?)\](.*)$/
    for (const rawLine of String(text).split(/\r?\n/)) {
      const match = timestamp.exec(rawLine)
      if (!match)
        continue
      const time = Number(match[1]) * 60 + Number(match[2])
      const line = match[3].trim()
      if (line !== "")
        lines.push({ t: time, x: line, e: 0, w: [] })
    }
    return lines.sort((a, b) => a.t - b.t)
  }

  function applyResult(result) {
    if (result.instrumental === true) {
      root.clearLyrics()
      root.state = "instrumental"
      return
    }
    const sourceLines = Array.isArray(result.synced) ? result.synced : []
    root.lines = sourceLines.filter(line => Number.isFinite(line.t) && line.t >= 0 && typeof line.x === "string")
      .map(line => {
        const words = Array.isArray(line.w) &&
          line.w.every(word => Number.isFinite(word.t) && word.t >= line.t && typeof word.x === "string") &&
          line.w.map(word => word.x).join("") === line.x
          ? line.w.map(word => ({ t: word.t, x: word.x })) : []
        return { t: line.t, x: line.x, e: Number.isFinite(line.e) ? line.e : 0, w: words }
      })
      .sort((a, b) => a.t - b.t)
    root.synced = root.lines.length > 0
    root.plainLines = typeof result.plain === "string" ? result.plain.trim().split("\n") : []
    if (!root.synced && !root.plainLines.some(line => line.trim() !== "")) {
      root.useEmbeddedLyrics("none")
      return
    }
    const attribution = result.attribution || ({})
    root.attributionName = attribution.name || ""
    root.attributionUrl = attribution.url || ""
    root.state = "ready"
    root.updateActiveIndex()
  }

  function useEmbeddedLyrics(fallbackState) {
    const text = root.embeddedLyrics().trim()
    if (text !== "") {
      root.lines = []
      root.plainLines = text.split("\n")
      root.synced = false
      root.state = "ready"
    } else {
      root.clearLyrics()
      root.state = fallbackState
    }
  }

  function updateActiveIndex() {
    const position = root.player ? Number(root.player.position) || 0 : 0
    root.currentPosition = position
    let low = 0
    let high = root.lines.length - 1
    let found = -1
    while (low <= high) {
      const mid = (low + high) >> 1
      if (root.lines[mid].t <= position) {
        found = mid
        low = mid + 1
      } else {
        high = mid - 1
      }
    }
    root.activeIndex = found
    root.activeWordIndex = -1
    const words = found >= 0 ? root.lines[found].w : []
    low = 0
    high = words.length - 1
    while (low <= high) {
      const mid = (low + high) >> 1
      if (words[mid].t <= position) {
        root.activeWordIndex = mid
        low = mid + 1
      } else {
        high = mid - 1
      }
    }
  }

}
