#include <cassert>

#include "SessionPresentation.h"

int main() {
  using session_presentation::Indicator;
  using session_presentation::visualFor;

  const auto running = visualFor(watch_v2::WorkState::Running);
  const auto input = visualFor(watch_v2::WorkState::NeedsInput);
  const auto opened = visualFor(watch_v2::WorkState::NeedsInput, true);
  const auto complete = visualFor(watch_v2::WorkState::Complete);
  const auto failed = visualFor(watch_v2::WorkState::Failed);
  const auto unknown = visualFor(watch_v2::WorkState::Unknown);

  assert(running.rgb == 0x4292F5 && running.indicator == Indicator::Orbit &&
         running.animated);
  assert(input.rgb == 0xF7AC42 && input.indicator == Indicator::Pulse &&
         input.animated);
  assert(opened.rgb == 0xF7AC42 && opened.indicator == Indicator::Ring &&
         !opened.animated);
  assert(complete.rgb == 0x2BC96E && complete.indicator == Indicator::Check &&
         !complete.animated);
  assert(failed.rgb == 0xF55A68 && failed.indicator == Indicator::Alert &&
         !failed.animated);
  assert(unknown.rgb == 0x7D8A98 && unknown.indicator == Indicator::Dot &&
         !unknown.animated);
  assert(session_presentation::rgb565(complete.rgb) == 0x2E4D);

  assert(session_presentation::animationFrame(0) == 0);
  assert(session_presentation::animationFrame(250) == 1);
  assert(session_presentation::animationFrame(1750) == 7);
  assert(session_presentation::animationFrame(2000) == 0);
  assert(session_presentation::animationFrame(1000, 0, 8) == 0);
  return 0;
}
