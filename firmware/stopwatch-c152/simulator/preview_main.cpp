// Native, headless, pixel-identical dashboard renderer.
#include <M5GFX.h>

#include <cstdint>
#include <cstring>
#include <cstdio>
#include <string>
#include <vector>

#include "DashboardUi.h"
#include "WatchFaceUi.h"

namespace {

dashboard::State previewState(const char* scenario) {
  dashboard::State state;
  state.linkHealth = dashboard::LinkHealth::CodexLive;
  state.batteryPercent = 82;
  state.quotaAvailable = true;
  state.remainingPercent = 82.0f;
  state.resetInSeconds = 4 * 86400 + 3 * 3600;
  state.threads = {{
      {0xE9EEF5, 0.90f, false},  // idle
      {0x3794FF, 1.00f, true},   // thinking
      {0x2DDD72, 1.00f, false},  // complete
      {0xFFB020, 1.00f, false},  // requires input
      {0xFF4D5E, 1.00f, false},  // error
      {0x000000, 0.00f, false},  // unassigned
  }};

  if (std::strcmp(scenario, "ble") == 0) {
    state.linkHealth = dashboard::LinkHealth::BleOnly;
    state.batteryPercent = 61;
    state.charging = true;
    state.docked = true;
  } else if (std::strcmp(scenario, "live-stale") == 0) {
    state.linkHealth = dashboard::LinkHealth::CodexLive;
    state.quotaStale = true;
    state.batteryPercent = 17;
    state.remainingPercent = 19.0f;
    state.resetInSeconds = 17 * 3600 + 22 * 60;
  } else if (std::strcmp(scenario, "offline") == 0) {
    state.linkHealth = dashboard::LinkHealth::Offline;
    state.batteryPercent = 44;
    state.quotaAvailable = false;
    state.remainingPercent = 0.0f;
    state.resetInSeconds = 0;
  } else if (std::strcmp(scenario, "power-hold") == 0) {
    state.powerOverlay = dashboard::PowerOverlay::HoldToPowerOff;
    state.powerHoldProgress = 0.56f;
  } else if (std::strcmp(scenario, "power-off") == 0) {
    state.linkHealth = dashboard::LinkHealth::Offline;
    state.powerOverlay = dashboard::PowerOverlay::PoweringOff;
  }
  return state;
}

watch_v2::Payload makeProvider(const char* id, const char* windowId,
                               float percent, std::uint32_t reset) {
  watch_v2::Payload payload;
  watch_v2::copyAscii(payload.providerId, sizeof(payload.providerId), id);
  payload.windowCount = 1;
  watch_v2::copyAscii(payload.windows[0].id, sizeof(payload.windows[0].id),
                      windowId);
  payload.windows[0].remainingPercent = percent;
  payload.windows[0].resetInSeconds = reset;
  return payload;
}

watch_model::Store previewStore(const char* scenario) {
  watch_model::Store store;
  store.apply(makeProvider("codex", "5h", 72.0f, 900), 1000);
  store.apply(makeProvider("kimi", "week", 35.0f, 3 * 86400), 2000);
  store.apply(makeProvider("glm", "month", 88.0f, 20 * 86400), 3000);

  watch_v2::Payload codex = makeProvider("codex", "5h", 72.0f, 900);
  codex.windowCount = 2;
  watch_v2::copyAscii(codex.windows[1].id, sizeof(codex.windows[1].id), "week");
  codex.windows[1].remainingPercent = 54.0f;
  codex.windows[1].resetInSeconds = 4 * 86400 + 3 * 3600;
  codex.workItemCount = 3;
  codex.workItems[0].slot = 0;
  watch_v2::copyAscii(codex.workItems[0].name, sizeof(codex.workItems[0].name),
                      "review");
  watch_v2::copyAscii(codex.workItems[0].source,
                      sizeof(codex.workItems[0].source), "codex");
  codex.workItems[0].state = watch_v2::WorkState::Running;
  codex.workItems[1].slot = 1;
  watch_v2::copyAscii(codex.workItems[1].name, sizeof(codex.workItems[1].name),
                      "fix-ci");
  watch_v2::copyAscii(codex.workItems[1].source,
                      sizeof(codex.workItems[1].source), "codex");
  codex.workItems[1].state = watch_v2::WorkState::NeedsInput;
  codex.workItems[2].slot = 2;
  watch_v2::copyAscii(codex.workItems[2].name, sizeof(codex.workItems[2].name),
                      "docs");
  watch_v2::copyAscii(codex.workItems[2].source,
                      sizeof(codex.workItems[2].source), "kimi");
  codex.workItems[2].state = watch_v2::WorkState::Complete;
  codex.workItems[2].latest = true;
  if (std::strcmp(scenario, "v2-sessions-failed") == 0) {
    codex.workItems[2].state = watch_v2::WorkState::Failed;
  }
  codex.activeCount = 2;
  codex.hasActiveCount = true;
  store.apply(codex, 4000);

  if (std::strcmp(scenario, "v2-offline") == 0 ||
      std::strcmp(scenario, "v2-pet-sleep") == 0) {
    return watch_model::Store{};
  }
  return store;
}

watchface::State previewFaceState(const char* scenario) {
  watchface::State state;
  state.nowMs = 60000;
  state.sync = watchface::SyncDot::Synced;
  state.bleConnected = true;
  state.hostLive = true;
  state.timeValid = true;
  state.hour = 21;
  state.minute = 45;
  state.batteryPercent = 82;
  state.firmwareVersion = "0.2.1-tokenlink";
  state.protocolVersion = 2;

  if (std::strcmp(scenario, "v2-home") == 0) {
    state.page = watchface::Page::Home;
  } else if (std::strcmp(scenario, "v2-quota") == 0) {
    state.page = watchface::Page::Quota;
    state.selectedIndex = 0;
  } else if (std::strcmp(scenario, "v2-quota-expanded") == 0) {
    state.page = watchface::Page::Quota;
    state.selectedIndex = 0;
    state.quotaExpanded = true;
  } else if (std::strcmp(scenario, "v2-sessions") == 0 ||
             std::strcmp(scenario, "v2-sessions-failed") == 0) {
    state.page = watchface::Page::Sessions;
    state.selectedIndex = 1;
  } else if (std::strcmp(scenario, "v2-system") == 0) {
    state.page = watchface::Page::System;
  } else if (std::strcmp(scenario, "v2-pet") == 0) {
    state.page = watchface::Page::Home;
    state.petTheme = true;
    state.nowMs = 60500;  // mid bounce
  } else if (std::strcmp(scenario, "v2-pet-sleep") == 0) {
    state.page = watchface::Page::Home;
    state.petTheme = true;
    state.sync = watchface::SyncDot::Offline;
    state.bleConnected = false;
    state.hostLive = false;
  } else if (std::strcmp(scenario, "v2-offline") == 0) {
    state.page = watchface::Page::Home;
    state.sync = watchface::SyncDot::Offline;
    state.bleConnected = false;
    state.hostLive = false;
  }
  return state;
}

bool isV2Scenario(const char* scenario) {
  return std::strncmp(scenario, "v2-", 3) == 0;
}

bool validScenario(const char* scenario) {
  return std::strcmp(scenario, "live") == 0 ||
         std::strcmp(scenario, "ble") == 0 ||
         std::strcmp(scenario, "live-stale") == 0 ||
         std::strcmp(scenario, "offline") == 0 ||
         std::strcmp(scenario, "power-hold") == 0 ||
         std::strcmp(scenario, "power-off") == 0 ||
         std::strcmp(scenario, "v2-home") == 0 ||
         std::strcmp(scenario, "v2-quota") == 0 ||
         std::strcmp(scenario, "v2-quota-expanded") == 0 ||
         std::strcmp(scenario, "v2-sessions") == 0 ||
         std::strcmp(scenario, "v2-sessions-failed") == 0 ||
         std::strcmp(scenario, "v2-system") == 0 ||
         std::strcmp(scenario, "v2-pet") == 0 ||
         std::strcmp(scenario, "v2-pet-sleep") == 0 ||
         std::strcmp(scenario, "v2-offline") == 0;
}

bool writePpm(lgfx::LGFX_Sprite& sprite, const char* path) {
  std::FILE* output = std::fopen(path, "wb");
  if (output == nullptr) return false;
  std::fprintf(output, "P6\n%d %d\n255\n", dashboard::kWidth,
               dashboard::kHeight);
  std::vector<lgfx::bgr888_t> pixels(dashboard::kWidth * dashboard::kHeight);
  sprite.readRectRGB(0, 0, dashboard::kWidth, dashboard::kHeight, pixels.data());
  for (const auto& pixel : pixels) {
    const std::uint8_t rgb[3] = {pixel.R8(), pixel.G8(), pixel.B8()};
    std::fwrite(rgb, 1, sizeof(rgb), output);
  }
  return std::fclose(output) == 0;
}

}  // namespace

int main(int argc, char** argv) {
  const char* outputPath = argc > 1 ? argv[1] : "dashboard-preview.ppm";
  const char* scenario = argc > 2 ? argv[2] : "live";
  if (!validScenario(scenario)) {
    std::fprintf(stderr, "Unknown scenario '%s'\n", scenario);
    return 2;
  }
  lgfx::LGFX_Sprite framebuffer;
  framebuffer.setColorDepth(16);
  if (framebuffer.createSprite(dashboard::kWidth, dashboard::kHeight) == nullptr) {
    std::fprintf(stderr, "Could not allocate preview framebuffer\n");
    return 1;
  }
  framebuffer.setTextWrap(false);
  if (isV2Scenario(scenario)) {
    watch_model::Store store = previewStore(scenario);
    watchface::render(framebuffer, previewFaceState(scenario), store);
  } else {
    dashboard::render(framebuffer, previewState(scenario));
  }
  if (!writePpm(framebuffer, outputPath)) {
    std::fprintf(stderr, "Could not write %s\n", outputPath);
    return 1;
  }
  std::printf("Rendered %s [%s] (%d x %d, RGB565)\n", outputPath, scenario,
              dashboard::kWidth, dashboard::kHeight);
  return 0;
}
