import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
  @State private var hotKey = AppSettings.shared.hotKey
  @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

  var body: some View {
    Form {
      LabeledContent("Quick add hotkey") {
        HStack {
          HotKeyRecorder(combo: $hotKey)
          Button("Reset") {
            hotKey = .default
          }
          .disabled(hotKey == .default)
        }
      }
      Toggle("Launch at login", isOn: $launchAtLogin)
    }
    .formStyle(.grouped)
    .scrollDisabled(true)
    .scrollIndicators(.hidden)
    .frame(width: 380)
    .fixedSize()
    .onChange(of: hotKey) { _, newValue in
      AppSettings.shared.hotKey = newValue
      NotificationCenter.default.post(name: .hotKeyChanged, object: nil)
    }
    .onChange(of: launchAtLogin) { _, enabled in
      do {
        if enabled {
          try SMAppService.mainApp.register()
        } else {
          try SMAppService.mainApp.unregister()
        }
      } catch {
        launchAtLogin = SMAppService.mainApp.status == .enabled
      }
    }
    .onAppear {
      NSApp.activate(ignoringOtherApps: true)
    }
  }
}
