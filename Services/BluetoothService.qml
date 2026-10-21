pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import qs.Common

// Bluetooth pairing orchestration.
//
// Runs an interactive `bluetoothctl` session that registers a BlueZ agent so
// pairing requests (numeric confirmation, PIN entry, authorization) surface in
// the UI instead of stalling or silently failing. A pairing session pauses
// adapter discovery to avoid HCI churn, pairs, then trusts and connects.
Singleton {
  id: root

  // "idle" | "pairing" | "confirm" | "pin" | "failed"
  property string requestState: "idle"
  property string requestAddress: ""
  property string requestName: ""
  // Passkey shown for numeric confirmation (may be empty when the CLI buffered
  // it without a flush; the UI then asks the user to verify on the device).
  property string requestPasskey: ""
  property string requestMessage: ""
  readonly property bool busy: requestState !== "idle" && requestState !== "failed"

  readonly property var adapter: Bluetooth.defaultAdapter

  Process {
    id: btctl
    command: ["bluetoothctl"]
    environment: ({ "LC_ALL": "C" })

    onStarted: {
      btctl.write("agent on\n")
      if (controller.address)
        btctl.write("pair " + controller.address + "\n")
    }

    stdout: SplitParser {
      onRead: data => root._handleLine(String(data))
    }

    onExited: {
      // A crashed/terminated CLI mid-session should surface as a failure
      // instead of waiting out the 90 s timeout.
      if (root.requestState === "pairing" || root.requestState === "confirm"
          || root.requestState === "pin")
        root.finish(false, "Pairing failed unexpectedly")
    }
  }

  Timer {
    id: pairTimeout
    interval: 90000
    running: root.busy
    onTriggered: root.cancelPairing()
  }

  QtObject {
    id: controller

    property string address: ""

    function start(address) {
      controller.address = address
      root.requestState = "pairing"
      root.requestAddress = address
      root.requestPasskey = ""
      root.requestMessage = "Pairing…"
      // Stop discovery while pairing; restartDiscovery() resumes afterwards.
      if (root.adapter)
        root.adapter.discovering = false
      btctl.running = false
      Qt.callLater(function() {
        btctl.running = true
      })
    }

    function shutdown() {
      btctl.running = false
      controller.address = ""
    }
  }

  function pairDevice(device) {
    if (!device || root.busy)
      return
    const address = device.address || ""
    if (!address || !root.adapter)
      return
    root.requestName = device.name || device.deviceName || ""
    controller.start(address)
  }

  // Resumes adapter discovery after a pairing session ends.
  function restartDiscovery() {
    if (requestState === "idle" && root.adapter)
      root.adapter.discovering = false
  }

  // accept: user accepted the device-side passkey/authorization (or confirmed
  // the PIN they typed in).
  function confirmRequest(accept) {
    if (requestState !== "confirm" && requestState !== "pin")
      return
    if (accept) {
      if (requestState === "pin") {
        const digits = String(requestPasskey || "").replace(/\D/g, "")
        if (digits.length < 3 || digits.length > 8) {
          requestMessage = "Enter a PIN of 3–8 digits"
          return
        }
        btctl.write(digits + "\n")
      } else {
        btctl.write("yes\n")
      }
      requestState = "pairing"
      requestMessage = "Pairing…"
    } else {
      btctl.write("no\n")
      finish(false, "Pairing cancelled")
    }
  }

  // Text typed by the user for PIN-entry pairing before confirming.
  function submitPinText(pin) {
    if (requestState !== "pin")
      return false
    const digits = String(pin || "").replace(/\D/g, "")
    if (digits.length < 3 || digits.length > 8)
      return false
    requestPasskey = digits
    return true
  }

  function cancelPairing() {
    if (!busy)
      return
    btctl.write("no\n")
    btctl.write("cancel-pairing\n")
    finish(false, "Pairing cancelled")
  }

  function dismiss() {
    if (busy)
      return
    requestState = "idle"
    requestMessage = ""
  }

  function forgetDevice(device) {
    if (device)
      device.forget()
  }

  function finish(ok, message) {
    pairTimeout.stop()
    requestState = ok ? "idle" : "failed"
    requestMessage = message || ""
    controller.shutdown()
  }

  function _handleLine(line) {
    const text = String(line || "").trim()
    if (!text)
      return

    // Anything while no session is running is background chatter.
    if (!controller.address)
      return

    if (/Agent registered|Agent unregistered/i.test(text))
      return

    if (/Request confirmation|Confirm passkey/i.test(text))
      return _startConfirm(text)

    if (/Request PIN code|Enter PIN/i.test(text)) {
      root.requestState = "pin"
      root.requestPasskey = ""
      root.requestMessage = "Enter the PIN shown on the device"
      pairTimeout.restart()
      return
    }

    if (/Request authorization|Authorize/i.test(text)) {
      root.requestState = "confirm"
      root.requestMessage = "Device requests permission to pair"
      pairTimeout.restart()
      return
    }

    // While waiting for a user action, ignore passive updates.
    if (requestState !== "pairing")
      return

    if (text.includes("Pairing successful")) {
      const addr = controller.address
      if (addr) {
        btctl.write("trust " + addr + "\n")
        btctl.write("connect " + addr + "\n")
      }
      requestMessage = "Paired. Connecting…"
      pairTimeout.restart()
      return
    }

    if (/Connect(ed|ion successful)/i.test(text) && !/Failed|refused/i.test(text)) {
      finish(true, "")
      return
    }

    if (/Failed to (pair|connect)|Operation failed|Authentication (failed|rejected)|Connection refused/i.test(text)) {
      const cleaned = text.replace(/^\[?.*?\]\s*/, "").trim()
      finish(false, cleaned || "Pairing failed")
      return
    }
  }

  function _startConfirm(text) {
    // bluetoothctl prints "Confirm passkey [yes/no]: <digits>"; capture the
    // passkey when it is already flushed, otherwise ask the user to check the
    // device screen.
    const match = String(text).match(/(\d{3,10})\s*$/)
    root.requestState = "confirm"
    root.requestPasskey = match ? match[1] : ""
    root.requestMessage = root.requestPasskey
      ? "Confirm passkey " + root.requestPasskey
      : "Confirm the pair code on the device screen"
    pairTimeout.restart()
  }
}
