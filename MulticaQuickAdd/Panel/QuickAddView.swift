import AppKit
import SwiftUI

struct QuickAddView: View {
  @Bindable var model: QuickAddModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      promptEditor
      if let loadError = model.loadError {
        Label(loadError, systemImage: "exclamationmark.triangle")
          .font(.caption)
          .foregroundStyle(.orange)
          .lineLimit(2)
      }
      HStack(spacing: 12) {
        workspacePicker
        projectPicker
        createdByPicker
        Spacer()
        submitButton
      }
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 16)
    .frame(width: 640)
    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
  }

  private var promptEditor: some View {
    GrowingTextView(
      text: $model.prompt,
      onSubmit: { model.submit() },
      onEscape: { model.dismiss() }
    )
    .overlay(alignment: .topLeading) {
      if model.prompt.isEmpty {
        Text("Describe an issue for Multica")
          .font(.system(size: 22))
          .foregroundStyle(.secondary)
          .padding(.top, 4)
          .allowsHitTesting(false)
      }
    }
  }

  private var workspacePicker: some View {
    Picker(
      "Workspace",
      selection: Binding(
        get: { model.selectedWorkspaceID },
        set: { model.selectWorkspace($0) })
    ) {
      ForEach(model.workspaces) { workspace in
        Text(workspace.name).tag(Optional(workspace.id))
      }
    }
    .labelsHidden()
    .pickerStyle(.menu)
    .buttonStyle(.borderless)
    .controlSize(.small)
    .fixedSize()
  }

  @ViewBuilder
  private var projectPicker: some View {
    if let catalog = model.catalog, !catalog.projects.isEmpty {
      Picker(
        "Project",
        selection: Binding(
          get: { model.selectedProjectID },
          set: { model.selectProject($0) })
      ) {
        Text("No project").tag(String?.none)
        ForEach(catalog.projects) { project in
          Text(projectLabel(project)).tag(Optional(project.id))
        }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .buttonStyle(.borderless)
      .controlSize(.small)
      .fixedSize()
    }
  }

  @ViewBuilder
  private var createdByPicker: some View {
    if let catalog = model.catalog {
      if catalog.createdByOptions.isEmpty {
        Text("No agents")
          .font(.callout)
          .foregroundStyle(.secondary)
      } else {
        Picker(
          "Created by",
          selection: Binding(
            get: { model.selectedCreatedBy },
            set: { newValue in
              if let newValue {
                model.selectCreatedBy(newValue)
              }
            })
        ) {
          if !catalog.agents.isEmpty {
            Section("Agents") {
              ForEach(catalog.agents) { agent in
                Text(agent.name)
                  .tag(Optional(CreatedBy(kind: .agent, id: agent.id, name: agent.name)))
              }
            }
          }
          if !catalog.squads.isEmpty {
            Section("Squads") {
              ForEach(catalog.squads) { squad in
                Text(squad.name)
                  .tag(Optional(CreatedBy(kind: .squad, id: squad.id, name: squad.name)))
              }
            }
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .buttonStyle(.borderless)
        .controlSize(.small)
        .fixedSize()
      }
    } else if model.selectedWorkspaceID != nil && model.loadError == nil {
      Text("Loading…")
        .font(.callout)
        .foregroundStyle(.secondary)
    }
  }

  private var submitButton: some View {
    Button(action: { model.submit() }) {
      Image(systemName: "arrow.up")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 28, height: 28)
        .background(
          Circle().fill(model.canSubmit ? Color.accentColor : Color.gray.opacity(0.4))
        )
    }
    .buttonStyle(.plain)
    .disabled(!model.canSubmit)
  }

  private func projectLabel(_ project: Project) -> String {
    if let icon = project.icon, !icon.isEmpty {
      return "\(icon) \(project.title)"
    }
    return project.title
  }
}

struct GrowingTextView: NSViewRepresentable {
  @Binding var text: String
  var onSubmit: () -> Void
  var onEscape: () -> Void

  static let font = NSFont.systemFont(ofSize: 22)
  private static let minHeight: CGFloat = 40
  private static let maxHeight: CGFloat = 240

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSTextView.scrollableTextView()
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    if let textView = scrollView.documentView as? NSTextView {
      textView.delegate = context.coordinator
      textView.font = Self.font
      textView.isRichText = false
      textView.allowsUndo = true
      textView.drawsBackground = false
      textView.textContainerInset = NSSize(width: 0, height: 4)
      textView.textContainer?.lineFragmentPadding = 0
      context.coordinator.textView = textView
    }
    NotificationCenter.default.addObserver(
      context.coordinator,
      selector: #selector(Coordinator.windowDidBecomeKey(_:)),
      name: NSWindow.didBecomeKeyNotification,
      object: nil)
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.parent = self
    guard let textView = scrollView.documentView as? NSTextView else { return }
    if textView.string != text {
      textView.string = text
    }
  }

  func sizeThatFits(
    _ proposal: ProposedViewSize, nsView: NSScrollView, context: Context
  ) -> CGSize? {
    let width: CGFloat =
      if let proposed = proposal.width, proposed.isFinite, proposed > 0 {
        proposed
      } else {
        592
      }
    return CGSize(width: width, height: Self.measuredHeight(text: text, width: width - 2))
  }

  private static func measuredHeight(text: String, width: CGFloat) -> CGFloat {
    var measured = text.isEmpty ? " " : text
    if measured.hasSuffix("\n") {
      measured += " "
    }
    let bounds = (measured as NSString).boundingRect(
      with: CGSize(width: width, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      attributes: [.font: font])
    return min(max(ceil(bounds.height) + 12, minHeight), maxHeight)
  }

  @MainActor
  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: GrowingTextView
    weak var textView: NSTextView?

    init(parent: GrowingTextView) {
      self.parent = parent
    }

    func textDidChange(_ notification: Notification) {
      guard let textView else { return }
      parent.text = textView.string
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
      if commandSelector == #selector(NSResponder.insertNewline(_:)) {
        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
          return false
        }
        parent.onSubmit()
        return true
      }
      // NSTextView maps Esc to complete(_:), so handle both.
      if commandSelector == #selector(NSResponder.cancelOperation(_:))
        || commandSelector == Selector(("complete:"))
      {
        parent.onEscape()
        return true
      }
      return false
    }

    @objc func windowDidBecomeKey(_ notification: Notification) {
      guard let textView, let window = textView.window,
        (notification.object as? NSWindow) === window
      else { return }
      window.makeFirstResponder(textView)
      textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
    }
  }
}
