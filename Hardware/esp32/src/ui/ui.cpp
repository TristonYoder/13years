// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#include "ui.h"
#include "ui/fonts/fonts.h"
#include "ui/icons/icons.h"
#include "ui/logo/logo.h"
#include "cue/default_roles.h"
#include "storage/nvs_store.h"
#include "hw/touch_xpt2046.h"
#include "hw/rgb_led.h"
#include <TFT_eSPI.h>
#include <lvgl.h>
#include <WiFi.h>

namespace ui {

static TFT_eSPI tft = TFT_eSPI();

static lv_disp_draw_buf_t draw_buf;
static lv_color_t buf[TFT_WIDTH * TFT_HEIGHT / 10];
static lv_indev_drv_t indev_drv;

static const int kBacklightLedcChannel = 0;
static const int kBacklightLedcFreqHz = 5000;
static const int kBacklightLedcResBits = 8;

static void flush_cb(lv_disp_drv_t *disp, const lv_area_t *area, lv_color_t *color_p) {
  uint32_t w = (area->x2 - area->x1 + 1);
  uint32_t h = (area->y2 - area->y1 + 1);
  tft.startWrite();
  tft.setAddrWindow(area->x1, area->y1, w, h);
  tft.pushColors((uint16_t *)color_p, w * h, true);
  tft.endWrite();
  lv_disp_flush_ready(disp);
}

static void touch_read_cb(lv_indev_drv_t *drv, lv_indev_data_t *data) {
  uint16_t x, y;
  bool pressed = touch::read(x, y);
  if (pressed) {
    data->point.x = x;
    data->point.y = y;
    data->state = LV_INDEV_STATE_PRESSED;
  } else {
    data->state = LV_INDEV_STATE_RELEASED;
  }
}

void setBacklight(uint8_t percent) {
  if (percent > 100) percent = 100;
  uint32_t duty = (uint32_t)percent * 255 / 100;
  ledcWrite(kBacklightLedcChannel, duty);
}

void init() {
  lv_init();

  tft.init();
  tft.setRotation(store::getDisplayFlipped() ? 2 : 0);
  tft.fillScreen(TFT_BLACK);

  touch::init();
  touch::setFlipped(store::getDisplayFlipped());

  static lv_disp_drv_t disp_drv;
  lv_disp_drv_init(&disp_drv);
  lv_disp_draw_buf_init(&draw_buf, buf, NULL, TFT_WIDTH * TFT_HEIGHT / 10);
  disp_drv.hor_res = tft.width();
  disp_drv.ver_res = tft.height();
  disp_drv.flush_cb = flush_cb;
  disp_drv.draw_buf = &draw_buf;
  lv_disp_drv_register(&disp_drv);

  lv_indev_drv_init(&indev_drv);
  indev_drv.type = LV_INDEV_TYPE_POINTER;
  indev_drv.read_cb = touch_read_cb;
  lv_indev_drv_register(&indev_drv);

  ledcSetup(kBacklightLedcChannel, kBacklightLedcFreqHz, kBacklightLedcResBits);
  ledcAttachPin(TFT_BL, kBacklightLedcChannel);
  setBacklight(100);

  Serial.println("[ui] LVGL + TFT_eSPI + touch initialized");
}

static lv_obj_t *messageScreen = nullptr;
static lv_obj_t *messageLabel = nullptr;
static lv_obj_t *messageDetail = nullptr;
static lv_obj_t *messageLogo = nullptr;

static constexpr lv_coord_t kLogoTopY = 40;
static constexpr lv_coord_t kLogoTextY = kLogoTopY + 118 + 14;

static void ensureMessageScreen() {
  if (messageScreen) return;
  messageScreen = lv_obj_create(NULL);
  lv_obj_set_style_bg_color(messageScreen, lv_color_hex(0x000000), 0);
  lv_obj_set_style_bg_opa(messageScreen, LV_OPA_COVER, 0);
  lv_obj_clear_flag(messageScreen, LV_OBJ_FLAG_SCROLLABLE);

  messageLogo = lv_img_create(messageScreen);
  lv_img_set_src(messageLogo, &logo_13);
  lv_obj_align(messageLogo, LV_ALIGN_TOP_MID, 0, kLogoTopY);
  lv_obj_add_flag(messageLogo, LV_OBJ_FLAG_HIDDEN);

  messageLabel = lv_label_create(messageScreen);
  lv_label_set_long_mode(messageLabel, LV_LABEL_LONG_WRAP);
  lv_obj_set_width(messageLabel, 220);
  lv_obj_set_style_text_align(messageLabel, LV_TEXT_ALIGN_CENTER, 0);
  lv_obj_set_style_text_color(messageLabel, lv_color_white(), 0);
  lv_obj_set_style_text_font(messageLabel, &inter_bold_18, 0);
  lv_obj_center(messageLabel);

  messageDetail = lv_label_create(messageScreen);
  lv_label_set_long_mode(messageDetail, LV_LABEL_LONG_WRAP);
  lv_obj_set_width(messageDetail, 220);
  lv_obj_set_style_text_align(messageDetail, LV_TEXT_ALIGN_CENTER, 0);
  lv_obj_set_style_text_color(messageDetail, lv_color_hex(0xB0B0B0), 0);
  lv_obj_set_style_text_font(messageDetail, &inter_regular_14, 0);
  lv_obj_add_flag(messageDetail, LV_OBJ_FLAG_HIDDEN);
}

static void showMessageScreen(const char *text) {
  ensureMessageScreen();
  lv_obj_add_flag(messageLogo, LV_OBJ_FLAG_HIDDEN);
  lv_obj_add_flag(messageDetail, LV_OBJ_FLAG_HIDDEN);
  lv_obj_center(messageLabel);
  lv_label_set_text(messageLabel, text);
  lv_scr_load(messageScreen);
}

static void showWifiHelpScreen(const char *title, const char *detail) {
  ensureMessageScreen();
  lv_obj_add_flag(messageLogo, LV_OBJ_FLAG_HIDDEN);
  lv_obj_clear_flag(messageDetail, LV_OBJ_FLAG_HIDDEN);
  lv_label_set_text(messageLabel, title);
  lv_label_set_text(messageDetail, detail);
  lv_obj_align(messageLabel, LV_ALIGN_TOP_MID, 0, 74);
  lv_obj_align_to(messageDetail, messageLabel, LV_ALIGN_OUT_BOTTOM_MID, 0, 16);
  lv_scr_load(messageScreen);
}

static void showBrandedMessageScreen(const char *text) {
  ensureMessageScreen();
  lv_obj_clear_flag(messageLogo, LV_OBJ_FLAG_HIDDEN);
  lv_obj_add_flag(messageDetail, LV_OBJ_FLAG_HIDDEN);
  lv_obj_align(messageLabel, LV_ALIGN_TOP_MID, 0, kLogoTextY);
  lv_label_set_text(messageLabel, text);
  lv_scr_load(messageScreen);
}

static void showWaitingForDataScreen(bool wifiConnected) {
  String msg = "Waiting for Producer...\n";
  msg += wifiConnected ? "IP: " + WiFi.localIP().toString() : String("(WiFi not connected)");
  showBrandedMessageScreen(msg.c_str());
}

static lv_obj_t *pagerScreen = nullptr;
static lv_obj_t *roleBtn = nullptr, *roleBtnLabel = nullptr, *roleBtnChevron = nullptr;
static lv_obj_t *connRow = nullptr, *connDot = nullptr, *connLabel = nullptr;
static lv_obj_t *stateLabel = nullptr;
static lv_obj_t *personLabel = nullptr;
static lv_obj_t *itemCard = nullptr, *itemTitleLabel = nullptr, *timerLabel = nullptr, *projActualLabel = nullptr;
static lv_obj_t *noteLabel = nullptr;
static lv_obj_t *msgBanner = nullptr, *msgBannerIcon = nullptr, *msgBannerLabel = nullptr;

static bool showingRolePicker = false;
static bool rolePickerNeedsBuild = true;
static cue::Engine *gEngine = nullptr;

static void onRoleBtnClicked(lv_event_t *e) {
  showingRolePicker = true;
  rolePickerNeedsBuild = true;
}

static void buildPagerScreen() {
  pagerScreen = lv_obj_create(NULL);
  lv_obj_set_style_bg_opa(pagerScreen, LV_OPA_COVER, 0);
  lv_obj_clear_flag(pagerScreen, LV_OBJ_FLAG_SCROLLABLE);

  roleBtn = lv_obj_create(pagerScreen);
  lv_obj_remove_style_all(roleBtn);
  lv_obj_set_size(roleBtn, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
  lv_obj_set_style_bg_color(roleBtn, lv_color_black(), 0);
  lv_obj_set_style_bg_opa(roleBtn, LV_OPA_30, 0);
  lv_obj_set_style_radius(roleBtn, 8, 0);
  lv_obj_set_style_pad_hor(roleBtn, 10, 0);
  lv_obj_set_style_pad_ver(roleBtn, 5, 0);
  lv_obj_set_style_pad_column(roleBtn, 5, 0);
  lv_obj_set_flex_flow(roleBtn, LV_FLEX_FLOW_ROW);
  lv_obj_set_flex_align(roleBtn, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
  lv_obj_add_flag(roleBtn, LV_OBJ_FLAG_CLICKABLE);
  lv_obj_clear_flag(roleBtn, LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_align(roleBtn, LV_ALIGN_TOP_LEFT, 6, 6);
  lv_obj_add_event_cb(roleBtn, onRoleBtnClicked, LV_EVENT_CLICKED, nullptr);

  roleBtnLabel = lv_label_create(roleBtn);
  lv_obj_set_style_text_font(roleBtnLabel, &inter_bold_14, 0);
  lv_label_set_text(roleBtnLabel, "Role");

  roleBtnChevron = lv_img_create(roleBtn);
  lv_img_set_src(roleBtnChevron, &chevron_down);

  connRow = lv_obj_create(pagerScreen);
  lv_obj_remove_style_all(connRow);
  lv_obj_set_size(connRow, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
  lv_obj_set_style_pad_column(connRow, 4, 0);
  lv_obj_set_flex_flow(connRow, LV_FLEX_FLOW_ROW);
  lv_obj_set_flex_align(connRow, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
  lv_obj_clear_flag(connRow, LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_align(connRow, LV_ALIGN_TOP_RIGHT, -6, 10);

  connDot = lv_obj_create(connRow);
  lv_obj_remove_style_all(connDot);
  lv_obj_set_size(connDot, 8, 8);
  lv_obj_set_style_radius(connDot, LV_RADIUS_CIRCLE, 0);
  lv_obj_set_style_bg_opa(connDot, LV_OPA_COVER, 0);
  lv_obj_clear_flag(connDot, LV_OBJ_FLAG_SCROLLABLE);

  connLabel = lv_label_create(connRow);
  lv_obj_set_style_text_font(connLabel, &inter_bold_14, 0);

  stateLabel = lv_label_create(pagerScreen);
  lv_obj_set_style_text_font(stateLabel, &inter_black_32, 0);
  lv_obj_align(stateLabel, LV_ALIGN_TOP_MID, 0, 42);

  personLabel = lv_label_create(pagerScreen);
  lv_obj_set_style_text_font(personLabel, &inter_bold_14, 0);
  lv_obj_align(personLabel, LV_ALIGN_TOP_MID, 0, 84);

  itemCard = lv_obj_create(pagerScreen);
  lv_obj_set_style_bg_color(itemCard, lv_color_black(), 0);
  lv_obj_set_style_bg_opa(itemCard, LV_OPA_30, 0);
  lv_obj_set_style_radius(itemCard, 12, 0);
  lv_obj_set_style_border_width(itemCard, 0, 0);
  lv_obj_set_style_pad_all(itemCard, 4, 0);
  lv_obj_clear_flag(itemCard, LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_set_size(itemCard, 220, 100);
  lv_obj_align(itemCard, LV_ALIGN_TOP_MID, 0, 118);

  itemTitleLabel = lv_label_create(itemCard);
  lv_obj_set_style_text_font(itemTitleLabel, &inter_bold_14, 0);
  lv_label_set_long_mode(itemTitleLabel, LV_LABEL_LONG_DOT);
  lv_obj_set_width(itemTitleLabel, 208);
  lv_obj_set_style_text_align(itemTitleLabel, LV_TEXT_ALIGN_CENTER, 0);
  lv_obj_align(itemTitleLabel, LV_ALIGN_TOP_MID, 0, 2);

  timerLabel = lv_label_create(itemCard);
  lv_obj_set_style_text_font(timerLabel, &inter_black_32, 0);
  lv_obj_align(timerLabel, LV_ALIGN_CENTER, 0, 10);

  projActualLabel = lv_label_create(itemCard);
  lv_obj_set_style_text_font(projActualLabel, &inter_bold_14, 0);
  lv_obj_align(projActualLabel, LV_ALIGN_BOTTOM_MID, 0, -2);

  noteLabel = lv_label_create(pagerScreen);
  lv_obj_set_style_text_font(noteLabel, &inter_bold_14, 0);
  lv_label_set_long_mode(noteLabel, LV_LABEL_LONG_WRAP);
  lv_obj_set_width(noteLabel, 220);
  lv_obj_set_style_text_align(noteLabel, LV_TEXT_ALIGN_CENTER, 0);
  lv_obj_align(noteLabel, LV_ALIGN_TOP_MID, 0, 232);

  msgBanner = lv_obj_create(pagerScreen);
  lv_obj_set_style_bg_color(msgBanner, lv_color_hex(0xFFD400), 0);
  lv_obj_set_style_bg_opa(msgBanner, LV_OPA_COVER, 0);
  lv_obj_set_style_radius(msgBanner, 8, 0);
  lv_obj_set_style_border_width(msgBanner, 0, 0);
  lv_obj_set_style_pad_all(msgBanner, 4, 0);
  lv_obj_set_style_pad_column(msgBanner, 8, 0);
  lv_obj_set_flex_flow(msgBanner, LV_FLEX_FLOW_ROW);
  lv_obj_set_flex_align(msgBanner, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
  lv_obj_clear_flag(msgBanner, LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_set_size(msgBanner, 220, 32);
  lv_obj_align(msgBanner, LV_ALIGN_BOTTOM_MID, 0, -8);

  msgBannerIcon = lv_img_create(msgBanner);
  lv_img_set_src(msgBannerIcon, &message_square_text);
  lv_obj_set_style_img_recolor(msgBannerIcon, lv_color_black(), 0);
  lv_obj_set_style_img_recolor_opa(msgBannerIcon, LV_OPA_COVER, 0);

  msgBannerLabel = lv_label_create(msgBanner);
  lv_obj_set_style_text_font(msgBannerLabel, &inter_bold_14, 0);
  lv_obj_set_style_text_color(msgBannerLabel, lv_color_black(), 0);
  lv_label_set_long_mode(msgBannerLabel, LV_LABEL_LONG_DOT);
  lv_obj_set_flex_grow(msgBannerLabel, 1);
  lv_obj_set_style_text_align(msgBannerLabel, LV_TEXT_ALIGN_CENTER, 0);
}

static void refreshPagerScreen(cue::Engine &engine, bool wifiConnected, bool lanConnected) {
  cue::RoleView role = engine.activeRole();
  CueState state = role.state;

  lv_obj_set_style_bg_color(pagerScreen, lv_color_hex(cueStateBgColor(state)), 0);
  lv_color_t textColor = lv_color_hex(cueStateTextColor(state));

  String roleLabelText = role.name.length() > 0 ? role.name : engine.selectedRoleId();
  lv_label_set_text(roleBtnLabel, roleLabelText.c_str());

  lv_obj_set_style_text_color(roleBtnLabel, textColor, 0);
  lv_obj_set_style_text_color(connLabel, textColor, 0);
  lv_obj_set_style_text_color(stateLabel, textColor, 0);
  lv_obj_set_style_text_color(personLabel, textColor, 0);
  lv_obj_set_style_text_color(itemTitleLabel, textColor, 0);
  lv_obj_set_style_text_color(timerLabel, textColor, 0);
  lv_obj_set_style_text_color(projActualLabel, textColor, 0);
  lv_obj_set_style_text_color(noteLabel, textColor, 0);
  lv_obj_set_style_img_recolor(roleBtnChevron, textColor, 0);
  lv_obj_set_style_img_recolor_opa(roleBtnChevron, LV_OPA_COVER, 0);

  bool isLive = wifiConnected && lanConnected && engine.isProducerLive();
  lv_obj_set_style_bg_color(connDot, isLive ? lv_palette_main(LV_PALETTE_GREEN) : lv_palette_main(LV_PALETTE_RED), 0);
  if (!wifiConnected) {
    lv_label_set_text(connLabel, "No WiFi");
  } else if (!lanConnected) {
    lv_label_set_text(connLabel, "Connecting...");
  } else if (isLive) {
    lv_label_set_text(connLabel, "Live");
  } else {
    lv_label_set_text(connLabel, "Disconnected");
  }

  lv_label_set_text(stateLabel, cueStateDisplayName(state));

  if (role.personName.length() > 0) {
    String forLine = "FOR: " + role.personName;
    forLine.toUpperCase();
    lv_label_set_text(personLabel, forLine.c_str());
    lv_obj_clear_flag(personLabel, LV_OBJ_FLAG_HIDDEN);
  } else {
    lv_obj_add_flag(personLabel, LV_OBJ_FLAG_HIDDEN);
  }

  cue::TimerView timer = engine.activeTimer();
  if (timer.found) {
    lv_obj_clear_flag(itemCard, LV_OBJ_FLAG_HIDDEN);
    String title = timer.title;
    title.toUpperCase();
    lv_label_set_text(itemTitleLabel, title.c_str());

    if (timer.isHeader()) {
      lv_obj_add_flag(timerLabel, LV_OBJ_FLAG_HIDDEN);
      lv_obj_add_flag(projActualLabel, LV_OBJ_FLAG_HIDDEN);
    } else {
      lv_obj_clear_flag(timerLabel, LV_OBJ_FLAG_HIDDEN);
      lv_obj_clear_flag(projActualLabel, LV_OBJ_FLAG_HIDDEN);
      int remaining = timer.remainingSeconds();
      int absRemaining = remaining < 0 ? -remaining : remaining;
      char buf[16];
      snprintf(buf, sizeof(buf), "%s%02d:%02d", remaining < 0 ? "+" : "", absRemaining / 60, absRemaining % 60);
      lv_label_set_text(timerLabel, buf);
      lv_label_set_text(projActualLabel, timer.isDurationActual ? "ACTUAL" : "PROJECTED");
    }
  } else {
    lv_obj_add_flag(itemCard, LV_OBJ_FLAG_HIDDEN);
  }

  String note = engine.currentNote();
  if (note.length() > 0) {
    lv_label_set_text(noteLabel, note.c_str());
    lv_obj_clear_flag(noteLabel, LV_OBJ_FLAG_HIDDEN);
  } else {
    lv_obj_add_flag(noteLabel, LV_OBJ_FLAG_HIDDEN);
  }

  cue::MessageView msg = engine.latestRelevantMessage();
  if (msg.found) {
    lv_label_set_text(msgBannerLabel, msg.text.c_str());
    lv_obj_clear_flag(msgBanner, LV_OBJ_FLAG_HIDDEN);
  } else {
    lv_obj_add_flag(msgBanner, LV_OBJ_FLAG_HIDDEN);
  }
}

static const int kMaxRolePickerRows = 8;
static lv_obj_t *rolePickerScreen = nullptr;
static String rolePickerIds[kMaxRolePickerRows];

static void onRoleRowClicked(lv_event_t *e) {
  const char *roleId = (const char *)lv_event_get_user_data(e);
  if (gEngine && roleId) {
    Serial.printf("[ui] role selected: %s\n", roleId);
    gEngine->setSelectedRoleId(String(roleId));
    led::setForCueState(gEngine->activeRole().state);
  }
  showingRolePicker = false;
}

static void onRolePickerCancelClicked(lv_event_t *e) {
  showingRolePicker = false;
}

static void addRoleRow(lv_obj_t *parent, const char *roleId, const char *displayName) {
  lv_obj_t *row = lv_obj_create(parent);
  lv_obj_set_size(row, 210, 36);
  lv_obj_set_style_bg_color(row, lv_color_hex(0x2A3244), 0);
  lv_obj_set_style_bg_opa(row, LV_OPA_COVER, 0);
  lv_obj_set_style_radius(row, 6, 0);
  lv_obj_set_style_border_width(row, 0, 0);
  lv_obj_clear_flag(row, LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_add_flag(row, LV_OBJ_FLAG_CLICKABLE);
  lv_obj_add_event_cb(row, onRoleRowClicked, LV_EVENT_CLICKED, (void *)roleId);

  lv_obj_t *label = lv_label_create(row);
  lv_obj_set_style_text_font(label, &inter_regular_14, 0);
  lv_obj_set_style_text_color(label, lv_color_white(), 0);
  lv_label_set_text(label, displayName);
  lv_obj_center(label);
}

static void buildRolePickerScreen(cue::Engine &engine) {
  if (rolePickerScreen) {
    lv_obj_del(rolePickerScreen);
    rolePickerScreen = nullptr;
  }
  rolePickerScreen = lv_obj_create(NULL);
  lv_obj_set_style_bg_color(rolePickerScreen, lv_color_hex(0x000000), 0);
  lv_obj_set_style_bg_opa(rolePickerScreen, LV_OPA_COVER, 0);
  lv_obj_set_flex_flow(rolePickerScreen, LV_FLEX_FLOW_COLUMN);
  lv_obj_set_flex_align(rolePickerScreen, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
  lv_obj_set_style_pad_row(rolePickerScreen, 6, 0);
  lv_obj_set_style_pad_all(rolePickerScreen, 8, 0);

  lv_obj_t *title = lv_label_create(rolePickerScreen);
  lv_label_set_text(title, "Select this pager's role");
  lv_obj_set_style_text_color(title, lv_color_white(), 0);
  lv_obj_set_style_text_font(title, &inter_regular_18, 0);

  int count = engine.roleCount();
  if (count > 0) {
    if (count > kMaxRolePickerRows) count = kMaxRolePickerRows;
    for (int i = 0; i < count; i++) {
      cue::RoleView r = engine.roleAt(i);
      rolePickerIds[i] = r.id;
      addRoleRow(rolePickerScreen, rolePickerIds[i].c_str(), r.name.c_str());
    }
  } else {
    count = kDefaultRoleCount < kMaxRolePickerRows ? kDefaultRoleCount : kMaxRolePickerRows;
    for (int i = 0; i < count; i++) {
      rolePickerIds[i] = kDefaultRoles[i].id;
      addRoleRow(rolePickerScreen, rolePickerIds[i].c_str(), kDefaultRoles[i].name);
    }
  }

  lv_obj_t *cancelRow = lv_obj_create(rolePickerScreen);
  lv_obj_set_size(cancelRow, 210, 32);
  lv_obj_set_style_bg_opa(cancelRow, LV_OPA_TRANSP, 0);
  lv_obj_set_style_border_width(cancelRow, 1, 0);
  lv_obj_set_style_border_color(cancelRow, lv_color_white(), 0);
  lv_obj_set_style_radius(cancelRow, 6, 0);
  lv_obj_clear_flag(cancelRow, LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_add_flag(cancelRow, LV_OBJ_FLAG_CLICKABLE);
  lv_obj_add_event_cb(cancelRow, onRolePickerCancelClicked, LV_EVENT_CLICKED, nullptr);
  lv_obj_t *cancelLabel = lv_label_create(cancelRow);
  lv_obj_set_style_text_color(cancelLabel, lv_color_white(), 0);
  lv_label_set_text(cancelLabel, "Cancel");
  lv_obj_center(cancelLabel);
}

void setDisplayFlipped(bool flipped) {
  if (flipped == store::getDisplayFlipped()) return;
  store::setDisplayFlipped(flipped);
  tft.setRotation(flipped ? 2 : 0);
  touch::setFlipped(flipped);
  lv_obj_invalidate(lv_scr_act());
  Serial.printf("[ui] display rotation -> %s\n", flipped ? "180 degrees" : "normal");
}

bool isDisplayFlipped() {
  return store::getDisplayFlipped();
}

void update(Phase phase, cue::Engine &engine, bool wifiConnected, bool lanConnected) {
  gEngine = &engine;

  switch (phase) {
    case Phase::Boot:
      showMessageScreen("Booting...");
      return;
    case Phase::WifiPrompt: {
      String ssid, password;
      if (store::getWifiCreds(ssid, password) && ssid.length() > 0) {
        static String detail;
        detail = "\"" + ssid + "\"\n\n"
                 "Still trying. To change the network, connect this pager to a "
                 "Mac with a USB cable and open 13 Years Producer.\n\n"
                 "File > Flash a Pager";
        showWifiHelpScreen("Can't join Wi-Fi", detail.c_str());
      } else {
        showWifiHelpScreen(
          "Not set up yet",
          "Connect this pager to a Mac with a USB cable and open "
          "13 Years Producer.\n\n"
          "File > Flash a Pager");
      }
      return;
    }
    case Phase::Connecting:
      showMessageScreen("Connecting to WiFi...");
      return;
    case Phase::Running:
      break;
  }

  bool connectedToProducer = wifiConnected && lanConnected && engine.isProducerLive();
  if (!engine.hasSyncedWithProducer() || !connectedToProducer) {
    showWaitingForDataScreen(wifiConnected);
    return;
  }

  if (showingRolePicker) {
    if (rolePickerNeedsBuild) {
      buildRolePickerScreen(engine);
      rolePickerNeedsBuild = false;
    }
    lv_scr_load(rolePickerScreen);
    return;
  }

  if (!pagerScreen) buildPagerScreen();
  lv_scr_load(pagerScreen);
  refreshPagerScreen(engine, wifiConnected, lanConnected);
}

void runTouchCalibration() {
  Serial.println("[ui] interactive calibration isn't implemented for the new touch bus yet — "
                  "see touch_xpt2046.cpp's kRawXMin/Max/kRawYMin/Max and SWAP_XY/INVERT_X/INVERT_Y "
                  "constants, and use `touchraw` to check real readings while tuning them");
}

void runRawTouchReadout(uint32_t durationMs) {
  Serial.printf("[ui] raw touch readout for %ums — touch the screen now\n", durationMs);
  unsigned long start = millis();
  unsigned long lastPrint = 0;
  while (millis() - start < durationMs) {
    if (millis() - lastPrint >= 200) {
      lastPrint = millis();
      uint16_t rawX = 0, rawY = 0, rawZ = 0;
      touch::readRaw(rawX, rawY, rawZ);
      uint16_t mappedX = 0, mappedY = 0;
      bool pressed = touch::read(mappedX, mappedY);
      if (pressed) {
        Serial.printf("[touchraw] rawZ=%u rawXY=(%u,%u) -> mapped=(%u,%u)\n", rawZ, rawX, rawY, mappedX, mappedY);
      } else {
        Serial.printf("[touchraw] rawZ=%u rawXY=(%u,%u) (below pressure threshold)\n", rawZ, rawX, rawY);
      }
    }
  }
  Serial.println("[ui] raw touch readout done");
}

}
