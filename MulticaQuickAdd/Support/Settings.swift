import Foundation

extension Notification.Name {
  static let hotKeyChanged = Notification.Name("MulticaQuickAdd.hotKeyChanged")
}

@MainActor
final class AppSettings {
  static let shared = AppSettings()

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  var hotKey: KeyCombo {
    get { read(KeyCombo.self, key: "hotKey") ?? .default }
    set { write(newValue, key: "hotKey") }
  }

  var lastWorkspaceID: String? {
    get { defaults.string(forKey: "lastWorkspaceID") }
    set { defaults.set(newValue, forKey: "lastWorkspaceID") }
  }

  func lastProjectID(workspaceID: String) -> String? {
    defaults.string(forKey: "lastProjectID.\(workspaceID)")
  }

  func setLastProjectID(_ id: String?, workspaceID: String) {
    defaults.set(id, forKey: "lastProjectID.\(workspaceID)")
  }

  func lastCreatedBy(workspaceID: String) -> CreatedBy? {
    read(CreatedBy.self, key: "lastCreatedBy.\(workspaceID)")
  }

  func setLastCreatedBy(_ createdBy: CreatedBy?, workspaceID: String) {
    write(createdBy, key: "lastCreatedBy.\(workspaceID)")
  }

  var cachedWorkspaces: [Workspace]? {
    get { read([Workspace].self, key: "cache.workspaces") }
    set { write(newValue, key: "cache.workspaces") }
  }

  func cachedCatalog(workspaceID: String) -> WorkspaceCatalog? {
    read(WorkspaceCatalog.self, key: "cache.catalog.\(workspaceID)")
  }

  func setCachedCatalog(_ catalog: WorkspaceCatalog, workspaceID: String) {
    write(catalog, key: "cache.catalog.\(workspaceID)")
  }

  private func read<T: Decodable>(_ type: T.Type, key: String) -> T? {
    guard let data = defaults.data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
  }

  private func write<T: Encodable>(_ value: T?, key: String) {
    guard let value, let data = try? JSONEncoder().encode(value) else {
      defaults.removeObject(forKey: key)
      return
    }
    defaults.set(data, forKey: key)
  }
}
