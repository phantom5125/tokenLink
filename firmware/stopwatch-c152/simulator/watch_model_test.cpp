#include <ArduinoJson.h>

#include <cassert>
#include <cstring>

#include "WatchModel.h"

namespace {

watch_v2::Payload makePayload(const char* provider, float percent) {
  watch_v2::Payload payload;
  watch_v2::copyAscii(payload.providerId, sizeof(payload.providerId), provider);
  payload.windowCount = 1;
  watch_v2::copyAscii(payload.windows[0].id, sizeof(payload.windows[0].id),
                      "week");
  payload.windows[0].remainingPercent = percent;
  payload.windows[0].resetInSeconds = 3600;
  return payload;
}

}  // namespace

int main() {
  watch_model::Store store;

  assert(store.providerCount() == 0);
  assert(store.tightest().providerIndex < 0);

  // Two providers; the tighter window wins regardless of arrival order.
  store.apply(makePayload("codex", 72.0f), 1000);
  store.apply(makePayload("kimi", 35.0f), 2000);
  assert(store.providerCount() == 2);
  watch_model::TightestWindow tightest = store.tightest();
  assert(tightest.providerIndex >= 0 && tightest.windowIndex == 0);
  const watch_model::ProviderEntry* tight =
      store.providerAt(static_cast<std::size_t>(tightest.providerIndex));
  assert(tight != nullptr && std::strcmp(tight->id, "kimi") == 0);

  // Re-applying the same provider updates in place.
  store.apply(makePayload("kimi", 90.0f), 3000);
  assert(store.providerCount() == 2);
  tightest = store.tightest();
  tight = store.providerAt(static_cast<std::size_t>(tightest.providerIndex));
  assert(tight != nullptr && std::strcmp(tight->id, "codex") == 0);

  // All five TokenLink providers fit. A sixth source evicts the stalest entry
  // instead of being dropped.
  store.apply(makePayload("glm", 50.0f), 4000);
  store.apply(makePayload("minimax", 60.0f), 5000);
  store.apply(makePayload("newco", 10.0f), 6000);
  assert(store.providerCount() == watch_model::kMaxProviders);
  bool sawCodex = false;
  for (std::size_t i = 0; i < store.providerCount(); ++i) {
    if (std::strcmp(store.providerAt(i)->id, "codex") == 0) sawCodex = true;
  }
  assert(sawCodex);
  store.apply(makePayload("claude", 15.0f), 7000);
  sawCodex = false;
  for (std::size_t i = 0; i < store.providerCount(); ++i) {
    if (std::strcmp(store.providerAt(i)->id, "codex") == 0) sawCodex = true;
  }
  assert(!sawCodex);  // codex was received at t=1000, the stalest entry
  tightest = store.tightest();
  tight = store.providerAt(static_cast<std::size_t>(tightest.providerIndex));
  assert(tight != nullptr && std::strcmp(tight->id, "newco") == 0);

  // Work items replace as a set; settings merge field by field.
  watch_v2::Payload payload = makePayload("codex", 80.0f);
  payload.hasWorkItems = true;
  payload.workItemCount = 2;
  payload.workItems[0].slot = 0;
  watch_v2::copyAscii(payload.workItems[0].name,
                      sizeof(payload.workItems[0].name), "review");
  payload.workItems[1].slot = 1;
  payload.workItems[1].state = watch_v2::WorkState::NeedsInput;
  payload.workItems[1].latest = true;
  payload.activeCount = 5;
  payload.hasActiveCount = true;
  payload.settings.theme = watch_v2::Theme::Pet;
  payload.settings.hasTheme = true;
  store.apply(payload, 8000);
  assert(store.workItemCount() == 2);
  assert(store.workItems()[1].state == watch_v2::WorkState::NeedsInput);
  assert(store.workItems()[1].latest);
  assert(store.hasActiveCount());
  assert(store.activeCount() == 5);
  assert(store.settings().theme == watch_v2::Theme::Pet);
  assert(store.settings().wake == watch_v2::WakeMode::Raise);  // untouched

  // A payload without work_items keeps the previous set.
  store.apply(makePayload("codex", 70.0f), 9000);
  assert(store.workItemCount() == 2);

  // An explicitly empty work_items array clears stale rows.
  watch_v2::Payload empty = makePayload("codex", 65.0f);
  empty.hasWorkItems = true;
  store.apply(empty, 10000);
  assert(store.workItemCount() == 0);
}
