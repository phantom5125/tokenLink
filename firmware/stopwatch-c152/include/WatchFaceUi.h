// SPDX-License-Identifier: MIT
// Protocol v2 watch face: four fixed pages in a ring (P0 home, P1 quota,
// P2 sessions, P3 system). It is the boot/default UI; the legacy dashboard in
// DashboardUi.h appears only after an actual v1 payload.

#pragma once

#include <M5GFX.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>

#include "DashboardUi.h"  // shared palette, fonts, helpers
#include "NunitoDigitsVlw.h"
#include "PetTheme.h"
#include "SessionPresentation.h"
#include "WatchFaceQuota.h"
#include "WatchFaceRuntime.h"
#include "WatchModel.h"

namespace watchface {

enum class Page : std::uint8_t {
  Home = 0,
  Quota = 1,
  Sessions = 2,
  System = 3,
};

constexpr int kPageCount = 4;

inline Page nextPage(Page page) {
  return static_cast<Page>((static_cast<int>(page) + 1) % kPageCount);
}

inline Page previousPage(Page page) {
  return static_cast<Page>((static_cast<int>(page) + kPageCount - 1) %
                           kPageCount);
}

enum class SyncDot : std::uint8_t {
  Offline,  // grey
  Stale,    // amber
  Synced,   // green
};

struct State {
  Page page = Page::Home;
  std::uint32_t nowMs = 0;
  SyncDot sync = SyncDot::Offline;
  bool bleConnected = false;
  bool hostLive = false;

  // Wall clock from the RX8130 RTC. System hour format renders as 24h: the
  // firmware has no locale setting of its own.
  bool timeValid = false;
  int hour = 0;
  int minute = 0;
  watch_v2::HourFormat hourFormat = watch_v2::HourFormat::System;

  // In-page selection: provider row on P1, work item row on P2. -1 = none.
  std::int8_t selectedIndex = 0;
  bool quotaExpanded = false;  // P1: show the selected provider's windows
  watch_face_runtime::FaceID face = watch_face_runtime::FaceID::Data;

  std::int8_t batteryPercent = -1;
  bool charging = false;

  const char* firmwareVersion = "";
  std::uint8_t protocolVersion = 2;

  // Transient pill (SEND / LISTENING / VOICE CHAT / swipe), same role as the
  // v1 dashboard transient.
  const char* transient = nullptr;
  std::uint16_t transientColor = dashboard::kVoice;

  dashboard::PowerOverlay powerOverlay = dashboard::PowerOverlay::None;
  float powerHoldProgress = 0.0f;
};

constexpr int kCenterX = dashboard::kCenterX;
constexpr int kCenterY = 233;

// P2 rows, also used by workItemAtPoint().
constexpr int kSessionRowY = 122;
constexpr int kSessionRowHeight = 94;

// Keep the quota horseshoe clear of the clock at the top of the round screen.
// The dedicated center also lets the rest of the watch face keep using the
// physical display center for overlays and page layouts.
constexpr int kHomeArcCenterY = 258;
constexpr int kHomeArcOuterRadius = 188;
constexpr int kHomeArcInnerRadius = 162;
constexpr int kHomeSessionPillLeft = 158;
constexpr int kHomeSessionPillTop = 382;
constexpr int kHomeSessionPillWidth = 150;
constexpr int kHomeSessionPillHeight = 38;

constexpr int kQuotaListTop = 88;
constexpr int kQuotaRowHeight = 82;
constexpr int kVisibleQuotaRows = 4;

template <typename Surface>
std::uint16_t syncColor(Surface& surface, SyncDot sync) {
  switch (sync) {
    case SyncDot::Synced: return surface.color565(43, 201, 110);
    case SyncDot::Stale: return dashboard::kWarning;
    case SyncDot::Offline: return dashboard::kMuted;
  }
  return dashboard::kMuted;
}

inline std::uint16_t workStateColor(watch_v2::WorkState state) {
  return session_presentation::rgb565(
      session_presentation::visualFor(state).rgb);
}

template <typename Surface>
void drawWorkStateIndicator(Surface& surface, watch_v2::WorkState state,
                            bool seen, int x, int y, std::uint32_t nowMs) {
  const session_presentation::Visual visual =
      session_presentation::visualFor(state, seen);
  const std::uint16_t color = session_presentation::rgb565(visual.rgb);
  switch (visual.indicator) {
    case session_presentation::Indicator::Orbit: {
      static constexpr std::int8_t offsets[8][2] = {
          {0, -7}, {5, -5}, {7, 0}, {5, 5},
          {0, 7}, {-5, 5}, {-7, 0}, {-5, -5},
      };
      const std::uint8_t frame = session_presentation::animationFrame(nowMs);
      surface.drawCircle(
          x, y, 8, dashboard::rgb888To565(surface, visual.rgb, 0.30f));
      surface.fillCircle(x + offsets[frame][0], y + offsets[frame][1], 3,
                         color);
      break;
    }
    case session_presentation::Indicator::Pulse: {
      const float phase = (nowMs % 1600) / 1600.0f;
      const float pulse = phase < 0.5f ? phase * 2.0f : 2.0f - phase * 2.0f;
      const int radius = 7 + static_cast<int>(std::round(pulse * 3.0f));
      surface.drawCircle(
          x, y, radius,
          dashboard::rgb888To565(surface, visual.rgb, 0.30f + 0.50f * pulse));
      surface.fillCircle(
          x, y, 5,
          dashboard::rgb888To565(surface, visual.rgb, 0.70f + 0.30f * pulse));
      break;
    }
    case session_presentation::Indicator::Check:
      surface.fillCircle(x, y, 8, color);
      surface.drawLine(x - 4, y, x - 1, y + 3, dashboard::kBackground);
      surface.drawLine(x - 4, y + 1, x - 1, y + 4,
                       dashboard::kBackground);
      surface.drawLine(x - 1, y + 3, x + 5, y - 4,
                       dashboard::kBackground);
      surface.drawLine(x - 1, y + 4, x + 5, y - 3,
                       dashboard::kBackground);
      break;
    case session_presentation::Indicator::Alert:
      surface.fillCircle(x, y, 8, color);
      surface.drawFastVLine(x, y - 5, 7, dashboard::kBackground);
      surface.drawFastVLine(x + 1, y - 5, 7, dashboard::kBackground);
      surface.fillCircle(x, y + 4, 1, dashboard::kBackground);
      break;
    case session_presentation::Indicator::Ring:
      surface.drawCircle(x, y, 8, color);
      surface.drawCircle(x, y, 7, color);
      surface.fillCircle(x, y, 2, color);
      break;
    case session_presentation::Indicator::Dot:
      surface.drawCircle(x, y, 8,
                         dashboard::rgb888To565(surface, visual.rgb, 0.35f));
      surface.fillCircle(x, y, 3, color);
      break;
  }
}

template <typename Surface>
void drawPageDots(Surface& surface, Page page) {
  for (int i = 0; i < kPageCount; ++i) {
    const bool active = static_cast<int>(page) == i;
    surface.fillCircle(kCenterX - 27 + i * 18, 446, active ? 4 : 2,
                       active ? dashboard::kText : dashboard::kTrack);
  }
}

template <typename Surface>
void drawTitle(Surface& surface, const char* title, int y = 46) {
  surface.loadFont(dashboard::font_data::kSpaceMono18Vlw);
  dashboard::centered(surface, title, kCenterX, y, dashboard::kMuted);
  surface.unloadFont();
}

template <typename Surface>
void drawClock(Surface& surface, const State& state, int y) {
  char text[12];
  if (!state.timeValid) {
    std::snprintf(text, sizeof(text), "--:--");
  } else if (state.hourFormat == watch_v2::HourFormat::H12) {
    const int h12 = state.hour % 12 == 0 ? 12 : state.hour % 12;
    std::snprintf(text, sizeof(text), "%d:%02d %s", h12, state.minute,
                  state.hour < 12 ? "AM" : "PM");
  } else {
    std::snprintf(text, sizeof(text), "%02d:%02d", state.hour, state.minute);
  }
  surface.loadFont(dashboard::font_data::kSpaceMono46Vlw);
  dashboard::centered(surface, text, kCenterX, y, dashboard::kText);
  surface.unloadFont();
}

inline void formatCountdown(std::uint32_t seconds, char* output,
                            std::size_t size) {
  if (seconds == 0) {
    std::snprintf(output, size, "--");
    return;
  }
  const std::uint32_t days = seconds / 86400;
  const std::uint32_t hours = (seconds % 86400) / 3600;
  const std::uint32_t minutes = (seconds % 3600) / 60;
  if (days > 0) {
    std::snprintf(output, size, "%luD %02luH", static_cast<unsigned long>(days),
                  static_cast<unsigned long>(hours));
  } else if (hours > 0) {
    std::snprintf(output, size, "%luH %02luM",
                  static_cast<unsigned long>(hours),
                  static_cast<unsigned long>(minutes));
  } else {
    std::snprintf(output, size, "%luM", static_cast<unsigned long>(minutes));
  }
}

inline void formatAge(std::uint32_t ageSeconds, char* output,
                      std::size_t size) {
  if (ageSeconds < 60) {
    std::snprintf(output, size, "%luS AGO", static_cast<unsigned long>(ageSeconds));
  } else if (ageSeconds < 3600) {
    std::snprintf(output, size, "%luM AGO",
                  static_cast<unsigned long>(ageSeconds / 60));
  } else {
    std::snprintf(output, size, "%luH AGO",
                  static_cast<unsigned long>(ageSeconds / 3600));
  }
}

template <typename Surface>
void drawProviderChip(Surface& surface, int x, int y, const char* providerId,
                      std::uint16_t color) {
  surface.fillSmoothRoundRect(x, y, 40, 40, 12, dashboard::kPanelPressed);
  const int cx = x + 20;
  const int cy = y + 20;
  if (std::strcmp(providerId, "codex") == 0) {
    // A compact six-loop mark: recognizable at watch distance without
    // shipping bitmap assets in firmware.
    for (int i = 0; i < 6; ++i) {
      const float angle = static_cast<float>(i) * 1.0471976f;
      const int px = cx + static_cast<int>(9.0f * std::cos(angle));
      const int py = cy + static_cast<int>(9.0f * std::sin(angle));
      surface.drawCircle(px, py, 7, color);
    }
  } else if (std::strcmp(providerId, "claude") == 0) {
    for (int i = 0; i < 8; ++i) {
      const float angle = static_cast<float>(i) * 0.7853982f;
      surface.drawLine(cx + static_cast<int>(6.0f * std::cos(angle)),
                       cy + static_cast<int>(6.0f * std::sin(angle)),
                       cx + static_cast<int>(14.0f * std::cos(angle)),
                       cy + static_cast<int>(14.0f * std::sin(angle)), color);
    }
    surface.fillCircle(cx, cy, 5, color);
  } else if (std::strcmp(providerId, "kimi") == 0) {
    surface.fillCircle(cx - 2, cy, 13, color);
    surface.fillCircle(cx + 4, cy - 4, 12, dashboard::kPanelPressed);
  } else if (std::strcmp(providerId, "glm") == 0) {
    surface.drawLine(cx, cy - 14, cx + 13, cy, color);
    surface.drawLine(cx + 13, cy, cx, cy + 14, color);
    surface.drawLine(cx, cy + 14, cx - 13, cy, color);
    surface.drawLine(cx - 13, cy, cx, cy - 14, color);
    surface.fillCircle(cx, cy, 4, color);
  } else if (std::strcmp(providerId, "minimax") == 0) {
    surface.drawLine(cx - 13, cy + 11, cx - 13, cy - 11, color);
    surface.drawLine(cx - 13, cy - 11, cx, cy + 2, color);
    surface.drawLine(cx, cy + 2, cx + 13, cy - 11, color);
    surface.drawLine(cx + 13, cy - 11, cx + 13, cy + 11, color);
  } else {
    char letter[2] = {providerId[0] == '\0' ? '?' : providerId[0], '\0'};
    if (letter[0] >= 'a' && letter[0] <= 'z') letter[0] -= 'a' - 'A';
    surface.loadFont(dashboard::font_data::kSpaceMono18Vlw);
    dashboard::centered(surface, letter, cx, cy + 1, color);
    surface.unloadFont();
  }
}

template <typename Surface>
std::uint16_t providerColor(Surface& surface, const char* providerId) {
  if (std::strcmp(providerId, "codex") == 0) return surface.color565(99, 230, 190);
  if (std::strcmp(providerId, "claude") == 0) return surface.color565(224, 133, 88);
  if (std::strcmp(providerId, "kimi") == 0) return surface.color565(118, 142, 255);
  if (std::strcmp(providerId, "glm") == 0) return surface.color565(76, 168, 255);
  if (std::strcmp(providerId, "minimax") == 0) return surface.color565(244, 111, 166);
  return dashboard::kAccent;
}

inline std::uint16_t quotaColor(float remaining, bool stale) {
  if (stale) return dashboard::kMuted;
  if (remaining < 10.0f) return dashboard::kDanger;
  if (remaining < 25.0f) return dashboard::kWarning;
  return dashboard::kAccent;
}

template <typename Surface>
void drawQuotaBar(Surface& surface, int x, int y, int width, float remaining,
                  std::uint16_t color) {
  const float bounded = std::max(0.0f, std::min(100.0f, remaining));
  surface.fillSmoothRoundRect(x, y, width, 7, 4, dashboard::kTrack);
  const int fill = static_cast<int>(width * bounded / 100.0f);
  if (fill > 0) surface.fillSmoothRoundRect(x, y, fill, 7, 4, color);
}

inline int activeWorkItemCount(const watch_model::Store& store) {
  if (store.hasActiveCount()) return store.activeCount();
  int count = 0;
  for (std::uint8_t i = 0; i < store.workItemCount(); ++i) {
    const watch_v2::WorkState state = store.workItems()[i].state;
    if (state == watch_v2::WorkState::Running ||
        state == watch_v2::WorkState::NeedsInput) {
      ++count;
    }
  }
  return count;
}

inline const char* friendlyWorkState(watch_v2::WorkState state,
                                     bool seen = false) {
  switch (state) {
    case watch_v2::WorkState::Running: return "RUNNING";
    case watch_v2::WorkState::NeedsInput: return seen ? "OPENED" : "ACTION";
    case watch_v2::WorkState::Complete: return "DONE";
    case watch_v2::WorkState::Failed: return "FAILED";
    case watch_v2::WorkState::Unknown: return "UNKNOWN";
  }
  return "UNKNOWN";
}

// The work item most worth surfacing on P0: needs_input first, then a recent
// completion. Returns nullptr when there is nothing to alert about.
inline const watch_v2::WorkItem* alertItem(const watch_model::Store& store) {
  const watch_v2::WorkItem* opened = nullptr;
  const watch_v2::WorkItem* complete = nullptr;
  for (std::uint8_t i = 0; i < store.workItemCount(); ++i) {
    const watch_v2::WorkItem& item = store.workItems()[i];
    if (item.state == watch_v2::WorkState::NeedsInput) {
      if (!item.seen) return &item;
      if (opened == nullptr) opened = &item;
    }
    if (complete == nullptr && item.state == watch_v2::WorkState::Complete) {
      complete = &item;
    }
  }
  return opened != nullptr ? opened : complete;
}

template <typename Surface>
void drawAlertStrip(Surface& surface, const State& state,
                    const watch_model::Store& store) {
  const watch_v2::WorkItem* item = alertItem(store);
  if (item == nullptr) return;

  const bool alertNeedsInput =
      item->state == watch_v2::WorkState::NeedsInput;
  const bool seeksAttention = alertNeedsInput && !item->seen;
  float brightness = 1.0f;
  if (seeksAttention) {
    // 1.6 s breathing cycle: the one state allowed to seek attention.
    const float phase = (state.nowMs % 1600) / 1600.0f;
    brightness = phase < 0.5f ? phase * 2.0f : 2.0f - phase * 2.0f;
    brightness = 0.35f + 0.65f * brightness;
  }
  const std::uint16_t strip =
      dashboard::rgb888To565(surface,
                             alertNeedsInput ? 0xF7AC42 : 0x2BC96E,
                             brightness * 0.30f);
  surface.fillSmoothRoundRect(73, 366, 320, 44, 14, strip);
  char message[40];
  std::snprintf(message, sizeof(message), "%s %s", item->name,
                friendlyWorkState(item->state, item->seen));
  for (char* c = message; *c != '\0'; ++c) {
    if (*c >= 'a' && *c <= 'z') *c -= 'a' - 'A';
  }
  surface.loadFont(dashboard::font_data::kSpaceMono18Vlw);
  dashboard::centered(surface, message, kCenterX, 389,
                      alertNeedsInput ? dashboard::kWarning
                                      : dashboard::kAccent);
  surface.unloadFont();
}

// --- P0 home ---------------------------------------------------------------

struct ArcPoint {
  int x;
  int y;
};

inline ArcPoint homeArcPoint(int angleDegrees, int radius) {
  constexpr float kDegreesToRadians = 0.01745329252f;
  const float radians = angleDegrees * kDegreesToRadians;
  return {kCenterX + static_cast<int>(std::lround(std::cos(radians) * radius)),
          kHomeArcCenterY +
              static_cast<int>(std::lround(std::sin(radians) * radius))};
}

template <typename Surface>
void fillWrappedArc(Surface& surface, int startDegrees, int endDegrees,
                    int outerRadius, int innerRadius, std::uint16_t color) {
  const int requestedSpan = std::max(0, endDegrees - startDegrees);
  while (startDegrees >= 360) startDegrees -= 360;
  while (startDegrees < 0) startDegrees += 360;
  const int normalizedEnd =
      startDegrees +
      std::min(watch_face_quota::kArcSweepDegrees, requestedSpan);
  if (normalizedEnd <= 360) {
    surface.fillArc(kCenterX, kHomeArcCenterY, outerRadius, innerRadius,
                    startDegrees, normalizedEnd, color);
  } else {
    surface.fillArc(kCenterX, kHomeArcCenterY, outerRadius, innerRadius,
                    startDegrees, 360, color);
    surface.fillArc(kCenterX, kHomeArcCenterY, outerRadius, innerRadius, 0,
                    normalizedEnd - 360, color);
  }
}

template <typename Surface>
void drawRoundedHomeArc(Surface& surface, int endDegrees,
                        std::uint16_t color, bool drawStartCap = true) {
  fillWrappedArc(surface, watch_face_quota::kArcStartDegrees, endDegrees,
                 kHomeArcOuterRadius, kHomeArcInnerRadius, color);
  constexpr int kMidRadius =
      (kHomeArcOuterRadius + kHomeArcInnerRadius) / 2;
  constexpr int kCapRadius =
      (kHomeArcOuterRadius - kHomeArcInnerRadius) / 2;
  if (drawStartCap) {
    const ArcPoint start = homeArcPoint(watch_face_quota::kArcStartDegrees,
                                        kMidRadius);
    surface.fillCircle(start.x, start.y, kCapRadius, color);
  }
  const ArcPoint end = homeArcPoint(endDegrees, kMidRadius);
  surface.fillCircle(end.x, end.y, kCapRadius, color);
}

inline const char* homeWindowLabel(const char* id) {
  if (std::strcmp(id, "week") == 0 || std::strcmp(id, "weekly") == 0 ||
      std::strcmp(id, "seven_day") == 0 ||
      std::strcmp(id, "seven_day_opus") == 0 ||
      std::strcmp(id, "seven_day_sonnet") == 0) {
    return "WEEK LEFT";
  }
  if (std::strcmp(id, "month") == 0 || std::strcmp(id, "monthly") == 0 ||
      std::strcmp(id, "mcp-monthly") == 0) {
    return "MONTH LEFT";
  }
  if (std::strcmp(id, "5h") == 0 || std::strcmp(id, "primary") == 0) {
    return "5H LEFT";
  }
  return "QUOTA LEFT";
}

template <typename Surface>
void drawHomeSessionPill(Surface& surface,
                         const watch_model::Store& store) {
  const int activeCount = activeWorkItemCount(store);
  const watch_v2::WorkItem* alert = alertItem(store);
  const bool pendingAction =
      alert != nullptr && alert->state == watch_v2::WorkState::NeedsInput &&
      !alert->seen;
  const std::uint16_t color = pendingAction
                                  ? dashboard::kWarning
                                  : (activeCount > 0 ? dashboard::kAccent
                                                     : dashboard::kMuted);
  surface.fillSmoothRoundRect(kHomeSessionPillLeft, kHomeSessionPillTop,
                              kHomeSessionPillWidth, kHomeSessionPillHeight, 19,
                              dashboard::kPanel);
  surface.fillCircle(kHomeSessionPillLeft + 22,
                     kHomeSessionPillTop + kHomeSessionPillHeight / 2, 4,
                     color);
  char label[20];
  if (pendingAction) {
    std::snprintf(label, sizeof(label), "ACTION");
  } else {
    std::snprintf(label, sizeof(label), "%d ACTIVE", activeCount);
  }
  surface.loadFont(dashboard::font_data::kSpaceMono18Vlw);
  surface.setTextDatum(middle_center);
  surface.setTextColor(color);
  surface.drawString(label, kHomeSessionPillLeft + 87,
                     kHomeSessionPillTop + kHomeSessionPillHeight / 2);
  surface.unloadFont();
}

template <typename Surface>
void renderHome(Surface& surface, const State& state,
                const watch_model::Store& store) {
  // A single logo-like horseshoe answers the primary glance question: how
  // much of the tightest quota remains, and whether it is ahead of time pace.
  drawRoundedHomeArc(surface,
                     watch_face_quota::kArcStartDegrees +
                         watch_face_quota::kArcSweepDegrees,
                     dashboard::kTrack);

  char clock[12];
  if (!state.timeValid) {
    std::snprintf(clock, sizeof(clock), "--:--");
  } else if (state.hourFormat == watch_v2::HourFormat::H12) {
    const int h12 = state.hour % 12 == 0 ? 12 : state.hour % 12;
    std::snprintf(clock, sizeof(clock), "%d:%02d%s", h12, state.minute,
                  state.hour < 12 ? "A" : "P");
  } else {
    std::snprintf(clock, sizeof(clock), "%02d:%02d", state.hour, state.minute);
  }
  const watch_model::TightestWindow tightest = store.tightest();
  if (tightest.providerIndex >= 0) {
    const watch_model::ProviderEntry* provider =
        store.providerAt(static_cast<std::size_t>(tightest.providerIndex));
    const watch_v2::Window& window = provider->windows[tightest.windowIndex];
    const float remaining =
        std::max(0.0f, std::min(100.0f, window.remainingPercent));
    const bool stale = state.nowMs - provider->receivedAtMs > 180000;
    const std::uint16_t color = quotaColor(remaining, stale);
    if (remaining > 0.0f) {
      drawRoundedHomeArc(surface, watch_face_quota::arcAngle(remaining), color);
    }

    surface.loadFont(dashboard::font_data::kSpaceMono18Vlw);
    char providerLabel[20];
    std::snprintf(providerLabel, sizeof(providerLabel), "%s", provider->id);
    for (char* c = providerLabel; *c != '\0'; ++c) {
      if (*c >= 'a' && *c <= 'z') *c -= 'a' - 'A';
    }
    dashboard::centered(surface, providerLabel, kCenterX, 122,
                        stale ? dashboard::kMuted : dashboard::kText);
    surface.unloadFont();

    char value[5];
    std::snprintf(value, sizeof(value), "%.0f", remaining);
    const int digitCount = static_cast<int>(std::strlen(value));
    const int numericWidth = digitCount * 55;
    const int numberStart = kCenterX - (numericWidth + 31) / 2;
    surface.loadFont(dashboard::font_data::kNunitoDigits92Vlw);
    dashboard::centered(surface, value, numberStart + numericWidth / 2, 209,
                        stale ? dashboard::kMuted : dashboard::kText);
    surface.unloadFont();
    surface.loadFont(dashboard::font_data::kNunitoDigits28Vlw);
    dashboard::centered(surface, "%", numberStart + numericWidth + 18, 213,
                        stale ? dashboard::kMuted : dashboard::kText);
    surface.unloadFont();

    surface.loadFont(dashboard::font_data::kSpaceMono18Vlw);
    dashboard::centered(surface, homeWindowLabel(window.id), kCenterX, 274,
                        dashboard::kMuted);
    const std::uint32_t remainingReset =
        watch_face_quota::remainingResetSeconds(
            window.resetInSeconds, provider->receivedAtMs, state.nowMs);
    float planned = 0.0f;
    if (watch_face_quota::plannedRemainingPercent(
            window.durationSeconds, window.hasDuration, remainingReset,
            planned)) {
      const int planAngle = watch_face_quota::arcAngle(planned);
      const ArcPoint tickInner =
          homeArcPoint(planAngle, kHomeArcInnerRadius - 6);
      const ArcPoint tickOuter =
          homeArcPoint(planAngle, kHomeArcOuterRadius + 5);
      surface.drawLine(tickInner.x, tickInner.y, tickOuter.x, tickOuter.y,
                       dashboard::kText);
      surface.drawLine(tickInner.x + 1, tickInner.y, tickOuter.x + 1,
                       tickOuter.y, dashboard::kText);

      char planLabel[16];
      char deltaLabel[12];
      const int delta = watch_face_quota::paceDeltaPoints(remaining, planned);
      std::snprintf(planLabel, sizeof(planLabel), "PLAN %.0f%%", planned);
      std::snprintf(deltaLabel, sizeof(deltaLabel), "  %s%dPP",
                    delta >= 0 ? "+" : "", delta);
      const int planWidth = surface.textWidth(planLabel);
      const int deltaWidth = surface.textWidth(deltaLabel);
      surface.setTextDatum(middle_left);
      surface.setTextColor(dashboard::kText);
      surface.drawString(planLabel, kCenterX - (planWidth + deltaWidth) / 2,
                         307);
      surface.setTextColor(delta < 0 ? dashboard::kWarning
                                     : dashboard::kAccent);
      surface.drawString(deltaLabel,
                         kCenterX - (planWidth + deltaWidth) / 2 + planWidth,
                         307);
    }
    char countdown[16];
    formatCountdown(remainingReset, countdown, sizeof(countdown));
    char reset[24];
    std::snprintf(reset, sizeof(reset), "RESET %s", countdown);
    dashboard::centered(surface, reset, kCenterX, 338, dashboard::kMuted);
    surface.unloadFont();
  } else {
    surface.loadFont(dashboard::font_data::kSpaceMono18Vlw);
    dashboard::centered(surface, "TOKENLINK", kCenterX, 122,
                        dashboard::kText);
    dashboard::centered(surface,
                        state.bleConnected ? "WAITING FOR QUOTA"
                                           : "WATCH OFFLINE",
                        kCenterX, 226, dashboard::kMuted);
    surface.unloadFont();
  }
  // Draw the clock after both arc layers so the numerals remain crisp when the
  // actual quota crosses the 12 o'clock region.
  surface.loadFont(dashboard::font_data::kNunitoDigits28Vlw);
  dashboard::centered(surface, clock, kCenterX, 54, dashboard::kText);
  surface.unloadFont();
  surface.fillCircle(181, 122, 4, syncColor(surface, state.sync));
  drawHomeSessionPill(surface, store);
}

// Pet-theme P0: same glance answers (time, sync, tightest quota, alerts) with
// Pip as the protagonist. Interaction is identical to the data theme.
constexpr int kPetTop = 150;

template <typename Surface>
void renderPetHome(Surface& surface, const State& state,
                   const watch_model::Store& store) {
  drawClock(surface, state, 76);
  surface.fillCircle(kCenterX, 124, 6, syncColor(surface, state.sync));

  const watch_v2::WorkItem* alert = alertItem(store);
  const bool needsInput =
      alert != nullptr && alert->state == watch_v2::WorkState::NeedsInput &&
      !alert->seen;

  const watch_model::TightestWindow tightest = store.tightest();
  float remaining = 0.0f;
  const bool hasQuota = tightest.providerIndex >= 0;
  if (hasQuota) {
    const watch_model::ProviderEntry* provider =
        store.providerAt(static_cast<std::size_t>(tightest.providerIndex));
    remaining = provider->windows[tightest.windowIndex].remainingPercent;
  }
  const petface::Mood mood =
      petface::classify(state.bleConnected, state.sync == SyncDot::Stale,
                        hasQuota, remaining, needsInput);
  petface::render(surface, kCenterX, kPetTop, mood, state.nowMs);

  if (hasQuota) {
    surface.loadFont(dashboard::font_data::kSpaceMono18Vlw);
    char value[8];
    std::snprintf(value, sizeof(value), "%.0f%%",
                  std::max(0.0f, std::min(100.0f, remaining)));
    dashboard::centered(surface, value, kCenterX, 260,
                        state.sync == SyncDot::Stale ? dashboard::kMuted
                                                     : dashboard::kText);
    surface.unloadFont();
  }
  drawAlertStrip(surface, state, store);
}

// --- P1 quota ---------------------------------------------------------------

template <typename Surface>
void renderQuotaRow(Surface& surface, int y, const char* id,
                    const watch_v2::Window& window,
                    std::uint32_t receivedAtMs, std::uint32_t nowMs,
                    bool stale, bool selected) {
  if (selected) {
    surface.fillSmoothRoundRect(48, y, 370, 74, 16,
                                dashboard::kPanelPressed);
  }
  drawProviderChip(surface, 60, y + 9, id,
                   stale ? dashboard::kMuted : providerColor(surface, id));

  surface.loadFont(dashboard::font_data::kSpaceMono18Vlw);
  surface.setTextDatum(textdatum_t::top_left);
  surface.setTextSize(1.0f);
  const std::uint16_t textColor = stale ? dashboard::kMuted : dashboard::kText;
  surface.setTextColor(textColor);
  char name[20];
  std::snprintf(name, sizeof(name), "%s", id);
  for (char* c = name; *c != '\0'; ++c) {
    if (*c >= 'a' && *c <= 'z') *c -= 'a' - 'A';
  }
  surface.drawString(name, 112, y + 2);

  const float remaining =
      std::max(0.0f, std::min(100.0f, window.remainingPercent));
  char detail[28];
  char countdown[16];
  const std::uint32_t elapsed = (nowMs - receivedAtMs) / 1000;
  const std::uint32_t remainingReset =
      elapsed >= window.resetInSeconds ? 0 : window.resetInSeconds - elapsed;
  formatCountdown(remainingReset, countdown, sizeof(countdown));
  if (stale) {
    char age[16];
    formatAge(elapsed, age, sizeof(age));
    std::snprintf(detail, sizeof(detail), "%s / %s", window.id, age);
  } else {
    std::snprintf(detail, sizeof(detail), "%s / RESET %s", window.id,
                  countdown);
  }
  for (char* c = detail; *c != '\0'; ++c) {
    if (*c >= 'a' && *c <= 'z') *c -= 'a' - 'A';
  }
  surface.setTextColor(dashboard::kMuted);
  surface.drawString(detail, 112, y + 27);
  const std::uint16_t valueColor = quotaColor(remaining, stale);
  char value[8];
  std::snprintf(value, sizeof(value), "%.0f%%", remaining);
  surface.setTextDatum(textdatum_t::top_right);
  surface.setTextColor(valueColor);
  surface.drawString(value, 402, y + 2);
  drawQuotaBar(surface, 112, y + 55, 290, remaining, valueColor);
  surface.unloadFont();
}

template <typename Surface>
void renderQuota(Surface& surface, const State& state,
                 const watch_model::Store& store) {
  if (state.quotaExpanded) {
    const watch_model::ProviderEntry* provider =
        store.providerAt(static_cast<std::size_t>(
            std::max<std::int8_t>(0, state.selectedIndex)));
    if (provider == nullptr) {
      drawTitle(surface, "QUOTA");
    } else {
      char title[24];
      std::snprintf(title, sizeof(title), "%s", provider->id);
      for (char* c = title; *c != '\0'; ++c) {
        if (*c >= 'a' && *c <= 'z') *c -= 'a' - 'A';
      }
      drawTitle(surface, title);
      const bool stale =
          state.nowMs - provider->receivedAtMs > 180000;  // kQuotaStaleAfterMs
      int y = 112;
      for (std::uint8_t w = 0; w < provider->windowCount; ++w) {
        const watch_v2::Window& window = provider->windows[w];
        surface.fillSmoothRoundRect(64, y - 10, 338, 76, 16,
                                    dashboard::kPanel);
        surface.loadFont(dashboard::font_data::kSpaceMono18Vlw);
        surface.setTextDatum(textdatum_t::top_left);
        surface.setTextColor(dashboard::kMuted);
        char label[12];
        std::snprintf(label, sizeof(label), "%s", window.id);
        for (char* c = label; *c != '\0'; ++c) {
          if (*c >= 'a' && *c <= 'z') *c -= 'a' - 'A';
        }
        surface.drawString(label, 84, y);
        const float remaining =
            std::max(0.0f, std::min(100.0f, window.remainingPercent));
        const std::uint16_t color = quotaColor(remaining, stale);
        surface.setTextColor(color);
        char value[8];
        const std::uint32_t elapsed =
            (state.nowMs - provider->receivedAtMs) / 1000;
        const std::uint32_t remainingReset = elapsed >= window.resetInSeconds
                                                 ? 0
                                                 : window.resetInSeconds - elapsed;
        char countdown[16];
        formatCountdown(remainingReset, countdown, sizeof(countdown));
        std::snprintf(value, sizeof(value), "%.0f%%", remaining);
        surface.setTextDatum(textdatum_t::top_right);
        surface.drawString(value, 382, y);
        drawQuotaBar(surface, 84, y + 30, 298, remaining, color);
        char reset[24];
        std::snprintf(reset, sizeof(reset), "RESET %s", countdown);
        surface.setTextDatum(textdatum_t::top_left);
        surface.setTextColor(dashboard::kMuted);
        surface.drawString(reset, 84, y + 43);
        surface.unloadFont();
        y += 88;
      }
      surface.loadFont(dashboard::font_data::kSpaceMono18Vlw);
      dashboard::centered(surface, "TAP TO ALL QUOTAS", kCenterX, 408,
                          dashboard::kMuted);
      surface.unloadFont();
    }
    return;
  }

  drawTitle(surface, "QUOTA");
  surface.fillCircle(388, 47, 5, syncColor(surface, state.sync));
  const std::size_t count = store.providerCount();
  if (count == 0) {
    surface.loadFont(dashboard::font_data::kSpaceMono18Vlw);
    dashboard::centered(surface, state.bleConnected ? "WAITING SYNC"
                                                    : "OFFLINE",
                        kCenterX, 233, dashboard::kMuted);
    surface.unloadFont();
    return;
  }
  const int selected = std::max(0, std::min(static_cast<int>(count) - 1,
                                           static_cast<int>(state.selectedIndex)));
  const int first = std::max(0, selected - (kVisibleQuotaRows - 1));
  const int visible = std::min(kVisibleQuotaRows, static_cast<int>(count) - first);
  for (int row = 0; row < visible; ++row) {
    const std::size_t i = static_cast<std::size_t>(first + row);
    const watch_model::ProviderEntry* provider = store.providerAt(i);
    // Each row shows that provider's own tightest window.
    int tightestWindow = 0;
    for (std::uint8_t w = 1; w < provider->windowCount; ++w) {
      if (provider->windows[w].remainingPercent <
          provider->windows[tightestWindow].remainingPercent) {
        tightestWindow = w;
      }
    }
    if (provider->windowCount == 0) continue;
    const bool stale =
        state.nowMs - provider->receivedAtMs > 180000;
    renderQuotaRow(surface, kQuotaListTop + row * kQuotaRowHeight,
                   provider->id, provider->windows[tightestWindow],
                   provider->receivedAtMs, state.nowMs, stale,
                   static_cast<std::int8_t>(i) == state.selectedIndex);
  }
  if (count > kVisibleQuotaRows) {
    surface.loadFont(dashboard::font_data::kSpaceMono18Vlw);
    surface.setTextDatum(textdatum_t::middle_center);
    surface.setTextColor(dashboard::kMuted);
    surface.drawString(first == 0 ? "v" : "^", 430, 248);
    surface.unloadFont();
  }
}

// --- P2 sessions -------------------------------------------------------------

template <typename Surface>
void renderSessions(Surface& surface, const State& state,
                    const watch_model::Store& store) {
  drawTitle(surface, "SESSIONS", 42);
  surface.loadFont(dashboard::font_data::kSpaceMono18Vlw);
  surface.setTextSize(0.78f);
  char summary[32];
  std::snprintf(summary, sizeof(summary), "%d ACTIVE / %u SHOWN",
                activeWorkItemCount(store),
                static_cast<unsigned>(store.workItemCount()));
  dashboard::centered(surface, summary, kCenterX, 69, dashboard::kMuted);
  surface.unloadFont();
  if (store.workItemCount() == 0) {
    surface.loadFont(dashboard::font_data::kSpaceMono18Vlw);
    dashboard::centered(surface, "NO WORK ITEMS", kCenterX, 233,
                        dashboard::kMuted);
    surface.unloadFont();
    return;
  }
  for (std::uint8_t i = 0; i < store.workItemCount(); ++i) {
    const watch_v2::WorkItem& item = store.workItems()[i];
    const int y = kSessionRowY + i * kSessionRowHeight;
    const bool selected = state.selectedIndex == static_cast<std::int8_t>(i);
    surface.fillSmoothRoundRect(52, y - 35, 362, 78, 17,
                                selected ? dashboard::kPanelPressed
                                         : dashboard::kPanel);
    drawWorkStateIndicator(surface, item.state, item.seen, 78, y - 10,
                           state.nowMs);

    surface.loadFont(dashboard::font_data::kSpaceMono18Vlw);
    surface.setTextDatum(textdatum_t::top_left);
    surface.setTextSize(1.0f);
    surface.setTextColor(dashboard::kText);
    surface.drawString(item.name, 100, y - 28);
    surface.setTextColor(dashboard::kMuted);
    char source[16];
    std::snprintf(source, sizeof(source), "%s", item.source);
    for (char* c = source; *c != '\0'; ++c) {
      if (*c >= 'a' && *c <= 'z') *c -= 'a' - 'A';
    }
    surface.drawString(source, 100, y + 3);
    const int stateX = 100 + surface.textWidth(source) + 18;
    surface.drawString("/", stateX - 12, y + 3);
    surface.setTextColor(workStateColor(item.state));
    surface.drawString(friendlyWorkState(item.state, item.seen), stateX,
                       y + 3);
    if (selected && std::strcmp(item.source, "codex") == 0) {
      surface.setTextDatum(textdatum_t::top_right);
      surface.setTextColor(dashboard::kAccent);
      surface.drawString("FOCUS >", 398, y + 3);
    }
    surface.unloadFont();
  }
}

// Tap target for P2 rows. Returns the work-item index or -1.
inline int workItemAtPoint(int x, int y, std::uint8_t itemCount) {
  if (x < 52 || x > 414) return -1;
  for (std::uint8_t i = 0; i < itemCount; ++i) {
    const int rowY = kSessionRowY + i * kSessionRowHeight;
    if (y >= rowY - 35 && y <= rowY + 43) return i;
  }
  return -1;
}

inline bool homeSessionsAtPoint(int x, int y) {
  return x >= kHomeSessionPillLeft &&
         x <= kHomeSessionPillLeft + kHomeSessionPillWidth &&
         y >= kHomeSessionPillTop &&
         y <= kHomeSessionPillTop + kHomeSessionPillHeight;
}

inline bool homeQuotaAtPoint(int x, int y) {
  const int dx = x - kCenterX;
  const int dy = y - kHomeArcCenterY;
  constexpr int kHitRadius = kHomeArcOuterRadius + 2;
  return dx * dx + dy * dy <= kHitRadius * kHitRadius &&
         !homeSessionsAtPoint(x, y);
}

inline int quotaProviderAtPoint(int x, int y, std::size_t providerCount,
                                std::int8_t selectedIndex) {
  if (x < 48 || x > 418 || providerCount == 0) return -1;
  const int selected = std::max(
      0, std::min(static_cast<int>(providerCount) - 1,
                  static_cast<int>(selectedIndex)));
  const int first = std::max(0, selected - (kVisibleQuotaRows - 1));
  for (int row = 0;
       row < std::min(kVisibleQuotaRows, static_cast<int>(providerCount) - first);
       ++row) {
    const int top = kQuotaListTop + row * kQuotaRowHeight;
    if (y >= top && y <= top + 74) return first + row;
  }
  return -1;
}

// --- P3 system ---------------------------------------------------------------

template <typename Surface>
void renderSystemRow(Surface& surface, int y, const char* label,
                     const char* value, std::uint16_t color) {
  surface.loadFont(dashboard::font_data::kSpaceMono18Vlw);
  surface.setTextDatum(textdatum_t::top_left);
  surface.setTextSize(1.0f);
  surface.setTextColor(dashboard::kMuted);
  surface.drawString(label, 90, y);
  surface.setTextColor(color);
  surface.drawString(value, 220, y);
  surface.unloadFont();
}

template <typename Surface>
void renderSystem(Surface& surface, const State& state,
                  const watch_model::Store& store) {
  drawTitle(surface, "SYSTEM");
  int y = 116;
  renderSystemRow(surface, y, "BLE", state.bleConnected ? "CONNECTED" : "OFFLINE",
                  state.bleConnected ? dashboard::kAccent : dashboard::kMuted);
  y += 46;
  renderSystemRow(surface, y, "HOST",
                  state.hostLive ? "CODEX LIVE" : "NO RPC",
                  state.hostLive ? dashboard::kVoice : dashboard::kMuted);
  y += 46;
  {
    // Newest payload across providers.
    std::uint32_t newest = 0;
    bool any = false;
    for (std::size_t i = 0; i < store.providerCount(); ++i) {
      const watch_model::ProviderEntry* provider = store.providerAt(i);
      if (provider->receivedAtMs > 0 &&
          (!any || state.nowMs - provider->receivedAtMs <
                       state.nowMs - newest)) {
        newest = provider->receivedAtMs;
        any = true;
      }
    }
    char value[20];
    if (any) {
      char age[16];
      formatAge((state.nowMs - newest) / 1000, age, sizeof(age));
      std::snprintf(value, sizeof(value), "%s", age);
    } else {
      std::snprintf(value, sizeof(value), "NEVER");
    }
    renderSystemRow(surface, y, "SYNC", value, dashboard::kText);
  }
  y += 46;
  {
    char value[20];
    std::snprintf(value, sizeof(value), "v%u", state.protocolVersion);
    renderSystemRow(surface, y, "PROTO", value, dashboard::kText);
  }
  y += 46;
  {
    char value[24];
    std::snprintf(value, sizeof(value), "%s", state.firmwareVersion);
    renderSystemRow(surface, y, "FW", value, dashboard::kText);
  }
  y += 46;
  {
    char value[16];
    if (state.batteryPercent < 0) {
      std::snprintf(value, sizeof(value), "--%%");
    } else {
      std::snprintf(value, sizeof(value), "%d%%%s", state.batteryPercent,
                    state.charging ? " CHG" : "");
    }
    renderSystemRow(surface, y, "BATT", value,
                    state.batteryPercent >= 0 && state.batteryPercent <= 20
                        ? dashboard::kWarning
                        : dashboard::kText);
  }
  surface.fillSmoothRoundRect(100, 395, 266, 34, 12, dashboard::kPanelPressed);
  surface.loadFont(dashboard::font_data::kSpaceMono18Vlw);
  dashboard::centered(surface, "TAP TO REFRESH", kCenterX, 413,
                      state.hostLive ? dashboard::kAccent : dashboard::kMuted);
  surface.unloadFont();
}

inline bool systemRefreshAtPoint(int x, int y) {
  return x >= 100 && x <= 366 && y >= 395 && y <= 429;
}

// --- overlays ------------------------------------------------------------------

template <typename Surface>
void drawTransient(Surface& surface, const State& state) {
  if (state.transient == nullptr) return;
  surface.fillSmoothRoundRect(kCenterX - 102, kCenterY - 32, 204, 64, 18,
                              state.transientColor);
  surface.fillSmoothRoundRect(kCenterX - 98, kCenterY - 28, 196, 56, 15,
                              dashboard::kPanel);
  surface.loadFont(dashboard::font_data::kSpaceMono18Vlw);
  dashboard::centered(surface, state.transient, kCenterX, kCenterY + 1,
                      state.transientColor);
  surface.unloadFont();
}

template <typename Surface>
void drawPowerOverlay(Surface& surface, const State& state) {
  if (state.powerOverlay == dashboard::PowerOverlay::None) return;
  // Reuse the v1 overlay: power state owns the screen regardless of page.
  dashboard::State legacy;
  legacy.powerOverlay = state.powerOverlay;
  legacy.powerHoldProgress = state.powerHoldProgress;
  dashboard::drawPowerOverlay(surface, legacy);
}

template <typename Surface>
void render(Surface& surface, const State& state,
            const watch_model::Store& store) {
  surface.fillScreen(dashboard::kBackground);
  switch (state.page) {
    case Page::Home:
      switch (watch_face_runtime::descriptor(state.face).homeRenderer) {
        case watch_face_runtime::HomeRenderer::DataCards:
          renderHome(surface, state, store);
          break;
        case watch_face_runtime::HomeRenderer::Character:
          renderPetHome(surface, state, store);
          break;
      }
      break;
    case Page::Quota:
      renderQuota(surface, state, store);
      break;
    case Page::Sessions:
      renderSessions(surface, state, store);
      break;
    case Page::System:
      renderSystem(surface, state, store);
      break;
  }
  drawPageDots(surface, state.page);
  drawTransient(surface, state);
  drawPowerOverlay(surface, state);
}

}  // namespace watchface
