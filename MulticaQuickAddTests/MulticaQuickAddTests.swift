import Foundation
import Testing

@testable import MulticaQuickAdd

struct CLIDecodingTests {
  @Test func decodesWorkspaces() throws {
    let json = """
      [
        {"id": "ws-1", "name": "Tim Smart", "slug": "tim-smart"},
        {"id": "ws-2", "name": "Effectful", "slug": "effectful"}
      ]
      """
    let workspaces = try JSONDecoder().decode([Workspace].self, from: Data(json.utf8))
    #expect(
      workspaces == [
        Workspace(id: "ws-1", name: "Tim Smart"),
        Workspace(id: "ws-2", name: "Effectful"),
      ])
  }

  @Test func decodesProjects() throws {
    let json = """
      [
        {"id": "p-1", "title": "slopcop", "icon": "🤖", "status": "in_progress", "issue_count": 1},
        {"id": "p-2", "title": "website", "icon": null}
      ]
      """
    let projects = try JSONDecoder().decode([Project].self, from: Data(json.utf8))
    #expect(
      projects == [
        Project(id: "p-1", title: "slopcop", icon: "🤖"),
        Project(id: "p-2", title: "website", icon: nil),
      ])
  }

  @Test func decodesAgents() throws {
    let json = """
      [{"id": "a-1", "name": "Claude Engineer", "model": "claude-fable-5", "status": "idle"}]
      """
    let agents = try JSONDecoder().decode([Agent].self, from: Data(json.utf8))
    #expect(agents == [Agent(id: "a-1", name: "Claude Engineer")])
  }

  @Test func decodesSquads() throws {
    let json = """
      [{"id": "s-1", "name": "Engineering", "member_count": 8}]
      """
    let squads = try JSONDecoder().decode([Squad].self, from: Data(json.utf8))
    #expect(squads == [Squad(id: "s-1", name: "Engineering")])
  }
}

struct ConfigTests {
  @Test func loadsConfig() throws {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "config-\(UUID().uuidString).json")
    let json = """
      {"server_url": "https://api.multica.ai", "app_url": "https://multica.ai", "token": "tok_123"}
      """
    try Data(json.utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let config = try MulticaAPI.loadConfig(at: url)
    #expect(config.serverURL == URL(string: "https://api.multica.ai"))
    #expect(config.token == "tok_123")
  }

  @Test func missingConfigMeansNotLoggedIn() {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "missing-\(UUID().uuidString).json")
    #expect(throws: APIError.notLoggedIn) {
      try MulticaAPI.loadConfig(at: url)
    }
  }
}

struct QuickCreateRequestTests {
  private let config = MulticaConfig(
    serverURL: URL(string: "https://api.multica.ai")!, token: "tok_123")

  @Test func buildsAgentRequest() throws {
    let request = try MulticaAPI.quickCreateRequest(
      config: config,
      workspaceID: "ws-1",
      prompt: "Fix the login bug",
      createdBy: CreatedBy(kind: .agent, id: "a-1", name: "Claude Engineer"),
      projectID: nil)

    #expect(
      request.url?.absoluteString
        == "https://api.multica.ai/api/issues/quick-create?workspace_id=ws-1")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok_123")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

    let body = try JSONDecoder().decode([String: String].self, from: request.httpBody ?? Data())
    #expect(body == ["prompt": "Fix the login bug", "agent_id": "a-1"])
  }

  @Test func buildsSquadRequestWithProject() throws {
    let request = try MulticaAPI.quickCreateRequest(
      config: config,
      workspaceID: "ws-1",
      prompt: "Ship the website",
      createdBy: CreatedBy(kind: .squad, id: "s-1", name: "Engineering"),
      projectID: "p-1")

    let body = try JSONDecoder().decode([String: String].self, from: request.httpBody ?? Data())
    #expect(body == ["prompt": "Ship the website", "squad_id": "s-1", "project_id": "p-1"])
  }

  @Test func handlesTrailingSlashInServerURL() throws {
    let config = MulticaConfig(serverURL: URL(string: "https://api.multica.ai/")!, token: "t")
    let request = try MulticaAPI.quickCreateRequest(
      config: config,
      workspaceID: "ws-1",
      prompt: "x",
      createdBy: CreatedBy(kind: .agent, id: "a-1", name: "A"),
      projectID: nil)
    #expect(
      request.url?.absoluteString
        == "https://api.multica.ai/api/issues/quick-create?workspace_id=ws-1")
  }
}
