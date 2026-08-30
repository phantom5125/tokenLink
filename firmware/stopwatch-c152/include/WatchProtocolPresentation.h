// SPDX-License-Identifier: MIT

#pragma once

#include <cstdint>

namespace watch_protocol_presentation {

// This firmware is a protocol-v2 product, so its four-page UI is visible from
// boot. Receiving an actual legacy payload opts the current connection into the
// v1 dashboard; merely waiting for the Mac must never expose the old UI.
constexpr std::uint8_t kDefaultProtocol = 2;

constexpr std::uint8_t protocolForPayload(bool isV2) { return isV2 ? 2 : 1; }

}  // namespace watch_protocol_presentation
