// SPDX-License-Identifier: MIT
// Pure quota-dial calculations shared by the watch UI and native tests.

#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>

namespace watch_face_quota {

// M5GFX uses 0 degrees at 3 o'clock and increases clockwise. Starting at 130
// and sweeping 280 degrees leaves the TokenLink logo-like opening at 6 o'clock.
constexpr int kArcStartDegrees = 130;
constexpr int kArcSweepDegrees = 280;

inline float clampPercent(float percent) {
  return std::max(0.0f, std::min(100.0f, percent));
}

inline std::uint32_t remainingResetSeconds(std::uint32_t resetInSeconds,
                                           std::uint32_t receivedAtMs,
                                           std::uint32_t nowMs) {
  const std::uint32_t elapsedSeconds = (nowMs - receivedAtMs) / 1000;
  return elapsedSeconds >= resetInSeconds ? 0
                                          : resetInSeconds - elapsedSeconds;
}

inline bool plannedRemainingPercent(std::uint32_t durationSeconds,
                                    bool hasDuration,
                                    std::uint32_t remainingSeconds,
                                    float& output) {
  if (!hasDuration || durationSeconds == 0) return false;
  output = clampPercent(100.0f * static_cast<float>(remainingSeconds) /
                        static_cast<float>(durationSeconds));
  return true;
}

inline int arcAngle(float percent) {
  return kArcStartDegrees + static_cast<int>(std::lround(
                                kArcSweepDegrees * clampPercent(percent) /
                                100.0f));
}

inline int paceDeltaPoints(float actualPercent, float plannedPercent) {
  return static_cast<int>(std::lround(clampPercent(actualPercent) -
                                      clampPercent(plannedPercent)));
}

}  // namespace watch_face_quota
