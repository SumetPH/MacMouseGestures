public func replayOffsets(for timestamps: [UInt64]) -> [UInt64] {
  guard let first = timestamps.first else { return [] }
  return timestamps.map { $0 >= first ? $0 - first : 0 }
}
