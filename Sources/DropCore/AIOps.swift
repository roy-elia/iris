import AVFAudio
import CoreGraphics
import Foundation
import FoundationModels
import Speech
import Vision

/// On-device intelligence: speech transcription (Speech's `SpeechAnalyzer`), and summaries,
/// alt text and file names from Apple's on-device language model (FoundationModels). Nothing
/// leaves the Mac; macOS may download its speech model for a language the first time.
public enum AIOps {
  // MARK: Availability

  /// Why the language model can't be used right now, or nil when it can.
  public static var languageModelProblem: String? {
    switch SystemLanguageModel.default.availability {
    case .available: return nil
    case .unavailable(.appleIntelligenceNotEnabled):
      return "Turn on Apple Intelligence in System Settings to use this."
    case .unavailable(.deviceNotEligible): return "This Mac doesn't support Apple Intelligence."
    case .unavailable(.modelNotReady): return "Apple Intelligence is still getting ready. Try again shortly."
    case .unavailable: return "Apple Intelligence isn't available right now."
    }
  }

  public static var languageModelAvailable: Bool { languageModelProblem == nil }

  /// Text sent to the model in one request. The context window (4,096 tokens on current
  /// Macs) has to hold the instructions, the text and the answer.
  static let chunkCharacters = 3_500

  // MARK: Transcription

  /// Speech in an audio or video file as timed cues. Audio goes through ffmpeg first, so any
  /// format the app reads works.
  public static func transcribe(_ source: URL, locale preferred: Locale = .current) async throws
    -> [SubtitleCue]
  {
    let name = source.lastPathComponent
    var found = await SpeechTranscriber.supportedLocale(equivalentTo: preferred)
    if found == nil {
      found = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US"))
    }
    guard let locale = found else {
      throw DropError.wrongInput("Speech transcription isn't available on this Mac.")
    }

    let work = FileManager.default.temporaryDirectory.appendingPathComponent(
      "fdu-speech-\(UUID().uuidString).wav")
    defer { try? FileManager.default.removeItem(at: work) }
    let info = try await VideoOps.probe(source)
    guard info.hasAudio else { throw DropError.wrongInput("\(name) has no audio track.") }
    _ = try await ToolRunner.run(
      .ffmpeg,
      [
        "-hide_banner", "-nostdin", "-y", "-loglevel", "error", "-i", source.path, "-vn", "-ac", "1", "-ar",
        "16000",
        "-c:a", "pcm_s16le", work.path,
      ])

    let transcriber = SpeechTranscriber(
      locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
    // The first use of a language downloads its model (handled by macOS).
    if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
      try await request.downloadAndInstall()
    }
    let file = try AVAudioFile(forReading: work)
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    let collector = Task { () -> [Word] in
      var words: [Word] = []
      for try await result in transcriber.results {
        for run in result.text.runs {
          guard let range = run.audioTimeRange else { continue }
          let text = String(result.text[run.range].characters)
          words.append(Word(text: text, start: range.start.seconds, end: range.end.seconds))
        }
      }
      return words
    }
    if let last = try await analyzer.analyzeSequence(from: file) {
      try await analyzer.finalizeAndFinish(through: last)
    } else {
      await analyzer.cancelAndFinishNow()
    }
    let cues = cues(from: try await collector.value)
    guard !cues.isEmpty else { throw DropError.wrongInput("No speech was found in \(name).") }
    return cues
  }

  struct Word: Equatable {
    var text: String
    var start: Double
    var end: Double
  }

  static let maxCueCharacters = 84
  static let maxCueSeconds = 7.0
  static let pauseSplit = 0.8

  /// Groups timed words into subtitle cues: at most two short lines and seven seconds, broken
  /// at sentence ends and pauses.
  static func cues(from words: [Word]) -> [SubtitleCue] {
    var cues: [SubtitleCue] = []
    var current: [Word] = []
    func flush() {
      let text = current.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
      if !text.isEmpty, let first = current.first, let last = current.last {
        cues.append(SubtitleCue(start: first.start, end: max(last.end, first.start + 0.3), text: wrap(text)))
      }
      current = []
    }
    for word in words where !word.text.isEmpty {
      if let last = current.last {
        let length = current.map(\.text).joined().count + word.text.count
        let tooLong =
          length > maxCueCharacters || word.end - (current.first?.start ?? word.start) > maxCueSeconds
        let paused = word.start - last.end > pauseSplit
        let sentenceEnded = [".", "?", "!", "。", "？", "！"].contains {
          last.text.trimmingCharacters(in: .whitespaces).hasSuffix($0)
        }
        if tooLong || paused || (sentenceEnded && length > 20) { flush() }
      }
      current.append(word)
    }
    flush()
    return cues
  }

  /// Breaks a cue into two lines near the middle when it's long.
  static func wrap(_ text: String, width: Int = 42) -> String {
    guard text.count > width else { return text }
    let middle = text.index(text.startIndex, offsetBy: text.count / 2)
    let before = text[..<middle].lastIndex(of: " ")
    let after = text[middle...].firstIndex(of: " ")
    let split: String.Index? =
      switch (before, after) {
      case (let b?, let a?): text.distance(from: b, to: middle) <= text.distance(from: middle, to: a) ? b : a
      case (let b?, nil): b
      case (nil, let a?): a
      default: nil
      }
    guard let split else { return text }
    return text[..<split].trimmingCharacters(in: .whitespaces) + "\n"
      + text[split...].trimmingCharacters(in: .whitespaces)
  }

  // MARK: Language model

  static let tooLongMessage = "The text was too long for the on-device model."
  static let declinedMessage = "Apple Intelligence declined to work with this content."

  /// One request to the on-device model. `maxTokens` caps the reply, which keeps answers
  /// short and stops the model running on when the input is repetitive.
  static func ask(_ prompt: String, instructions: String, maxTokens: Int) async throws -> String {
    if let problem = languageModelProblem { throw DropError.wrongInput(problem) }
    let session = LanguageModelSession(instructions: instructions)
    do {
      let response = try await session.respond(
        to: prompt, options: GenerationOptions(maximumResponseTokens: maxTokens))
      let answer = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
      if isRefusal(answer) { throw DropError.wrongInput(declinedMessage) }
      return answer
    } catch let error as LanguageModelSession.GenerationError {
      switch error {
      case .guardrailViolation:
        throw DropError.wrongInput(declinedMessage)
      case .exceededContextWindowSize:
        throw DropError.wrongInput(tooLongMessage)
      case .unsupportedLanguageOrLocale:
        throw DropError.wrongInput("Apple Intelligence doesn't support this language yet.")
      default:
        throw DropError.wrongInput("Apple Intelligence couldn't finish: \(error.localizedDescription)")
      }
    }
  }

  /// Whether the model answered by declining instead of doing the task.
  static func isRefusal(_ answer: String) -> Bool {
    let start = answer.lowercased().replacingOccurrences(of: "’", with: "'")
    return [
      "i cannot", "i can't", "i'm sorry", "i am sorry", "sorry,", "i'm unable", "i am unable", "i apologize",
    ]
    .contains { start.hasPrefix($0) }
  }

  /// Splits long text at paragraph (or sentence) boundaries into model-sized pieces.
  static func chunks(_ text: String, size: Int = chunkCharacters) -> [String] {
    let cleaned = text.replacingOccurrences(of: "\r\n", with: "\n")
    guard cleaned.count > size else { return [cleaned] }
    var pieces: [String] = []
    var current = ""
    for paragraph in cleaned.components(separatedBy: "\n") {
      if current.count + paragraph.count + 1 > size, !current.isEmpty {
        pieces.append(current)
        current = ""
      }
      if paragraph.count > size {
        // A huge paragraph: cut at sentence ends.
        var rest = Substring(paragraph)
        while rest.count > size {
          let window = rest.prefix(size)
          let cut =
            window.lastIndex(where: { ".!?。".contains($0) }).map { rest.index(after: $0) } ?? window.endIndex
          pieces.append(String(rest[..<cut]))
          rest = rest[cut...]
        }
        current = String(rest)
      } else {
        current += (current.isEmpty ? "" : "\n") + paragraph
      }
    }
    if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { pieces.append(current) }
    return pieces
  }

  static let summaryInstructions = """
    You summarise documents for the person who owns them. Write in the same language as the text. \
    Be faithful to the text: never add facts that aren't in it. Use plain, direct sentences.
    """

  /// Bullet points for one part of a long document. Dense text (numbers, tables, other
  /// scripts) can still overflow the context window, so such a part is halved and retried.
  static func bulletPoints(_ piece: String, depth: Int = 0) async throws -> String {
    do {
      return try await ask(
        "Summarise this part of a longer document as 3 to 6 short bullet points:\n\n\(piece)",
        instructions: summaryInstructions, maxTokens: 250)
    } catch DropError.wrongInput(let message)
      where message == tooLongMessage && depth < 3 && piece.count > 400
    {
      let halves = chunks(piece, size: piece.count / 2 + 1)
      var points: [String] = []
      for half in halves { points.append(try await bulletPoints(half, depth: depth + 1)) }
      return points.joined(separator: "\n")
    }
  }

  /// A Markdown summary: a short overview paragraph, then key points. Long text is summarised
  /// in pieces and the pieces are then combined.
  public static func summarize(_ text: String, title: String) async throws -> String {
    let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard body.count >= 40 else { throw DropError.wrongInput("There isn't enough text to summarise.") }
    var notes = chunks(body)
    // Reduce until everything fits in one request.
    while notes.count > 1 || notes[0].count > chunkCharacters {
      var reduced: [String] = []
      for piece in notes { reduced.append(try await bulletPoints(piece)) }
      notes = chunks(reduced.joined(separator: "\n"))
    }
    let answer = try await ask(
      """
      Summarise the text below. Reply in exactly this format, with no other text:
      OVERVIEW: <two or three sentences>
      POINTS:
      - <key point>
      - <key point>
      (3 to 7 points)

      Text:
      \(notes[0])
      """,
      instructions: summaryInstructions, maxTokens: 400)
    return formatSummary(answer, title: title)
  }

  /// Turns the model's OVERVIEW/POINTS reply into Markdown (and tolerates loose replies).
  static func formatSummary(_ answer: String, title: String) -> String {
    var overview: [String] = []
    var points: [String] = []
    var inPoints = false
    for raw in answer.components(separatedBy: "\n") {
      let line = raw.trimmingCharacters(in: .whitespaces)
      if line.isEmpty { continue }
      if line.uppercased().hasPrefix("OVERVIEW:") {
        let rest = line.dropFirst("OVERVIEW:".count).trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { overview.append(rest) }
      } else if line.uppercased().hasPrefix("POINTS:") {
        inPoints = true
      } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
        inPoints = true
        points.append(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces))
      } else if inPoints {
        points.append(line)
      } else {
        overview.append(line)
      }
    }
    var md = "# Summary: \(title)\n\n"
    if !overview.isEmpty { md += overview.joined(separator: " ") + "\n\n" }
    if !points.isEmpty {
      md += "## Key points\n\n" + points.map { "- \($0)" }.joined(separator: "\n") + "\n\n"
    }
    md += "_Summarised on this Mac by Apple Intelligence. Check important details against the original._\n"
    return md
  }

  // MARK: Images

  /// What Vision finds in an image: labels, any text, and counts of people and animals.
  struct ImageFacts: Equatable {
    var labels: [String] = []
    var text: String = ""
    var faces = 0
    var animals: [String] = []
    var width = 0
    var height = 0

    var description: String {
      var parts: [String] = []
      if !labels.isEmpty {
        parts.append("Detected subjects (most confident first): \(labels.joined(separator: ", "))")
      }
      if faces > 0 { parts.append("People's faces: \(faces)") }
      if !animals.isEmpty { parts.append("Animals: \(animals.joined(separator: ", "))") }
      if !text.isEmpty { parts.append("Text in the image: \"\(text.prefix(300))\"") }
      parts.append("Shape: \(width >= height ? (width > height * 3 / 2 ? "wide" : "landscape") : "portrait")")
      return parts.joined(separator: "\n")
    }
  }

  static func imageFacts(_ url: URL) throws -> ImageFacts {
    let image = try ImageOps.loadOriented(try ImageInput.readableURL(for: url))
    var facts = ImageFacts(width: image.width, height: image.height)
    let classify = VNClassifyImageRequest()
    let text = VNRecognizeTextRequest()
    text.recognitionLevel = .accurate
    let faces = VNDetectFaceRectanglesRequest()
    let animals = VNRecognizeAnimalsRequest()
    try VNImageRequestHandler(cgImage: image).perform([classify, text, faces, animals])
    facts.labels = (classify.results ?? []).filter { $0.confidence > 0.15 }.prefix(8)
      .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
    facts.text = (text.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    facts.faces = faces.results?.count ?? 0
    facts.animals = (animals.results ?? []).compactMap { $0.labels.first?.identifier }
    return facts
  }

  static let altTextInstructions = """
    You write alt text for images so people using screen readers know what's in them. \
    Use only the detected facts you're given; don't invent colours, names, places or actions you weren't told about. \
    Never start with "Image of" or "Picture of".
    """

  /// One sentence of alt text (about 125 characters or fewer). Without the language model,
  /// it's put together from the detected facts.
  public static func altText(_ url: URL) async throws -> String {
    let facts = try imageFacts(url)
    guard languageModelAvailable else { return fallbackAltText(facts) }
    // If the model declines, the detected facts still make usable alt text.
    guard
      let answer = try? await ask(
        "Write one alt-text sentence, under 125 characters, for an image with these detected contents:\n\(facts.description)\nReply with the sentence only.",
        instructions: altTextInstructions, maxTokens: 80)
    else { return fallbackAltText(facts) }
    return cleanSentence(answer)
  }

  static func fallbackAltText(_ facts: ImageFacts) -> String {
    var parts: [String] = []
    if !facts.labels.isEmpty { parts.append(facts.labels.prefix(3).joined(separator: ", ")) }
    if facts.faces > 0 { parts.append(facts.faces == 1 ? "one person" : "\(facts.faces) people") }
    if !facts.text.isEmpty { parts.append("with the text \"\(facts.text.prefix(60))\"") }
    let body = parts.isEmpty ? "An image" : parts.joined(separator: "; ")
    return body.prefix(1).uppercased() + body.dropFirst()
  }

  static func cleanSentence(_ s: String) -> String {
    var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if let first = t.components(separatedBy: "\n").first { t = first }
    t = t.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’ "))
    for prefix in ["Alt text:", "Alt-text:", "Image of ", "Picture of ", "A picture of ", "An image of "]
    where t.lowercased().hasPrefix(prefix.lowercased()) {
      t = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
      t = t.prefix(1).uppercased() + t.dropFirst()
    }
    return t
  }

  // MARK: Names from content

  static let nameInstructions = """
    You suggest short, descriptive file names. Reply with the name only: 2 to 6 words in Title Case, \
    no file extension, no quotes, no punctuation except hyphens. Base it only on the content you're given.
    """

  /// A descriptive name (without extension) for a file, from what's in it.
  public static func suggestedName(for file: DroppedFile) async throws -> String {
    if let problem = languageModelProblem { throw DropError.wrongInput(problem) }
    let content: String
    switch file.kind {
    case .image:
      content = "An image. " + (try imageFacts(file.url)).description
    case .audio, .video:
      let words = try await transcribe(file.url).map(\.text).joined(separator: " ")
      content = "A recording. Transcript: " + String(words.prefix(2_500))
    case .document, .pdf, .office:
      let text = try await RichText.load(file.url, kind: file.kind).string
      content =
        "A document. Its text begins: "
        + String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_500))
    default:
      throw DropError.wrongInput("Naming from content works on images, documents, PDFs, audio and video.")
    }
    let answer = try await ask(
      "Suggest a file name for this content:\n\n\(content)", instructions: nameInstructions, maxTokens: 30)
    let name = sanitizedName(answer)
    guard !name.isEmpty else { throw DropError.wrongInput("No name could be worked out for \(file.name).") }
    return name
  }

  /// Makes a model's reply safe as a file name.
  static func sanitizedName(_ raw: String) -> String {
    var s = raw.components(separatedBy: "\n").first ?? raw
    s = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’`*. \t"))
    if let dot = s.lastIndex(of: "."), s.distance(from: dot, to: s.endIndex) <= 5 { s = String(s[..<dot]) }
    let banned = CharacterSet(charactersIn: "/\\:*?\"<>|\u{0}").union(.controlCharacters).union(.newlines)
    s = String(String.UnicodeScalarView(s.unicodeScalars.filter { !banned.contains($0) }))
    s = s.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
    if s.count > 60 {
      s = String(s.prefix(60))
      if let space = s.lastIndex(of: " ") { s = String(s[..<space]) }
    }
    return s
  }

  /// Renames the file in its folder (contents untouched), keeping the extension. Returns the
  /// new location; an existing name gets " (1)" and so on.
  public static func rename(_ url: URL, to stem: String, fileManager: FileManager = .default) throws -> URL {
    let ext = url.pathExtension
    let desired = url.deletingLastPathComponent().appendingPathComponent(
      ext.isEmpty ? stem : "\(stem).\(ext)")
    if desired.standardizedFileURL == url.standardizedFileURL { return url }
    let target = OutputNamer.uniqueURL(for: desired, fileManager: fileManager)
    try fileManager.moveItem(at: url, to: target)
    return target
  }

  /// Puts renamed files back under their old names (when those names are still free).
  public static func undo(_ renames: [OperationResult.Rename], fileManager: FileManager = .default)
    -> [String]
  {
    var problems: [String] = []
    for r in renames.reversed() {
      if fileManager.fileExists(atPath: r.from.path) {
        problems.append(
          "\(r.from.lastPathComponent) already exists, so \(r.to.lastPathComponent) kept its new name.")
        continue
      }
      do { try fileManager.moveItem(at: r.to, to: r.from) } catch {
        problems.append("\(r.to.lastPathComponent): \(error.localizedDescription)")
      }
    }
    return problems
  }
}
