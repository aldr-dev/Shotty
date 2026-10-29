import AppKit

let appDelegate = MainActor.assumeIsolated { AppDelegate() }
NSApplication.shared.delegate = appDelegate
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
