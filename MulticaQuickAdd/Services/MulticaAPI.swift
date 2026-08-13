import Foundation

struct MulticaConfig: Decodable, Equatable, Sendable {
  var serverURL: URL
  var token: String

  private enum CodingKeys: String, CodingKey {
    case serverURL = "server_url"
    case token
  }
}

enum APIError: LocalizedError, Equatable {
  case notLoggedIn
  case badServerURL
  case server(status: Int, message: String)

  var errorDescription: String? {
    switch self {
    case .notLoggedIn:
      "Not logged in. Run \"multica login\" first."
    case .badServerURL:
      "The server URL in ~/.multica/config.json is invalid."
    case .server(let status, let message):
      message.isEmpty ? "The server responded with status \(status)." : message
    }
  }
}

protocol IssueSubmitter: Sendable {
  func submit(
    workspaceID: String, prompt: String, assignee: Assignee, projectID: String?,
    attachments: [PendingAttachment]
  ) async throws
}

enum MulticaAPI {
  static var defaultConfigURL: URL {
    FileManager.default.homeDirectoryForCurrentUser.appending(path: ".multica/config.json")
  }

  static func loadConfig(at url: URL = defaultConfigURL) throws -> MulticaConfig {
    guard let data = try? Data(contentsOf: url),
      let config = try? JSONDecoder().decode(MulticaConfig.self, from: data)
    else { throw APIError.notLoggedIn }
    return config
  }

  static func quickCreateRequest(
    config: MulticaConfig,
    workspaceID: String,
    prompt: String,
    assignee: Assignee,
    projectID: String?,
    attachmentIDs: [String] = []
  ) throws -> URLRequest {
    guard
      let url = endpointURL(
        config: config, path: "/api/issues/quick-create", workspaceID: workspaceID)
    else { throw APIError.badServerURL }

    let payload = QuickCreatePayload(
      prompt: prompt,
      agentID: assignee.kind == .agent ? assignee.id : nil,
      squadID: assignee.kind == .squad ? assignee.id : nil,
      projectID: projectID,
      attachmentIDs: attachmentIDs.isEmpty ? nil : attachmentIDs)

    return try jsonRequest(url: url, token: config.token, payload: payload)
  }

  // Quick-create only accepts agent or squad actors, so issues for a human
  // go through the plain create endpoint: first prompt line becomes the
  // title, the rest the description.
  static func createIssueRequest(
    config: MulticaConfig,
    workspaceID: String,
    prompt: String,
    memberUserID: String,
    projectID: String?,
    attachmentIDs: [String] = []
  ) throws -> URLRequest {
    guard let url = endpointURL(config: config, path: "/api/issues", workspaceID: workspaceID)
    else { throw APIError.badServerURL }

    let (title, description) = titleAndDescription(from: prompt)
    let payload = CreateIssuePayload(
      title: title,
      description: description,
      assigneeType: "member",
      assigneeID: memberUserID,
      projectID: projectID,
      attachmentIDs: attachmentIDs.isEmpty ? nil : attachmentIDs)

    return try jsonRequest(url: url, token: config.token, payload: payload)
  }

  static func titleAndDescription(from prompt: String) -> (title: String, description: String?) {
    guard let newline = prompt.firstIndex(of: "\n") else { return (prompt, nil) }
    let title = String(prompt[..<newline])
    let description = String(prompt[prompt.index(after: newline)...])
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return (title, description.isEmpty ? nil : description)
  }

  private static func jsonRequest(
    url: URL, token: String, payload: some Encodable
  ) throws -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(payload)
    return request
  }

  static func uploadRequest(
    config: MulticaConfig,
    workspaceID: String,
    attachment: PendingAttachment,
    boundary: String = "multica-quick-add-\(UUID().uuidString)"
  ) throws -> URLRequest {
    guard let url = endpointURL(config: config, path: "/api/upload-file", workspaceID: workspaceID)
    else { throw APIError.badServerURL }

    let filename = attachment.filename
      .replacingOccurrences(of: "\"", with: "_")
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "\r", with: " ")
    var body = Data()
    body.append(Data("--\(boundary)\r\n".utf8))
    body.append(
      Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".utf8))
    body.append(Data("Content-Type: application/octet-stream\r\n\r\n".utf8))
    body.append(attachment.data)
    body.append(Data("\r\n--\(boundary)--\r\n".utf8))

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
    request.setValue(
      "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.httpBody = body
    return request
  }

  struct UploadedAttachment: Decodable, Equatable, Sendable {
    var id: String
    var filename: String?
    var markdownURL: String?

    private enum CodingKeys: String, CodingKey {
      case id
      case filename
      case markdownURL = "markdown_url"
    }
  }

  static func uploadedAttachment(from data: Data) throws -> UploadedAttachment {
    guard let response = try? JSONDecoder().decode(UploadedAttachment.self, from: data),
      !response.id.isEmpty
    else {
      throw APIError.server(status: 0, message: "Upload response is missing the attachment id.")
    }
    return response
  }

  // Multica's own clients bind attachments twice: attachment_ids joins the
  // files to the issue, and a markdown image reference in the body is what
  // actually renders them. Mirrors packages/views/editor/use-coordinated-uploads.ts.
  static func markdownReference(
    for uploaded: UploadedAttachment, fallbackFilename: String, config: MulticaConfig
  ) -> String {
    let filename = uploaded.filename ?? fallbackFilename
    let link =
      uploaded.markdownURL
      ?? config.serverURL.appending(path: "api/attachments/\(uploaded.id)/download").absoluteString
    return "![\(filename)](\(link))"
  }

  static func appendingMarkdown(_ markdown: String, to body: String) -> String {
    let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? markdown : trimmed + "\n\n" + markdown
  }

  @discardableResult
  static func send(_ request: URLRequest) async throws -> Data {
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw APIError.server(status: 0, message: "Unexpected response from the server.")
    }
    guard (200..<300).contains(http.statusCode) else {
      throw APIError.server(status: http.statusCode, message: errorMessage(from: data))
    }
    return data
  }

  private static func endpointURL(config: MulticaConfig, path: String, workspaceID: String) -> URL?
  {
    guard var components = URLComponents(url: config.serverURL, resolvingAgainstBaseURL: false)
    else { return nil }
    let basePath =
      components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
    components.path = basePath + path
    components.queryItems = [URLQueryItem(name: "workspace_id", value: workspaceID)]
    return components.url
  }

  private static func errorMessage(from data: Data) -> String {
    struct ServerError: Decodable {
      var error: String?
      var message: String?
    }
    if let decoded = try? JSONDecoder().decode(ServerError.self, from: data),
      let message = decoded.error ?? decoded.message
    {
      return message
    }
    return String(data: data.prefix(300), encoding: .utf8) ?? ""
  }

  private struct QuickCreatePayload: Encodable {
    var prompt: String
    var agentID: String?
    var squadID: String?
    var projectID: String?
    var attachmentIDs: [String]?

    private enum CodingKeys: String, CodingKey {
      case prompt
      case agentID = "agent_id"
      case squadID = "squad_id"
      case projectID = "project_id"
      case attachmentIDs = "attachment_ids"
    }
  }

  private struct CreateIssuePayload: Encodable {
    var title: String
    var description: String?
    var assigneeType: String
    var assigneeID: String
    var projectID: String?
    var attachmentIDs: [String]?

    private enum CodingKeys: String, CodingKey {
      case title
      case description
      case assigneeType = "assignee_type"
      case assigneeID = "assignee_id"
      case projectID = "project_id"
      case attachmentIDs = "attachment_ids"
    }
  }
}

struct MulticaAPIClient: IssueSubmitter {
  func submit(
    workspaceID: String, prompt: String, assignee: Assignee, projectID: String?,
    attachments: [PendingAttachment]
  ) async throws {
    let config = try MulticaAPI.loadConfig()
    var prompt = prompt
    var attachmentIDs: [String] = []
    for attachment in attachments {
      let uploadRequest = try MulticaAPI.uploadRequest(
        config: config, workspaceID: workspaceID, attachment: attachment)
      let response = try await MulticaAPI.send(uploadRequest)
      let uploaded = try MulticaAPI.uploadedAttachment(from: response)
      attachmentIDs.append(uploaded.id)
      let reference = MulticaAPI.markdownReference(
        for: uploaded, fallbackFilename: attachment.filename, config: config)
      prompt = MulticaAPI.appendingMarkdown(reference, to: prompt)
    }
    let request =
      switch assignee.kind {
      case .agent, .squad:
        try MulticaAPI.quickCreateRequest(
          config: config,
          workspaceID: workspaceID,
          prompt: prompt,
          assignee: assignee,
          projectID: projectID,
          attachmentIDs: attachmentIDs)
      case .member:
        try MulticaAPI.createIssueRequest(
          config: config,
          workspaceID: workspaceID,
          prompt: prompt,
          memberUserID: assignee.id,
          projectID: projectID,
          attachmentIDs: attachmentIDs)
      }
    try await MulticaAPI.send(request)
  }
}
