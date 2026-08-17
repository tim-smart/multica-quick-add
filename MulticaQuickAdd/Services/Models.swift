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
  var skills: [Skill]? = nil

  var enabledSkills: [Skill] {
    (skills ?? []).filter { $0.enabled != false }
  }
}

struct Squad: Codable, Identifiable, Hashable, Sendable {
  let id: String
  let name: String
  var leaderID: String? = nil

  private enum CodingKeys: String, CodingKey {
    case id
    case name
    case leaderID = "leader_id"
  }
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

struct Skill: Codable, Identifiable, Hashable, Sendable {
  let id: String
  let name: String
  var description: String? = nil
  var enabled: Bool? = nil
}

extension Skill {
  // Multica serializes a skill mention as [/label](slash://skill/<id>) in
  // issue markdown; the daemon extracts these refs when building the agent
  // prompt. Mirrors packages/views/editor/extensions/slash-command-extension.ts.
  var markdownReference: String {
    var label = name
    for character in ["\\", "[", "]", "(", ")"] {
      label = label.replacingOccurrences(of: character, with: "\\" + character)
    }
    return "[/\(label)](slash://skill/\(id))"
  }

  static func expandingReference(in prompt: String, skills: [Skill]) -> String {
    guard prompt.hasPrefix("/") else { return prompt }
    let name = prompt.dropFirst().prefix { !$0.isWhitespace }
    guard let skill = skills.first(where: { $0.name == name }) else { return prompt }
    return skill.markdownReference + prompt.dropFirst(1 + name.count)
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

  // The daemon only honors skill refs assigned to the executing agent, and a
  // squad issue is executed by the squad's leader.
  func skills(for assignee: Assignee) -> [Skill] {
    switch assignee.kind {
    case .agent:
      agents.first { $0.id == assignee.id }?.enabledSkills ?? []
    case .squad:
      squads.first { $0.id == assignee.id }?.leaderID
        .flatMap { leaderID in agents.first { $0.id == leaderID } }?.enabledSkills ?? []
    case .member:
      []
    }
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
