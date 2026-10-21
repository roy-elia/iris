import AppKit
import Foundation
import PDFKit
import WebKit

/// Renders an HTML page to a paginated PDF with WebKit, so its CSS layout, images and tables
/// are kept (the attributed-text path keeps only the text and simple styling).
@MainActor
enum WebPDF {
  /// Styling for Markdown pages, which have none of their own.
  nonisolated static let markdownStyle = """
    body{font:11pt/1.5 -apple-system,sans-serif;margin:0}
    table{border-collapse:collapse}td,th{border:1px solid #bbb;padding:4px 8px}
    code,pre{font-family:ui-monospace,Menlo,monospace;background:#f4f4f4}
    pre{padding:8px;white-space:pre-wrap}
    blockquote{border-left:3px solid #ccc;margin-left:0;padding-left:1em;color:#555}
    img{max-width:100%}
    """

  /// How long loading may take before the caller falls back.
  static let timeout: TimeInterval = 60

  static func render(html: String, baseURL: URL?, to destination: URL) async throws {
    let width = RichText.pageSize.width - 2 * RichText.pageMargin
    // Nothing is fetched from the network and no script runs: remote references are
    // stripped as for every HTML read, and a content rule blocks any request that remains.
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = false
    configuration.userContentController.add(try await offlineRules())
    let view = WKWebView(
      frame: CGRect(x: 0, y: 0, width: width, height: RichText.pageSize.height), configuration: configuration)
    let loader = Loader()
    view.navigationDelegate = loader
    view.loadHTMLString(RichText.stripRemote(html), baseURL: baseURL)
    try await loader.wait(timeout: timeout)

    // WebKit makes one page as tall as the document, which is then cut into Letter pages.
    let tall = try await view.pdf(configuration: WKPDFConfiguration())
    guard let doc = PDFDocument(data: tall), let page = doc.page(at: 0),
      (doc.string ?? "").contains(where: { !$0.isWhitespace })
    else { throw DropError.writeFailed(destination.lastPathComponent) }
    try paginate(page, to: destination)
  }

  /// A content rule list that blocks every web and WebSocket request.
  static func offlineRules() async throws -> WKContentRuleList {
    let rules = #"[{"trigger":{"url-filter":"^(https?|wss?|ftp)://"},"action":{"type":"block"}}]"#
    guard
      let list = try await WKContentRuleListStore.default().compileContentRuleList(
        forIdentifier: "FileDropUtility.offline", encodedContentRuleList: rules)
    else { throw DropError.wrongInput("The page couldn't be rendered offline.") }
    return list
  }

  /// Draws `page` onto Letter pages, breaking between lines of text so none is cut in half.
  static func paginate(_ page: PDFPage, to destination: URL) throws {
    let bounds = page.bounds(for: .mediaBox)
    let margin = RichText.pageMargin
    let usable = RichText.pageSize.height - 2 * margin
    let scale = min(1, (RichText.pageSize.width - 2 * margin) / bounds.width)
    let sliceHeight = usable / scale
    // Line boxes measured from the top of the tall page.
    let lines = (page.selection(for: bounds)?.selectionsByLine() ?? []).map { line -> ClosedRange<CGFloat> in
      let box = line.bounds(for: page)
      return (bounds.maxY - box.maxY)...(bounds.maxY - box.minY)
    }
    var cuts: [CGFloat] = [0]
    while bounds.height - cuts.last! > sliceHeight {
      var cut = cuts.last! + sliceHeight
      // Move the cut up to the top of any line it would split, unless that line starts the slice.
      if let split = lines.first(where: { $0.contains(cut) && $0.lowerBound > cuts.last! + 1 }) {
        cut = split.lowerBound
      }
      cuts.append(cut)
    }
    cuts.append(bounds.height)

    var box = CGRect(origin: .zero, size: RichText.pageSize)
    guard let context = CGContext(destination as CFURL, mediaBox: &box, nil) else {
      throw DropError.writeFailed(destination.lastPathComponent)
    }
    for (top, bottom) in zip(cuts, cuts.dropFirst()) {
      context.beginPDFPage(nil)
      context.saveGState()
      // Clip to the slice's area on the page, then shift the tall page so the slice lands there.
      let height = (bottom - top) * scale
      context.clip(
        to: CGRect(
          x: margin, y: RichText.pageSize.height - margin - height, width: box.width - 2 * margin,
          height: height))
      context.translateBy(x: margin, y: RichText.pageSize.height - margin)
      context.scaleBy(x: scale, y: scale)
      context.translateBy(x: -bounds.minX, y: -(bounds.maxY - top))
      page.draw(with: .mediaBox, to: context)
      context.restoreGState()
      context.endPDFPage()
    }
    context.closePDF()
  }

  /// Waits for the page (and the images it loads) to finish.
  final class Loader: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var done = false

    func wait(timeout: TimeInterval) async throws {
      try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
        continuation = c
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
          MainActor.assumeIsolated { self?.finish(DropError.wrongInput("The page took too long to load.")) }
        }
      }
    }

    private func finish(_ error: Error?) {
      guard !done, let continuation else { return }
      done = true
      if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(nil) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
      finish(error)
    }
    func webView(
      _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error
    ) { finish(error) }
  }
}
