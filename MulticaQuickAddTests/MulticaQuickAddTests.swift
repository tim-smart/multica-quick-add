import AppKit
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
      [{"id": "a-1", "name": "Claude Engineer", "model": "claude-fable-5", "status": "idle",
        "skills": [{"id": "sk-1", "name": "tdd", "description": "Test first", "enabled": true}]}]
      """
    let agents = try JSONDecoder().decode([Agent].self, from: Data(json.utf8))
    #expect(
      agents == [
        Agent(
          id: "a-1", name: "Claude Engineer",
          skills: [Skill(id: "sk-1", name: "tdd", description: "Test first", enabled: true)])
      ])
  }

  @Test func decodesAgentsWithoutSkills() throws {
    let json = """
      [{"id": "a-1", "name": "Claude Engineer"}]
      """
    let agents = try JSONDecoder().decode([Agent].self, from: Data(json.utf8))
    #expect(agents == [Agent(id: "a-1", name: "Claude Engineer")])
    #expect(agents.first?.enabledSkills == [])
  }

  @Test func decodesSquads() throws {
    let json = """
      [{"id": "s-1", "name": "Engineering", "leader_id": "a-1", "member_count": 8}]
      """
    let squads = try JSONDecoder().decode([Squad].self, from: Data(json.utf8))
    #expect(squads == [Squad(id: "s-1", name: "Engineering", leaderID: "a-1")])
  }

  @Test func decodesMembers() throws {
    let json = """
      [{"id": "m-1", "user_id": "u-1", "name": "Tim Smart", "email": "tim@example.com", "role": "owner"}]
      """
    let members = try JSONDecoder().decode([Member].self, from: Data(json.utf8))
    #expect(members == [Member(userID: "u-1", name: "Tim Smart")])
    #expect(members.first?.id == "u-1")
  }

  @Test func decodesCatalogCachedWithoutMembers() throws {
    let json = """
      {"projects": [], "agents": [{"id": "a-1", "name": "Claude"}], "squads": []}
      """
    let catalog = try JSONDecoder().decode(WorkspaceCatalog.self, from: Data(json.utf8))
    #expect(catalog.agents == [Agent(id: "a-1", name: "Claude")])
    #expect(catalog.members.isEmpty)
  }
}

struct SkillTests {
  private let tdd = Skill(id: "sk-1", name: "tdd", description: "Test first")
  private let audit = Skill(id: "sk-2", name: "audit-fix", enabled: true)
  private let disabled = Skill(id: "sk-3", name: "off", enabled: false)

  private var catalog: WorkspaceCatalog {
    WorkspaceCatalog(
      agents: [
        Agent(id: "a-1", name: "Claude", skills: [tdd, disabled]),
        Agent(id: "a-2", name: "Codex", skills: [audit]),
      ],
      squads: [
        Squad(id: "s-1", name: "Engineering", leaderID: "a-2"),
        Squad(id: "s-2", name: "Leaderless"),
      ])
  }

  @Test func skillsForAgentExcludeDisabled() {
    let skills = catalog.skills(for: Assignee(kind: .agent, id: "a-1", name: "Claude"))
    #expect(skills == [tdd])
  }

  @Test func skillsForSquadComeFromLeader() {
    #expect(catalog.skills(for: Assignee(kind: .squad, id: "s-1", name: "Engineering")) == [audit])
    #expect(catalog.skills(for: Assignee(kind: .squad, id: "s-2", name: "Leaderless")) == [])
  }

  @Test func membersHaveNoSkills() {
    #expect(catalog.skills(for: Assignee(kind: .member, id: "u-1", name: "Tim")) == [])
  }

  @Test func expandsLeadingSkillReference() {
    let expanded = Skill.expandingReference(in: "/tdd fix the login bug", skills: [tdd, audit])
    #expect(expanded == "[/tdd](slash://skill/sk-1) fix the login bug")
  }

  @Test func expandsBareSkillReference() {
    let expanded = Skill.expandingReference(in: "/audit-fix", skills: [tdd, audit])
    #expect(expanded == "[/audit-fix](slash://skill/sk-2)")
  }

  @Test func leavesUnknownSlashTokenAlone() {
    #expect(
      Skill.expandingReference(in: "/usr/local is broken", skills: [tdd]) == "/usr/local is broken")
    #expect(Skill.expandingReference(in: "no slash", skills: [tdd]) == "no slash")
  }

  @Test func escapesMarkdownCharactersInLabel() {
    let odd = Skill(id: "sk-9", name: #"we[i]r\d(name)"#)
    #expect(
      Skill.expandingReference(in: #"/we[i]r\d(name) go"#, skills: [odd])
        == #"[/we\[i\]r\\d\(name\)](slash://skill/sk-9) go"#)
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
      assignee: Assignee(kind: .agent, id: "a-1", name: "Claude Engineer"),
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
      assignee: Assignee(kind: .squad, id: "s-1", name: "Engineering"),
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
      assignee: Assignee(kind: .agent, id: "a-1", name: "A"),
      projectID: nil)
    #expect(
      request.url?.absoluteString
        == "https://api.multica.ai/api/issues/quick-create?workspace_id=ws-1")
  }

  @Test func includesAttachmentIDs() throws {
    let request = try MulticaAPI.quickCreateRequest(
      config: config,
      workspaceID: "ws-1",
      prompt: "Fix the login bug",
      assignee: Assignee(kind: .agent, id: "a-1", name: "Claude Engineer"),
      projectID: nil,
      attachmentIDs: ["att-1", "att-2"])

    struct Body: Decodable {
      var prompt: String
      var agentID: String
      var attachmentIDs: [String]

      enum CodingKeys: String, CodingKey {
        case prompt
        case agentID = "agent_id"
        case attachmentIDs = "attachment_ids"
      }
    }
    let body = try JSONDecoder().decode(Body.self, from: request.httpBody ?? Data())
    #expect(body.prompt == "Fix the login bug")
    #expect(body.agentID == "a-1")
    #expect(body.attachmentIDs == ["att-1", "att-2"])
  }
}

struct CreateIssueRequestTests {
  private let config = MulticaConfig(
    serverURL: URL(string: "https://api.multica.ai")!, token: "tok_123")

  @Test func buildsMemberRequest() throws {
    let request = try MulticaAPI.createIssueRequest(
      config: config,
      workspaceID: "ws-1",
      prompt: "Fix the login bug\nUsers get a 500 after OAuth.",
      memberUserID: "u-1",
      projectID: "p-1",
      attachmentIDs: ["att-1"])

    #expect(request.url?.absoluteString == "https://api.multica.ai/api/issues?workspace_id=ws-1")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok_123")

    struct Body: Decodable {
      var title: String
      var description: String?
      var assigneeType: String
      var assigneeID: String
      var projectID: String?
      var attachmentIDs: [String]?

      enum CodingKeys: String, CodingKey {
        case title
        case description
        case assigneeType = "assignee_type"
        case assigneeID = "assignee_id"
        case projectID = "project_id"
        case attachmentIDs = "attachment_ids"
      }
    }
    let body = try JSONDecoder().decode(Body.self, from: request.httpBody ?? Data())
    #expect(body.title == "Fix the login bug")
    #expect(body.description == "Users get a 500 after OAuth.")
    #expect(body.assigneeType == "member")
    #expect(body.assigneeID == "u-1")
    #expect(body.projectID == "p-1")
    #expect(body.attachmentIDs == ["att-1"])
  }

  @Test func singleLinePromptHasNoDescription() {
    let (title, description) = MulticaAPI.titleAndDescription(from: "Fix the login bug")
    #expect(title == "Fix the login bug")
    #expect(description == nil)
  }

  @Test func blankRemainderMeansNoDescription() {
    let (title, description) = MulticaAPI.titleAndDescription(from: "Fix the login bug\n\n  ")
    #expect(title == "Fix the login bug")
    #expect(description == nil)
  }
}

struct UploadRequestTests {
  private let config = MulticaConfig(
    serverURL: URL(string: "https://api.multica.ai")!, token: "tok_123")

  @Test func buildsMultipartRequest() throws {
    let attachment = PendingAttachment(filename: "screen.png", data: Data("PNGDATA".utf8))
    let request = try MulticaAPI.uploadRequest(
      config: config, workspaceID: "ws-1", attachment: attachment, boundary: "test-boundary")

    #expect(
      request.url?.absoluteString == "https://api.multica.ai/api/upload-file?workspace_id=ws-1")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok_123")
    #expect(
      request.value(forHTTPHeaderField: "Content-Type")
        == "multipart/form-data; boundary=test-boundary")

    let expectedBody = """
      --test-boundary\r
      Content-Disposition: form-data; name="file"; filename="screen.png"\r
      Content-Type: application/octet-stream\r
      \r
      PNGDATA\r
      --test-boundary--\r

      """
    #expect(request.httpBody == Data(expectedBody.utf8))
  }

  @Test func sanitizesFilename() throws {
    let attachment = PendingAttachment(filename: "a\"b\r\n.png", data: Data())
    let request = try MulticaAPI.uploadRequest(
      config: config, workspaceID: "ws-1", attachment: attachment, boundary: "b")
    let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
    #expect(body.contains("filename=\"a_b  .png\""))
  }

  @Test func decodesUploadedAttachment() throws {
    let json = """
      {"id": "att-1", "filename": "screen.png", "url": "https://static.multica.ai/x.png",
       "markdown_url": "https://api.multica.ai/api/attachments/att-1/download"}
      """
    let uploaded = try MulticaAPI.uploadedAttachment(from: Data(json.utf8))
    #expect(uploaded.id == "att-1")
    #expect(uploaded.filename == "screen.png")
    #expect(uploaded.markdownURL == "https://api.multica.ai/api/attachments/att-1/download")
  }

  @Test func missingAttachmentIDThrows() {
    #expect(throws: APIError.self) {
      try MulticaAPI.uploadedAttachment(from: Data("{}".utf8))
    }
    #expect(throws: APIError.self) {
      try MulticaAPI.uploadedAttachment(from: Data(#"{"id": ""}"#.utf8))
    }
  }

  @Test func markdownReferenceUsesServerURL() {
    let uploaded = MulticaAPI.UploadedAttachment(
      id: "att-1", filename: "screen.png",
      markdownURL: "https://static.multica.ai/x.png")
    #expect(
      MulticaAPI.markdownReference(for: uploaded, fallbackFilename: "f.png", config: config)
        == "![screen.png](https://static.multica.ai/x.png)")

    let bare = MulticaAPI.UploadedAttachment(id: "att-2", filename: nil, markdownURL: nil)
    #expect(
      MulticaAPI.markdownReference(for: bare, fallbackFilename: "f.png", config: config)
        == "![f.png](https://api.multica.ai/api/attachments/att-2/download)")
  }

  @Test func appendsMarkdownWithBlankLine() {
    #expect(
      MulticaAPI.appendingMarkdown("![a](b)", to: "Fix the bug\n") == "Fix the bug\n\n![a](b)")
    #expect(MulticaAPI.appendingMarkdown("![a](b)", to: "  ") == "![a](b)")
  }
}

struct ImagePasteboardTests {
  private func withPasteboard(_ body: (NSPasteboard) throws -> Void) rethrows {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    pasteboard.clearContents()
    try body(pasteboard)
  }

  @Test func attachesBitmapWithNoText() {
    withPasteboard { pasteboard in
      pasteboard.setData(Data("PNG".utf8), forType: .png)
      let images = ImagePasteboard.pastedImages(from: pasteboard)
      #expect(images.map(\.filename) == [ImagePasteboard.pastedFilename])
      #expect(images.first?.data == Data("PNG".utf8))
    }
  }

  @Test func prefersTextOverBitmap() {
    withPasteboard { pasteboard in
      pasteboard.setData(Data("PNG".utf8), forType: .png)
      pasteboard.setString("cell text", forType: .string)
      #expect(ImagePasteboard.pastedImages(from: pasteboard).isEmpty)
    }
  }

  @Test func attachesBitmapWhenTextIsImageURL() {
    withPasteboard { pasteboard in
      pasteboard.setData(Data("PNG".utf8), forType: .png)
      pasteboard.setString("https://example.com/cat.png", forType: .string)
      #expect(ImagePasteboard.pastedImages(from: pasteboard).count == 1)
    }
  }

  @Test func dragIgnoresText() {
    withPasteboard { pasteboard in
      pasteboard.setData(Data("PNG".utf8), forType: .png)
      pasteboard.setString("cell text", forType: .string)
      #expect(ImagePasteboard.draggedImages(from: pasteboard).count == 1)
    }
  }

  @Test func readsImageFiles() throws {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "paste-\(UUID().uuidString).png")
    try Data("PNGFILE".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    withPasteboard { pasteboard in
      pasteboard.writeObjects([url as NSURL])
      let images = ImagePasteboard.pastedImages(from: pasteboard)
      #expect(images.map(\.filename) == [url.lastPathComponent])
      #expect(images.first?.data == Data("PNGFILE".utf8))
    }
  }

  @Test func ignoresNonImageFiles() throws {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "paste-\(UUID().uuidString).txt")
    try Data("TEXT".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    withPasteboard { pasteboard in
      pasteboard.writeObjects([url as NSURL])
      #expect(ImagePasteboard.pastedImages(from: pasteboard).isEmpty)
    }
  }
}
