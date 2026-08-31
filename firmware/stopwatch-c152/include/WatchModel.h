// SPDX-License-Identifier: MIT
// Watch-side model for protocol v2: per-provider quota windows, named work
// items, and Mac-pushed settings. Pure logic; unit-tested in simulator/.

#pragma once

#include <array>
#include <cstdint>
#include <cstring>

#include "WatchProtocolV2.h"

namespace watch_model {

// TokenLink currently supports five quota sources. The Quota page scrolls a
// four-row viewport, while the store keeps every enabled source so vertical
// selection never silently evicts one during a multi-payload sync.
constexpr std::size_t kMaxProviders = 5;

struct ProviderEntry {
  bool valid = false;
  char id[watch_v2::kProviderIdCapacity] = {};
  watch_v2::Window windows[watch_v2::kMaxWindows] = {};
  std::uint8_t windowCount = 0;
  std::uint32_t receivedAtMs = 0;
  std::uint32_t syncedAt = 0;
  bool hasSyncedAt = false;
};

// A window plus the provider it belongs to, for the P0 "most constrained"
// summary and the P1 rows.
struct TightestWindow {
  std::int8_t providerIndex = -1;
  std::int8_t windowIndex = -1;
};

class Store {
 public:
  // Applies one v2 payload. Work items are Mac-managed as a full slot set:
  // a payload that carries the work_items key replaces the whole set, while a
  // payload without it leaves the previous set untouched. Returns true when
  // anything visible changed.
  bool apply(const watch_v2::Payload& payload, std::uint32_t nowMs) {
    bool changed = false;

    ProviderEntry* entry = findProvider(payload.providerId);
    if (entry == nullptr) entry = allocateProvider(payload.providerId);
    if (entry == nullptr) return false;

    if (payload.windowCount > 0) {
      entry->windowCount = payload.windowCount;
      for (std::uint8_t i = 0; i < payload.windowCount; ++i) {
        entry->windows[i] = payload.windows[i];
      }
      changed = true;
    }
    entry->receivedAtMs = nowMs;
    entry->syncedAt = payload.syncedAt;
    entry->hasSyncedAt = payload.hasSyncedAt;

    // work_items is a Mac-managed full slot set. Presence replaces the whole
    // set, including an explicitly empty array; absence leaves slots alone.
    if (payload.hasWorkItems) {
      workItemCount_ = payload.workItemCount;
      for (std::uint8_t i = 0; i < payload.workItemCount; ++i) {
        workItems_[i] = payload.workItems[i];
      }
      changed = true;
    }

    if (payload.hasActiveCount &&
        (!hasActiveCount_ || activeCount_ != payload.activeCount)) {
      activeCount_ = payload.activeCount;
      hasActiveCount_ = true;
      changed = true;
    }

    bool settingsChanged = false;
    if (payload.settings.hasFace && settings_.face != payload.settings.face) {
      settings_.face = payload.settings.face;
      settingsChanged = true;
    }
    if (payload.settings.hasWake && settings_.wake != payload.settings.wake) {
      settings_.wake = payload.settings.wake;
      settingsChanged = true;
    }
    if (payload.settings.hasHourFormat &&
        settings_.hourFormat != payload.settings.hourFormat) {
      settings_.hourFormat = payload.settings.hourFormat;
      settingsChanged = true;
    }
    if (settingsChanged) {
      ++settingsVersion_;
      changed = true;
    }
    return changed;
  }

  const ProviderEntry* providerAt(std::size_t index) const {
    std::size_t seen = 0;
    for (const ProviderEntry& entry : providers_) {
      if (!entry.valid) continue;
      if (seen == index) return &entry;
      ++seen;
    }
    return nullptr;
  }

  std::size_t providerCount() const {
    std::size_t count = 0;
    for (const ProviderEntry& entry : providers_) {
      count += entry.valid ? 1U : 0U;
    }
    return count;
  }

  // The window with the least remaining quota across every provider. This is
  // the single number the P0 home page answers with.
  TightestWindow tightest() const {
    TightestWindow result;
    for (std::size_t p = 0; p < providers_.size(); ++p) {
      const ProviderEntry& entry = providers_[p];
      if (!entry.valid) continue;
      for (std::size_t w = 0; w < entry.windowCount; ++w) {
        if (result.windowIndex < 0 ||
            entry.windows[w].remainingPercent <
                providers_[result.providerIndex]
                    .windows[result.windowIndex]
                    .remainingPercent) {
          result.providerIndex = static_cast<std::int8_t>(p);
          result.windowIndex = static_cast<std::int8_t>(w);
        }
      }
    }
    return result;
  }

  const watch_v2::WorkItem* workItems() const { return workItems_; }
  std::uint8_t workItemCount() const { return workItemCount_; }
  bool hasActiveCount() const { return hasActiveCount_; }
  std::uint16_t activeCount() const { return activeCount_; }

  const watch_v2::Settings& settings() const { return settings_; }
  // Bumped whenever a payload changes an effective setting, so the main loop
  // can persist and apply changes exactly once.
  std::uint32_t settingsVersion() const { return settingsVersion_; }

 private:
  ProviderEntry* findProvider(const char* id) {
    for (ProviderEntry& entry : providers_) {
      if (entry.valid && std::strcmp(entry.id, id) == 0) return &entry;
    }
    return nullptr;
  }

  ProviderEntry* allocateProvider(const char* id) {
    for (ProviderEntry& entry : providers_) {
      if (!entry.valid) {
        entry = ProviderEntry{};
        entry.valid = true;
        watch_v2::copyAscii(entry.id, sizeof(entry.id), id);
        return &entry;
      }
    }
    // Table full: evict the stalest entry so a newly enabled provider still
    // shows up instead of being silently dropped.
    ProviderEntry* oldest = &providers_[0];
    for (ProviderEntry& entry : providers_) {
      if (entry.receivedAtMs < oldest->receivedAtMs) oldest = &entry;
    }
    *oldest = ProviderEntry{};
    oldest->valid = true;
    watch_v2::copyAscii(oldest->id, sizeof(oldest->id), id);
    return oldest;
  }

  std::array<ProviderEntry, kMaxProviders> providers_ = {};
  watch_v2::WorkItem workItems_[watch_v2::kMaxWorkItems] = {};
  std::uint8_t workItemCount_ = 0;
  std::uint16_t activeCount_ = 0;
  bool hasActiveCount_ = false;
  watch_v2::Settings settings_ = {};
  std::uint32_t settingsVersion_ = 0;
};

}  // namespace watch_model
