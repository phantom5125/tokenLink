// SPDX-License-Identifier: MIT

#pragma once

#include <cstdint>

#include "WatchProtocolV2.h"

namespace session_presentation {

// Color is never the only state signal: every indicator also has a distinct
// shape and the Sessions row keeps its text label.
enum class Indicator : std::uint8_t {
  Orbit,
  Pulse,
  Check,
  Alert,
  Ring,
  Dot,
};

struct Visual {
  std::uint32_t rgb;
  Indicator indicator;
  bool animated;
};

inline Visual visualFor(watch_v2::WorkState state, bool seen = false) {
  switch (state) {
    case watch_v2::WorkState::Running:
      return {0x4292F5, Indicator::Orbit, true};       // azure
    case watch_v2::WorkState::NeedsInput:
      if (seen) return {0xF7AC42, Indicator::Ring, false};
      return {0xF7AC42, Indicator::Pulse, true};       // amber
    case watch_v2::WorkState::Complete:
      return {0x2BC96E, Indicator::Check, false};      // spring green
    case watch_v2::WorkState::Failed:
      return {0xF55A68, Indicator::Alert, false};      // coral
    case watch_v2::WorkState::Unknown:
      return {0x7D8A98, Indicator::Dot, false};        // neutral grey
  }
  return {0x7D8A98, Indicator::Dot, false};            // defensive grey
}

constexpr std::uint16_t rgb565(std::uint32_t rgb) {
  return static_cast<std::uint16_t>(
      (((rgb >> 16) & 0xFF) >> 3) << 11 |
      (((rgb >> 8) & 0xFF) >> 2) << 5 |
      ((rgb & 0xFF) >> 3));
}

constexpr std::uint8_t animationFrame(std::uint32_t nowMs,
                                      std::uint16_t frameMs = 250,
                                      std::uint8_t frameCount = 8) {
  return frameMs == 0 || frameCount == 0
             ? 0
             : static_cast<std::uint8_t>((nowMs / frameMs) % frameCount);
}

}  // namespace session_presentation
