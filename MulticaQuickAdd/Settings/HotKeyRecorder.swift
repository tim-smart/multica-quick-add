import AppKit
import Carbon.HIToolbox
import SwiftUI

struct HotKeyRecorder: View {
  @Binding var combo: KeyCombo
  @State private var isRecording = false
  @State private var monitor: Any?

  var body: some View {
    Button {
      if isRecording {
        stopRecording()
      } else {
        startRecording()
      }
    } label: {
      Text(isRecording ? "Press shortcut…" : combo.displayString)
        .frame(minWidth: 110)
    }
    .onDisappear {
      stopRecording()
    }
  }

  private func startRecording() {
    isRecording = true
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      let keyCode = event.keyCode
      let newCombo = KeyCombo(event: event)
      MainActor.assumeIsolated {
        handle(keyCode: keyCode, newCombo: newCombo)
      }
      return nil
    }
  }

  private func handle(keyCode: UInt16, newCombo: KeyCombo?) {
    if keyCode == UInt16(kVK_Escape) {
      stopRecording()
      return
    }
    if let newCombo {
      combo = newCombo
      stopRecording()
    }
  }

  private func stopRecording() {
    isRecording = false
    if let monitor {
      NSEvent.removeMonitor(monitor)
    }
    monitor = nil
  }
}
