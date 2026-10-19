import AppKit
import DropCore

/// Handles the Finder Quick Actions / Services menu items that `scripts/bundle.sh`
/// lists under NSServices. Every item sends `runQuickAction` with a `QuickAction`
/// spec (such as `convert-image:png`) as its NSUserData.
final class ServiceProvider: NSObject {
  @MainActor static let shared = ServiceProvider()

  @MainActor
  @objc func runQuickAction(
    _ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>
  ) {
    guard let spec = userData, let action = QuickAction(spec: spec) else {
      error.pointee = "File Drop Utility doesn't know this action." as NSString
      return
    }
    let urls =
      pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
      ?? []
    guard !urls.isEmpty else {
      error.pointee = "No files were selected." as NSString
      return
    }
    AppModel.shared.runQuickAction(action, on: urls)
  }
}
