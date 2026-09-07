import AppKit
import GameController
import CoreHaptics

// Standalone capability probe; --test sends two brief pulses if supported.
final class Probe: NSObject, NSApplicationDelegate {
    var engines: [CHHapticEngine] = []
    var players: [CHHapticPatternPlayer] = []
    var seen = Set<ObjectIdentifier>()
    var timer: Timer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        GCController.shouldMonitorBackgroundEvents = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in self.inspect() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { NSApp.terminate(nil) }
    }
    func inspect() {
        for controller in GCController.controllers() where !seen.contains(ObjectIdentifier(controller)) {
            seen.insert(ObjectIdentifier(controller))
            print("Controller: \(controller.vendorName ?? "unknown")")
            print("Light: \(controller.light != nil)")
            guard let haptics = controller.haptics else { print("Haptics: nil"); fflush(stdout); continue }
            print("Haptic localities: \(haptics.supportedLocalities)")
            if CommandLine.arguments.contains("--test"), !haptics.supportedLocalities.isEmpty {
                let locality = haptics.supportedLocalities.contains(.default) ? GCHapticsLocality.default : haptics.supportedLocalities.first!
                do {
                    guard let engine = haptics.createEngine(withLocality: locality) else { print("No engine"); continue }
                    engines.append(engine)
                    try engine.start()
                    let events = [0.0, 0.35].map { time in
                        CHHapticEvent(eventType: .hapticContinuous, parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.65)], relativeTime: time, duration: 0.18)
                    }
                    let player = try engine.makePlayer(with: CHHapticPattern(events: events, parameters: []))
                    players.append(player)
                    try player.start(atTime: CHHapticTimeImmediate)
                    print("Two-pulse command accepted by haptic engine")
                } catch { print("Haptic test error: \(error)") }
            }
            fflush(stdout)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let probe = Probe()
app.delegate = probe
app.run()
