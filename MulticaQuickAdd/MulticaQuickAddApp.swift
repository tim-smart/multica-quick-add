import AppKit
import SwiftUI

@main
struct MulticaQuickAddApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    MenuBarExtra {
      Button("Open Quick Add") {
        appDelegate.showPanel()
      }
      SettingsLink {
        Text("Settings…")
      }
      Divider()
      Button("Quit \(AppMetadata.name)") {
        NSApplication.shared.terminate(nil)
      }
    } label: {
      Image(nsImage: .multicaMenuBarIcon)
    }

    Settings {
      SettingsView()
    }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let model = QuickAddModel()
  private let hotKeyManager = HotKeyManager()
  private var panelController: QuickAddPanelController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    panelController = QuickAddPanelController(model: model)
    registerHotKey()
    Notifier.requestAuthorization()
    NotificationCenter.default.addObserver(
      self, selector: #selector(hotKeyChanged), name: .hotKeyChanged, object: nil)
  }

  func showPanel() {
    panelController?.show()
  }

  @objc private func hotKeyChanged() {
    registerHotKey()
  }

  private func registerHotKey() {
    hotKeyManager.register(AppSettings.shared.hotKey) { [weak self] in
      self?.panelController?.toggle()
    }
  }
}
