#pragma once

#include <cstddef>
#include <cstdio>
#include <cstring>

namespace watch_command_frame {

// BLE notifications must fit the default ATT payload because the C152 can
// have a low-MTU HID connection alongside TokenLink's private GATT connection.
constexpr std::size_t kDefaultAttPayloadBytes = 20;

inline bool encode(char* output, std::size_t capacity, const char* action,
                   int slot) {
  if (output == nullptr || capacity == 0 || action == nullptr) return false;

  int length = -1;
  if (std::strcmp(action, "focus") == 0 && slot >= 0 && slot <= 2) {
    length = std::snprintf(output, capacity, "{\"a\":\"f\",\"s\":%d}", slot);
  } else if (std::strcmp(action, "refresh") == 0) {
    length = std::snprintf(output, capacity, "{\"a\":\"r\"}");
  }

  return length > 0 && static_cast<std::size_t>(length) < capacity &&
         static_cast<std::size_t>(length) <= kDefaultAttPayloadBytes;
}

}  // namespace watch_command_frame
