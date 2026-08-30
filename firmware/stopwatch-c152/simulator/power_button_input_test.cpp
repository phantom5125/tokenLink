#include <cassert>

#include "PowerButtonInput.h"

using power_button_input::Action;
using power_button_input::arbitrate;

int main() {
  // Normal direct state transitions own the click and suppress the duplicated
  // M5Unified IRQ event.
  assert(arbitrate(true, true, false, false) == Action::BeginPress);
  assert(arbitrate(true, false, true, true) == Action::FinishPress);

  // A complete click that occurred between direct samples must still surface.
  assert(arbitrate(false, false, false, true) == Action::CompleteClick);
  assert(arbitrate(true, false, false, true) == Action::CompleteClick);

  // If the release sample fails, its latched click can finish a tracked press.
  assert(arbitrate(false, false, true, true) == Action::FinishPress);

  // A current held state wins over a stale latched event.
  assert(arbitrate(true, true, true, true) == Action::None);
  assert(arbitrate(false, false, false, false) == Action::None);
}
