// SPDX-License-Identifier: MIT
#pragma once

#include <cstddef>
#include <cstdint>

namespace ble_identity {

constexpr std::size_t kAddressSize = 6;

inline void makeRandomStatic(const std::uint8_t* entropy,
                             std::uint8_t* address) {
  for (std::size_t index = 0; index < kAddressSize; ++index) {
    address[index] = entropy[index];
  }
  // Bluetooth random-static device addresses require the top two bits to be 1.
  address[0] = static_cast<std::uint8_t>((address[0] & 0x3F) | 0xC0);

  // The remaining 46 bits may not be all zeroes or all ones. Random input is
  // overwhelmingly unlikely to hit either value, but normalize those two
  // cases so every generated address is valid by construction.
  bool lowerBitsAreZero = (address[0] & 0x3F) == 0;
  bool lowerBitsAreOne = (address[0] & 0x3F) == 0x3F;
  for (std::size_t index = 1; index < kAddressSize; ++index) {
    lowerBitsAreZero = lowerBitsAreZero && address[index] == 0x00;
    lowerBitsAreOne = lowerBitsAreOne && address[index] == 0xFF;
  }
  if (lowerBitsAreZero || lowerBitsAreOne) {
    address[kAddressSize - 1] ^= 0x01;
  }
}

inline bool isRandomStatic(const std::uint8_t* address) {
  return (address[0] & 0xC0) == 0xC0;
}

}  // namespace ble_identity
