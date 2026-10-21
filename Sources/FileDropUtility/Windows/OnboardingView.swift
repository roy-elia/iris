import DropCore
import SwiftUI

/// First-run walkthrough: welcome, the three wheels, folder access and finishing touches.
struct OnboardingView: View {
  let onFinish: () -> Void

  enum Page: Int, CaseIterable {
    case welcome, demo, convert, tools, actions, fileTypes, folders, finish
  }

  init(onFinish: @escaping () -> Void, startPage: Page = .welcome) {
    self.onFinish = onFinish
    _page = State(initialValue: startPage)
  }

  @EnvironmentObject private var model: AppModel
  @State private var page: Page
  @State private var folderStatus: String?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(spacing: 0) {
      Group {
        switch page {
        case .welcome: welcome
        case .demo: demo
        case .convert: wheelPage(.convert)
        case .tools: wheelPage(.tools)
        case .actions: wheelPage(.actions)
        case .fileTypes: fileTypes
        case .folders: folders
        case .finish: finish
        }
      }
      .id(page)
      .morphTransition(reduceMotion: reduceMotion)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      dots.padding(.bottom, 18)
    }
    .padding(.top, 28)
    .padding(.horizontal, DesignTokens.Spacing.inset)
  }

  // MARK: Pages

  private var welcome: some View {
    VStack(spacing: 18) {
      AppGlyphView()
        .frame(width: 64, height: 64)
        .foregroundStyle(DesignTokens.Palette.brandInk)
      Text("Welcome to").font(.title2).foregroundStyle(Color.secondary)
      Text("Iris").font(.largeTitle.weight(.bold))
      Text("Convert, fix and send files without opening another app.")
        .font(.title3)
        .foregroundStyle(Color.secondary)
        .multilineTextAlignment(.center)
      continueButton
    }
    .padding(32)
  }

  private var demo: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        backButton
        Spacer()
      }
      Text("See it in action").font(.largeTitle.weight(.bold))
      WheelDemoView()
        .frame(maxWidth: .infinity)
      HStack {
        Spacer()
        continueButton
      }
    }
    .padding(.horizontal, 36)
  }

  private func wheelPage(_ kind: WheelKind) -> some View {
    HStack(spacing: 36) {
      RadialWheel(kind: kind, items: kind.items(for: []), centerText: "2.4 MB", mode: .click) { _, _ in }
        .frame(width: 330, height: 330)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 18) {
        backButton
        Text(kind.longTitle).font(.largeTitle.weight(.bold))
        Text("1. Drag files").font(.title2.weight(.semibold))
        HStack(spacing: 12) {
          Text("2. Hold").font(.title2.weight(.semibold))
          Keycap(symbol: kind.keySymbol, name: kind.keyName)
        }
        Text(blurb(kind)).font(.callout).foregroundStyle(Color.secondary).fixedSize(
          horizontal: false, vertical: true)
        continueButton
      }
      .frame(maxWidth: 300, alignment: .leading)
    }
    .padding(.horizontal, 32)
  }

  /// What the wheels offer for each kind of file.
  private var fileTypes: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        backButton
        Spacer()
      }
      Text("The wheels fit the file").font(.largeTitle.weight(.bold))
      Text("Drop a different kind of file and each wheel offers what makes sense for it.")
        .font(.callout).foregroundStyle(Color.secondary)
      LazyVGrid(
        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12
      ) {
        ForEach(Self.fileTypeCards, id: \.title) { card in
          HStack(alignment: .top, spacing: 12) {
            Image(systemName: card.symbol)
              .font(.title2)
              .foregroundStyle(DesignTokens.Palette.brandInk)
              .frame(width: 30)
              .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
              Text(card.title).font(.headline)
              Text(card.detail).font(.caption).foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
          }
          .padding(12)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(.quinary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
          .accessibilityElement(children: .combine)
        }
      }
      HStack {
        Spacer()
        continueButton
      }
    }
    .padding(.horizontal, 36)
  }

  private static let fileTypeCards: [(symbol: String, title: String, detail: String)] = [
    (
      "photo", "Images",
      "Convert, compress to a size, metadata, annotate, redact, crop, backgrounds, frames, collages, QR codes."
    ),
    (
      "film", "Video",
      "MP4, MOV, WebM, GIF and more; compress, trim, split, join, speed, frames, crop and timed redaction."
    ),
    (
      "waveform", "Audio",
      "MP3, WAV, FLAC, Opus and more; trim silence, bleep, normalize loudness, channels, visualizer videos."
    ),
    (
      "doc.richtext", "Documents and PDFs",
      "Word, RTF, Markdown, HTML, EPUB and Pages; PDF to text or images, OCR, organize pages."
    ),
    (
      "captions.bubble", "Subtitles and archives",
      "SRT and VTT convert both ways; zip files unpack into a folder."
    ),
    (
      "paperclip", "Floats",
      "Park files in a glass tab at the screen edge, then drag them out wherever you need them."
    ),
  ]

  private var folders: some View {
    HStack(spacing: 36) {
      VStack(spacing: 14) {
        Image(systemName: "folder.fill.badge.person.crop")
          .font(.system(size: 96))
          .foregroundStyle(DesignTokens.Palette.brandInk)
          .accessibilityHidden(true)
        Button("Check Folder Access…") { checkFolders() }
          .buttonStyle(.glass).tint(nil)
          .accessibilityIdentifier("checkFolders")
        Text(folderStatus ?? "Skip for now and macOS will ask the first time it's needed.")
          .font(.caption)
          .foregroundStyle(Color.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 260)
      }
      .frame(width: 300)
      VStack(alignment: .leading, spacing: 16) {
        backButton
        Text("Folder access").font(.largeTitle.weight(.bold))
        Text(
          "Results are saved next to the originals. macOS asks once per protected folder (Desktop, Documents, Downloads). Checking now gets those prompts out of the way."
        )
        .font(.callout)
        .foregroundStyle(Color.secondary)
        .fixedSize(horizontal: false, vertical: true)
        continueButton
      }
      .frame(maxWidth: 300, alignment: .leading)
    }
    .padding(.horizontal, 32)
  }

  private var finish: some View {
    HStack(spacing: 36) {
      VStack(spacing: 10) {
        HStack(spacing: 14) {
          Image(systemName: "wifi").foregroundStyle(Color.secondary)
          AppGlyphView()
            .frame(width: 18, height: 18)
            .padding(8)
            .background(
              .tint.opacity(0.3),
              in: RoundedRectangle(cornerRadius: DesignTokens.Radius.chip, style: .continuous))
          Text("9:41").monospacedDigit()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .background(
          .quinary,
          in: RoundedRectangle(cornerRadius: DesignTokens.Radius.control, style: .continuous)
        )
        .accessibilityHidden(true)
        Image(systemName: "arrow.up")
          .foregroundStyle(DesignTokens.Palette.brandInk)
          .frame(maxWidth: .infinity, alignment: .trailing)
          .padding(.trailing, 70)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 10) {
          Toggle(
            "Launch at login",
            isOn: Binding(get: { model.settings.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
          Toggle("Wheels while dragging", isOn: $model.settings.wheelTriggerEnabled)
          if let error = model.settingsError {
            Text(error).font(.caption).foregroundStyle(Color.red)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .groupBoxed()
      }
      .frame(width: 320)
      VStack(alignment: .leading, spacing: 16) {
        backButton
        Text("Finish setup").font(.largeTitle.weight(.bold))
        Text("The app lives in the menu bar. You can change these and everything else in Settings.")
          .font(.callout)
          .foregroundStyle(Color.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Button("Done") {
          model.settings.hasCompletedOnboarding = true
          onFinish()
        }
        .primaryActionStyle()
        .keyboardShortcut(.defaultAction)
        .accessibilityIdentifier("onboardingDone")
      }
      .frame(maxWidth: 300, alignment: .leading)
    }
    .padding(.horizontal, 32)
  }

  // MARK: Pieces

  private var continueButton: some View {
    Button("Continue") { go(+1) }
      .primaryActionStyle()
      .keyboardShortcut(.defaultAction)
      .accessibilityIdentifier("onboardingContinue")
  }

  private var backButton: some View {
    Button {
      go(-1)
    } label: {
      Label("Back", systemImage: "arrow.left").font(.callout)
    }
    .buttonStyle(.plain)
    .foregroundStyle(Color.secondary)
    .accessibilityIdentifier("onboardingBack")
  }

  private var dots: some View {
    HStack(spacing: 7) {
      ForEach(Page.allCases, id: \.self) { p in
        Capsule(style: .continuous)
          .fill(p == page ? DesignTokens.Palette.brand : Color.secondary.opacity(0.4))
          .frame(width: p == page ? 18 : 7, height: 7)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Page \(page.rawValue + 1) of \(Page.allCases.count)")
  }

  private func go(_ delta: Int) {
    guard let next = Page(rawValue: page.rawValue + delta) else { return }
    withMorph(reduceMotion: reduceMotion) { page = next }
  }

  private func blurb(_ kind: WheelKind) -> String {
    switch kind {
    case .convert:
      "Change the format: images, videos, audio, documents, PDFs and subtitles each get the choices that fit them."
    case .tools:
      "Compress, edit and fix: crop, annotate, redact, trim, split, bleep, normalize, organize PDF pages and more."
    case .actions:
      "AirDrop, keep files in a Float at the screen edge, copy, move, copy paths or open a terminal in the folder."
    }
  }

  private func checkFolders() {
    let fm = FileManager.default
    let folders: [FileManager.SearchPathDirectory] = [
      .desktopDirectory, .documentDirectory, .downloadsDirectory,
    ]
    var allowed = 0
    for folder in folders {
      if let url = fm.urls(for: folder, in: .userDomainMask).first,
        (try? fm.contentsOfDirectory(atPath: url.path)) != nil
      {
        allowed += 1
      }
    }
    folderStatus =
      allowed == folders.count
      ? "All set: Desktop, Documents and Downloads are available."
      : "\(allowed) of \(folders.count) folders allowed. Change this in System Settings › Privacy & Security › Files and Folders."
  }
}
