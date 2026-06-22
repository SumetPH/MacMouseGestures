import Foundation
import GestureCore

enum ProbeMode: String {
  case probe
  case fallback
  case hybrid
  case nativeRecord = "native-record"
  case privateReplay = "private-replay"
  case touchSynthesis = "touch-synthesis"
  case fluidSynthesis = "fluid-synthesis"
  case privateDrag = "private-drag"

  var postsScroll: Bool { self == .probe || self == .hybrid }
  var sendsShortcut: Bool { self == .fallback || self == .hybrid }
}

struct Configuration {
  var mode: ProbeMode = .probe
  var threshold = 80.0
  var scrollScale = 1.0
  var fluidDistance: Double?
  var showsOverlay = true
  var replayFile: String?
  var synthesisDirection: SyntheticSwipeDirection = .left

  static func parse(_ arguments: [String]) throws -> Configuration {
    var configuration = Configuration()
    var index = 1
    while index < arguments.count {
      switch arguments[index] {
      case "--mode":
        index += 1
        guard index < arguments.count, let mode = ProbeMode(rawValue: arguments[index]) else {
          throw ParseError(
            "--mode requires probe, fallback, hybrid, native-record, private-replay, touch-synthesis, fluid-synthesis, or private-drag"
          )
        }
        configuration.mode = mode
      case "--threshold":
        index += 1
        guard index < arguments.count, let value = Double(arguments[index]), value > 0 else {
          throw ParseError("--threshold requires a positive number")
        }
        configuration.threshold = value
      case "--scroll-scale":
        index += 1
        guard index < arguments.count, let value = Double(arguments[index]), value != 0 else {
          throw ParseError("--scroll-scale requires a non-zero number")
        }
        configuration.scrollScale = value
      case "--fluid-distance":
        index += 1
        guard index < arguments.count, let value = Double(arguments[index]), value > 0 else {
          throw ParseError("--fluid-distance requires a positive number")
        }
        configuration.fluidDistance = value
      case "--no-overlay":
        configuration.showsOverlay = false
      case "--replay-file":
        index += 1
        guard index < arguments.count else {
          throw ParseError("--replay-file requires a native-record log path")
        }
        configuration.replayFile = arguments[index]
      case "--direction":
        index += 1
        guard index < arguments.count else {
          throw ParseError("--direction requires left or right")
        }
        switch arguments[index] {
        case "left": configuration.synthesisDirection = .left
        case "right": configuration.synthesisDirection = .right
        default: throw ParseError("--direction requires left or right")
        }
      case "--help", "-h":
        print(Self.usage)
        exit(0)
      default:
        throw ParseError("unknown argument: \(arguments[index])")
      }
      index += 1
    }
    return configuration
  }

  static let usage = """
    Usage: spaces-gesture-probe [--mode probe|fallback|hybrid|native-record|private-replay|touch-synthesis|fluid-synthesis|private-drag]
                                [--threshold 80] [--fluid-distance pixels] [--scroll-scale 1] [--no-overlay]

      probe     Post continuous pixel scroll events only (default; tests live Spaces drag)
      fallback  Post Ctrl+Arrow on release only
      hybrid    Post scroll while dragging, then Ctrl+Arrow on release
      native-record  Passively record native trackpad Spaces gesture events
      private-replay Replay serialized type-29 events from --replay-file once
      touch-synthesis Create a fresh private swipe event; use --direction left|right
      fluid-synthesis Create a type-30 fluid gesture; use --direction left|right
      private-drag Right-button drag controls a live type-30 Spaces gesture
      --threshold Public fallback/hybrid switch distance (private-drag uses halfway progress)
      --fluid-distance Override the full animation distance (default: 52% of start display width)
      Y / N     Record whether the last gesture showed a live Spaces animation
    """
}

struct ParseError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}
