import Foundation
import os

extension Logger {
  static let subsystem = "dev.sumetph.MacMouseGestures"

  init(category: String) {
    self.init(subsystem: Self.subsystem, category: category)
  }
}

/// Structured gesture event log: one JSON record per event, written to the unified log.
final class EventLogger {
  private let logger = Logger(category: "events")
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
      logger.error("Failed to encode event record: \(event, privacy: .public)")
      return
    }
    logger.info("\(line, privacy: .public)")
  }
}
