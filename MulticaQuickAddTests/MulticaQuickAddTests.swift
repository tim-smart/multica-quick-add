import Testing

@testable import MulticaQuickAdd

struct MulticaQuickAddTests {
  @Test func appName() {
    #expect(AppMetadata.name == "Multica Quick Add")
  }
}
