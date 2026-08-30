#include <ArduinoJson.h>

#include <cassert>
#include <cstring>
#include <string>

#include "WatchProtocolV2.h"
#include "WatchCommandFrame.h"

namespace {

bool parseJson(const char* json, watch_v2::Payload& payload) {
  DynamicJsonDocument document(2048);
  if (deserializeJson(document, json)) return false;
  if (!document.is<JsonObject>()) return false;
  const JsonObjectConst object = document.as<JsonObjectConst>();
  if (!watch_v2::isV2Payload(object)) return false;
  return watch_v2::parse(object, payload);
}

}  // namespace

int main() {
  {
    char frame[watch_command_frame::kDefaultAttPayloadBytes + 1] = {};
    assert(watch_command_frame::encode(frame, sizeof(frame), "focus", 2));
    assert(std::string(frame) == R"({"a":"f","s":2})");
    assert(std::strlen(frame) <= watch_command_frame::kDefaultAttPayloadBytes);
    assert(watch_command_frame::encode(frame, sizeof(frame), "refresh", -1));
    assert(std::string(frame) == R"({"a":"r"})");
    assert(!watch_command_frame::encode(frame, sizeof(frame), "focus", 3));
  }
  {
    watch_v2::Payload payload;
    assert(parseJson(
        R"({"v":2,"provider_id":"codex","windows":[{"id":"5h","remaining_percent":72,"reset_in_seconds":900}],"work_items":[{"slot":0,"name":"review","source":"codex","state":"running"},{"slot":1,"name":"fix-ci","source":"codex","state":"needs_input","latest":true,"seen":true},{"slot":2,"name":"maybe","source":"codex","state":"unknown"}],"active_count":5,"synced_at":1787616000})",
        payload));
    assert(std::strcmp(payload.providerId, "codex") == 0);
    assert(payload.windowCount == 1);
    assert(std::strcmp(payload.windows[0].id, "5h") == 0);
    assert(payload.windows[0].remainingPercent == 72.0f);
    assert(payload.windows[0].resetInSeconds == 900);
    assert(payload.hasWorkItems);
    assert(payload.workItemCount == 3);
    assert(payload.workItems[0].slot == 0);
    assert(std::strcmp(payload.workItems[0].name, "review") == 0);
    assert(payload.workItems[0].state == watch_v2::WorkState::Running);
    assert(payload.workItems[1].state == watch_v2::WorkState::NeedsInput);
    assert(payload.workItems[1].latest);
    assert(payload.workItems[1].seen);
    assert(payload.workItems[2].state == watch_v2::WorkState::Unknown);
    assert(payload.hasActiveCount && payload.activeCount == 5);
    assert(payload.hasSyncedAt && payload.syncedAt == 1787616000);
    assert(!payload.settings.hasFace);
  }

  // Unknown fields are ignored.
  {
    watch_v2::Payload payload;
    assert(parseJson(
        R"({"v":2,"provider_id":"kimi","windows":[{"id":"week","remaining_percent":40.5,"reset_in_seconds":3600,"extra":true}],"future_field":{"nested":[1,2,3]}})",
        payload));
    assert(std::strcmp(payload.providerId, "kimi") == 0);
    assert(payload.windowCount == 1);
    assert(!payload.hasWorkItems);
    assert(payload.workItemCount == 0);
    assert(!payload.hasActiveCount);
    assert(!payload.hasSyncedAt);
  }

  // Presence of an empty array is distinct from an omitted work_items key.
  {
    watch_v2::Payload payload;
    assert(parseJson(R"({"v":2,"provider_id":"codex","work_items":[]})",
                     payload));
    assert(payload.hasWorkItems);
    assert(payload.workItemCount == 0);
  }

  // Invalid entries are skipped, valid siblings survive.
  {
    watch_v2::Payload payload;
    assert(parseJson(
        R"({"v":2,"provider_id":"glm","windows":[{"id":"5h","remaining_percent":-1,"reset_in_seconds":10},{"id":"week","remaining_percent":55,"reset_in_seconds":100},{"id":"month","remaining_percent":80,"reset_in_seconds":200},{"id":"quarter","remaining_percent":90,"reset_in_seconds":300}],"work_items":[{"slot":0,"name":"a","source":"codex","state":"complete"},{"slot":7,"name":"bad-slot","source":"codex","state":"running"},{"slot":1,"name":"b","source":"kimi","state":"bogus"},{"slot":2,"name":"c","source":"kimi","state":"failed"},{"slot":3,"name":"d","source":"kimi","state":"running"}]})",
        payload));
    assert(payload.windowCount == 3);  // 4th window beyond the cap is dropped
    assert(std::strcmp(payload.windows[0].id, "week") == 0);
    assert(payload.workItemCount == 2);  // bad slot/state dropped, cap at 3
    assert(std::strcmp(payload.workItems[0].name, "a") == 0);
    assert(payload.workItems[0].state == watch_v2::WorkState::Complete);
    assert(std::strcmp(payload.workItems[1].name, "c") == 0);
    assert(payload.workItems[1].state == watch_v2::WorkState::Failed);
  }

  // Names are truncated to 12 printable ASCII characters.
  {
    watch_v2::Payload payload;
    assert(parseJson(
        R"({"v":2,"provider_id":"codex","work_items":[{"slot":0,"name":"this-name-is-way-too-long","source":"codex","state":"running"}]})",
        payload));
    assert(payload.workItemCount == 1);
    assert(std::strlen(payload.workItems[0].name) == 12);
    assert(std::strcmp(payload.workItems[0].name, "this-name-is") == 0);
  }

  // Settings block.
  {
    watch_v2::Payload payload;
    assert(parseJson(
        R"({"v":2,"provider_id":"codex","settings":{"theme":"pet","wake":"tap","hour_format":"h24"}})",
        payload));
    assert(payload.settings.hasFace &&
           payload.settings.face == watch_face_runtime::FaceID::Pet);
    assert(payload.settings.hasWake &&
           payload.settings.wake == watch_v2::WakeMode::Tap);
    assert(payload.settings.hasHourFormat &&
           payload.settings.hourFormat == watch_v2::HourFormat::H24);
  }
  {
    watch_v2::Payload payload;
    assert(parseJson(
        R"({"v":2,"provider_id":"codex","settings":{"theme":"plasma","wake":"shake","hour_format":"binary"}})",
        payload));
    assert(!payload.settings.hasFace);
    assert(!payload.settings.hasWake);
    assert(!payload.settings.hasHourFormat);
  }

  // Not v2 or malformed payloads are rejected.
  {
    watch_v2::Payload payload;
    assert(!parseJson(R"({"remaining_percent":72,"reset_in_seconds":900})",
                     payload));
    assert(!parseJson(R"({"v":1,"provider_id":"codex"})", payload));
    assert(!parseJson(R"({"v":2})", payload));
    assert(!parseJson(R"({"v":2,"provider_id":""})", payload));
    assert(!parseJson("not-json", payload));
  }
}
