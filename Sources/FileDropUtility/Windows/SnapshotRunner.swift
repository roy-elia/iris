#if DEBUG
  import AppKit
  import SwiftUI

  /// Debug-only: `FileDropUtility --snapshot <folder>` renders every screen over a busy
  /// backdrop in several appearances, captures each real window with `screencapture`, and
  /// quits. Real windows are used because Liquid Glass is composited by the window server
  /// and doesn't appear in offscreen renders.
  /// A borderless window that can still become key, so its controls draw as active.
  final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
  }

  @MainActor
  enum SnapshotRunner {
    struct Variant {
      let name: String
      let appearance: NSAppearance.Name
      let largestText: Bool
    }

    static let variants = [
      Variant(name: "light", appearance: .aqua, largestText: false),
      Variant(name: "dark", appearance: .darkAqua, largestText: false),
      Variant(name: "light-contrast", appearance: .accessibilityHighContrastAqua, largestText: false),
      Variant(name: "dark-contrast", appearance: .accessibilityHighContrastDarkAqua, largestText: false),
      Variant(name: "dark-largest-text", appearance: .darkAqua, largestText: true),
    ]

    static func runIfRequested() -> Bool {
      let args = CommandLine.arguments
      guard let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count else { return false }
      let folder = URL(fileURLWithPath: args[index + 1], isDirectory: true)
      let only = args.firstIndex(of: "--only").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
      try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      Task { await run(into: folder, only: only) }
      return true
    }

    private static func run(into folder: URL, only: String?) async {
      for screen in Screens.all where only.map({ screen.name.contains($0) }) ?? true {
        for variant in variants {
          await capture(screen: screen.name, size: screen.size, variant: variant, folder: folder)
        }
      }
      print("SNAPSHOTS DONE")
      NSApp.terminate(nil)
    }

    private static func capture(screen: String, size: CGSize, variant: Variant, folder: URL) async {
      let model = PreviewData.model()
      // Screens that are whole windows with a toolbar are captured in a real titled window,
      // over the window's own background; the rest float over a busy backdrop.
      let windowed = screen.hasPrefix("Panel-") || screen.hasPrefix("Onboarding-")
      let content = ZStack {
        if !windowed { SnapshotBackdrop() }
        Screens.view(screen, model: model)
          .dynamicTypeSize(variant.largestText ? .accessibility5 : .large)
      }
      .frame(
        width: size.width, height: variant.largestText ? size.height * 1.5 : size.height,
        alignment: windowed ? .top : .center)

      let window = KeyableWindow(
        contentRect: NSRect(x: 60, y: 60, width: size.width, height: size.height),
        styleMask: windowed ? [.titled, .fullSizeContentView] : [.borderless], backing: .buffered,
        defer: false)
      window.appearance = NSAppearance(named: variant.appearance)
      let hosting = NSHostingController(rootView: content.brandTint())
      if windowed {
        hosting.sceneBridgingOptions = [.toolbars]
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
      }
      window.contentViewController = hosting
      window.setContentSize(window.contentViewController!.view.fittingSize)
      window.level = .floating
      // Key and active, so controls draw as they do in use rather than as inactive.
      NSApp.activate()
      window.makeKeyAndOrderFront(nil)
      try? await Task.sleep(for: .milliseconds(screen == "Editor" || screen.hasPrefix("Video-") ? 3000 : 900))

      let out = folder.appendingPathComponent("\(screen)--\(variant.name).png")
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
      process.arguments = ["-x", "-o", "-l\(window.windowNumber)", out.path]
      try? process.run()
      process.waitUntilExit()
      print(
        process.terminationStatus == 0
          ? "captured \(out.lastPathComponent)" : "FAILED \(out.lastPathComponent)")
      window.orderOut(nil)
    }
  }
#endif
