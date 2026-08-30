// SPDX-License-Identifier: MIT
#pragma once

#include <cstdint>

namespace power_button_input {

enum class Action : std::uint8_t {
  None,
  BeginPress,
  FinishPress,
  CompleteClick,
};

// M5Unified consumes the PM1's latched click IRQ before application code runs.
// Direct PM1 state sampling is still needed for held presses, but a short click
// can begin and end between two samples. Prefer live state transitions and use
// the latched M5Unified click only when it is not a duplicate of that path.
inline Action arbitrate(bool directSampled, bool directPressed,
                        bool trackingPress, bool unifiedClicked) {
  if (directSampled) {
    if (directPressed && !trackingPress) return Action::BeginPress;
    if (!directPressed && trackingPress) return Action::FinishPress;
    // A live held state wins over a stale IRQ from an earlier click.
    if (directPressed) return Action::None;
  }
  if (unifiedClicked) {
    return trackingPress ? Action::FinishPress : Action::CompleteClick;
  }
  return Action::None;
}

}  // namespace power_button_input
