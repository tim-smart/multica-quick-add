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

struct Member: Codable, Identifiable, Hashable, Sendable {
  let userID: String
  let name: String

  var id: String { userID }

  private enum CodingKeys: String, CodingKey {
    case userID = "user_id"
    case name
  }
}

enum AssigneeKind: String, Codable, Sendable {
  case agent
  case squad
  case member
}

struct Assignee: Codable, Identifiable, Hashable, Sendable {
  var kind: AssigneeKind
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
  var members: [Member] = []

  var assigneeOptions: [Assignee] {
    agents.map { Assignee(kind: .agent, id: $0.id, name: $0.name) }
      + squads.map { Assignee(kind: .squad, id: $0.id, name: $0.name) }
      + members.map { Assignee(kind: .member, id: $0.id, name: $0.name) }
  }
}

extension WorkspaceCatalog {
  // Tolerates cached catalogs written before a field existed.
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    projects = try container.decodeIfPresent([Project].self, forKey: .projects) ?? []
    agents = try container.decodeIfPresent([Agent].self, forKey: .agents) ?? []
    squads = try container.decodeIfPresent([Squad].self, forKey: .squads) ?? []
    members = try container.decodeIfPresent([Member].self, forKey: .members) ?? []
  }
}
