import Foundation

/// A unit of work that turns inputs into output files.
public protocol Job: Sendable {
  var title: String { get }
  /// Media jobs share a smaller concurrency limit than quick image and file jobs.
  var isHeavy: Bool { get }
  func run(_ context: JobContext) async throws -> OperationResult
}

extension Job {
  public var isHeavy: Bool { false }
}

/// What a running job can use: progress reporting and cancellation checks.
public struct JobContext: Sendable {
  let report: @Sendable (Double) -> Void

  /// Reports progress from 0 to 1. Values are clamped and never go backwards.
  public func progress(_ fraction: Double) { report(fraction) }

  public func checkCancelled() throws { try Task.checkCancellation() }
}

/// A job's state as seen from outside.
public enum JobState: Equatable, Sendable {
  case queued
  case running(progress: Double)
  case finished(OperationResult)
  case failed(String)
  case cancelled
}

/// A submitted job: watch its state, await its result, or cancel it.
public final class JobHandle: @unchecked Sendable, Identifiable {
  public let id = UUID()
  public let title: String
  private let lock = NSLock()
  private var _state: JobState = .queued
  private var observers: [@Sendable (JobState) -> Void] = []
  fileprivate var task: Task<OperationResult?, Never>?

  init(title: String) { self.title = title }

  public var state: JobState { lock.withLock { _state } }

  /// Calls `observer` now and on every change, on an arbitrary thread.
  public func observe(_ observer: @escaping @Sendable (JobState) -> Void) {
    let current = lock.withLock {
      observers.append(observer)
      return _state
    }
    observer(current)
  }

  public func cancel() { task?.cancel() }

  /// The job's result, or nil if it failed or was cancelled.
  public func result() async -> OperationResult? { await task?.value ?? nil }

  fileprivate func set(_ newState: JobState) {
    let toNotify: [@Sendable (JobState) -> Void] = lock.withLock {
      // Progress only moves forward; terminal states are final.
      switch (_state, newState) {
      case (.finished, _), (.failed, _), (.cancelled, _): return []
      case (.running(let old), .running(let new)) where new <= old: return []
      default:
        _state = newState
        return observers
      }
    }
    for observer in toNotify { observer(newState) }
  }
}

/// Runs jobs concurrently, with separate limits for quick and heavy (media) work.
public actor JobEngine {
  public static let shared = JobEngine()

  private let quick: Gate
  private let heavy: Gate

  public init(quickLimit: Int = 4, heavyLimit: Int = 2) {
    quick = Gate(limit: quickLimit)
    heavy = Gate(limit: heavyLimit)
  }

  @discardableResult
  public nonisolated func submit(_ job: some Job) -> JobHandle {
    let handle = JobHandle(title: job.title)
    let gate = job.isHeavy ? heavy : quick
    handle.task = Task {
      await gate.enter()
      defer { Task { await gate.leave() } }
      guard !Task.isCancelled else {
        handle.set(.cancelled)
        return nil
      }
      handle.set(.running(progress: 0))
      let context = JobContext { fraction in
        handle.set(.running(progress: min(max(fraction, 0), 1)))
      }
      do {
        let result = try await job.run(context)
        try Task.checkCancellation()
        handle.set(.finished(result))
        return result
      } catch is CancellationError {
        handle.set(.cancelled)
        return nil
      } catch {
        handle.set(.failed(error.localizedDescription))
        return nil
      }
    }
    return handle
  }
}

/// A counting semaphore for async code.
actor Gate {
  private let limit: Int
  private var running = 0
  private var waiters: [CheckedContinuation<Void, Never>] = []

  init(limit: Int) { self.limit = max(1, limit) }

  func enter() async {
    if running < limit {
      running += 1
      return
    }
    await withCheckedContinuation { waiters.append($0) }
  }

  func leave() {
    if waiters.isEmpty {
      running = max(0, running - 1)
    } else {
      waiters.removeFirst().resume()  // The slot passes straight to the next waiter.
    }
  }
}

/// Wraps the existing synchronous `Processor` operations as jobs.
public struct ProcessorJob: Job {
  public let operation: FileOperation
  public let files: [DroppedFile]
  public let settings: AppSettings

  public init(operation: FileOperation, files: [DroppedFile], settings: AppSettings) {
    self.operation = operation
    self.files = files
    self.settings = settings
  }

  public var title: String { operation.summary }

  public func run(_ context: JobContext) async throws -> OperationResult {
    let processor = Processor(settings: settings)
    context.progress(0.05)
    let result = processor.run(operation, on: files)
    context.progress(1)
    return result
  }
}
