#include <cassert>
#include <cstring>

#include "WatchFaceRuntime.h"

int main() {
  using namespace watch_face_runtime;

  static_assert(kRuntimeVersion == 1);
  static_assert(kBuiltInFaces.size() == 2);

  const Descriptor& data = descriptor(FaceID::Data);
  assert(std::strcmp(data.wireId, "data") == 0);
  assert(data.homeRenderer == HomeRenderer::DataCards);
  assert(data.homeInteraction == HomeInteraction::NavigateCards);

  const Descriptor& pet = descriptor(fromWireId("pet"));
  assert(pet.id == FaceID::Pet);
  assert(pet.homeRenderer == HomeRenderer::Character);
  assert(pet.homeInteraction == HomeInteraction::RefreshPrimary);

  FaceID resolved = FaceID::Data;
  assert(resolve("pet", resolved));
  assert(resolved == FaceID::Pet);
  assert(!resolve("future.face", resolved));
  assert(fromWireId("future.face") == FaceID::Data);
  assert(fromWireId(nullptr) == FaceID::Data);
}
