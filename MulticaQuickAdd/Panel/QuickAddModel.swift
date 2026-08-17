import Foundation
import Observation

@MainActor
@Observable
final class QuickAddModel {
  var prompt = "" {
    didSet {
      guard prompt != oldValue else { return }
      skillHighlightIndex = 0
      if skillQuery != dismissedSkillQuery {
        dismissedSkillQuery = nil
      }
    }
  }
  var skillHighlightIndex = 0
  private var dismissedSkillQuery: String?
  private(set) var attachments: [PendingAttachment] = []
  private(set) var workspaces: [Workspace] = []
  private(set) var catalog: WorkspaceCatalog?
  private(set) var selectedWorkspaceID: String?
  private(set) var selectedProjectID: String?
  private(set) var selectedAssignee: Assignee?
  private(set) var loadError: String?

  // True while an NSOpenPanel is up, so the panel controller skips auto-hide
  // when the quick add panel resigns key.
  var isFilePickerOpen = false

  var dismiss: () -> Void = {}
  var refocus: () -> Void = {}

  private let dataSource: any MulticaDataSource
  private let submitter: any IssueSubmitter
  private let settings: AppSettings
  private var refreshTask: Task<Void, Never>?

  init(
    dataSource: any MulticaDataSource = MulticaCLI(),
    submitter: any IssueSubmitter = MulticaAPIClient(),
    settings: AppSettings = .shared
  ) {
    self.dataSource = dataSource
    self.submitter = submitter
    self.settings = settings
    workspaces = settings.cachedWorkspaces ?? []
    applyWorkspace(settings.lastWorkspaceID ?? workspaces.first?.id)
  }

  var selectedWorkspace: Workspace? {
    workspaces.first { $0.id == selectedWorkspaceID }
  }

  var selectedProject: Project? {
    catalog?.projects.first { $0.id == selectedProjectID }
  }

  // The picker is open while the prompt is a single "/partial" token; typing
  // whitespace or accepting a suggestion closes it.
  private var skillQuery: String? {
    guard prompt.hasPrefix("/"), !prompt.contains(where: \.isWhitespace) else { return nil }
    return String(prompt.dropFirst())
  }

  private var availableSkills: [Skill] {
    guard let catalog, let assignee = selectedAssignee else { return [] }
    return catalog.skills(for: assignee)
  }

  var skillSuggestions: [Skill] {
    guard let query = skillQuery, query != dismissedSkillQuery else { return [] }
    let skills = availableSkills
    let matches =
      query.isEmpty ? skills : skills.filter { $0.name.localizedCaseInsensitiveContains(query) }
    return Array(matches.prefix(8))
  }

  @discardableResult
  func moveSkillHighlight(by delta: Int) -> Bool {
    let count = skillSuggestions.count
    guard count > 0 else { return false }
    skillHighlightIndex = (skillHighlightIndex + delta + count) % count
    return true
  }

  @discardableResult
  func acceptSkillSuggestion(_ skill: Skill? = nil) -> Bool {
    let suggestions = skillSuggestions
    guard !suggestions.isEmpty else { return false }
    let chosen = skill ?? suggestions[min(skillHighlightIndex, suggestions.count - 1)]
    prompt = "/\(chosen.name) "
    return true
  }

  func handleEscape() {
    if skillSuggestions.isEmpty {
      dismiss()
    } else {
      dismissedSkillQuery = skillQuery
    }
  }

  var canSubmit: Bool {
    !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && selectedWorkspaceID != nil && selectedAssignee != nil
  }

  func panelWillOpen() {
    refresh()
  }

  func addAttachments(_ newAttachments: [PendingAttachment]) {
    attachments.append(contentsOf: newAttachments)
  }

  func removeAttachment(id: UUID) {
    attachments.removeAll { $0.id == id }
  }

  func refresh() {
    refreshTask?.cancel()
    refreshTask = Task { await performRefresh() }
  }

  func selectWorkspace(_ id: String?) {
    guard id != selectedWorkspaceID else { return }
    applyWorkspace(id)
    refresh()
  }

  func selectProject(_ id: String?) {
    selectedProjectID = id
    guard let workspaceID = selectedWorkspaceID else { return }
    settings.setLastProjectID(id, workspaceID: workspaceID)
  }

  func selectAssignee(_ assignee: Assignee) {
    selectedAssignee = assignee
    guard let workspaceID = selectedWorkspaceID else { return }
    settings.setLastAssignee(assignee, workspaceID: workspaceID)
  }

  func submit() {
    if acceptSkillSuggestion() { return }
    guard canSubmit, let workspaceID = selectedWorkspaceID, let assignee = selectedAssignee
    else { return }
    let prompt = Skill.expandingReference(
      in: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
      skills: availableSkills)
    let attachments = attachments
    let projectID = selectedProjectID
    self.prompt = ""
    self.attachments = []
    dismiss()
    Task {
      do {
        try await submitter.submit(
          workspaceID: workspaceID, prompt: prompt, assignee: assignee, projectID: projectID,
          attachments: attachments)
        Notifier.notify(title: "Sent to \(assignee.name)", body: prompt)
      } catch {
        self.prompt = prompt
        self.attachments = attachments
        Notifier.notify(title: "Quick add failed", body: error.localizedDescription)
      }
    }
  }

  private func applyWorkspace(_ id: String?) {
    selectedWorkspaceID = id
    settings.lastWorkspaceID = id
    guard let id else {
      catalog = nil
      selectedProjectID = nil
      selectedAssignee = nil
      return
    }
    catalog = settings.cachedCatalog(workspaceID: id)
    selectedProjectID = settings.lastProjectID(workspaceID: id)
    selectedAssignee = settings.lastAssignee(workspaceID: id)
    reconcileSelections()
  }

  private func performRefresh() async {
    do {
      let workspaces = try await dataSource.workspaces()
      self.workspaces = workspaces
      settings.cachedWorkspaces = workspaces
      if selectedWorkspaceID == nil || !workspaces.contains(where: { $0.id == selectedWorkspaceID })
      {
        applyWorkspace(workspaces.first?.id)
      }
      guard let workspaceID = selectedWorkspaceID else {
        loadError = "No workspaces found."
        return
      }
      let catalog = try await dataSource.catalog(workspaceID: workspaceID)
      guard workspaceID == selectedWorkspaceID else { return }
      self.catalog = catalog
      settings.setCachedCatalog(catalog, workspaceID: workspaceID)
      reconcileSelections()
      loadError = nil
    } catch is CancellationError {
    } catch {
      loadError = error.localizedDescription
    }
  }

  private func reconcileSelections() {
    guard let catalog else { return }
    if let projectID = selectedProjectID,
      !catalog.projects.contains(where: { $0.id == projectID })
    {
      selectedProjectID = nil
    }
    let options = catalog.assigneeOptions
    if let current = selectedAssignee {
      selectedAssignee = options.first { $0.kind == current.kind && $0.id == current.id }
    }
    if selectedAssignee == nil {
      selectedAssignee = options.first
    }
  }
}
