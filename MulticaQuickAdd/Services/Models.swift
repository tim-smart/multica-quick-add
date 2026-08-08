import Foundation

struct Workspace: Codable, Identifiable, Hashable, Sendable {
  let id: String
  let name: String
}

struct Project: Codable, Identifiable, Hashable, Sendable {
  let id: String
  let title: String
  var icon: String?
}

struct Agent: Codable, Identifiable, Hashable, Sendable {
  let id: String
  let name: String
}

struct Squad: Codable, Identifiable, Hashable, Sendable {
  let id: String
  let name: String
}

enum CreatedByKind: String, Codable, Sendable {
  case agent
  case squad
}

struct CreatedBy: Codable, Identifiable, Hashable, Sendable {
  var kind: CreatedByKind
  var id: String
  var name: String
}

struct PendingAttachment: Identifiable, Hashable, Sendable {
  let id: UUID
  var filename: String
  var data: Data

  init(id: UUID = UUID(), filename: String, data: Data) {
    self.id = id
    self.filename = filename
    self.data = data
  }
}

struct WorkspaceCatalog: Codable, Hashable, Sendable {
  var projects: [Project] = []
  var agents: [Agent] = []
  var squads: [Squad] = []

  var createdByOptions: [CreatedBy] {
    agents.map { CreatedBy(kind: .agent, id: $0.id, name: $0.name) }
      + squads.map { CreatedBy(kind: .squad, id: $0.id, name: $0.name) }
  }
}
