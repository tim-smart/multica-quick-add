import Foundation

protocol MulticaDataSource: Sendable {
  func workspaces() async throws -> [Workspace]
  func catalog(workspaceID: String) async throws -> WorkspaceCatalog
}

struct MulticaCLI: MulticaDataSource {
  enum CLIError: LocalizedError, Equatable {
    case notInstalled
    case failed(String)

    var errorDescription: String? {
      switch self {
      case .notInstalled:
        "The multica CLI was not found. Install it at /usr/local/bin/multica."
      case .failed(let message):
        message
      }
    }
  }

  var executableURL: URL? = MulticaCLI.locate()

  static func locate() -> URL? {
    var candidates = ["/usr/local/bin/multica"]
    if let path = ProcessInfo.processInfo.environment["PATH"] {
      candidates += path.split(separator: ":").map { "\($0)/multica" }
    }
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
      .map { URL(fileURLWithPath: $0) }
  }

  func workspaces() async throws -> [Workspace] {
    try await list([Workspace].self, "workspace")
  }

  func catalog(workspaceID: String) async throws -> WorkspaceCatalog {
    async let projects = list([Project].self, "project", workspaceID: workspaceID)
    async let agents = list([Agent].self, "agent", workspaceID: workspaceID)
    async let squads = list([Squad].self, "squad", workspaceID: workspaceID)
    return try await WorkspaceCatalog(projects: projects, agents: agents, squads: squads)
  }

  private func list<T: Decodable>(
    _ type: T.Type, _ resource: String, workspaceID: String? = nil
  ) async throws -> T {
    var arguments = [resource, "list", "--output", "json"]
    if let workspaceID {
      arguments += ["--workspace-id", workspaceID]
    }
    return try JSONDecoder().decode(type, from: try await run(arguments))
  }

  private func run(_ arguments: [String]) async throws -> Data {
    guard let executableURL else { throw CLIError.notInstalled }
    return try await Task.detached {
      let process = Process()
      process.executableURL = executableURL
      process.arguments = arguments
      let stdout = Pipe()
      let stderr = Pipe()
      process.standardOutput = stdout
      process.standardError = stderr
      try process.run()
      let output = stdout.fileHandleForReading.readDataToEndOfFile()
      let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else {
        let message = String(data: errorOutput, encoding: .utf8)?
          .trimmingCharacters(in: .whitespacesAndNewlines)
        throw CLIError.failed(
          message?.isEmpty == false
            ? message! : "multica \(arguments.joined(separator: " ")) failed")
      }
      return output
    }.value
  }
}
