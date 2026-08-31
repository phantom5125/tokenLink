// SPDX-License-Identifier: MIT
// Built-in watch-face registry and behavior contract. Package loading will
// extend this boundary later; v1 only describes the two firmware-owned faces.

#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <cstring>

namespace watch_face_runtime {

constexpr std::uint8_t kRuntimeVersion = 1;

enum class FaceID : std::uint8_t {
  Data,
  Pet,
};

enum class HomeRenderer : std::uint8_t {
  DataCards,
  Character,
};

enum class HomeInteraction : std::uint8_t {
  NavigateCards,
  RefreshPrimary,
};

struct Descriptor {
  FaceID id;
  const char* wireId;
  HomeRenderer homeRenderer;
  HomeInteraction homeInteraction;
};

constexpr std::array<Descriptor, 2> kBuiltInFaces = {{
    {FaceID::Data, "data", HomeRenderer::DataCards,
     HomeInteraction::NavigateCards},
    {FaceID::Pet, "pet", HomeRenderer::Character,
     HomeInteraction::RefreshPrimary},
}};

static_assert(kBuiltInFaces[0].id == FaceID::Data,
              "Data must remain the safe fallback face");

inline const Descriptor& descriptor(FaceID id) {
  for (const Descriptor& candidate : kBuiltInFaces) {
    if (candidate.id == id) return candidate;
  }
  return kBuiltInFaces[0];
}

inline bool resolve(const char* wireId, FaceID& output) {
  if (wireId != nullptr) {
    for (const Descriptor& candidate : kBuiltInFaces) {
      if (std::strcmp(candidate.wireId, wireId) == 0) {
        output = candidate.id;
        return true;
      }
    }
  }
  return false;
}

inline FaceID fromWireId(const char* wireId) {
  FaceID output = FaceID::Data;
  resolve(wireId, output);
  return output;
}

}  // namespace watch_face_runtime
