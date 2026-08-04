import Foundation
import Observation

@MainActor
@Observable
final class QuickAddModel {
  var prompt = ""
  private(set) var workspaces: [Workspace] = []
  private(set) var catalog: WorkspaceCatalog?
  private(set) var selectedWorkspaceID: String?
  private(set) var selectedProjectID: String?
  private(set) var selectedCreatedBy: CreatedBy?
  private(set) var loadError: String?

  var dismiss: () -> Void = {}

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

  var canSubmit: Bool {
    !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && selectedWorkspaceID != nil && selectedCreatedBy != nil
  }

  func panelWillOpen() {
    refresh()
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

  func selectCreatedBy(_ createdBy: CreatedBy) {
    selectedCreatedBy = createdBy
    guard let workspaceID = selectedWorkspaceID else { return }
    settings.setLastCreatedBy(createdBy, workspaceID: workspaceID)
  }

  func submit() {
    guard canSubmit, let workspaceID = selectedWorkspaceID, let createdBy = selectedCreatedBy
    else { return }
    let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    let projectID = selectedProjectID
    self.prompt = ""
    dismiss()
    Task {
      do {
        try await submitter.submitQuickCreate(
          workspaceID: workspaceID, prompt: prompt, createdBy: createdBy, projectID: projectID)
        Notifier.notify(title: "Sent to \(createdBy.name)", body: prompt)
      } catch {
        self.prompt = prompt
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
      selectedCreatedBy = nil
      return
    }
    catalog = settings.cachedCatalog(workspaceID: id)
    selectedProjectID = settings.lastProjectID(workspaceID: id)
    selectedCreatedBy = settings.lastCreatedBy(workspaceID: id)
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
    let options = catalog.createdByOptions
    if let current = selectedCreatedBy {
      selectedCreatedBy = options.first { $0.kind == current.kind && $0.id == current.id }
    }
    if selectedCreatedBy == nil {
      selectedCreatedBy = options.first
    }
  }
}
