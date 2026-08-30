// SPDX-License-Identifier: MIT
// Raise-to-wake detection from BMI270 accelerometer samples. The Bosch wrist
// gesture engine needs the 8 KB feature config blob, which this port does not
// ship; instead the desk-sleep loop polls the accelerometer at ~10 Hz and this
// detector looks for a wrist-raise acceleration change. Tap-to-wake remains
// available regardless.

#pragma once

#include <cmath>
#include <cstdint>

namespace raise_wake {

class Detector {
 public:
  explicit constexpr Detector(float thresholdG = 0.30f,
                              std::uint32_t refractoryMs = 1000)
      : thresholdG_(thresholdG), refractoryMs_(refractoryMs) {}

  // Feed one accelerometer sample (g). Returns true once per raise gesture.
  bool sample(float ax, float ay, float az, std::uint32_t nowMs) {
    const float magnitude = std::sqrt(ax * ax + ay * ay + az * az);
    if (!primed_) {
      baseline_ = magnitude;
      primed_ = true;
      return false;
    }
    const float delta = std::fabs(magnitude - baseline_);
    // Slow EMA tracks resting orientation so a held pose does not retrigger.
    baseline_ = baseline_ * 0.9f + magnitude * 0.1f;
    if (delta < thresholdG_) return false;
    if (hasFired_ && static_cast<std::int32_t>(nowMs - lastFireMs_) <
                         static_cast<std::int32_t>(refractoryMs_)) {
      return false;
    }
    hasFired_ = true;
    lastFireMs_ = nowMs;
    baseline_ = magnitude;
    return true;
  }

  void reset() {
    primed_ = false;
    hasFired_ = false;
  }

 private:
  float thresholdG_;
  std::uint32_t refractoryMs_;
  float baseline_ = 1.0f;
  std::uint32_t lastFireMs_ = 0;
  bool primed_ = false;
  bool hasFired_ = false;
};

}  // namespace raise_wake
