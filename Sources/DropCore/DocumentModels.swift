import AppKit
import Foundation

/// Text documents the app reads.
public enum DocumentFormat: String, CaseIterable, Codable, Sendable {
  case docx, doc, odt, rtf, rtfd, txt, md, html, epub, pages, textClipping

  public init?(fileExtension ext: String) {
    switch ext.lowercased() {
    case "docx": self = .docx
    case "doc": self = .doc
    case "odt": self = .odt
    case "rtf": self = .rtf
    case "rtfd": self = .rtfd
    case "txt", "text": self = .txt
    case "md", "markdown", "mdown": self = .md
    case "html", "htm", "xhtml": self = .html
    case "epub": self = .epub
    case "pages": self = .pages
    case "textclipping": self = .textClipping
    default: return nil
    }
  }

  public var displayName: String {
    switch self {
    case .md: "Markdown"
    case .html: "HTML"
    case .epub: "EPUB"
    case .pages: "Pages"
    case .textClipping: "Text Clipping"
    default: rawValue.uppercased()
    }
  }

  /// Formats that may be folders (bundles) on disk.
  public var mayBePackage: Bool { self == .rtfd || self == .pages }
}

/// Presentations, spreadsheets and tables, which convert to PDF.
public enum OfficeFormat: String, CaseIterable, Codable, Sendable {
  case key, ppt, pptx, numbers, xls, xlsx, ods, csv, tsv

  public init?(fileExtension ext: String) {
    self.init(rawValue: ext.lowercased())
  }

  public var displayName: String {
    switch self {
    case .key: "Keynote"
    case .numbers: "Numbers"
    default: rawValue.uppercased()
    }
  }

  public var mayBePackage: Bool { self == .key || self == .numbers }

  /// Tables the app reads itself (and can convert to any text output).
  public var isTable: Bool { self == .csv || self == .tsv }

  /// The iWork app that opens this format, when one is needed.
  public var app: IWorkApp? {
    switch self {
    case .key, .ppt, .pptx: .keynote
    case .numbers, .xls, .xlsx, .ods: .numbers
    case .csv, .tsv: nil
    }
  }
}

public enum IWorkApp: String, Sendable {
  case pages = "Pages"
  case keynote = "Keynote"
  case numbers = "Numbers"

  public var bundleID: String {
    switch self {
    case .pages: "com.apple.iWork.Pages"
    case .keynote: "com.apple.iWork.Keynote"
    case .numbers: "com.apple.iWork.Numbers"
    }
  }

  /// Whether the app is installed (looked up by bundle ID).
  public var isInstalled: Bool {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
  }
}

public enum SubtitleFormat: String, CaseIterable, Codable, Sendable {
  case srt, vtt

  public var displayName: String { rawValue.uppercased() }
}

/// What text documents, PDFs and tables convert to.
public enum DocumentOutput: String, CaseIterable, Codable, Sendable {
  case pdf, docx, rtf, txt, md, html, epub, pages
  /// An EPUB of page images, for PDFs.
  case epubFixed

  public var fileExtension: String {
    switch self {
    case .epubFixed: "epub"
    default: rawValue
    }
  }

  public var displayName: String {
    switch self {
    case .md: "Markdown"
    case .html: "HTML"
    case .epub: "EPUB"
    case .epubFixed: "EPUB (Pages)"
    case .pages: "Pages"
    case .txt: "Text"
    default: rawValue.uppercased()
    }
  }

  public var unavailableReason: String? {
    self == .pages && !IWorkApp.pages.isInstalled ? "Needs Pages" : nil
  }
}

/// One page in an organised PDF: which source page, turned by how much.
public struct PDFPageRef: Codable, Equatable, Hashable, Sendable {
  public var index: Int
  /// Clockwise, in multiples of 90.
  public var rotation: Int

  public init(index: Int, rotation: Int = 0) {
    self.index = index
    self.rotation = ((rotation % 360) + 360) % 360
  }
}

/// The pages of the organised PDF, in order. Pages left out are deleted.
public struct PDFPagePlan: Codable, Equatable, Hashable, Sendable {
  public var pages: [PDFPageRef]
  /// Scale every page to the widest page's width.
  public var equalWidths: Bool

  public init(pages: [PDFPageRef], equalWidths: Bool = false) {
    self.pages = pages
    self.equalWidths = equalWidths
  }

  public static func identity(pageCount: Int) -> PDFPagePlan {
    PDFPagePlan(pages: (0..<pageCount).map { PDFPageRef(index: $0) })
  }

  public func isIdentity(pageCount: Int) -> Bool { self == .identity(pageCount: pageCount) }
}
