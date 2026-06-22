import Foundation

final class EventLogger {
  private let dateFormatter = ISO8601DateFormatter()
  private let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
  }()

  func write(_ event: String, _ fields: [String: String] = [:]) {
    var record = fields
    record["event"] = event
    record["timestamp"] = dateFormatter.string(from: Date())
    guard let data = try? encoder.encode(record), let line = String(data: data, encoding: .utf8)
    else {
      return
    }
    print(line)
    fflush(stdout)
  }
}
