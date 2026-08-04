import AppKit
import Carbon.HIToolbox

struct KeyCombo: Codable, Equatable, Sendable {
  var keyCode: UInt32
  var carbonModifiers: UInt32

  static let `default` = KeyCombo(
    keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(cmdKey | shiftKey))

  init(keyCode: UInt32, carbonModifiers: UInt32) {
    self.keyCode = keyCode
    self.carbonModifiers = carbonModifiers
  }

  init?(event: NSEvent) {
    let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
    guard !flags.isEmpty else { return nil }
    self.init(keyCode: UInt32(event.keyCode), carbonModifiers: flags.carbonModifiers)
  }

  var displayString: String {
    var symbols = ""
    if carbonModifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
    if carbonModifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
    if carbonModifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
    if carbonModifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
    return symbols + keyName
  }

  private var keyName: String {
    switch Int(keyCode) {
    case kVK_Space: return "Space"
    case kVK_Return: return "Return"
    case kVK_Tab: return "Tab"
    case kVK_Delete: return "Delete"
    case kVK_ForwardDelete: return "⌦"
    case kVK_Escape: return "Esc"
    case kVK_LeftArrow: return "←"
    case kVK_RightArrow: return "→"
    case kVK_UpArrow: return "↑"
    case kVK_DownArrow: return "↓"
    default: return Self.translate(keyCode: keyCode) ?? "Key \(keyCode)"
    }
  }

  private static func translate(keyCode: UInt32) -> String? {
    guard
      let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
      let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
    else { return nil }
    let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
    return data.withUnsafeBytes { buffer -> String? in
      guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
        return nil
      }
      var deadKeyState: UInt32 = 0
      var characters = [UniChar](repeating: 0, count: 4)
      var length = 0
      let status = UCKeyTranslate(
        layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
        UInt32(kUCKeyTranslateNoDeadKeysMask), &deadKeyState, characters.count, &length,
        &characters)
      guard status == noErr, length > 0 else { return nil }
      return String(utf16CodeUnits: characters, count: length).uppercased()
    }
  }
}

extension NSEvent.ModifierFlags {
  var carbonModifiers: UInt32 {
    var result: UInt32 = 0
    if contains(.control) { result |= UInt32(controlKey) }
    if contains(.option) { result |= UInt32(optionKey) }
    if contains(.shift) { result |= UInt32(shiftKey) }
    if contains(.command) { result |= UInt32(cmdKey) }
    return result
  }
}

@MainActor
final class HotKeyManager {
  private var hotKeyRef: EventHotKeyRef?
  private var eventHandlerRef: EventHandlerRef?
  private var handler: (() -> Void)?

  func register(_ combo: KeyCombo, handler: @escaping () -> Void) {
    unregister()
    self.handler = handler
    installEventHandlerIfNeeded()
    let hotKeyID = EventHotKeyID(signature: 0x4D51_4144, id: 1)
    var ref: EventHotKeyRef?
    RegisterEventHotKey(
      combo.keyCode, combo.carbonModifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref)
    hotKeyRef = ref
  }

  func unregister() {
    if let hotKeyRef {
      UnregisterEventHotKey(hotKeyRef)
    }
    hotKeyRef = nil
  }

  private func installEventHandlerIfNeeded() {
    guard eventHandlerRef == nil else { return }
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetEventDispatcherTarget(),
      { _, _, userData in
        guard let userData else { return noErr }
        let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
        MainActor.assumeIsolated {
          manager.handler?()
        }
        return noErr
      }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandlerRef)
  }
}
