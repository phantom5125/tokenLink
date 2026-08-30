import Foundation
import Testing

@testable import TokenLinkCore

private func at(_ seconds: TimeInterval) -> Date {
  Date(timeIntervalSince1970: seconds)
}

@Test func workItemStateRawValuesMatchWireFormat() throws {
  #expect(WorkItemState.running.rawValue == "running")
  #expect(WorkItemState.needsInput.rawValue == "needs_input")
  #expect(WorkItemState.completed.rawValue == "complete")
  #expect(WorkItemState.failed.rawValue == "failed")
  #expect(WorkItemState.unknown.rawValue == "unknown")
  #expect(WorkItemState.running.isActive)
  #expect(WorkItemState.needsInput.isActive)
  #expect(!WorkItemState.completed.isActive)
  #expect(!WorkItemState.failed.isActive)
  #expect(
    [
      WorkItemState.needsInput,
      .failed,
      .running,
      .completed,
      .unknown,
    ].map(\.watchDisplayPriority) == [0, 1, 2, 3, 4])
  let data = try JSONEncoder().encode(WorkItemState.needsInput)
  #expect(String(decoding: data, as: UTF8.self) == "\"needs_input\"")
}

@Test func reportedActiveCountIsIndependentOfThreeDisplaySlots() async {
  let store = WorkItemStore()
  _ = await store.upsert(
    id: "a", name: "a", source: .codex, state: .running, updatedAt: at(100))
  #expect(await store.activeSessionCount == 1)

  await store.reportActiveSessionCount(5)
  #expect(await store.activeSessionCount == 5)
  #expect(await store.items.count == 1)
}

@Test func sanitizedNameTruncatesToTwelveASCII() {
  #expect(WorkItem.sanitizedName("fix-ci-pipeline") == "fix-ci-pipel")
  #expect(WorkItem.sanitizedName("review") == "review")
}

@Test func sanitizedNameFiltersNonASCIIAndFallsBack() {
  #expect(WorkItem.sanitizedName("检查 IPv6 支持") == "IPv6")
  #expect(WorkItem.sanitizedName("检查支持") == "task")
  #expect(WorkItem.sanitizedName("  \n\t") == "task")
  #expect(WorkItem.sanitizedName("", fallback: "thread") == "thread")
}

@Test func storeAssignsLowestFreeSlotInOrder() async {
  let store = WorkItemStore()
  let a = await store.upsert(
    id: "a", name: "a", source: .codex, state: .running, updatedAt: at(100))
  let b = await store.upsert(
    id: "b", name: "b", source: .codex, state: .running, updatedAt: at(200))
  let c = await store.upsert(
    id: "c", name: "c", source: .codex, state: .running, updatedAt: at(300))
  #expect(a?.slot == 0)
  #expect(b?.slot == 1)
  #expect(c?.slot == 2)
  let slots = await store.items.map(\.slot)
  #expect(slots == [0, 1, 2])
}

@Test func storeReusesSlotAfterRemove() async {
  let store = WorkItemStore()
  _ = await store.upsert(id: "a", name: "a", source: .codex, state: .running, updatedAt: at(100))
  _ = await store.upsert(id: "b", name: "b", source: .codex, state: .running, updatedAt: at(200))
  await store.remove(id: "a")
  let c = await store.upsert(
    id: "c", name: "c", source: .codex, state: .running, updatedAt: at(300))
  #expect(c?.slot == 0)
}

@Test func completeProviderPollRemovesOnlyMissingItemsFromThatProvider() async {
  let store = WorkItemStore()
  _ = await store.upsert(
    id: "keep", name: "keep", source: .codex, state: .running,
    updatedAt: at(100))
  _ = await store.upsert(
    id: "remove", name: "remove", source: .codex, state: .completed,
    updatedAt: at(200))
  _ = await store.upsert(
    id: "other", name: "other", source: .kimi, state: .running,
    updatedAt: at(300))

  await store.removeMissing(source: .codex, keepingIDs: ["keep"])

  #expect(Set(await store.items.map(\.id)) == Set(["keep", "other"]))
}

@Test func storeEvictsLeastRecentlyActiveAtCapacity() async {
  let store = WorkItemStore()
  _ = await store.upsert(id: "a", name: "a", source: .codex, state: .running, updatedAt: at(100))
  _ = await store.upsert(id: "b", name: "b", source: .codex, state: .running, updatedAt: at(200))
  _ = await store.upsert(id: "c", name: "c", source: .codex, state: .running, updatedAt: at(300))

  let d = await store.upsert(
    id: "d", name: "d", source: .codex, state: .running, updatedAt: at(400))

  #expect(d?.slot == 0)
  let ids = await store.items.map(\.id)
  #expect(ids == ["d", "b", "c"])
  #expect(await store.item(forSlot: 0)?.id == "d")
}

@Test func storeDropsStaleNewItemWhenFull() async {
  let store = WorkItemStore()
  _ = await store.upsert(id: "a", name: "a", source: .codex, state: .running, updatedAt: at(100))
  _ = await store.upsert(id: "b", name: "b", source: .codex, state: .running, updatedAt: at(200))
  _ = await store.upsert(id: "c", name: "c", source: .codex, state: .running, updatedAt: at(300))

  let stale = await store.upsert(
    id: "stale", name: "s", source: .codex, state: .completed, updatedAt: at(50))

  #expect(stale == nil)
  #expect(await store.items.count == 3)
}

@Test func actionableItemReplacesLessUsefulRecentItemAndKeepsOtherSlotsStable() async {
  let store = WorkItemStore()
  _ = await store.upsert(
    id: "running", name: "running", source: .codex, state: .running,
    updatedAt: at(300))
  _ = await store.upsert(
    id: "done", name: "done", source: .codex, state: .completed,
    updatedAt: at(500))
  _ = await store.upsert(
    id: "failed", name: "failed", source: .codex, state: .failed,
    updatedAt: at(200))

  let needsInput = await store.upsert(
    id: "approval", name: "approval", source: .codex, state: .needsInput,
    updatedAt: at(100))

  #expect(needsInput?.slot == 1)
  #expect(await store.item(forSlot: 0)?.id == "running")
  #expect(await store.item(forSlot: 1)?.id == "approval")
  #expect(await store.item(forSlot: 2)?.id == "failed")
}

@Test func recentCompletionCannotDisplaceActiveOrActionableItems() async {
  let store = WorkItemStore()
  _ = await store.upsert(
    id: "input", name: "input", source: .codex, state: .needsInput,
    updatedAt: at(100))
  _ = await store.upsert(
    id: "failed", name: "failed", source: .codex, state: .failed,
    updatedAt: at(200))
  _ = await store.upsert(
    id: "running", name: "running", source: .codex, state: .running,
    updatedAt: at(300))

  let completed = await store.upsert(
    id: "done", name: "done", source: .codex, state: .completed,
    updatedAt: at(1_000))

  #expect(completed == nil)
  #expect(Set(await store.items.map(\.id)) == Set(["input", "failed", "running"]))
}

@Test func upsertRefreshesExistingItemInPlace() async {
  let store = WorkItemStore()
  _ = await store.upsert(id: "a", name: "old", source: .codex, state: .running, updatedAt: at(100))
  let updated = await store.upsert(
    id: "a", name: "new", source: .codex, state: .completed, updatedAt: at(200))
  #expect(updated?.slot == 0)
  #expect(updated?.name == "new")
  #expect(updated?.state == .completed)
  #expect(updated?.updatedAt == at(200))
  #expect(await store.items.count == 1)
}

@Test func customNameSurvivesLaterPolls() async {
  let store = WorkItemStore()
  _ = await store.upsert(id: "a", name: "poll", source: .codex, state: .running, updatedAt: at(100))
  await store.rename(id: "a", to: "my-review")
  let refreshed = await store.upsert(
    id: "a", name: "poll-v2", source: .codex, state: .completed, updatedAt: at(200))
  #expect(refreshed?.name == "my-review")
  #expect(refreshed?.state == .completed)
  #expect(refreshed?.isCustomNamed == true)
}

@Test func renameIsSanitizedAndMissingItemIsIgnored() async {
  let store = WorkItemStore()
  _ = await store.upsert(id: "a", name: "a", source: .codex, state: .running, updatedAt: at(100))
  await store.rename(id: "a", to: "a-very-long-custom-name")
  #expect(await store.item(forSlot: 0)?.name == "a-very-long-")
  await store.rename(id: "ghost", to: "x")
  #expect(await store.items.count == 1)
}

@Test func payloadItemsAreSortedBySlotWithWireFields() async {
  let store = WorkItemStore()
  _ = await store.upsert(
    id: "a", name: "review", source: .codex, state: .running, updatedAt: at(100))
  _ = await store.upsert(
    id: "b", name: "fix-ci", source: .codex, state: .needsInput, updatedAt: at(200))
  let payload = await store.payloadItems()
  #expect(
    payload == [
      WorkItemPayload(slot: 0, name: "review", source: "codex", state: .running),
      WorkItemPayload(
        slot: 1, name: "fix-ci", source: "codex", state: .needsInput, latest: true),
    ])
}
