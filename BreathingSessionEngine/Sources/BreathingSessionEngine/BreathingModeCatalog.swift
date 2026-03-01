import Foundation

public enum BreathingModeCatalog {
  public static func loadAll() throws -> [BreathingModeSpec] {
    var urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "BreathingModes") ?? []
    if urls.isEmpty {
      urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
    }
    let decoder = JSONDecoder()
    return try urls
      .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
      .map { url in
        let data = try Data(contentsOf: url)
        return try decoder.decode(BreathingModeSpec.self, from: data)
      }
  }

  public static func load(id: String) throws -> BreathingModeSpec {
    let url =
      Bundle.module.url(forResource: id, withExtension: "json", subdirectory: "BreathingModes")
      ?? Bundle.module.url(forResource: id, withExtension: "json", subdirectory: nil)
    guard let url else {
      throw NSError(
        domain: "BreathingModeCatalog",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Missing mode: \(id)"]
      )
    }
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(BreathingModeSpec.self, from: data)
  }
}
