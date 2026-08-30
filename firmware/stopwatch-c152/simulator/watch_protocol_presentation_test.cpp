#include <cassert>

#include "WatchProtocolPresentation.h"

int main() {
  static_assert(watch_protocol_presentation::kDefaultProtocol == 2);
  static_assert(watch_protocol_presentation::protocolForPayload(true) == 2);
  static_assert(watch_protocol_presentation::protocolForPayload(false) == 1);

  assert(watch_protocol_presentation::kDefaultProtocol == 2);
  assert(watch_protocol_presentation::protocolForPayload(true) == 2);
  assert(watch_protocol_presentation::protocolForPayload(false) == 1);
  return 0;
}
