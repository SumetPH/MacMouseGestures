import CoreGraphics
import Foundation
import GestureCore

@MainActor
final class PrivateGestureReplayer {
  private struct RecordedEvent {
    let data: Data
    let timestamp: UInt64
  }

  private let logger = EventLogger()

  func run(logPath: String) async throws {
    let recordedEvents = try loadEvents(logPath: logPath)
    guard !recordedEvents.isEmpty else { throw ReplayError.noRawGestureEvents }

    let offsets = replayOffsets(for: recordedEvents.map(\.timestamp))
    logger.write(
      "private_replay_ready",
      [
        "event_count": "\(recordedEvents.count)",
        "duration_ns": "\(offsets.last ?? 0)",
        "starts_in_seconds": "2",
      ])
    try await Task.sleep(for: .seconds(2))

    let replayStart = CGEvent(source: nil)?.timestamp ?? 0
    var previousOffset: UInt64 = 0
    for (index, recordedEvent) in recordedEvents.enumerated() {
      let offset = offsets[index]
      if offset > previousOffset {
        try await Task.sleep(for: .nanoseconds(Int64(offset - previousOffset)))
      }
      guard
        let event = CGEvent(
          withDataAllocator: kCFAllocatorDefault,
          data: recordedEvent.data as CFData)
      else { throw ReplayError.invalidSerializedEvent(index) }

      event.timestamp = replayStart + offset
      event.post(tap: .cgSessionEventTap)
      previousOffset = offset
    }
    logger.write("private_replay_posted", ["event_count": "\(recordedEvents.count)"])
  }

  private func loadEvents(logPath: String) throws -> [RecordedEvent] {
    let contents = try String(contentsOfFile: logPath, encoding: .utf8)
    return contents.split(separator: "\n").compactMap { line in
      guard
        let lineData = String(line).data(using: .utf8),
        let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: String],
        object["event"] == "native_gesture_raw",
        let encoded = object["cg_data_base64"],
        let eventData = Data(base64Encoded: encoded),
        let timestampText = object["cg_timestamp"],
        let timestamp = UInt64(timestampText)
      else { return nil }
      return RecordedEvent(data: eventData, timestamp: timestamp)
    }
  }
}

enum ReplayError: Error, CustomStringConvertible {
  case noRawGestureEvents
  case invalidSerializedEvent(Int)

  var description: String {
    switch self {
    case .noRawGestureEvents: "No native_gesture_raw events found in the replay file"
    case .invalidSerializedEvent(let index): "Could not decode serialized event at index \(index)"
    }
  }
}
