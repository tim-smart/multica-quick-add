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
  func submitQuickCreate(
    workspaceID: String, prompt: String, createdBy: CreatedBy, projectID: String?
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
    createdBy: CreatedBy,
    projectID: String?
  ) throws -> URLRequest {
    guard var components = URLComponents(url: config.serverURL, resolvingAgainstBaseURL: false)
    else { throw APIError.badServerURL }
    let basePath =
      components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
    components.path = basePath + "/api/issues/quick-create"
    components.queryItems = [URLQueryItem(name: "workspace_id", value: workspaceID)]
    guard let url = components.url else { throw APIError.badServerURL }

    let payload = QuickCreatePayload(
      prompt: prompt,
      agentID: createdBy.kind == .agent ? createdBy.id : nil,
      squadID: createdBy.kind == .squad ? createdBy.id : nil,
      projectID: projectID)

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(payload)
    return request
  }

  static func send(_ request: URLRequest) async throws {
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw APIError.server(status: 0, message: "Unexpected response from the server.")
    }
    guard (200..<300).contains(http.statusCode) else {
      throw APIError.server(status: http.statusCode, message: errorMessage(from: data))
    }
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

    private enum CodingKeys: String, CodingKey {
      case prompt
      case agentID = "agent_id"
      case squadID = "squad_id"
      case projectID = "project_id"
    }
  }
}

struct MulticaAPIClient: IssueSubmitter {
  func submitQuickCreate(
    workspaceID: String, prompt: String, createdBy: CreatedBy, projectID: String?
  ) async throws {
    let config = try MulticaAPI.loadConfig()
    let request = try MulticaAPI.quickCreateRequest(
      config: config,
      workspaceID: workspaceID,
      prompt: prompt,
      createdBy: createdBy,
      projectID: projectID)
    try await MulticaAPI.send(request)
  }
}
