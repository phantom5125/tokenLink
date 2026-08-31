// SPDX-License-Identifier: MIT
// Copyright (c) 2026 imliubo
// StopWatch port changes copyright (c) 2026 Codex Micro for StopWatch contributors

#include <Arduino.h>
#include <M5PM1.h>
#include <M5Unified.h>
#include <Preferences.h>

#include <array>
#include <cmath>
#include <cstring>

#include "CodexMicroBle.h"
#include "CompletionBanner.h"
#include "ConnectionHealth.h"
#include "DashboardUi.h"
#include "PetTheme.h"
#include "PowerButtonInput.h"
#include "PowerButtonGesture.h"
#include "RaiseWake.h"
#include "TouchGesture.h"
#include "WatchFaceUi.h"
#if defined(CODEX_STOPWATCH_USB_MIC)
#include "UsbMic.h"
#endif

namespace {

constexpr uint32_t kQuotaStaleAfterMs = 180000;
constexpr uint32_t kHostRpcLiveForMs = 300000;
constexpr uint32_t kCompletionBannerMs = 5000;
constexpr uint32_t kVoiceTapBannerMs = 900;
constexpr uint32_t kVoiceClickPulseMs = 70;
constexpr uint32_t kTouchKeyPulseMs = 55;
constexpr int kSwipeThresholdPx = 52;
constexpr uint8_t kButtonHapticIntensity = 176;
// 144 (56% PWM duty) sat at the motor's start threshold and spun up only
// sometimes; 176 matches the physical buttons, which never felt flaky.
constexpr uint8_t kTouchHapticIntensity = 176;
constexpr uint8_t kSwipeHapticIntensity = 168;
constexpr uint32_t kWakeHapticDurationMs = 20;
constexpr uint32_t kButtonHapticDurationMs = 42;
constexpr uint32_t kTouchHapticDurationMs = 32;
constexpr uint32_t kSwipeHapticDurationMs = 40;
constexpr uint32_t kBatteryDimAfterMs = 120000;
constexpr uint32_t kBatteryDeskSleepAfterMs = 300000;
constexpr uint32_t kDockDimAfterMs = 600000;
constexpr uint32_t kDockDeskSleepAfterMs = 1800000;
constexpr uint32_t kPowerTelemetryIntervalMs = 2000;
constexpr uint32_t kBatteryTelemetryIntervalMs = 30000;
constexpr uint32_t kPowerHoldPromptMs = 2000;
constexpr uint32_t kTravelPowerOffMs = 6000;
constexpr uint32_t kPowerButtonDoubleClickMs = 500;
constexpr uint8_t kActiveBrightness = 120;
constexpr uint8_t kDimBrightness = 24;
// Protocol v2 timings.
constexpr uint32_t kRightLongPressMs = 600;
constexpr uint32_t kCenterVoiceHoldMs = 600;
constexpr uint32_t kV2RedrawMs = 200;
constexpr uint32_t kSessionsRedrawMs = 250;
constexpr uint32_t kImuPollMs = 100;
// M5Unified's IOExpander_Base API is zero-based: physical M5IOE1 G8 is 7,
// while physical G5 is 4.
constexpr uint8_t kIoeSharedL3bEnable = 7;
constexpr uint8_t kIoePanelReset = 4;
#if defined(CODEX_STOPWATCH_USB_MIC)
// G8 powers the shared L3B rail, including the microphone path. The optional
// USB-mic image therefore keeps G8 on and uses brightness-only desk sleep.
constexpr bool kCutSharedRailInDeskSleep = false;
#else
// The default wireless image can remove the AMOLED/audio/motor L3B rail while
// leaving the ESP32, touch controller, PM1, and BLE transport alive.
constexpr bool kCutSharedRailInDeskSleep = true;
#endif
#if !defined(CODEX_STOPWATCH_USB_MIC)
constexpr uint32_t kCompletionChimeSampleRate = 12000;
constexpr uint32_t kCompletionChimeDurationMs = 270;
constexpr size_t kCompletionChimeSamples =
    kCompletionChimeSampleRate * kCompletionChimeDurationMs / 1000;
constexpr float kPi = 3.14159265358979323846f;
constexpr uint8_t kCompletionChimeVolume = 160;
#endif

constexpr char kLeftMicSwitch[] = "ACT10";
// ChatGPT 26.727 exposes one combined Mic key but no independent ACT10/ACT11
// switch setting. Use the fourth configurable Command Key for Voice Chat.
constexpr char kVoiceChatCommandKey[] = "ACT09";
constexpr char kSendKey[] = "ACT12";
const char* kAgentKeys[] = {"AG00", "AG01", "AG02", "AG03", "AG04", "AG05"};

CodexMicroBle codex;
CodexMicroState state;
M5Canvas canvas(&M5.Display);
M5PM1 powerManager;
uint32_t lastDrawMs = 0;
uint32_t lastBatteryMs = 0;
uint32_t lastPowerTelemetryMs = 0;
uint32_t quotaWaitingSinceMs = 0;
bool leftPressed = false;
bool rightPressed = false;
bool touchAgentPressed = false;
bool touchSendPressed = false;
bool touchTracking = false;
bool voiceTapBannerVisible = false;
bool voiceClickReleasePending = false;
int8_t activeTouchAgent = -1;
int16_t touchStartX = 0;
int16_t touchStartY = 0;
touch_gesture::Direction activeSwipe = touch_gesture::Direction::None;
uint32_t voiceTapBannerUntilMs = 0;
uint32_t voiceClickReleaseAtMs = 0;
uint32_t rightPressedAtMs = 0;
uint32_t touchSendStartedAtMs = 0;
uint32_t lastPowerOverlayDrawMs = 0;
std::array<dashboard::AgentStatus, 6> previousAgentStatuses = {};
std::array<bool, 6> agentStatusObserved = {};
completion_banner::Timer completionBanner;
#if !defined(CODEX_STOPWATCH_USB_MIC)
std::array<int16_t, kCompletionChimeSamples> completionChimePcm = {};
#endif
bool hapticActive = false;
uint32_t hapticUntilMs = 0;
uint32_t lastActivityMs = 0;
uint8_t appliedBrightness = kActiveBrightness;
int8_t batteryPercent = -1;
bool charging = false;
bool docked = false;
bool dockStateInitialized = false;
bool pendingDockState = false;
uint8_t pendingDockSamples = 0;
bool deskSleeping = false;
bool displayRailOff = false;
bool speakerSuspended = false;
bool powerManagerReady = false;
bool powerButtonPollingReady = false;
bool powerButtonPressed = false;
bool powerButtonWokeDisplay = false;
bool pendingPowerClickWokeDisplay = false;
power_button_gesture::Detector powerButtonGesture(kPowerButtonDoubleClickMs);
bool touchPowerHoldConsumed = false;
dashboard::PowerOverlay powerOverlay = dashboard::PowerOverlay::None;
bool renderedHealthValid = false;
dashboard::LinkHealth renderedLinkHealth = dashboard::LinkHealth::Offline;
bool renderedQuotaStale = false;
int8_t renderedBatteryPercent = -1;
bool renderedCharging = false;
bool renderedDocked = false;

// --- Protocol v2 watch-face state -------------------------------------------
watchface::Page currentPage = watchface::Page::Home;
int8_t quotaSelection = 0;
int8_t sessionSelection = 0;
bool quotaExpanded = false;
bool rightLongPressFired = false;
bool centerVoiceFired = false;
int8_t touchSessionItem = -1;
bool touchPetPressed = false;
watchface::Page homeTouchDestination = watchface::Page::Sessions;
uint32_t lastV2RedrawMs = 0;
uint32_t lastImuPollMs = 0;
raise_wake::Detector raiseDetector;
Preferences watchPrefs;
watch_v2::Settings appliedSettings = {};
uint32_t appliedSettingsVersion = 0;

void drawScreen();
void stopHaptic();
[[noreturn]] void enterTravelPowerOff();

void setPanelRail(bool enabled) {
  auto& ioe1 = M5.getIOExpander(0);
  // Official C152 mapping: M5IOE1 G8 is PYB_L3B_EN. G4 is touch reset;
  // pulling G4 low here would make a sleeping display impossible to touch-wake.
  ioe1.setHighImpedance(kIoeSharedL3bEnable, false);
  ioe1.setDirection(kIoeSharedL3bEnable, true);
  ioe1.digitalWrite(kIoeSharedL3bEnable, enabled);
}

void setPanelReset(bool high) {
  auto& ioe1 = M5.getIOExpander(0);
  // Official C152 mapping: M5IOE1 G5 is CO5300 reset.
  ioe1.setHighImpedance(kIoePanelReset, false);
  ioe1.setDirection(kIoePanelReset, true);
  ioe1.digitalWrite(kIoePanelReset, high);
}

void enterDeskSleep() {
  if (deskSleeping || leftPressed || rightPressed || touchTracking) return;
  stopHaptic();
  raiseDetector.reset();
#if !defined(CODEX_STOPWATCH_USB_MIC)
  speakerSuspended = M5.Speaker.isRunning();
  if (speakerSuspended) M5.Speaker.end();
#endif
  M5.Display.setBrightness(0);
#if !defined(CODEX_STOPWATCH_USB_MIC)
  // The USB microphone build keeps the shared AMOLED/audio rail powered and
  // uses brightness-only desk sleep. The CO5300 Sleep Out path through the
  // framebuffer wrapper is not reliable enough on C152 to use while docked.
  M5.Display.sleep();
  M5.Display.waitDisplay();
#endif
  if (kCutSharedRailInDeskSleep) {
    // The repository-owned M5GFX patch forwards sleep to the physical AMOLED
    // and allows a repeat controller init while preserving its framebuffer.
    M5.Display.releaseBus();
    setPanelRail(false);
    displayRailOff = true;
  }
  appliedBrightness = 0;
  deskSleeping = true;
  Serial.printf("POWER desk_sleep dock=%d hard_panel=%d\n", docked ? 1 : 0,
                displayRailOff ? 1 : 0);
}

void wakeDeskSleep() {
  if (!deskSleeping) return;
  if (displayRailOff) {
    setPanelRail(true);
    delay(10);
    setPanelReset(false);
    delay(8);
    setPanelReset(true);
    delay(2);
    // Panel_AMOLED_Framebuffer::init() is patched to forward repeat init to
    // the physical CO5300. This replays the pinned StopWatch command list and
    // re-initializes the released QSPI bus without reallocating the canvas.
    if (!M5.Display.getPanel()->init(true)) {
      Serial.println("POWER panel reinit failed");
    }
    displayRailOff = false;
  }
#if !defined(CODEX_STOPWATCH_USB_MIC)
  else {
    M5.Display.wakeup();
  }
#endif
  M5.Display.setRotation(0);
  M5.Display.setTextWrap(false);
  appliedBrightness = kActiveBrightness;
  M5.Display.setBrightness(appliedBrightness);
#if !defined(CODEX_STOPWATCH_USB_MIC)
  if (speakerSuspended) {
    if (!M5.Speaker.begin()) {
      Serial.println("POWER speaker resume failed");
    }
    M5.Speaker.setVolume(kCompletionChimeVolume);
    speakerSuspended = false;
  }
#endif
  deskSleeping = false;
  drawScreen();
  Serial.println("POWER desk_wake");
}

#if !defined(CODEX_STOPWATCH_USB_MIC)
float softNoteEnvelope(float noteTime, float noteDuration) {
  constexpr float kAttackSeconds = 0.038f;
  constexpr float kReleaseSeconds = 0.100f;
  if (noteTime < 0.0f || noteTime >= noteDuration) return 0.0f;

  float envelope = 1.0f;
  if (noteTime < kAttackSeconds) {
    const float phase = noteTime / kAttackSeconds;
    const float fade = sinf(phase * kPi * 0.5f);
    envelope *= fade * fade;
  }
  const float releaseStart = noteDuration - kReleaseSeconds;
  if (noteTime > releaseStart) {
    const float phase = (noteTime - releaseStart) / kReleaseSeconds;
    const float fade = cosf(phase * kPi * 0.5f);
    envelope *= fade * fade;
  }
  return envelope;
}

void buildCompletionChime() {
  // A subdued A4 -> C#5 major third with rounded attacks and long releases.
  // Keeping this as one PCM buffer avoids the hard edge between two tone() calls.
  constexpr float kFirstFrequency = 440.00f;
  constexpr float kSecondFrequency = 554.37f;
  constexpr float kFirstStart = 0.0f;
  constexpr float kFirstDuration = 0.145f;
  constexpr float kSecondStart = 0.105f;
  constexpr float kSecondDuration = 0.165f;
  constexpr float kPeakAmplitude = 0.135f * 32767.0f;

  for (size_t sample = 0; sample < completionChimePcm.size(); ++sample) {
    const float time = static_cast<float>(sample) / kCompletionChimeSampleRate;
    const float firstTime = time - kFirstStart;
    const float secondTime = time - kSecondStart;
    const float first =
        sinf(2.0f * kPi * kFirstFrequency * firstTime) *
        softNoteEnvelope(firstTime, kFirstDuration);
    const float second =
        sinf(2.0f * kPi * kSecondFrequency * secondTime) *
        softNoteEnvelope(secondTime, kSecondDuration);
    completionChimePcm[sample] =
        static_cast<int16_t>(kPeakAmplitude * (first + second));
  }
}
#endif

void startHaptic(uint8_t intensity, uint32_t durationMs) {
  M5.Power.setVibration(intensity);
  hapticActive = true;
  hapticUntilMs = millis() + durationMs;
}

void stopHaptic() {
  M5.Power.setVibration(0);
  hapticActive = false;
}

void updateHaptic() {
  if (!hapticActive || static_cast<int32_t>(millis() - hapticUntilMs) < 0) return;
  stopHaptic();
}

// Returns false when the screen was fully off, so the waking tap can be
// swallowed instead of acting on a control the user could not see.
bool noteActivity() {
  // Any non-power interaction after the first red click means the user did
  // not intend to put the desk to sleep. A second red click still reaches the
  // detector because red-button polling does not call noteActivity().
  powerButtonGesture.cancel();
  pendingPowerClickWokeDisplay = false;
  lastActivityMs = millis();
  if (deskSleeping) {
    wakeDeskSleep();
    return false;
  }
  if (appliedBrightness == kActiveBrightness) return true;
  const bool wasOff = appliedBrightness == 0;
  appliedBrightness = kActiveBrightness;
  M5.Display.setBrightness(kActiveBrightness);
  if (wasOff) drawScreen();  // redraws were paused while the panel was dark
  return !wasOff;
}

void updateIdleDimming() {
  // A held mic button or an ongoing touch counts as continuous use.
  if (leftPressed || rightPressed || touchTracking) lastActivityMs = millis();
  const uint32_t idleMs = millis() - lastActivityMs;
  const uint32_t dimAfterMs = docked ? kDockDimAfterMs : kBatteryDimAfterMs;
  const uint32_t sleepAfterMs =
      docked ? kDockDeskSleepAfterMs : kBatteryDeskSleepAfterMs;
  if (idleMs >= sleepAfterMs) {
    enterDeskSleep();
    return;
  }
  if (deskSleeping) return;
  const uint8_t target =
      idleMs >= dimAfterMs ? kDimBrightness : kActiveBrightness;
  if (target != appliedBrightness) {
    appliedBrightness = target;
    M5.Display.setBrightness(target);
  }
}

void updateVoiceTapBanner() {
  if (!voiceTapBannerVisible ||
      static_cast<int32_t>(millis() - voiceTapBannerUntilMs) < 0) {
    return;
  }
  voiceTapBannerVisible = false;
  drawScreen();
}

void beginVoiceChatClick() {
  if (voiceClickReleasePending) {
    codex.sendKey(kVoiceChatCommandKey, 0);
  }
  codex.sendKey(kVoiceChatCommandKey, 1);
  voiceClickReleasePending = true;
  voiceClickReleaseAtMs = millis() + kVoiceClickPulseMs;
}

void updateVoiceChatClick() {
  if (!voiceClickReleasePending ||
      static_cast<int32_t>(millis() - voiceClickReleaseAtMs) < 0) {
    return;
  }
  codex.sendKey(kVoiceChatCommandKey, 0);
  voiceClickReleasePending = false;
}

dashboard::ThreadVisual threadVisual(const ThreadLight& light) {
  dashboard::ThreadVisual visual;
  visual.color = light.color;
  visual.brightness = light.brightness;
  // Current Codex Desktop marks the focused slot with s=0.4 while e remains
  // "off". Keep accepting the older explicit breath effect as a focus signal.
  visual.focused = light.effect == "breath" || light.speed > 0.01f;
  return visual;
}

dashboard::AgentStatus classifyAgent(const ThreadLight& light) {
  return dashboard::classify(threadVisual(light));
}

uint32_t quotaResetRemaining() {
  if (!state.quota.available) return 0;
  const uint32_t elapsed = (millis() - state.quota.receivedAtMs) / 1000;
  return elapsed >= state.quota.resetInSeconds ? 0 : state.quota.resetInSeconds - elapsed;
}

connection_health::Result connectionHealth() {
  connection_health::Input input;
  input.bleConnected = state.connected;
  input.hostRpcObserved = state.hostRpcObserved;
  input.lastHostRpcAtMs = state.lastHostRpcAtMs;
  input.quotaWaitingSinceMs = quotaWaitingSinceMs;
  input.quotaAvailable = state.quota.available;
  input.quotaReceivedAtMs = state.quota.receivedAtMs;
  return connection_health::evaluate(input, millis(), kHostRpcLiveForMs,
                                     kQuotaStaleAfterMs);
}

dashboard::LinkHealth dashboardLinkHealth(connection_health::Link link) {
  switch (link) {
    case connection_health::Link::CodexLive:
      return dashboard::LinkHealth::CodexLive;
    case connection_health::Link::BleOnly:
      return dashboard::LinkHealth::BleOnly;
    case connection_health::Link::Offline:
      return dashboard::LinkHealth::Offline;
  }
  return dashboard::LinkHealth::Offline;
}

dashboard::State dashboardState() {
  dashboard::State ui;
  const connection_health::Result health = connectionHealth();
  ui.linkHealth = dashboardLinkHealth(health.link);
  ui.batteryPercent = batteryPercent;
  ui.charging = charging;
  ui.docked = docked;
  ui.quotaAvailable = state.quota.available;
  ui.quotaStale = health.quota == connection_health::Quota::Stale;
  ui.remainingPercent = state.quota.remainingPercent;
  ui.resetInSeconds = quotaResetRemaining();
  ui.leftPressed = leftPressed;
  ui.rightPressed = rightPressed || voiceTapBannerVisible;
  ui.sendPressed = touchSendPressed;
  ui.activeTouchAgent = touchAgentPressed ? activeTouchAgent : -1;
  ui.swipeDirection = static_cast<int>(activeSwipe);
  ui.completedAgent =
      completionBanner.visible(millis()) ? completionBanner.agent : -1;
  ui.powerOverlay = powerOverlay;
  if (touchPowerHoldConsumed) {
    const uint32_t heldMs = millis() - touchSendStartedAtMs;
    ui.powerHoldProgress = std::max(
        0.0f, std::min(1.0f,
            static_cast<float>(heldMs - kPowerHoldPromptMs) /
                static_cast<float>(kTravelPowerOffMs - kPowerHoldPromptMs)));
  }
  for (int i = 0; i < 6; ++i) ui.threads[i] = threadVisual(state.threads[i]);
  return ui;
}

// --- Protocol v2 watch face ---------------------------------------------------

bool v2Mode() { return state.watchProtocol == 2; }

watchface::SyncDot syncDot() {
  if (!state.connected) return watchface::SyncDot::Offline;
  const watch_model::Store& store = state.watchStore;
  uint32_t newest = 0;
  bool any = false;
  for (size_t i = 0; i < store.providerCount(); ++i) {
    const watch_model::ProviderEntry* provider = store.providerAt(i);
    if (provider->receivedAtMs > 0 &&
        (!any || millis() - provider->receivedAtMs < millis() - newest)) {
      newest = provider->receivedAtMs;
      any = true;
    }
  }
  if (!any) return watchface::SyncDot::Stale;
  return millis() - newest <= kQuotaStaleAfterMs ? watchface::SyncDot::Synced
                                                 : watchface::SyncDot::Stale;
}

watchface::State watchfaceState() {
  watchface::State ui;
  ui.page = currentPage;
  ui.nowMs = millis();
  ui.sync = syncDot();
  ui.bleConnected = state.connected;
  ui.hostLive =
      connectionHealth().link == connection_health::Link::CodexLive;

  m5::rtc_time_t time;
  if (M5.Rtc.isEnabled() && M5.Rtc.getTime(&time)) {
    ui.timeValid = true;
    ui.hour = time.hours;
    ui.minute = time.minutes;
  }
  ui.hourFormat = appliedSettings.hourFormat;

  // Keep selections inside their (possibly shrunk) item ranges.
  const size_t providerCount = state.watchStore.providerCount();
  const uint8_t workItemCount = state.watchStore.workItemCount();
  if (providerCount == 0) quotaSelection = 0;
  if (workItemCount == 0) sessionSelection = 0;
  if (quotaSelection >= static_cast<int8_t>(providerCount)) {
    quotaSelection = static_cast<int8_t>(providerCount) - 1;
  }
  if (sessionSelection >= static_cast<int8_t>(workItemCount)) {
    sessionSelection = static_cast<int8_t>(workItemCount) - 1;
  }
  ui.selectedIndex = currentPage == watchface::Page::Sessions
                         ? sessionSelection
                         : quotaSelection;
  ui.quotaExpanded = quotaExpanded;
  ui.face = appliedSettings.face;

  ui.batteryPercent = batteryPercent;
  ui.charging = charging;
  ui.firmwareVersion = CodexMicroBle::kFirmwareVersion;
  ui.protocolVersion = state.watchProtocol;

  if (touchSendPressed && currentPage == watchface::Page::Home) {
    ui.transient = "SEND";
    ui.transientColor = dashboard::kText;
  } else if (leftPressed) {
    ui.transient = "LISTENING";
    ui.transientColor = dashboard::kAccent;
  } else if (voiceTapBannerVisible) {
    ui.transient = "VOICE CHAT";
    ui.transientColor = dashboard::kVoice;
  } else if (activeSwipe != touch_gesture::Direction::None) {
    static constexpr const char* kSwipeMessages[] = {
        "STICK / UP", "STICK / RIGHT", "STICK / DOWN", "STICK / LEFT"};
    ui.transient = kSwipeMessages[static_cast<int>(activeSwipe)];
    ui.transientColor = dashboard::kAccent;
  }

  ui.powerOverlay = powerOverlay;
  if (touchPowerHoldConsumed) {
    const uint32_t heldMs = millis() - touchSendStartedAtMs;
    ui.powerHoldProgress = std::max(
        0.0f, std::min(1.0f,
            static_cast<float>(heldMs - kPowerHoldPromptMs) /
                static_cast<float>(kTravelPowerOffMs - kPowerHoldPromptMs)));
  }
  return ui;
}

void loadWatchSettings() {
  if (!watchPrefs.begin("codex-watch", true)) return;
  appliedSettings.face = watchPrefs.getUChar("theme", 0) == 1
                             ? watch_face_runtime::FaceID::Pet
                             : watch_face_runtime::FaceID::Data;
  appliedSettings.wake = watchPrefs.getUChar("wake", 0) == 1
                             ? watch_v2::WakeMode::Tap
                             : watch_v2::WakeMode::Raise;
  const uint8_t hourFormat = watchPrefs.getUChar("hourfmt", 0);
  appliedSettings.hourFormat = hourFormat == 1   ? watch_v2::HourFormat::H12
                               : hourFormat == 2 ? watch_v2::HourFormat::H24
                                                 : watch_v2::HourFormat::System;
  watchPrefs.end();
}

void persistWatchSettings() {
  if (!watchPrefs.begin("codex-watch", false)) return;
  watchPrefs.putUChar("theme",
                      appliedSettings.face == watch_face_runtime::FaceID::Pet
                          ? 1
                          : 0);
  watchPrefs.putUChar("wake",
                      appliedSettings.wake == watch_v2::WakeMode::Tap ? 1 : 0);
  watchPrefs.putUChar(
      "hourfmt", appliedSettings.hourFormat == watch_v2::HourFormat::H12 ? 1
                 : appliedSettings.hourFormat == watch_v2::HourFormat::H24 ? 2
                                                                           : 0);
  watchPrefs.end();
}

// The Mac owns watch settings; the firmware applies and persists whatever the
// latest v2 payload carried.
void applySettingsFromStore() {
  const uint32_t version = state.watchStore.settingsVersion();
  if (version == appliedSettingsVersion) return;
  appliedSettingsVersion = version;
  appliedSettings = state.watchStore.settings();
  persistWatchSettings();
  Serial.printf("WATCH settings face=%d wake=%d hourfmt=%d\n",
                static_cast<int>(appliedSettings.face),
                static_cast<int>(appliedSettings.wake),
                static_cast<int>(appliedSettings.hourFormat));
  drawScreen();
}

void focusWorkItem(int8_t index) {
  if (index < 0 || index >= state.watchStore.workItemCount()) return;
  const watch_v2::WorkItem& item = state.watchStore.workItems()[index];
  // Only Codex work items can be focused in v2 (design: other sources are
  // read-only on the watch). The Mac resolves slot -> session.
  if (std::strcmp(item.source, "codex") != 0) {
    Serial.printf("WATCH focus ignored source=%s slot=%u\n", item.source,
                  item.slot);
    return;
  }
  codex.sendWatchCommand("focus", static_cast<int8_t>(item.slot));
}

void pagePrimaryAction() {
  switch (currentPage) {
    case watchface::Page::Home:
      currentPage = watchface::Page::Sessions;
      quotaExpanded = false;
      break;
    case watchface::Page::Quota:
      quotaExpanded = !quotaExpanded;
      break;
    case watchface::Page::Sessions:
      focusWorkItem(sessionSelection);
      break;
    case watchface::Page::System:
      codex.sendWatchCommand("refresh");
      break;
  }
}

void adjustSelection(int delta) {
  if (currentPage == watchface::Page::Quota && !quotaExpanded) {
    const int count = static_cast<int>(state.watchStore.providerCount());
    if (count > 0) quotaSelection = (quotaSelection + delta + count) % count;
  } else if (currentPage == watchface::Page::Sessions) {
    const int count = state.watchStore.workItemCount();
    if (count > 0) sessionSelection = (sessionSelection + delta + count) % count;
  }
}

void drawScreen() {
  if (deskSleeping) return;
  const dashboard::State legacyUi = dashboardState();
  if (v2Mode()) {
    const watchface::State ui = watchfaceState();
    watchface::render(canvas, ui, state.watchStore);
  } else {
    dashboard::render(canvas, legacyUi);
  }
  canvas.pushSprite(0, 0);
  lastDrawMs = millis();
  renderedHealthValid = true;
  renderedLinkHealth = legacyUi.linkHealth;
  renderedQuotaStale = legacyUi.quotaStale;
  renderedBatteryPercent = legacyUi.batteryPercent;
  renderedCharging = legacyUi.charging;
  renderedDocked = legacyUi.docked;
}

int8_t agentAtPoint(int x, int y) {
  return static_cast<int8_t>(dashboard::agentAtPoint(x, y));
}

void beginTouchAgent(int8_t agent) {
  if (agent < 0 || agent >= 6) return;
  touchAgentPressed = true;
  activeTouchAgent = agent;
  drawScreen();
}

void commitTouchAgent() {
  if (!touchAgentPressed || activeTouchAgent < 0) return;
  const int8_t agent = activeTouchAgent;
  startHaptic(kTouchHapticIntensity, kTouchHapticDurationMs);
  codex.sendKey(kAgentKeys[agent], 1, agent);
  delay(kTouchKeyPulseMs);
  codex.sendKey(kAgentKeys[agent], 0, agent);
  // Stop here for a deterministic pulse; leaving it to the loop-end check
  // stretched the buzz by however long the next full redraw took.
  stopHaptic();
  touchAgentPressed = false;
  activeTouchAgent = -1;
  drawScreen();
}

void beginTouchSend() {
  if (touchSendPressed) return;
  touchSendPressed = true;
  touchSendStartedAtMs = millis();
  touchPowerHoldConsumed = false;
  centerVoiceFired = false;
  drawScreen();
}

void commitTouchSend() {
  if (!touchSendPressed) return;
  const uint32_t heldMs = millis() - touchSendStartedAtMs;
  startHaptic(kTouchHapticIntensity, kTouchHapticDurationMs);
  if (v2Mode()) {
    // Protocol v2 has no hidden single/double/long-press shortcuts. A release
    // activates only the visible target selected in beginTouchGesture().
    (void)heldMs;
    if (currentPage == watchface::Page::Home) {
      currentPage = homeTouchDestination;
      quotaExpanded = false;
    } else {
      pagePrimaryAction();
    }
    homeTouchDestination = watchface::Page::Sessions;
    touchSendPressed = false;
  } else {
    codex.sendKey(kSendKey, 1);
    delay(kTouchKeyPulseMs);
    codex.sendKey(kSendKey, 0);
    touchSendPressed = false;
  }
  // Stop here for a deterministic pulse; leaving it to the loop-end check
  // stretched the buzz by however long the next full redraw took.
  stopHaptic();
  drawScreen();
}

void clearTouchCandidate() {
  touchAgentPressed = false;
  touchSendPressed = false;
  touchSessionItem = -1;
  touchPetPressed = false;
  homeTouchDestination = watchface::Page::Sessions;
  activeTouchAgent = -1;
}

void commitTouchSessionItem() {
  const int8_t item = touchSessionItem;
  touchSessionItem = -1;
  if (item < 0) return;
  sessionSelection = item;
  startHaptic(kTouchHapticIntensity, kTouchHapticDurationMs);
  focusWorkItem(item);
  stopHaptic();
  drawScreen();
}

void commitTouchPet() {
  touchPetPressed = false;
  startHaptic(kTouchHapticIntensity, kTouchHapticDurationMs);
  codex.sendWatchCommand("refresh");
  stopHaptic();
  drawScreen();
}

void beginTouchGesture(int x, int y) {
  touchTracking = true;
  touchStartX = static_cast<int16_t>(x);
  touchStartY = static_cast<int16_t>(y);
  activeSwipe = touch_gesture::Direction::None;

  if (v2Mode()) {
    const watch_face_runtime::Descriptor& face =
        watch_face_runtime::descriptor(appliedSettings.face);
    Serial.printf("TOUCH begin x=%d y=%d page=%d\n", x, y,
                  static_cast<int>(currentPage));
    if (currentPage == watchface::Page::Sessions) {
      const int item = watchface::workItemAtPoint(
          x, y, state.watchStore.workItemCount());
      if (item >= 0) {
        touchSessionItem = static_cast<int8_t>(item);
        drawScreen();
        return;
      }
    }
    if (currentPage == watchface::Page::Home &&
        face.homeInteraction ==
            watch_face_runtime::HomeInteraction::NavigateCards) {
      if (watchface::homeSessionsAtPoint(x, y)) {
        homeTouchDestination = watchface::Page::Sessions;
        beginTouchSend();
        return;
      }
      if (watchface::homeQuotaAtPoint(x, y)) {
        homeTouchDestination = watchface::Page::Quota;
        beginTouchSend();
        return;
      }
    }
    if (currentPage == watchface::Page::Quota) {
      if (quotaExpanded) {
        if (x >= 64 && x <= 402 && y >= 80 && y <= 430) beginTouchSend();
        return;
      }
      const int provider = watchface::quotaProviderAtPoint(
          x, y, state.watchStore.providerCount(), quotaSelection);
      if (provider >= 0) {
        quotaSelection = static_cast<int8_t>(provider);
        beginTouchSend();
      }
      return;
    }
    if (currentPage == watchface::Page::System) {
      if (watchface::systemRefreshAtPoint(x, y)) beginTouchSend();
      return;
    }
    if (currentPage == watchface::Page::Home &&
        face.homeInteraction ==
            watch_face_runtime::HomeInteraction::RefreshPrimary &&
        petface::atPoint(x, y, watchface::kCenterX, watchface::kPetTop)) {
      touchPetPressed = true;
      return;
    }
    return;
  }

  const int8_t agent = agentAtPoint(x, y);
  Serial.printf("TOUCH begin x=%d y=%d agent=%d send=%d\n", x, y, agent,
                dashboard::sendAtPoint(x, y) ? 1 : 0);
  if (agent >= 0) {
    beginTouchAgent(agent);
  } else if (dashboard::sendAtPoint(x, y)) {
    beginTouchSend();
  }
}

void updateTouchGesture(int x, int y) {
  if (!touchTracking || touchPowerHoldConsumed ||
      activeSwipe != touch_gesture::Direction::None) {
    return;
  }
  const touch_gesture::Direction direction = touch_gesture::classifySwipe(
      x - touchStartX, y - touchStartY, kSwipeThresholdPx);
  if (direction == touch_gesture::Direction::None) return;

  clearTouchCandidate();
  activeSwipe = direction;
  startHaptic(kSwipeHapticIntensity, kSwipeHapticDurationMs);
  if (v2Mode()) {
    if (direction == touch_gesture::Direction::Left) {
      currentPage = watchface::nextPage(currentPage);
      quotaExpanded = false;
    }
    if (direction == touch_gesture::Direction::Right) {
      currentPage = watchface::previousPage(currentPage);
      quotaExpanded = false;
    }
    if (direction == touch_gesture::Direction::Up) adjustSelection(-1);
    if (direction == touch_gesture::Direction::Down) adjustSelection(1);
    Serial.printf("SWIPE direction=%s action=watch-ui page=%d\n",
                  touch_gesture::name(direction),
                  static_cast<int>(currentPage));
    drawScreen();
    return;
  }
  const float angle = touch_gesture::normalizedAngle(direction);
  codex.sendJoystick(angle, 1.0f);
  Serial.printf("SWIPE direction=%s angle=%.2f action=press\n",
                touch_gesture::name(direction), angle);
  drawScreen();
}

void finishTouchGesture() {
  if (!touchTracking) return;
  touchTracking = false;
  if (centerVoiceFired) {
    centerVoiceFired = false;
    voiceTapBannerVisible = false;
  }

  if (touchPowerHoldConsumed) {
    touchPowerHoldConsumed = false;
    powerOverlay = dashboard::PowerOverlay::None;
    clearTouchCandidate();
    drawScreen();
    return;
  }

  if (activeSwipe != touch_gesture::Direction::None) {
    const touch_gesture::Direction direction = activeSwipe;
    if (!v2Mode()) {
      const float angle = touch_gesture::normalizedAngle(direction);
      codex.sendJoystick(angle, 0.0f);
      Serial.printf("SWIPE direction=%s angle=%.2f action=release\n",
                    touch_gesture::name(direction), angle);
    }
    activeSwipe = touch_gesture::Direction::None;
    clearTouchCandidate();
    drawScreen();
    return;
  }

  if (touchAgentPressed) {
    commitTouchAgent();
  } else if (touchSessionItem >= 0) {
    commitTouchSessionItem();
  } else if (touchPetPressed) {
    commitTouchPet();
  } else if (touchSendPressed) {
    commitTouchSend();
  } else {
    clearTouchCandidate();
  }
}

void updateTouchPowerHold() {
  if (!touchTracking || activeSwipe != touch_gesture::Direction::None) return;
  // v2 deliberately has no invisible touch-and-hold command. Travel power-off
  // stays on the dedicated power control instead of overloading a data card.
  if (v2Mode()) return;
  if (!touchSendPressed && !touchPowerHoldConsumed) return;

  const uint32_t now = millis();
  const uint32_t heldMs = now - touchSendStartedAtMs;
  if (!touchPowerHoldConsumed && heldMs >= kPowerHoldPromptMs) {
    touchPowerHoldConsumed = true;
    touchSendPressed = false;  // releasing now must not emit Send
    powerOverlay = dashboard::PowerOverlay::HoldToPowerOff;
    lastPowerOverlayDrawMs = 0;
    startHaptic(kButtonHapticIntensity, kButtonHapticDurationMs);
  }
  if (!touchPowerHoldConsumed) return;
  if (heldMs >= kTravelPowerOffMs) enterTravelPowerOff();
  if (lastPowerOverlayDrawMs == 0 || now - lastPowerOverlayDrawMs >= 100) {
    lastPowerOverlayDrawMs = now;
    drawScreen();
  }
}

void startCompletionChime(int8_t agent) {
  noteActivity();  // a finished agent is worth lighting the screen for
  startHaptic(kButtonHapticIntensity, kButtonHapticDurationMs);
  completionBanner.show(agent, millis(), kCompletionBannerMs);
#if defined(CODEX_STOPWATCH_USB_MIC)
  const auto chimeRequest = stopwatch_usb_mic::requestCompletionChime();
  Serial.printf("Agent %d completed; local_chime_request=%u\n", agent + 1,
                static_cast<unsigned>(chimeRequest));
#else
  M5.Speaker.playRaw(completionChimePcm.data(), completionChimePcm.size(),
                     kCompletionChimeSampleRate, false, 1, -1, true);
  Serial.printf("Agent %d completed; soft chime played\n", agent + 1);
#endif
}

bool expireCompletionBanner(uint32_t now) {
  return completionBanner.expire(now);
}

void detectAgentTransitions(const CodexMicroState& latest) {
  for (int i = 0; i < 6; ++i) {
    const dashboard::AgentStatus next = classifyAgent(latest.threads[i]);
    if (agentStatusObserved[i] &&
        previousAgentStatuses[i] != dashboard::AgentStatus::Complete &&
        next == dashboard::AgentStatus::Complete) {
      startCompletionChime(static_cast<int8_t>(i));
    }
    // Requires-input also wakes the screen; routine status refreshes must not,
    // or host polling would keep the panel lit around the clock.
    if (agentStatusObserved[i] && previousAgentStatuses[i] != next &&
        next == dashboard::AgentStatus::RequiresInput) {
      noteActivity();
    }
    previousAgentStatuses[i] = next;
    agentStatusObserved[i] = true;
  }
}

void observeDockState(bool candidate) {
  if (dockStateInitialized && candidate == docked) {
    pendingDockSamples = 0;
    return;
  }
  if (pendingDockSamples == 0 || pendingDockState != candidate) {
    pendingDockState = candidate;
    pendingDockSamples = 1;
    return;
  }
  if (++pendingDockSamples < 2) return;

  const bool changed = !dockStateInitialized || docked != candidate;
  docked = candidate;
  dockStateInitialized = true;
  pendingDockSamples = 0;
  if (!changed) return;

  Serial.printf("POWER mode=%s\n", docked ? "dock" : "battery");
  if (docked) {
    // Plugging into a dock is intentional activity and should reveal the
    // charging state even if the panel had already entered desk sleep.
    lastActivityMs = millis();
    if (deskSleeping) wakeDeskSleep();
  }
}

void updatePowerTelemetry(bool force = false) {
  const uint32_t now = millis();
  bool batteryChanged = false;

  if (force || lastBatteryMs == 0 ||
      now - lastBatteryMs >= kBatteryTelemetryIntervalMs) {
    lastBatteryMs = now;
    const int level = M5.Power.getBatteryLevel();
    const int8_t nextLevel =
        level < 0 ? -1 : static_cast<int8_t>(constrain(level, 0, 100));
    batteryChanged = batteryPercent != nextLevel;
    batteryPercent = nextLevel;
  }

  if (force || lastPowerTelemetryMs == 0 ||
      now - lastPowerTelemetryMs >= kPowerTelemetryIntervalMs) {
    lastPowerTelemetryMs = now;
    const bool nextCharging =
        M5.Power.isCharging() == m5::Power_Class::is_charging;
    batteryChanged = batteryChanged || charging != nextCharging;
    charging = nextCharging;

    const int vinMv = M5.Power.getVBUSVoltage();
    // Hysteresis prevents a marginal cable from bouncing power policy. VIN,
    // not charge state, defines Dock Mode because a full battery may not be
    // actively charging while it is still externally powered.
    const bool candidateDock = dockStateInitialized && docked
                                   ? vinMv >= 3500
                                   : vinMv >= 4000;
    observeDockState(candidateDock);
  }

  if (batteryChanged && batteryPercent >= 0) {
    codex.setBattery(static_cast<uint8_t>(batteryPercent), charging);
  }
}

void releaseControlsForPowerOff() {
  if (leftPressed) {
    codex.sendKey(kLeftMicSwitch, 0);
    leftPressed = false;
  }
  if (voiceClickReleasePending) {
    codex.sendKey(kVoiceChatCommandKey, 0);
    voiceClickReleasePending = false;
  }
  if (activeSwipe != touch_gesture::Direction::None) {
    codex.sendJoystick(touch_gesture::normalizedAngle(activeSwipe), 0.0f);
    activeSwipe = touch_gesture::Direction::None;
  }
  rightPressed = false;
  voiceTapBannerVisible = false;
  touchTracking = false;
  clearTouchCandidate();
  codex.poll();
  delay(80);
  codex.poll();
}

[[noreturn]] void enterTravelPowerOff() {
  touchPowerHoldConsumed = true;
  powerOverlay = dashboard::PowerOverlay::PoweringOff;
  drawScreen();
  startHaptic(kButtonHapticIntensity, 60);
  delay(70);
  stopHaptic();
  delay(480);  // leave enough time to read the offline warning

  releaseControlsForPowerOff();
#if !defined(CODEX_STOPWATCH_USB_MIC)
  M5.Speaker.stop();
  M5.Speaker.end();
#endif
  M5.Display.setBrightness(0);
  M5.Display.sleep();
  M5.Display.waitDisplay();
  Serial.println("POWER travel_off wake=power_button_or_vin");
  Serial.flush();

  if (powerManagerReady) {
    const m5pm1_err_t result = powerManager.shutdown();
    Serial.printf("POWER PM1 shutdown returned=%d\n", static_cast<int>(result));
    Serial.flush();
  }
  // A successful PM1 shutdown removes power and never reaches here. Retry the
  // PM1 command through M5Unified, but never fall into an unconfigured ESP
  // deep sleep: the PM1 button and VIN would not necessarily wake that state.
  const bool fallbackSent = M5.Power.M5pm1.powerOff();
  Serial.printf("POWER PM1 fallback sent=%d\n", fallbackSent ? 1 : 0);
  Serial.flush();
  delay(500);
  // Both PM1 commands failed if execution is still alive. Reboot to a usable
  // dashboard rather than leaving the device permanently black.
  esp_restart();
  while (true) delay(1000);
}

void beginPowerButtonPress() {
  powerButtonPressed = true;
  powerButtonWokeDisplay = deskSleeping;
  lastActivityMs = millis();
  if (deskSleeping) {
    wakeDeskSleep();
    startHaptic(kButtonHapticIntensity, kWakeHapticDurationMs);
  }
}

void registerPowerButtonClick(bool wokeDisplay, uint32_t now) {
  const power_button_gesture::Event event = powerButtonGesture.release(now);
  if (event == power_button_gesture::Event::DoubleClick) {
    pendingPowerClickWokeDisplay = false;
    enterTravelPowerOff();
  }
  pendingPowerClickWokeDisplay = wokeDisplay;
}

void finishPowerButtonPress() {
  if (!powerButtonPressed) return;
  powerButtonPressed = false;
  registerPowerButtonClick(powerButtonWokeDisplay, millis());
  powerButtonWokeDisplay = false;
}

void completeLatchedPowerButtonClick(uint32_t now) {
  const bool wokeDisplay = deskSleeping;
  lastActivityMs = now;
  if (wokeDisplay) {
    wakeDeskSleep();
    startHaptic(kButtonHapticIntensity, kWakeHapticDurationMs);
  }
  Serial.printf("POWER red irq_click wake=%d\n", wokeDisplay ? 1 : 0);
  registerPowerButtonClick(wokeDisplay, now);
}

void updatePowerButton() {
  static uint32_t lastPollMs = 0;
  const uint32_t now = millis();
  if (powerButtonPollingReady) {
    const power_button_gesture::Event delayed = powerButtonGesture.poll(now);
    if (delayed == power_button_gesture::Event::SingleClick) {
      if (!pendingPowerClickWokeDisplay) enterDeskSleep();
      pendingPowerClickWokeDisplay = false;
    }

    // M5.update() runs first and consumes PM1's latched click IRQ into BtnPWR.
    // Capture it on every loop; unlike the instantaneous state below, this
    // survives clicks that begin and end between the 25 ms direct samples.
    const bool unifiedClicked = M5.BtnPWR.wasClicked();
    bool directSampled = false;
    bool pressed = false;
    if (lastPollMs == 0 || now - lastPollMs >= 25) {
      lastPollMs = now;
      directSampled = powerManager.btnGetState(&pressed) == M5PM1_OK;
    }

    const power_button_input::Action action = power_button_input::arbitrate(
        directSampled, pressed, powerButtonPressed, unifiedClicked);
    switch (action) {
      case power_button_input::Action::BeginPress:
        beginPowerButtonPress();
        break;
      case power_button_input::Action::FinishPress:
        finishPowerButtonPress();
        break;
      case power_button_input::Action::CompleteClick:
        completeLatchedPowerButtonClick(now);
        break;
      case power_button_input::Action::None:
        break;
    }
    return;
  }

  // The full PM1 path should be available on C152. Keep a degraded fallback
  // so the red key still has deterministic behavior if direct PM1 init fails.
  if (M5.BtnPWR.wasClicked()) {
    if (deskSleeping) {
      lastActivityMs = now;
      wakeDeskSleep();
    } else {
      enterDeskSleep();
    }
  }
}

void pressMicSwitch(const char* key, bool& pressed) {
  if (pressed) return;
  pressed = true;
  startHaptic(kButtonHapticIntensity, kButtonHapticDurationMs);
  codex.sendKey(key, 1);
  drawScreen();
}

void releaseMicSwitch(const char* key, bool& pressed) {
  if (!pressed) return;
  pressed = false;
  codex.sendKey(key, 0);
  drawScreen();
}

// v2 right-button long press: jump straight home from any page.
void updateRightButtonHold() {
  if (!v2Mode() || !rightPressed || rightLongPressFired) return;
  if (millis() - rightPressedAtMs < kRightLongPressMs) return;
  rightLongPressFired = true;
  currentPage = watchface::Page::Home;
  quotaExpanded = false;
  startHaptic(kButtonHapticIntensity, kButtonHapticDurationMs);
  Serial.println("PAGE home (right long press)");
  drawScreen();
}

// Desk sleep keeps the ESP32 and BLE alive, so raise-to-wake is a low-rate
// accelerometer poll instead of a deep-sleep interrupt. The BMI270 wrist
// gesture engine would need Bosch's 8 KB feature blob, which this port does
// not ship; see RaiseWake.h.
void pollRaiseWake() {
  if (!deskSleeping || appliedSettings.wake != watch_v2::WakeMode::Raise ||
      !M5.Imu.isEnabled()) {
    return;
  }
  const uint32_t now = millis();
  if (now - lastImuPollMs < kImuPollMs) return;
  lastImuPollMs = now;
  float ax = 0.0f, ay = 0.0f, az = 0.0f;
  if (!M5.Imu.getAccel(&ax, &ay, &az)) return;
  if (raiseDetector.sample(ax, ay, az, now)) {
    Serial.printf("WAKE raise ax=%.2f ay=%.2f az=%.2f\n", ax, ay, az);
    lastActivityMs = now;
    wakeDeskSleep();
    startHaptic(kButtonHapticIntensity, kWakeHapticDurationMs);
  }
}

}  // namespace

void setup() {
  Serial.begin(115200);
  delay(100);
  Serial.println("Codex Micro StopWatch port boot");

  auto config = M5.config();
  config.clear_display = true;
#if defined(CODEX_STOPWATCH_USB_MIC)
  config.internal_spk = false;
  config.internal_mic = true;
#endif
  M5.begin(config);
  quotaWaitingSinceMs = millis();
  M5.Display.setRotation(0);
  M5.Display.setBrightness(kActiveBrightness);
  M5.Display.setTextWrap(false);
  const m5pm1_err_t pm1Status = powerManager.begin(&M5.In_I2C);
  powerManagerReady = pm1Status == M5PM1_OK;
  if (powerManagerReady) {
    uint8_t wakeSource = 0;
    if (powerManager.getWakeSource(&wakeSource, M5PM1_CLEAN_ONCE) == M5PM1_OK) {
      Serial.printf("POWER wake_source=0x%02X\n", wakeSource);
    }
    // Travel Mode has no automatic timeout in this release. Clear a timer
    // left behind by factory/demo firmware so shutdown stays deterministic.
    const m5pm1_err_t timerStatus = powerManager.timerClear();
    if (timerStatus != M5PM1_OK) {
      Serial.printf("POWER stale timer clear failed=%d\n",
                    static_cast<int>(timerStatus));
    }
    // Discard the click used to boot from Travel Mode. Runtime clicks are read
    // by M5Unified and merged with direct button-state samples in the loop.
    const m5pm1_err_t buttonIrqClearStatus = powerManager.irqClearBtnAll();
    if (buttonIrqClearStatus != M5PM1_OK) {
      Serial.printf("POWER stale button IRQ clear failed=%d\n",
                    static_cast<int>(buttonIrqClearStatus));
    }
    const m5pm1_err_t resetStatus = powerManager.setSingleResetDisable(true);
    // Replace PM1's immediate hardware double-off with the same clean Travel
    // path used by the center hold. Long-hold Download remains enabled.
    const m5pm1_err_t doubleOffStatus =
        powerManager.setDoubleOffDisable(true);
    bool doubleOffDisabled = false;
    const m5pm1_err_t doubleOffReadStatus =
        powerManager.getDoubleOffDisable(&doubleOffDisabled);
    powerButtonPollingReady =
        resetStatus == M5PM1_OK && doubleOffStatus == M5PM1_OK &&
        doubleOffReadStatus == M5PM1_OK && doubleOffDisabled;
    if (!powerButtonPollingReady) {
      // If the software detector cannot be trusted, restore the documented
      // PM1 hardware double-click shutdown instead of leaving no red-button
      // power-off path. The six-second center hold remains available too.
      const m5pm1_err_t restoreDoubleOffStatus =
          powerManager.setDoubleOffDisable(false);
      Serial.printf(
          "POWER red-button config failed single=%d double=%d read=%d value=%d "
          "restore=%d\n",
          static_cast<int>(resetStatus), static_cast<int>(doubleOffStatus),
          static_cast<int>(doubleOffReadStatus), doubleOffDisabled ? 1 : 0,
          static_cast<int>(restoreDoubleOffStatus));
    } else {
      Serial.println("POWER red single=desk double=travel long=download");
    }
  } else {
    Serial.printf("POWER PM1 direct init failed=%d; using M5Unified fallback\n",
                  static_cast<int>(pm1Status));
  }
#if !defined(CODEX_STOPWATCH_USB_MIC)
  M5.Speaker.setVolume(kCompletionChimeVolume);
  buildCompletionChime();
#endif

  canvas.setColorDepth(16);
  canvas.setPsram(true);
  if (canvas.createSprite(M5.Display.width(), M5.Display.height()) == nullptr) {
    M5.Display.fillScreen(TFT_BLACK);
    M5.Display.setTextColor(TFT_RED);
    M5.Display.setTextDatum(middle_center);
    M5.Display.drawString("Canvas allocation failed", M5.Display.width() / 2,
                          M5.Display.height() / 2);
    Serial.println("Canvas allocation failed");
    while (true) delay(1000);
  }
  canvas.setTextWrap(false);

  loadWatchSettings();

#if defined(CODEX_STOPWATCH_USB_MIC)
  if (!stopwatch_usb_mic::begin()) {
    Serial.println("USB_MIC_FAILED");
  }
#endif

  codex.begin();
  state = codex.snapshot();
  lastActivityMs = millis();
  updatePowerTelemetry(true);
  drawScreen();
  Serial.println("CODEX_MICRO_STOPWATCH_READY");
}

void loop() {
  M5.update();
  codex.poll();
  updatePowerButton();

  const auto touch = M5.Touch.getDetail();
  // Serial captures proved the CST816S reports full-resolution framebuffer
  // coordinates despite the library's x_max=233 config claiming otherwise.
  const int touchX = touch.x;
  const int touchY = touch.y;
  if (touch.wasPressed()) {
    if (noteActivity()) {
      beginTouchGesture(touchX, touchY);
    } else {
      // The swallowed wake tap still answers with a short tick, so haptics
      // never read as randomly dead after the screen slept.
      startHaptic(kButtonHapticIntensity, kWakeHapticDurationMs);
    }
  }
  if (touchTracking && touch.isPressed()) {
    updateTouchGesture(touchX, touchY);
    updateTouchPowerHold();
  }
  if (touch.wasReleased()) {
    finishTouchGesture();
  }

  // Physical validation on the C152 enclosure: BtnA/GPIO2 is the left key and
  // BtnB/GPIO1 is the right key.
  if (M5.BtnA.wasPressed()) {
    noteActivity();  // physical keys act even from a dark screen
    Serial.printf("BUTTON physical=left key=%s action=press\n", kLeftMicSwitch);
    pressMicSwitch(kLeftMicSwitch, leftPressed);
  }
  if (M5.BtnA.wasReleased()) {
    Serial.printf("BUTTON physical=left key=%s action=release\n", kLeftMicSwitch);
    releaseMicSwitch(kLeftMicSwitch, leftPressed);
  }
  if (M5.BtnB.wasPressed()) {
    noteActivity();
    rightPressedAtMs = millis();
    rightPressed = true;
    rightLongPressFired = false;
    if (!v2Mode()) {
      voiceTapBannerVisible = true;
      voiceTapBannerUntilMs = millis() + kVoiceTapBannerMs;
    }
    startHaptic(kButtonHapticIntensity, kButtonHapticDurationMs);
    drawScreen();
  }
  if (M5.BtnB.wasReleased()) {
    const uint32_t heldMs = millis() - rightPressedAtMs;
    rightPressed = false;
    if (v2Mode()) {
      // v2: the right button owns navigation. Short press pages forward; a
      // long press (fired while still held in updateRightButtonHold) went home.
      if (!rightLongPressFired) {
        currentPage = watchface::nextPage(currentPage);
        quotaExpanded = false;
        Serial.printf("PAGE next=%d\n", static_cast<int>(currentPage));
      }
      rightLongPressFired = false;
    } else {
      beginVoiceChatClick();
      Serial.printf("BUTTON physical=right key=%s physical_hold=%lums click_pulse=%lums\n",
                    kVoiceChatCommandKey, static_cast<unsigned long>(heldMs),
                    static_cast<unsigned long>(kVoiceClickPulseMs));
    }
    drawScreen();
  }

  CodexMicroState latest = codex.snapshot();
  const bool shouldRedraw = latest.dirty;
  if (shouldRedraw) {
    detectAgentTransitions(latest);
  }
  state = latest;
  applySettingsFromStore();
  updatePowerTelemetry();
  const bool completionBannerExpired = expireCompletionBanner(millis());

  const dashboard::State currentUi = dashboardState();
  const bool derivedStateChanged =
      !renderedHealthValid || currentUi.linkHealth != renderedLinkHealth ||
      currentUi.quotaStale != renderedQuotaStale ||
      currentUi.batteryPercent != renderedBatteryPercent ||
      currentUi.charging != renderedCharging || currentUi.docked != renderedDocked;
  if (!deskSleeping &&
      (shouldRedraw || derivedStateChanged || completionBannerExpired)) {
    drawScreen();
  }

  // v2 pages animate (pet, breathing alerts) and show a wall clock, so they
  // redraw on a fixed cadence instead of waiting for state changes.
  if (!deskSleeping && v2Mode() && appliedBrightness > 0) {
    const uint32_t cadence =
        currentPage == watchface::Page::Home
            ? kV2RedrawMs
            : (currentPage == watchface::Page::Sessions ? kSessionsRedrawMs
                                                        : 500);
    if (millis() - lastDrawMs > cadence) drawScreen();
  }

  if (appliedBrightness > 0 && state.quota.available &&
      millis() - lastDrawMs > 30000) {
    drawScreen();
  }

  updateIdleDimming();
  updateHaptic();
  updateVoiceTapBanner();
  updateVoiceChatClick();
  updateRightButtonHold();
  pollRaiseWake();
  delay(8);
}
