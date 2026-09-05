pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The IPC bridge to an optional native backend (Go / Python / Rust / C / ++).
//
// This is the single seam where advanced system integration plugs in. A
// backend process may open a Unix socket at $MYSHELL_SOCKET and speak a simple
// line-delimited JSON protocol. If no server is present, services degrade
// gracefully to Quickshell's built-ins — the shell is fully usable standalone.
//
// Protocol sketch (for future backends):
//   -> {"id":1, "method":"battery.status"}
//   <- {"id":1, "result": {...}}
//   -> {"method":"subscribe", "services":["battery"]}
//   <- {"service":"battery", "data": {...}}
QtObject {
  id: root

  readonly property string socketPath: Quickshell.env("MYSHELL_SOCKET")
  readonly property bool backendAvailable: socketPath !== "" && requestSocket.connected

  property string apiVersion: "0.1.0"

  // Request/response socket. Kept minimal now; expand as backends land.
  property var requestSocket: null

  // A future backend can set backendAvailable and expose requests here.
  function sendRequest(method, params, callback) {
    console.warn("DMSService: no backend connected, ignored request", method)
    if (callback) callback(null)
  }

  function subscribe(services) {
    // No-op until a backend is present.
  }
}
