// SPDX-License-Identifier: MIT
// Optional pet watch-face theme (default off). "Pip" is an original 16x16
// pixel character drawn in code; no third-party artwork. The pet is only a
// skin over system state, per the TokenLink v2 design: energy = the tightest
// quota window, stale = drowsy, offline = sleeping, needs-input = jumping.

#pragma once

#include <M5GFX.h>

#include <cstdint>

#include "DashboardUi.h"  // palette

namespace petface {

constexpr int kSpriteSize = 16;
constexpr int kScale = 5;  // 80 x 80 px on the 466px face

enum class Mood : std::uint8_t {
  Lively,    // energy >= 60
  Ok,        // energy 25..60
  Low,       // energy < 25: droopy
  Drowsy,    // quota stale
  Sleeping,  // offline
  Alert,     // a work item needs input: jump
};

// State mapping is pure so the simulator can test it.
inline Mood classify(bool bleConnected, bool quotaStale, bool quotaAvailable,
                     float remainingPercent, bool needsInput) {
  if (!bleConnected) return Mood::Sleeping;
  if (needsInput) return Mood::Alert;
  if (quotaStale) return Mood::Drowsy;
  if (!quotaAvailable) return Mood::Drowsy;
  if (remainingPercent >= 60.0f) return Mood::Lively;
  if (remainingPercent >= 25.0f) return Mood::Ok;
  return Mood::Low;
}

// Sprite legend: '.' transparent, '#' ice outline, '=' teal body, 'o' eye.
// Eye rows (4-5) are patched per mood; the body is shared.
static constexpr const char* kBody[kSpriteSize] = {
    "................",
    ".....######.....",
    "...##======##...",
    "..#==========#..",
    ".#============#.",
    ".#============#.",
    ".#============#.",
    ".#============#.",
    "..#==========#..",
    "..#==========#..",
    "...#========#...",
    "....########....",
    "....#......#....",
    "...##......##...",
    "................",
    "................",
};

// Eyes are 2x2 blocks at rows 4-5, columns 5-6 and 9-10.
enum class EyeFrame : std::uint8_t { Open, Half, Closed };

inline bool eyePixel(EyeFrame frame, int row, int col) {
  const bool inLeft = col == 5 || col == 6;
  const bool inRight = col == 9 || col == 10;
  if (!inLeft && !inRight) return false;
  switch (frame) {
    case EyeFrame::Open: return row == 4 || row == 5;
    case EyeFrame::Half: return row == 5;
    case EyeFrame::Closed: return row == 5;
  }
  return false;
}

template <typename Surface>
void render(Surface& surface, int cx, int top, Mood mood, std::uint32_t nowMs) {
  // 10 fps frame clock keeps within the 8-12 fps design budget.
  const std::uint32_t frame = nowMs / 100;

  int offsetY = 0;
  EyeFrame eyes = EyeFrame::Open;
  bool showZzz = false;
  switch (mood) {
    case Mood::Lively:
      offsetY = (frame % 2 == 0) ? 0 : -4;  // gentle bounce
      eyes = (frame % 24 == 23) ? EyeFrame::Closed : EyeFrame::Open;  // blink
      break;
    case Mood::Ok:
      eyes = (frame % 24 == 23) ? EyeFrame::Closed : EyeFrame::Open;
      break;
    case Mood::Low:
      offsetY = 6;  // slumped
      eyes = EyeFrame::Half;
      break;
    case Mood::Drowsy:
      eyes = (frame % 16 < 12) ? EyeFrame::Half : EyeFrame::Closed;
      showZzz = true;
      break;
    case Mood::Sleeping:
      offsetY = 8;
      eyes = EyeFrame::Closed;
      showZzz = true;
      break;
    case Mood::Alert: {
      // Jump: parabolic hop twice per second.
      const float phase = (nowMs % 500) / 500.0f;
      offsetY = -static_cast<int>(14.0f * (1.0f - (phase - 0.5f) *
                                                 (phase - 0.5f) * 4.0f));
      eyes = EyeFrame::Open;
      break;
    }
  }

  const int left = cx - (kSpriteSize * kScale) / 2;
  const std::uint16_t bodyColor = dashboard::kAccent;
  const std::uint16_t outlineColor = dashboard::kText;
  const std::uint16_t eyeColor = dashboard::kBackground;

  for (int row = 0; row < kSpriteSize; ++row) {
    for (int col = 0; col < kSpriteSize; ++col) {
      const char pixel = kBody[row][col];
      if (pixel == '.') continue;
      std::uint16_t color = pixel == '#' ? outlineColor : bodyColor;
      if (pixel == '=' && eyePixel(eyes, row, col)) color = eyeColor;
      surface.fillRect(left + col * kScale, top + offsetY + row * kScale,
                       kScale, kScale, color);
    }
  }

  if (showZzz) {
    surface.loadFont(dashboard::font_data::kSpaceMono18Vlw);
    surface.setTextDatum(textdatum_t::top_left);
    surface.setTextColor(dashboard::kMuted);
    // Drifting "z Z" beside the head.
    const int drift = static_cast<int>((frame % 4));
    surface.drawString("z", left + kSpriteSize * kScale + 6,
                       top + 10 - drift * 4);
    if (mood == Mood::Sleeping) {
      surface.drawString("Z", left + kSpriteSize * kScale + 22,
                         top - 2 - drift * 4);
    }
    surface.unloadFont();
  }
}

// Tap target: the sprite bounds, generous for a round fingertip.
inline bool atPoint(int x, int y, int cx, int top) {
  const int half = (kSpriteSize * kScale) / 2 + 14;
  const int height = kSpriteSize * kScale + 28;
  return x >= cx - half && x <= cx + half && y >= top - 14 &&
         y <= top + height;
}

}  // namespace petface
