import AppKit
import ApplicationServices
import Foundation

do {
  let configuration = try Configuration.parse(CommandLine.arguments)
  if configuration.mode == .nativeRecord,
    !CGPreflightListenEventAccess() && !CGRequestListenEventAccess()
  {
    fputs(
      "Input Monitoring permission is required. Grant it in System Settings, then run again.\n",
      stderr)
    exit(2)
  }
  let prompt = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
  guard AXIsProcessTrustedWithOptions(prompt) else {
    fputs(
      "Accessibility permission is required. Grant it in System Settings, then run again.\n", stderr
    )
    exit(2)
  }

  let application = NSApplication.shared
  application.setActivationPolicy(.accessory)
  var runningController: GestureController?
  if configuration.mode == .privateReplay {
    guard let replayFile = configuration.replayFile else {
      throw ParseError("private-replay requires --replay-file PATH")
    }
    let replayer = PrivateGestureReplayer()
    Task { @MainActor in
      do {
        try await replayer.run(logPath: replayFile)
      } catch {
        fputs("Replay error: \(error)\n", stderr)
      }
      application.terminate(nil)
    }
  } else if configuration.mode == .touchSynthesis {
    let probe = PrivateTouchSynthesisProbe()
    Task { @MainActor in
      do {
        try await probe.run(direction: configuration.synthesisDirection)
      } catch {
        fputs("Touch synthesis error: \(error)\n", stderr)
      }
      application.terminate(nil)
    }
  } else if configuration.mode == .fluidSynthesis {
    let probe = PrivateFluidGestureProbe()
    Task { @MainActor in
      do {
        try await probe.run(direction: configuration.synthesisDirection)
      } catch {
        fputs("Fluid synthesis error: \(error)\n", stderr)
      }
      application.terminate(nil)
    }
  } else {
    let controller = GestureController(configuration: configuration)
    try controller.start()
    runningController = controller
    print(Configuration.usage)
  }
  withExtendedLifetime(runningController) {
    application.run()
  }
} catch {
  fputs("Error: \(error)\n\(Configuration.usage)\n", stderr)
  exit(1)
}
