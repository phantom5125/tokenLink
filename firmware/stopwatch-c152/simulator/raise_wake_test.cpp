#include <cassert>

#include "RaiseWake.h"

int main() {
  raise_wake::Detector detector(0.30f, 1000);

  // Resting samples prime the baseline without firing.
  assert(!detector.sample(0.0f, 0.0f, 1.0f, 0));
  assert(!detector.sample(0.0f, 0.0f, 1.0f, 100));

  // A raise is a motion spike against the resting baseline.
  assert(detector.sample(1.3f, 0.7f, 0.5f, 200));  // |g| ~ 1.56

  // The refractory window suppresses the settle-down edge and retriggering.
  assert(!detector.sample(0.0f, 0.0f, 1.0f, 300));
  assert(!detector.sample(1.3f, 0.7f, 0.5f, 400));

  // Settle back; the EMA returns the baseline to rest.
  for (int i = 0; i < 10; ++i) {
    assert(!detector.sample(0.0f, 0.0f, 1.0f, 500 + i * 100));
  }
  // Past the refractory window, a fresh spike fires again.
  assert(detector.sample(1.3f, 0.7f, 0.5f, 1600));

  // Slow drift (EMA tracks it) never fires.
  detector.reset();
  std::uint32_t now = 5000;
  assert(!detector.sample(0.0f, 0.0f, 1.0f, now));
  for (int i = 1; i <= 100; ++i) {
    const float tilt = 1.0f - 0.005f * i;  // gradual 0.5g drift over 10 s
    now += 100;
    assert(!detector.sample(0.0f, 0.0f, tilt, now));
  }
}
