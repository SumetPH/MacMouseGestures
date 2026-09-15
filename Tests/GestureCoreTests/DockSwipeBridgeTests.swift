import CoreGraphics
import DockSwipeBridge
import Testing

@Test("macOS 27 DockSwipe embeds a serializable HID payload without posting input")
func dockSwipePayload() throws {
  guard #available(macOS 27.0, *) else { return }
  let empty = try #require(CGEvent(source: nil))
  empty.type = CGEventType(rawValue: 30)!
  let emptySize = CFDataGetLength(empty.data)
  for axis: Int32 in [1, 2] {
    for phase: UInt32 in [1, 2, 4, 8] {
      let event = try #require(MMGCreateDockSwipe(phase, -0.7, -6.8, axis, .zero))
      #expect(event.type.rawValue == 30)
      let data = try #require(event.data)
      #expect(CFDataGetLength(data) > emptySize)
      let restored = try #require(CGEvent(withDataAllocator: nil, data: data))
      #expect(restored.type.rawValue == 30)
    }
  }
  #expect(MMGCreateDockSwipe(0, 0, 0, 1, .zero) == nil)
  #expect(MMGCreateDockSwipe(1, .nan, 0, 1, .zero) == nil)
}
