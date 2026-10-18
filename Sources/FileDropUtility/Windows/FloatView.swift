import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A small always-on-top glass card holding one file. Drag the preview out to drop the
/// file somewhere else.
struct FloatView: View {
  let url: URL
  @State private var thumbnail: NSImage?

  var body: some View {
    VStack(spacing: 8) {
      HStack {
        Text(url.lastPathComponent)
          .font(.caption.weight(.medium))
          .lineLimit(1)
          .truncationMode(.middle)
        Spacer()
        Button {
          WindowManager.shared.closeFloat(for: url)
        } label: {
          Image(systemName: "xmark")
            .font(.caption.weight(.bold))
            .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .accessibilityLabel("Close")
      }
      // The header moves the window; the preview below drags the file itself.
      .contentShape(Rectangle())
      .gesture(WindowDragGesture())
      .allowsWindowActivationEvents(true)
      Group {
        if let thumbnail {
          Image(nsImage: thumbnail).resizable().scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.control, style: .continuous))
        } else {
          Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit().padding(30)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .onDrag { NSItemProvider(object: url as NSURL) }
      .accessibilityLabel("Preview of \(url.lastPathComponent). Drag to move the file.")
    }
    .padding(DesignTokens.Spacing.cardPadding)
    .glassPanel(cornerRadius: DesignTokens.Radius.window)
    .padding(DesignTokens.Spacing.inset)
    .task {
      thumbnail = NSImage(contentsOf: url)
    }
  }
}
