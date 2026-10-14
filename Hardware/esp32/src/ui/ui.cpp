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
#include "net/lan_client.h"
#include <TFT_eSPI.h>
#include <lvgl.h>
#include <WiFi.h>

namespace ui {

static TFT_eSPI tft = TFT_eSPI();

static pagersync::CueDisplay gCueDisplay = pagersync::CueDisplay::Outline;

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

  pagersync::parseCueDisplay(store::getCueDisplay().c_str(), gCueDisplay);

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

static int shownKind = -1;
static String shownText;

static bool messageScreenCurrent(int kind, const char *text) {
  if (messageScreen && lv_scr_act() == messageScreen && shownKind == kind && shownText.equals(text)) return true;
  shownKind = kind;
  shownText = text;
  return false;
}

static void showMessageScreen(const char *text) {
  if (messageScreenCurrent(0, text)) return;
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
  if (messageScreenCurrent(3, text)) return;
  ensureMessageScreen();
  lv_obj_clear_flag(messageLogo, LV_OBJ_FLAG_HIDDEN);
  lv_obj_add_flag(messageDetail, LV_OBJ_FLAG_HIDDEN);
  lv_obj_align(messageLabel, LV_ALIGN_TOP_MID, 0, kLogoTextY);
  lv_label_set_text(messageLabel, text);
  lv_scr_load(messageScreen);
}

static void showWaitingForDataScreen(bool wifiConnected) {
  char msg[80];
  if (wifiConnected) {
    IPAddress ip = WiFi.localIP();
    snprintf(msg, sizeof(msg), "Waiting for Producer...\nIP: %u.%u.%u.%u", ip[0], ip[1], ip[2], ip[3]);
  } else {
    snprintf(msg, sizeof(msg), "Waiting for Producer...\n(WiFi not connected)");
  }
  showBrandedMessageScreen(msg);
}

static constexpr lv_coord_t kScreenW = 240;
static constexpr lv_coord_t kScreenH = 320;
static constexpr lv_coord_t kBorder = 7;
static constexpr lv_coord_t kMargin = 13;
static constexpr lv_coord_t kContentW = kScreenW - 2 * kMargin;
static constexpr lv_coord_t kCardPad = 6;
static constexpr lv_coord_t kInnerW = kContentW - 2 * kCardPad;
static constexpr lv_coord_t kTopY = 11;
static constexpr lv_coord_t kTopH = 44;
static constexpr lv_coord_t kRightColW = 100;
static constexpr lv_coord_t kStackBottom = 13;
static constexpr lv_coord_t kGap = 6;
static constexpr lv_coord_t kDividerGap = 5;
static constexpr uint32_t kGroundHex = 0x111114;
static constexpr uint32_t kNeutralFrameHex = 0x24242A;
static constexpr uint32_t kInkHex = 0xF2F2F5;
static constexpr uint32_t kMessageHex = 0xFFD400;
static constexpr int kMessageMaxLines = 3;

static lv_obj_t *pagerScreen = nullptr, *groundBox = nullptr;
static lv_obj_t *clockLabel = nullptr, *clockCaption = nullptr;
static lv_obj_t *cuePill = nullptr, *cueLabel = nullptr;
static lv_obj_t *roleBtn = nullptr, *roleBtnLabel = nullptr, *roleBtnChevron = nullptr;
static lv_obj_t *noConnLabel = nullptr;
static lv_obj_t *itemCard = nullptr, *itemTitleLabel = nullptr, *timerLabel = nullptr, *projActualLabel = nullptr;
static lv_obj_t *itemDivider = nullptr, *itemDividerLine = nullptr, *itemNotes = nullptr;
static lv_obj_t *bottomStack = nullptr;
static lv_obj_t *nextCard = nullptr, *nextRow = nullptr, *nextTitleLabel = nullptr, *nextLenLabel = nullptr, *nextNote = nullptr;
static lv_obj_t *msgPanel = nullptr, *msgLabel = nullptr;

static const lv_font_t *clockFont = &inter_bold_18;
static const lv_font_t *cueFont = &inter_bold_18;
static lv_coord_t clockSlotW = 0;

static bool showingRolePicker = false;
static bool rolePickerNeedsBuild = true;
static cue::Engine *gEngine = nullptr;
static String dismissedMsgId;

static void onRoleBtnClicked(lv_event_t *e) {
  showingRolePicker = true;
  rolePickerNeedsBuild = true;
}

static void onMsgPanelClicked(lv_event_t *e) {
  const cue::MessageView *m = gEngine ? gEngine->latestRelevantMessageRef() : nullptr;
  if (m) dismissedMsgId = m->id;
}

static lv_coord_t textWidth(const lv_font_t *font, const char *text) {
  lv_point_t size;
  lv_txt_get_size(&size, text, font, 0, 0, LV_COORD_MAX, LV_TEXT_FLAG_NONE);
  return size.x;
}

static void styleCard(lv_obj_t *card, lv_coord_t radius) {
  lv_obj_remove_style_all(card);
  lv_obj_set_style_bg_opa(card, LV_OPA_COVER, 0);
  lv_obj_set_style_radius(card, radius, 0);
  lv_obj_set_style_pad_all(card, kCardPad, 0);
  lv_obj_set_style_pad_row(card, 2, 0);
  lv_obj_set_flex_flow(card, LV_FLEX_FLOW_COLUMN);
  lv_obj_set_flex_align(card, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
  lv_obj_clear_flag(card, LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_set_width(card, kContentW);
  lv_obj_set_height(card, LV_SIZE_CONTENT);
}

static lv_obj_t *makeNoteGroup(lv_obj_t *parent) {
  lv_obj_t *sg = lv_spangroup_create(parent);
  lv_spangroup_set_mode(sg, LV_SPAN_MODE_FIXED);
  lv_spangroup_set_overflow(sg, LV_SPAN_OVERFLOW_ELLIPSIS);
  lv_obj_set_size(sg, kInnerW, 0);
  return sg;
}

static void buildPagerScreen() {
  pagerScreen = lv_obj_create(NULL);
  lv_obj_set_style_bg_opa(pagerScreen, LV_OPA_COVER, 0);
  lv_obj_set_style_pad_all(pagerScreen, 0, 0);
  lv_obj_clear_flag(pagerScreen, LV_OBJ_FLAG_SCROLLABLE);

  groundBox = lv_obj_create(pagerScreen);
  lv_obj_remove_style_all(groundBox);
  lv_obj_set_size(groundBox, kScreenW - 2 * kBorder, kScreenH - 2 * kBorder);
  lv_obj_set_pos(groundBox, kBorder, kBorder);
  lv_obj_set_style_radius(groundBox, 14, 0);
  lv_obj_set_style_bg_opa(groundBox, LV_OPA_COVER, 0);
  lv_obj_set_style_bg_color(groundBox, lv_color_hex(kGroundHex), 0);
  lv_obj_clear_flag(groundBox, LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_clear_flag(groundBox, LV_OBJ_FLAG_CLICKABLE);

  clockSlotW = kContentW - kRightColW - 4;
  if (textWidth(&inter_bold_18, "10:08:08 PM") > clockSlotW) clockFont = &inter_bold_14;
  if (textWidth(&inter_black_32, "STANDBY") + 16 <= clockSlotW) cueFont = &inter_black_32;
  lv_coord_t cueW = textWidth(cueFont, "STANDBY") + 20;
  if (cueW > clockSlotW) cueW = clockSlotW;
  lv_coord_t cueH = lv_font_get_line_height(cueFont) + 6;

  clockLabel = lv_label_create(pagerScreen);
  lv_obj_set_style_text_font(clockLabel, clockFont, 0);
  lv_label_set_long_mode(clockLabel, LV_LABEL_LONG_CLIP);
  lv_obj_set_width(clockLabel, clockSlotW);
  lv_obj_set_pos(clockLabel, kMargin, kTopY);

  clockCaption = lv_label_create(pagerScreen);
  lv_obj_set_style_text_font(clockCaption, &inter_regular_14, 0);
  lv_obj_set_style_text_letter_space(clockCaption, 1, 0);
  lv_obj_set_style_text_opa(clockCaption, LV_OPA_70, 0);
  lv_obj_set_pos(clockCaption, kMargin, kTopY + lv_font_get_line_height(clockFont) + 1);

  cuePill = lv_obj_create(pagerScreen);
  lv_obj_remove_style_all(cuePill);
  lv_obj_set_size(cuePill, cueW, cueH);
  lv_obj_set_pos(cuePill, kMargin, kTopY + (kTopH - cueH) / 2);
  lv_obj_set_style_radius(cuePill, 10, 0);
  lv_obj_clear_flag(cuePill, LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_clear_flag(cuePill, LV_OBJ_FLAG_CLICKABLE);

  cueLabel = lv_label_create(cuePill);
  lv_obj_set_style_text_font(cueLabel, cueFont, 0);
  lv_obj_set_style_text_color(cueLabel, lv_color_hex(kGroundHex), 0);
  lv_obj_center(cueLabel);

  noConnLabel = lv_label_create(pagerScreen);
  lv_obj_set_style_text_font(noConnLabel, &inter_regular_14, 0);
  lv_label_set_text(noConnLabel, "Reconnecting...");
  lv_obj_align(noConnLabel, LV_ALIGN_TOP_RIGHT, -kMargin, kTopY + 31);
  lv_obj_add_flag(noConnLabel, LV_OBJ_FLAG_HIDDEN);

  roleBtn = lv_obj_create(pagerScreen);
  lv_obj_remove_style_all(roleBtn);
  lv_obj_set_size(roleBtn, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
  lv_obj_set_style_bg_opa(roleBtn, LV_OPA_COVER, 0);
  lv_obj_set_style_radius(roleBtn, 8, 0);
  lv_obj_set_style_pad_hor(roleBtn, 8, 0);
  lv_obj_set_style_pad_ver(roleBtn, 5, 0);
  lv_obj_set_style_pad_column(roleBtn, 4, 0);
  lv_obj_set_flex_flow(roleBtn, LV_FLEX_FLOW_ROW);
  lv_obj_set_flex_align(roleBtn, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
  lv_obj_add_flag(roleBtn, LV_OBJ_FLAG_CLICKABLE);
  lv_obj_clear_flag(roleBtn, LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_align(roleBtn, LV_ALIGN_TOP_RIGHT, -kMargin, kTopY);
  lv_obj_add_event_cb(roleBtn, onRoleBtnClicked, LV_EVENT_CLICKED, nullptr);

  roleBtnLabel = lv_label_create(roleBtn);
  lv_obj_set_style_text_font(roleBtnLabel, &inter_bold_14, 0);
  lv_label_set_long_mode(roleBtnLabel, LV_LABEL_LONG_DOT);
  lv_obj_set_width(roleBtnLabel, kRightColW - 8 - 8 - 4 - 14 - 4);
  lv_label_set_text(roleBtnLabel, "Role");

  roleBtnChevron = lv_img_create(roleBtn);
  lv_img_set_src(roleBtnChevron, &chevron_down);

  itemCard = lv_obj_create(pagerScreen);
  styleCard(itemCard, 12);

  itemTitleLabel = lv_label_create(itemCard);
  lv_obj_set_style_text_font(itemTitleLabel, &inter_bold_14, 0);
  lv_label_set_long_mode(itemTitleLabel, LV_LABEL_LONG_DOT);
  lv_obj_set_width(itemTitleLabel, kInnerW);
  lv_obj_set_style_text_align(itemTitleLabel, LV_TEXT_ALIGN_CENTER, 0);

  timerLabel = lv_label_create(itemCard);
  lv_obj_set_style_text_font(timerLabel, &inter_black_32, 0);

  projActualLabel = lv_label_create(itemCard);
  lv_obj_set_style_text_font(projActualLabel, &inter_regular_14, 0);
  lv_obj_set_style_text_letter_space(projActualLabel, 1, 0);
  lv_obj_set_style_text_opa(projActualLabel, LV_OPA_70, 0);

  itemDivider = lv_obj_create(itemCard);
  lv_obj_remove_style_all(itemDivider);
  lv_obj_set_size(itemDivider, kInnerW, 2 * kDividerGap + 1);
  lv_obj_clear_flag(itemDivider, LV_OBJ_FLAG_SCROLLABLE);

  itemDividerLine = lv_obj_create(itemDivider);
  lv_obj_remove_style_all(itemDividerLine);
  lv_obj_set_size(itemDividerLine, kInnerW, 1);
  lv_obj_set_style_bg_opa(itemDividerLine, LV_OPA_30, 0);
  lv_obj_center(itemDividerLine);

  itemNotes = makeNoteGroup(itemCard);

  bottomStack = lv_obj_create(pagerScreen);
  lv_obj_remove_style_all(bottomStack);
  lv_obj_set_size(bottomStack, kContentW, LV_SIZE_CONTENT);
  lv_obj_set_flex_flow(bottomStack, LV_FLEX_FLOW_COLUMN);
  lv_obj_set_flex_align(bottomStack, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
  lv_obj_set_style_pad_row(bottomStack, kGap, 0);
  lv_obj_clear_flag(bottomStack, LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_clear_flag(bottomStack, LV_OBJ_FLAG_CLICKABLE);
  lv_obj_align(bottomStack, LV_ALIGN_BOTTOM_MID, 0, -kStackBottom);

  nextCard = lv_obj_create(bottomStack);
  styleCard(nextCard, 10);
  lv_obj_set_style_pad_row(nextCard, 1, 0);

  nextRow = lv_obj_create(nextCard);
  lv_obj_remove_style_all(nextRow);
  lv_obj_set_size(nextRow, kInnerW, LV_SIZE_CONTENT);
  lv_obj_set_flex_flow(nextRow, LV_FLEX_FLOW_ROW);
  lv_obj_set_flex_align(nextRow, LV_FLEX_ALIGN_SPACE_BETWEEN, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
  lv_obj_clear_flag(nextRow, LV_OBJ_FLAG_SCROLLABLE);

  nextLenLabel = lv_label_create(nextRow);
  lv_obj_set_style_text_font(nextLenLabel, &inter_bold_14, 0);
  lv_label_set_text(nextLenLabel, "0:00:00");
  lv_coord_t lenW = textWidth(&inter_bold_14, "0:00:00");
  lv_obj_set_width(nextLenLabel, lenW);
  lv_obj_set_style_text_align(nextLenLabel, LV_TEXT_ALIGN_RIGHT, 0);

  nextTitleLabel = lv_label_create(nextRow);
  lv_obj_set_style_text_font(nextTitleLabel, &inter_bold_14, 0);
  lv_label_set_long_mode(nextTitleLabel, LV_LABEL_LONG_DOT);
  lv_obj_set_width(nextTitleLabel, kInnerW - lenW - 6);
  lv_obj_move_to_index(nextTitleLabel, 0);

  nextNote = makeNoteGroup(nextCard);

  msgPanel = lv_obj_create(bottomStack);
  lv_obj_remove_style_all(msgPanel);
  lv_obj_set_size(msgPanel, kContentW, LV_SIZE_CONTENT);
  lv_obj_set_style_bg_color(msgPanel, lv_color_hex(kMessageHex), 0);
  lv_obj_set_style_bg_opa(msgPanel, LV_OPA_COVER, 0);
  lv_obj_set_style_radius(msgPanel, 10, 0);
  lv_obj_set_style_pad_all(msgPanel, 8, 0);
  lv_obj_clear_flag(msgPanel, LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_add_flag(msgPanel, LV_OBJ_FLAG_CLICKABLE);
  lv_obj_add_event_cb(msgPanel, onMsgPanelClicked, LV_EVENT_CLICKED, nullptr);

  msgLabel = lv_label_create(msgPanel);
  lv_obj_set_style_text_color(msgLabel, lv_color_hex(kGroundHex), 0);
  lv_label_set_long_mode(msgLabel, LV_LABEL_LONG_DOT);
  lv_obj_set_width(msgLabel, kContentW - 16);
}

struct PagerCache {
  bool valid = false;
  CueState state = CueState::Off;
  pagersync::CueDisplay display = pagersync::CueDisplay::Outline;
  int link = -1;
  String role;
  String clockText;
  int clockUtc = -1;
  bool timerShown = false;
  bool timerHeader = false;
  String title;
  int remaining = 0;
  bool remainingValid = false;
  bool actual = false;
  bool actualValid = false;
  String notesSig = "\1";
  bool nextShown = false;
  String nextTitle = "\1";
  int nextLen = -1;
  String nextNoteSig = "\1";
  bool msgShown = false;
  String msgId;
  String msgText;
  bool layoutDirty = true;
};

static PagerCache pc;

static void updateCueToggleLabel();

static lv_obj_t *cueToggleLabel = nullptr;

static bool gStaleLook = false;

static lv_color_t staleTint(uint32_t hex) {
  lv_color_t c = lv_color_hex(hex);
  if (!gStaleLook) return c;
  return lv_color_mix(lv_color_hex(0x7A7A7A), c, 160);
}

static void applyTheme(CueState state, pagersync::CueDisplay display) {
  bool cue = state != CueState::Off;
  bool full = display == pagersync::CueDisplay::Fullscreen;
  lv_color_t cueColor = staleTint(cueStateBgColor(state));
  lv_color_t ground = staleTint(kGroundHex);
  lv_color_t ink = (full && cue) ? ground : staleTint(kInkHex);

  lv_color_t screenBg = cue ? cueColor : (full ? ground : staleTint(kNeutralFrameHex));
  lv_obj_set_style_bg_color(pagerScreen, screenBg, 0);
  if (full) lv_obj_add_flag(groundBox, LV_OBJ_FLAG_HIDDEN);
  else lv_obj_clear_flag(groundBox, LV_OBJ_FLAG_HIDDEN);

  lv_color_t cardColor = full ? lv_color_black() : lv_color_white();
  lv_opa_t cardOpa = full ? 71 : LV_OPA_10;
  lv_obj_t *cards[] = {itemCard, nextCard, roleBtn};
  for (lv_obj_t *c : cards) {
    lv_obj_set_style_bg_color(c, cardColor, 0);
    lv_obj_set_style_bg_opa(c, cardOpa, 0);
  }
  lv_obj_set_style_bg_color(msgPanel, staleTint(kMessageHex), 0);
  lv_obj_set_style_border_width(msgPanel, full && cue ? 2 : 0, 0);
  lv_obj_set_style_border_color(msgPanel, ground, 0);

  lv_obj_set_style_bg_color(cuePill, cueColor, 0);
  lv_obj_set_style_bg_opa(cuePill, (cue && !full) ? LV_OPA_COVER : LV_OPA_TRANSP, 0);
  lv_label_set_text(cueLabel, cueStateDisplayName(state));
  lv_obj_center(cueLabel);

  lv_obj_t *labels[] = {clockLabel, clockCaption, noConnLabel, roleBtnLabel, itemTitleLabel, timerLabel,
                        projActualLabel, nextTitleLabel, nextLenLabel};
  for (lv_obj_t *l : labels) lv_obj_set_style_text_color(l, ink, 0);
  lv_obj_set_style_bg_color(itemDividerLine, ink, 0);
  lv_obj_set_style_img_recolor(roleBtnChevron, ink, 0);
  lv_obj_set_style_img_recolor_opa(roleBtnChevron, LV_OPA_COVER, 0);

  if (cue) {
    lv_obj_add_flag(clockLabel, LV_OBJ_FLAG_HIDDEN);
    lv_obj_add_flag(clockCaption, LV_OBJ_FLAG_HIDDEN);
    lv_obj_clear_flag(cuePill, LV_OBJ_FLAG_HIDDEN);
  } else {
    lv_obj_clear_flag(clockLabel, LV_OBJ_FLAG_HIDDEN);
    lv_obj_clear_flag(clockCaption, LV_OBJ_FLAG_HIDDEN);
    lv_obj_add_flag(cuePill, LV_OBJ_FLAG_HIDDEN);
  }

  pc.notesSig = "\1";
  pc.nextNoteSig = "\1";
  pc.layoutDirty = true;
}

static void setHidden(lv_obj_t *obj, bool hidden) {
  if (hidden) lv_obj_add_flag(obj, LV_OBJ_FLAG_HIDDEN);
  else lv_obj_clear_flag(obj, LV_OBJ_FLAG_HIDDEN);
}

static void clearSpans(lv_obj_t *sg) {
  while (lv_spangroup_get_child_cnt(sg) > 0) lv_spangroup_del_span(sg, lv_spangroup_get_child(sg, 0));
}

static void addNoteSpans(lv_obj_t *sg, const char *category, const char *text, bool newline, lv_color_t color) {
  String head = String(category) + ": ";
  lv_span_t *a = lv_spangroup_new_span(sg);
  lv_span_set_text(a, head.c_str());
  lv_style_set_text_font(&a->style, &inter_bold_14);
  lv_style_set_text_color(&a->style, color);
  String body = String(text);
  if (newline) body += "\n";
  lv_span_t *b = lv_spangroup_new_span(sg);
  lv_span_set_text(b, body.c_str());
  lv_style_set_text_font(&b->style, &inter_regular_14);
  lv_style_set_text_color(&b->style, color);
}

static lv_color_t currentInk() {
  bool cue = pc.state != CueState::Off;
  bool full = pc.display == pagersync::CueDisplay::Fullscreen;
  return (full && cue) ? staleTint(kGroundHex) : staleTint(kInkHex);
}

static void relayoutPager(bool timerShown, bool header, bool stackShown) {
  setHidden(bottomStack, !stackShown);
  lv_obj_update_layout(pagerScreen);

  lv_coord_t availTop = kTopY + kTopH + 4;
  lv_coord_t stackTop = stackShown ? lv_obj_get_y(bottomStack) : kScreenH - kStackBottom;
  lv_coord_t availH = stackTop - kGap - availTop;

  if (!timerShown) return;

  bool haveNotes = !header && lv_spangroup_get_child_cnt(itemNotes) > 0;
  setHidden(itemDivider, true);
  setHidden(itemNotes, true);
  lv_obj_update_layout(pagerScreen);
  lv_coord_t baseH = lv_obj_get_height(itemCard);

  if (haveNotes) {
    lv_coord_t lh = lv_font_get_line_height(&inter_regular_14);
    lv_coord_t need = lv_spangroup_get_expand_height(itemNotes, kInnerW);
    lv_coord_t room = availH - baseH - (2 * kDividerGap + 1) - 4;
    lv_coord_t fit = (room / lh) * lh;
    lv_coord_t h = need < fit ? need : fit;
    if (h >= lh) {
      lv_obj_set_height(itemNotes, h);
      setHidden(itemDivider, false);
      setHidden(itemNotes, false);
    }
  }

  lv_obj_update_layout(pagerScreen);
  lv_coord_t cardH = lv_obj_get_height(itemCard);
  lv_coord_t y = availTop + (availH > cardH ? (availH - cardH) / 2 : 0);
  lv_obj_set_pos(itemCard, kMargin, y);
}

static void refreshPagerScreen(cue::Engine &engine, bool linkLost) {
  const cue::RoleView *role = engine.activeRoleRef();
  CueState state = role ? role->state : CueState::Off;

  int link = linkLost ? 1 : 0;
  gStaleLook = linkLost;
  if (!pc.valid || state != pc.state || gCueDisplay != pc.display || link != pc.link) {
    pc.state = state;
    pc.display = gCueDisplay;
    applyTheme(state, gCueDisplay);
  }

  const String &roleLabelText = (role && role->name.length() > 0) ? role->name : engine.selectedRoleIdRef();
  if (!pc.valid || !pc.role.equals(roleLabelText.c_str())) {
    pc.role = roleLabelText;
    lv_label_set_text(roleBtnLabel, pc.role.c_str());
  }

  if (!pc.valid || link != pc.link) {
    pc.link = link;
    setHidden(noConnLabel, !linkLost);
  }

  int64_t wallMs = 0;
  char clockBuf[24];
  if (engine.wallClockMs(wallMs)) {
    pagersync::formatTimeOfDay(wallMs, engine.utcOffsetSeconds(), clockBuf, sizeof(clockBuf));
  } else {
    snprintf(clockBuf, sizeof(clockBuf), "--:--:--");
  }
  if (!pc.valid || !pc.clockText.equals(clockBuf)) {
    pc.clockText = clockBuf;
    lv_label_set_text(clockLabel, clockBuf);
    if (pc.valid) lv_refr_now(NULL);
  }
  int utc = engine.hasUtcOffset() ? 0 : 1;
  if (!pc.valid || utc != pc.clockUtc) {
    pc.clockUtc = utc;
    lv_label_set_text(clockCaption, utc ? "UTC" : "LOCAL TIME");
  }

  bool timerShown = engine.timerFound();
  bool header = timerShown && engine.timerIsHeader();
  bool actual = engine.timerIsDurationActual();
  if (!pc.valid || timerShown != pc.timerShown) {
    pc.timerShown = timerShown;
    setHidden(itemCard, !timerShown);
    pc.remainingValid = false;
    pc.layoutDirty = true;
  }
  if (timerShown) {
    const String &titleSrc = engine.timerTitle();
    if (!pc.valid || !pc.title.equals(titleSrc.c_str())) {
      pc.title = titleSrc;
      String title = titleSrc;
      title.toUpperCase();
      lv_label_set_text(itemTitleLabel, title.c_str());
    }
    if (!pc.valid || header != pc.timerHeader) {
      pc.timerHeader = header;
      setHidden(timerLabel, header);
      setHidden(projActualLabel, header);
      pc.remainingValid = false;
      pc.notesSig = "\1";
      pc.layoutDirty = true;
    }
    if (!header) {
      int remaining = engine.timerRemainingSeconds();
      if (!pc.remainingValid || remaining != pc.remaining) {
        pc.remaining = remaining;
        pc.remainingValid = true;
        int absRemaining = remaining < 0 ? -remaining : remaining;
        char buf[16];
        snprintf(buf, sizeof(buf), "%s%02d:%02d", remaining < 0 ? "+" : "", absRemaining / 60, absRemaining % 60);
        lv_label_set_text(timerLabel, buf);
      }
      if (!pc.valid || !pc.actualValid || actual != pc.actual) {
        pc.actual = actual;
        pc.actualValid = true;
        lv_label_set_text(projActualLabel, actual ? "ACTUAL" : "PROJECTED");
      }
    }

    String sig;
    int noteCount = header ? 0 : engine.roleNoteCount();
    for (int i = 0; i < noteCount; i++) {
      const char *cat = "";
      const char *txt = "";
      if (!engine.roleNoteAt(i, cat, txt)) break;
      sig += cat;
      sig += '\x1F';
      sig += txt;
      sig += '\x1E';
    }
    if (!pc.notesSig.equals(sig.c_str())) {
      pc.notesSig = sig;
      clearSpans(itemNotes);
      lv_color_t ink = currentInk();
      for (int i = 0; i < noteCount; i++) {
        const char *cat = "";
        const char *txt = "";
        if (!engine.roleNoteAt(i, cat, txt)) break;
        addNoteSpans(itemNotes, cat, txt, i < noteCount - 1, ink);
      }
      pc.layoutDirty = true;
    }
  }

  bool nextShown = timerShown && engine.nextFound();
  if (!pc.valid || nextShown != pc.nextShown) {
    pc.nextShown = nextShown;
    setHidden(nextCard, !nextShown);
    pc.nextTitle = "\1";
    pc.nextLen = -1;
    pc.nextNoteSig = "\1";
    pc.layoutDirty = true;
  }
  if (nextShown) {
    const char *nextTitleSrc = engine.nextTitle();
    if (!pc.nextTitle.equals(nextTitleSrc)) {
      pc.nextTitle = nextTitleSrc;
      String upper = pc.nextTitle;
      upper.toUpperCase();
      lv_label_set_text(nextTitleLabel, upper.c_str());
    }
    int nextLen = engine.nextLengthSeconds();
    if (nextLen != pc.nextLen) {
      pc.nextLen = nextLen;
      char lenBuf[16];
      pagersync::formatLength(nextLen, lenBuf, sizeof(lenBuf));
      lv_label_set_text(nextLenLabel, lenBuf);
    }
    const char *nCat = "";
    const char *nTxt = "";
    bool haveNextNote = engine.nextFirstNote(nCat, nTxt);
    String nsig = haveNextNote ? (String(nCat) + '\x1F' + nTxt) : String("");
    if (!pc.nextNoteSig.equals(nsig.c_str())) {
      pc.nextNoteSig = nsig;
      clearSpans(nextNote);
      if (haveNextNote) {
        addNoteSpans(nextNote, nCat, nTxt, false, currentInk());
        lv_obj_set_height(nextNote, lv_font_get_line_height(&inter_regular_14));
      }
      setHidden(nextNote, !haveNextNote);
      pc.layoutDirty = true;
    }
  }

  const cue::MessageView *msg = engine.latestRelevantMessageRef();
  bool msgShown = msg != nullptr && !dismissedMsgId.equals(msg->id.c_str());
  if (!pc.valid || msgShown != pc.msgShown ||
      (msgShown && (!pc.msgId.equals(msg->id.c_str()) || !pc.msgText.equals(msg->text.c_str())))) {
    pc.msgShown = msgShown;
    if (msgShown) {
      pc.msgId = msg->id;
      pc.msgText = msg->text;
      const lv_font_t *fonts[] = {&inter_bold_18, &inter_bold_14};
      const lv_font_t *chosen = fonts[1];
      lv_point_t size = {0, 0};
      for (const lv_font_t *f : fonts) {
        chosen = f;
        lv_txt_get_size(&size, msg->text.c_str(), f, 0, 0, kContentW - 16, LV_TEXT_FLAG_NONE);
        if (size.y <= kMessageMaxLines * lv_font_get_line_height(f)) break;
      }
      lv_coord_t maxH = kMessageMaxLines * lv_font_get_line_height(chosen);
      lv_obj_set_style_text_font(msgLabel, chosen, 0);
      lv_obj_set_height(msgLabel, size.y < maxH ? size.y : maxH);
      lv_label_set_text(msgLabel, msg->text.c_str());
    }
    setHidden(msgPanel, !msgShown);
    pc.layoutDirty = true;
  }

  if (pc.layoutDirty) {
    pc.layoutDirty = false;
    relayoutPager(timerShown, header, nextShown || msgShown);
  }

  pc.valid = true;
}

bool setCueDisplay(const char *name) {
  pagersync::CueDisplay d;
  if (!pagersync::parseCueDisplay(name, d)) return false;
  gCueDisplay = d;
  store::setCueDisplay(String(pagersync::cueDisplayName(d)));
  pc.valid = false;
  updateCueToggleLabel();
  Serial.printf("[ui] cue display -> %s\n", pagersync::cueDisplayName(d));
  return true;
}

const char *cueDisplayName() {
  return pagersync::cueDisplayName(gCueDisplay);
}

static const int kMaxRolePickerRows = 8;
static lv_obj_t *rolePickerScreen = nullptr;
static String rolePickerIds[kMaxRolePickerRows];
static lv_obj_t *pickerStatusLabel = nullptr, *pickerStatusDot = nullptr;
static String pickerStatusShown;

static void onRoleRowClicked(lv_event_t *e) {
  const char *roleId = (const char *)lv_event_get_user_data(e);
  if (gEngine && roleId) {
    Serial.printf("[ui] role selected: %s\n", roleId);
    gEngine->setSelectedRoleId(String(roleId));
    led::setForCueState(gEngine->activeRole().state);
  }
  showingRolePicker = false;
}

static void updateCueToggleLabel() {
  if (!cueToggleLabel) return;
  String text = String("Cue display: ") + (gCueDisplay == pagersync::CueDisplay::Fullscreen ? "Full screen" : "Outline");
  lv_label_set_text(cueToggleLabel, text.c_str());
  lv_obj_center(cueToggleLabel);
}

static void onCueToggleClicked(lv_event_t *e) {
  setCueDisplay(gCueDisplay == pagersync::CueDisplay::Fullscreen ? "outline" : "full");
}

static void onRolePickerCancelClicked(lv_event_t *e) {
  showingRolePicker = false;
}

static void addRoleRow(lv_obj_t *parent, const char *roleId, const char *displayName) {
  lv_obj_t *row = lv_obj_create(parent);
  lv_obj_set_size(row, 210, 30);
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

static void updatePickerStatus(cue::Engine &engine, bool wifiConnected, bool lanConnected, pagersync::LinkPhase phase) {
  if (!pickerStatusLabel) return;
  bool live = wifiConnected && lanConnected && phase == pagersync::LinkPhase::Live;
  String text = pagersync::linkStatusText(wifiConnected, lanConnected, phase);
  String host = lan::producerLabel();
  if (host.length() > 0) text += " - " + host;
  if (engine.hasClockOffset()) {
    char buf[32];
    snprintf(buf, sizeof(buf), "\nClock %+ld ms", (long)lround(engine.clockOffsetMs()));
    text += buf;
  } else {
    text += "\nClock not synced";
  }
  if (pickerStatusDot) {
    lv_obj_set_style_bg_color(pickerStatusDot, lv_color_hex(live ? 0x34C759 : 0xFF3B30), 0);
  }
  if (!pickerStatusShown.equals(text.c_str())) {
    pickerStatusShown = text;
    lv_label_set_text(pickerStatusLabel, text.c_str());
  }
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
  lv_obj_set_style_pad_row(rolePickerScreen, 4, 0);
  lv_obj_set_style_pad_all(rolePickerScreen, 4, 0);
  lv_obj_set_style_pad_bottom(rolePickerScreen, 26, 0);

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

  lv_obj_t *bgTitle = lv_label_create(rolePickerScreen);
  lv_label_set_text(bgTitle, "Background");
  lv_obj_set_style_text_color(bgTitle, lv_color_white(), 0);
  lv_obj_set_style_text_font(bgTitle, &inter_regular_18, 0);

  lv_obj_t *cueRow = lv_obj_create(rolePickerScreen);
  lv_obj_set_size(cueRow, 210, 30);
  lv_obj_set_style_bg_color(cueRow, lv_color_hex(0x2A3244), 0);
  lv_obj_set_style_bg_opa(cueRow, LV_OPA_COVER, 0);
  lv_obj_set_style_radius(cueRow, 6, 0);
  lv_obj_set_style_border_width(cueRow, 0, 0);
  lv_obj_clear_flag(cueRow, LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_add_flag(cueRow, LV_OBJ_FLAG_CLICKABLE);
  lv_obj_add_event_cb(cueRow, onCueToggleClicked, LV_EVENT_CLICKED, nullptr);
  cueToggleLabel = lv_label_create(cueRow);
  lv_obj_set_style_text_font(cueToggleLabel, &inter_regular_14, 0);
  lv_obj_set_style_text_color(cueToggleLabel, lv_color_white(), 0);
  updateCueToggleLabel();

  lv_obj_t *closeBtn = lv_obj_create(rolePickerScreen);
  lv_obj_remove_style_all(closeBtn);
  lv_obj_add_flag(closeBtn, LV_OBJ_FLAG_IGNORE_LAYOUT | LV_OBJ_FLAG_CLICKABLE);
  lv_obj_clear_flag(closeBtn, LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_set_size(closeBtn, 40, 40);
  lv_obj_align(closeBtn, LV_ALIGN_TOP_RIGHT, 0, -2);
  lv_obj_add_event_cb(closeBtn, onRolePickerCancelClicked, LV_EVENT_CLICKED, nullptr);
  lv_obj_t *closeLabel = lv_label_create(closeBtn);
  lv_obj_set_style_text_font(closeLabel, &inter_bold_18, 0);
  lv_obj_set_style_text_color(closeLabel, lv_color_white(), 0);
  lv_label_set_text(closeLabel, "X");
  lv_obj_center(closeLabel);

  lv_obj_t *statusRow = lv_obj_create(rolePickerScreen);
  lv_obj_remove_style_all(statusRow);
  lv_obj_add_flag(statusRow, LV_OBJ_FLAG_IGNORE_LAYOUT);
  lv_obj_clear_flag(statusRow, LV_OBJ_FLAG_CLICKABLE | LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_set_size(statusRow, 224, LV_SIZE_CONTENT);
  lv_obj_set_flex_flow(statusRow, LV_FLEX_FLOW_ROW);
  lv_obj_set_flex_align(statusRow, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
  lv_obj_set_style_pad_column(statusRow, 5, 0);
  lv_obj_align(statusRow, LV_ALIGN_BOTTOM_MID, 0, 26 - 3);

  pickerStatusDot = lv_obj_create(statusRow);
  lv_obj_remove_style_all(pickerStatusDot);
  lv_obj_set_size(pickerStatusDot, 7, 7);
  lv_obj_set_style_radius(pickerStatusDot, LV_RADIUS_CIRCLE, 0);
  lv_obj_set_style_bg_opa(pickerStatusDot, LV_OPA_COVER, 0);
  lv_obj_clear_flag(pickerStatusDot, LV_OBJ_FLAG_CLICKABLE);

  pickerStatusLabel = lv_label_create(statusRow);
  lv_label_set_long_mode(pickerStatusLabel, LV_LABEL_LONG_DOT);
  lv_obj_set_width(pickerStatusLabel, 200);
  lv_obj_set_style_text_color(pickerStatusLabel, lv_color_hex(0x8A8A90), 0);
  lv_obj_set_style_text_font(pickerStatusLabel, &inter_regular_14, 0);
  pickerStatusShown = "";
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

  pagersync::LinkPhase lp = pagersync::linkPhase((int64_t)engine.silenceMs());
  if (!engine.hasSyncedWithProducer() || lp == pagersync::LinkPhase::Lost) {
    showWaitingForDataScreen(wifiConnected);
    return;
  }
  bool linkLost = !wifiConnected || !lanConnected || lp != pagersync::LinkPhase::Live;

  if (showingRolePicker) {
    if (rolePickerNeedsBuild) {
      buildRolePickerScreen(engine);
      rolePickerNeedsBuild = false;
    }
    updatePickerStatus(engine, wifiConnected, lanConnected, lp);
    if (lv_scr_act() != rolePickerScreen) lv_scr_load(rolePickerScreen);
    return;
  }

  if (!pagerScreen) buildPagerScreen();
  if (lv_scr_act() != pagerScreen) {
    lv_scr_load(pagerScreen);
    pc.valid = false;
  }
  refreshPagerScreen(engine, linkLost);
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
