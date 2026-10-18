import Testing

@testable import DropCore

@Test func versionIsSet() {
  #expect(!DropCore.version.isEmpty)
}
