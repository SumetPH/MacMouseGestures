import CoreVideo
import Foundation

struct DisplayFrameTiming: Sendable {
  let outputTime: Double
  let nominalFrameDuration: Double
}

final class SwiftDisplayLink: @unchecked Sendable {
  private var displayLink: CVDisplayLink?
  private let callback: (DisplayFrameTiming) -> Void

  init(callback: @escaping (DisplayFrameTiming) -> Void) {
    self.callback = callback
    var link: CVDisplayLink?
    let status = CVDisplayLinkCreateWithActiveCGDisplays(&link)
    if status == kCVReturnSuccess, let link = link {
      self.displayLink = link
      
      let callbackWrapper: CVDisplayLinkOutputCallback = { (_, inNow, inOutputTime, _, _, displayLinkContext) -> CVReturn in
        let this = Unmanaged<SwiftDisplayLink>.fromOpaque(displayLinkContext!).takeUnretainedValue()
        let timestamp = inOutputTime.pointee
        let scale = Double(timestamp.videoTimeScale)
        guard scale > 0 else { return kCVReturnSuccess }
        let frameDuration = timestamp.videoRefreshPeriod > 0
          ? Double(timestamp.videoRefreshPeriod) / scale
          : this.nominalFrameDuration()
        this.callback(
          DisplayFrameTiming(
            outputTime: Double(timestamp.videoTime) / scale,
            nominalFrameDuration: frameDuration
          )
        )
        return kCVReturnSuccess
      }
      
      CVDisplayLinkSetOutputCallback(link, callbackWrapper, Unmanaged.passUnretained(self).toOpaque())
    }
  }

  func start() {
    if let link = displayLink, !CVDisplayLinkIsRunning(link) {
      CVDisplayLinkStart(link)
    }
  }

  func stop() {
    if let link = displayLink, CVDisplayLinkIsRunning(link) {
      CVDisplayLinkStop(link)
    }
  }

  @discardableResult
  func setCurrentDisplay(_ displayID: CGDirectDisplayID) -> Bool {
    guard let displayLink else { return false }
    return CVDisplayLinkSetCurrentCGDisplay(displayLink, displayID) == kCVReturnSuccess
  }

  func nominalFrameDuration() -> Double {
    guard let link = displayLink else { return 1.0 / 60.0 }
    let period = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(link)
    if period.timeScale > 0 {
      return Double(period.timeValue) / Double(period.timeScale)
    }
    return 1.0 / 60.0
  }

  deinit {
    stop()
  }
}
