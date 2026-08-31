// SPDX-License-Identifier: MIT
// Protocol v2 watch payload parsing. See docs/COMPANION_PROTOCOL.md and the
// TokenLink watch-face v2 design: the Mac writes one JSON object per provider
// to the quota characteristic; unknown fields are ignored by design.

#pragma once

#include <ArduinoJson.h>

#include <cmath>
#include <cstdint>
#include <cstring>

#include "WatchFaceRuntime.h"

namespace watch_v2 {

constexpr std::size_t kMaxWindows = 3;
constexpr std::size_t kMaxWorkItems = 3;
constexpr std::size_t kProviderIdCapacity = 13;   // 12 chars + NUL
constexpr std::size_t kWindowIdCapacity = 8;      // "5h" / "week" / "month"
constexpr std::size_t kWorkItemNameCapacity = 13; // 12 ASCII chars + NUL
constexpr std::size_t kWorkItemSourceCapacity = 9;

enum class WorkState : std::uint8_t {
  Running,
  NeedsInput,
  Complete,
  Failed,
  Unknown,
};

enum class WakeMode : std::uint8_t {
  Raise,  // BMI270 raise-to-wake plus tap
  Tap,    // tap only
};

enum class HourFormat : std::uint8_t {
  System,
  H12,
  H24,
};

struct Window {
  char id[kWindowIdCapacity] = {};
  float remainingPercent = 0.0f;
  std::uint32_t resetInSeconds = 0;
  std::uint32_t durationSeconds = 0;
  bool hasDuration = false;
};

struct WorkItem {
  std::uint8_t slot = 0;
  char name[kWorkItemNameCapacity] = {};
  char source[kWorkItemSourceCapacity] = {};
  WorkState state = WorkState::Unknown;
  bool latest = false;
  bool seen = false;
};

struct Settings {
  watch_face_runtime::FaceID face = watch_face_runtime::FaceID::Data;
  WakeMode wake = WakeMode::Raise;
  HourFormat hourFormat = HourFormat::System;
  bool hasFace = false;
  bool hasWake = false;
  bool hasHourFormat = false;
};

struct Payload {
  char providerId[kProviderIdCapacity] = {};
  Window windows[kMaxWindows];
  std::uint8_t windowCount = 0;
  WorkItem workItems[kMaxWorkItems];
  std::uint8_t workItemCount = 0;
  bool hasWorkItems = false;
  std::uint16_t activeCount = 0;
  bool hasActiveCount = false;
  std::uint32_t syncedAt = 0;
  bool hasSyncedAt = false;
  Settings settings;
};

// Copies at most capacity-1 ASCII bytes and always NUL-terminates. The Mac
// truncates names to 12 ASCII characters; the firmware truncates defensively
// and drops anything that is not printable ASCII.
inline void copyAscii(char* output, std::size_t capacity, const char* input) {
  std::size_t length = 0;
  if (input != nullptr) {
    while (length + 1 < capacity && input[length] != '\0') {
      const char c = input[length];
      if (c < 0x20 || c > 0x7E) break;
      output[length] = c;
      ++length;
    }
  }
  output[length] = '\0';
}

inline bool parseWorkState(const char* text, WorkState& state) {
  if (text == nullptr) return false;
  if (std::strcmp(text, "running") == 0) {
    state = WorkState::Running;
  } else if (std::strcmp(text, "needs_input") == 0) {
    state = WorkState::NeedsInput;
  } else if (std::strcmp(text, "complete") == 0) {
    state = WorkState::Complete;
  } else if (std::strcmp(text, "failed") == 0) {
    state = WorkState::Failed;
  } else if (std::strcmp(text, "unknown") == 0) {
    state = WorkState::Unknown;
  } else {
    return false;
  }
  return true;
}

inline const char* workStateName(WorkState state) {
  switch (state) {
    case WorkState::Running: return "RUNNING";
    case WorkState::NeedsInput: return "NEEDS INPUT";
    case WorkState::Complete: return "COMPLETE";
    case WorkState::Failed: return "FAILED";
    case WorkState::Unknown: return "UNKNOWN";
  }
  return "UNKNOWN";
}

// Returns true when the JSON object is a v2 payload (has "v": 2). Callers use
// this to pick the v2 path before invoking parse().
inline bool isV2Payload(JsonObjectConst value) {
  return value["v"].is<int>() && value["v"].as<int>() == 2;
}

// Tolerant v2 parse: a missing or malformed provider_id rejects the payload,
// while invalid individual windows/work items are skipped instead of failing
// the whole update. Unknown keys are ignored by ArduinoJson.
inline bool parse(JsonObjectConst value, Payload& output) {
  const char* providerId = value["provider_id"].as<const char*>();
  if (providerId == nullptr || providerId[0] == '\0') return false;
  copyAscii(output.providerId, sizeof(output.providerId), providerId);
  if (output.providerId[0] == '\0') return false;

  output.windowCount = 0;
  const JsonArrayConst windows = value["windows"].as<JsonArrayConst>();
  if (!windows.isNull()) {
    for (JsonObjectConst entry : windows) {
      if (output.windowCount >= kMaxWindows) break;
      const JsonVariantConst remaining = entry["remaining_percent"];
      const JsonVariantConst reset = entry["reset_in_seconds"];
      const char* id = entry["id"].as<const char*>();
      if (id == nullptr || !remaining.is<float>() ||
          !reset.is<std::uint32_t>()) {
        continue;
      }
      const float percent = remaining.as<float>();
      if (!std::isfinite(percent) || percent < 0.0f || percent > 100.0f) {
        continue;
      }
      Window& window = output.windows[output.windowCount];
      copyAscii(window.id, sizeof(window.id), id);
      if (window.id[0] == '\0') continue;
      window.remainingPercent = percent;
      window.resetInSeconds = reset.as<std::uint32_t>();
      const JsonVariantConst duration = entry["window_duration_seconds"];
      window.hasDuration = duration.is<std::uint32_t>() &&
                           duration.as<std::uint32_t>() > 0;
      window.durationSeconds =
          window.hasDuration ? duration.as<std::uint32_t>() : 0;
      ++output.windowCount;
    }
  }

  output.workItemCount = 0;
  const JsonArrayConst workItems = value["work_items"].as<JsonArrayConst>();
  output.hasWorkItems = !workItems.isNull();
  if (!workItems.isNull()) {
    for (JsonObjectConst entry : workItems) {
      if (output.workItemCount >= kMaxWorkItems) break;
      const JsonVariantConst slot = entry["slot"];
      const char* name = entry["name"].as<const char*>();
      if (!slot.is<int>() || name == nullptr) continue;
      const int slotValue = slot.as<int>();
      if (slotValue < 0 || slotValue > 2) continue;
      WorkState state;
      if (!parseWorkState(entry["state"].as<const char*>(), state)) continue;
      WorkItem& item = output.workItems[output.workItemCount];
      item.slot = static_cast<std::uint8_t>(slotValue);
      copyAscii(item.name, sizeof(item.name), name);
      if (item.name[0] == '\0') continue;
      copyAscii(item.source, sizeof(item.source), entry["source"] | "");
      item.state = state;
      item.latest = entry["latest"] | false;
      item.seen = entry["seen"] | false;
      ++output.workItemCount;
    }
  }

  output.hasActiveCount = false;
  const JsonVariantConst activeCount = value["active_count"];
  if (activeCount.is<int>()) {
    const int count = activeCount.as<int>();
    if (count >= 0 && count <= 65535) {
      output.activeCount = static_cast<std::uint16_t>(count);
      output.hasActiveCount = true;
    }
  }

  output.hasSyncedAt = value["synced_at"].is<std::uint32_t>();
  output.syncedAt =
      output.hasSyncedAt ? value["synced_at"].as<std::uint32_t>() : 0;

  const JsonObjectConst settings = value["settings"].as<JsonObjectConst>();
  if (!settings.isNull()) {
    const char* theme = settings["theme"].as<const char*>();
    watch_face_runtime::FaceID face;
    if (watch_face_runtime::resolve(theme, face)) {
      output.settings.face = face;
      output.settings.hasFace = true;
    }
    const char* wake = settings["wake"].as<const char*>();
    if (wake != nullptr) {
      if (std::strcmp(wake, "raise") == 0) {
        output.settings.wake = WakeMode::Raise;
        output.settings.hasWake = true;
      } else if (std::strcmp(wake, "tap") == 0) {
        output.settings.wake = WakeMode::Tap;
        output.settings.hasWake = true;
      }
    }
    const char* hourFormat = settings["hour_format"].as<const char*>();
    if (hourFormat != nullptr) {
      if (std::strcmp(hourFormat, "system") == 0) {
        output.settings.hourFormat = HourFormat::System;
        output.settings.hasHourFormat = true;
      } else if (std::strcmp(hourFormat, "h12") == 0) {
        output.settings.hourFormat = HourFormat::H12;
        output.settings.hasHourFormat = true;
      } else if (std::strcmp(hourFormat, "h24") == 0) {
        output.settings.hourFormat = HourFormat::H24;
        output.settings.hasHourFormat = true;
      }
    }
  }
  return true;
}

}  // namespace watch_v2
