// Print the CGWindowID of the frontmost on-screen window owned by a process.
//
// Exists because `screencapture -R <rect>` captures a REGION OF THE SCREEN, so
// anything floating over the app -- a terminal, a notification -- lands in the
// committed screenshot. `screencapture -l <windowID>` captures the window itself
// and is immune to overlap. Getting that id needs CGWindowListCopyWindowInfo,
// which AppleScript cannot reach.
//
//   swift tools/window-id.swift "solvr.ai"
import CoreGraphics
import Foundation

let owner = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                            kCGNullWindowID) as? [[String: Any]] else {
    FileHandle.standardError.write(Data("cannot read window list\n".utf8))
    exit(1)
}

// Layer 0 is a normal application window; menus, panels and the shadow layers
// used by some apps sit above it and would otherwise win.
for w in list {
    guard let name = w[kCGWindowOwnerName as String] as? String, name == owner,
          let layer = w[kCGWindowLayer as String] as? Int, layer == 0,
          let bounds = w[kCGWindowBounds as String] as? [String: Any],
          let h = bounds["Height"] as? Double, h > 200,
          let id = w[kCGWindowNumber as String] as? Int
    else { continue }
    print(id)
    exit(0)
}

FileHandle.standardError.write(Data("no on-screen window for \(owner)\n".utf8))
exit(1)
