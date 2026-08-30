#include <array>
#include <cassert>
#include <cstdint>

#include "BleIdentity.h"

int main() {
  const std::array<std::uint8_t, ble_identity::kAddressSize> firstEntropy = {
      0x00, 0x11, 0x22, 0x33, 0x44, 0x55};
  const std::array<std::uint8_t, ble_identity::kAddressSize> secondEntropy = {
      0x3F, 0x11, 0x22, 0x33, 0x44, 0x56};
  std::array<std::uint8_t, ble_identity::kAddressSize> first = {};
  std::array<std::uint8_t, ble_identity::kAddressSize> second = {};

  ble_identity::makeRandomStatic(firstEntropy.data(), first.data());
  ble_identity::makeRandomStatic(secondEntropy.data(), second.data());

  assert(ble_identity::isRandomStatic(first.data()));
  assert(ble_identity::isRandomStatic(second.data()));
  assert(first[0] == 0xC0);
  assert(second[0] == 0xFF);
  assert(first != second);

  const std::array<std::uint8_t, ble_identity::kAddressSize> zeroEntropy = {};
  const std::array<std::uint8_t, ble_identity::kAddressSize> oneEntropy = {
      0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
  std::array<std::uint8_t, ble_identity::kAddressSize> zero = {};
  std::array<std::uint8_t, ble_identity::kAddressSize> one = {};
  ble_identity::makeRandomStatic(zeroEntropy.data(), zero.data());
  ble_identity::makeRandomStatic(oneEntropy.data(), one.data());

  assert(ble_identity::isRandomStatic(zero.data()));
  assert(ble_identity::isRandomStatic(one.data()));
  assert(zero[ble_identity::kAddressSize - 1] == 0x01);
  assert(one[ble_identity::kAddressSize - 1] == 0xFE);
}
