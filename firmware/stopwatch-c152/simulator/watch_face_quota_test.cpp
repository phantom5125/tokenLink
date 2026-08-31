#include <cassert>
#include <cmath>

#include "WatchFaceQuota.h"

int main() {
  assert(watch_face_quota::remainingResetSeconds(3600, 1000, 61000) ==
         3540);
  assert(watch_face_quota::remainingResetSeconds(30, 1000, 61000) == 0);

  float planned = 0.0f;
  assert(watch_face_quota::plannedRemainingPercent(
      7 * 86400, true, 4 * 86400 + 3 * 3600, planned));
  assert(std::fabs(planned - 58.9286f) < 0.001f);
  assert(watch_face_quota::paceDeltaPoints(54.0f, planned) == -5);
  assert(!watch_face_quota::plannedRemainingPercent(0, false, 900, planned));

  assert(watch_face_quota::arcAngle(0.0f) == 130);
  assert(watch_face_quota::arcAngle(50.0f) == 270);
  assert(watch_face_quota::arcAngle(100.0f) == 410);
  assert(watch_face_quota::arcAngle(140.0f) == 410);
  return 0;
}
