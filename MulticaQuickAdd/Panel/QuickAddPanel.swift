import AppKit
import SwiftUI

final class QuickAddPanel: NSPanel {
  init(contentView: NSView) {
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 560, height: 140),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false)
    self.contentView = contentView
    isFloatingPanel = true
    level = .floating
    hidesOnDeactivate = false
    isMovableByWindowBackground = true
    backgroundColor = .clear
    isOpaque = false
    hasShadow = true
    isReleasedWhenClosed = false
    animationBehavior = .utilityWindow
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
  }

  override var canBecomeKey: Bool { true }

  override func cancelOperation(_ sender: Any?) {
    orderOut(nil)
  }
}

@MainActor
final class QuickAddPanelController: NSObject, NSWindowDelegate {
  private let panel: QuickAddPanel
  private let model: QuickAddModel
  private var topEdge: CGFloat?

  init(model: QuickAddModel) {
    self.model = model
    let hostingView = NSHostingView(rootView: QuickAddView(model: model))
    hostingView.sizingOptions = [.preferredContentSize]
    panel = QuickAddPanel(contentView: hostingView)
    super.init()
    panel.delegate = self
    model.dismiss = { [weak self] in self?.hide() }
  }

  func toggle() {
    if panel.isVisible {
      hide()
    } else {
      show()
    }
  }

  func show() {
    model.panelWillOpen()
    position()
    panel.makeKeyAndOrderFront(nil)
  }

  func hide() {
    panel.orderOut(nil)
  }

  private func position() {
    guard let screen = screenWithMouse() ?? NSScreen.main else { return }
    panel.layoutIfNeeded()
    let visible = screen.visibleFrame
    let x = visible.midX - panel.frame.width / 2
    let top = visible.maxY - visible.height * 0.25
    topEdge = top
    panel.setFrameTopLeftPoint(NSPoint(x: x, y: top))
  }

  private func screenWithMouse() -> NSScreen? {
    let mouseLocation = NSEvent.mouseLocation
    return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
  }

  func windowDidResize(_ notification: Notification) {
    // Keep the top edge fixed while the text area grows.
    guard let topEdge, panel.isVisible, panel.frame.maxY != topEdge else { return }
    panel.setFrameTopLeftPoint(NSPoint(x: panel.frame.minX, y: topEdge))
  }

  func windowDidResignKey(_ notification: Notification) {
    hide()
  }
}
