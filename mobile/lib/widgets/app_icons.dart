// Material Design Icons (Pictogrammers) used across the Moongate app.
//
// Every icon the UI shows is routed through this facade so the whole app
// draws from one consistent set. The glyphs come from the bundled Material
// Design Icons webfont (assets/fonts/MaterialDesignIcons.ttf), declared as the
// `MaterialDesignIcons` font family in pubspec.yaml. The icon set is licensed
// under the Pictogrammers Free License (icons and fonts: Apache License 2.0);
// see assets/fonts/LICENSE-MaterialDesignIcons.txt and THIRD_PARTY_NOTICES.md.
//
// Member names deliberately mirror Flutter's built-in `Icons.<name>` so a call
// site reads `AppIcons.<name>` with the same meaning. A handful of icons that
// have no close Material Design Icons match stay on the built-in Material set
// (noted inline); those are the only `Icons.` references that remain in the app.
//
// Codepoints are generated from the @mdi/font 7.4.47 stylesheet; edit the
// mapping, do not hand-tune codepoints.

// ignore_for_file: constant_identifier_names

import 'package:flutter/material.dart';

/// App-wide icon set, drawn from the bundled Material Design Icons font.
class AppIcons {
  AppIcons._();

  static const String _family = 'MaterialDesignIcons';

  static const IconData power_settings_new = IconData(0xF0425, fontFamily: _family); // mdi:power
  static const IconData play_arrow_rounded = IconData(0xF040A, fontFamily: _family); // mdi:play
  static const IconData hourglass_empty = IconData(0xF06AD, fontFamily: _family); // mdi:timer-sand-empty
  static const IconData chevron_right = IconData(0xF0142, fontFamily: _family); // mdi:chevron-right
  static const IconData add = IconData(0xF0415, fontFamily: _family); // mdi:plus
  // The per-printer HOTEND temperature icon: the plain 3D-printer nozzle, to
  // match what Duet's web UI shows (not a generic flame).
  static const IconData whatshot = IconData(0xF0E5B, fontFamily: _family); // mdi:printer-3d-nozzle
  static const IconData cloud_outlined = IconData(0xF0163, fontFamily: _family); // mdi:cloud-outline
  static const IconData check = IconData(0xF012C, fontFamily: _family); // mdi:check
  static const IconData refresh = IconData(0xF0450, fontFamily: _family); // mdi:refresh
  static const IconData restart_alt = IconData(0xF0709, fontFamily: _family); // mdi:restart
  static const IconData cloud_off = IconData(0xF0164, fontFamily: _family); // mdi:cloud-off-outline
  static const IconData close = IconData(0xF0156, fontFamily: _family); // mdi:close
  static const IconData check_circle_outline = IconData(0xF05E1, fontFamily: _family); // mdi:check-circle-outline
  // The heated-bed temperature icon: a radiator, to match Duet's web UI (not a
  // furniture bed).
  static const IconData bed = IconData(0xF0438, fontFamily: _family); // mdi:radiator
  static const IconData arrow_back = IconData(0xF004D, fontFamily: _family); // mdi:arrow-left
  static const IconData wifi_rounded = IconData(0xF05A9, fontFamily: _family); // mdi:wifi
  static const IconData wifi_off = IconData(0xF05AA, fontFamily: _family); // mdi:wifi-off
  static const IconData videocam_outlined = IconData(0xF0BDC, fontFamily: _family); // mdi:video-outline
  static const IconData sensor_window = IconData(0xF11DB, fontFamily: _family); // mdi:window-closed-variant
  static const IconData check_circle = IconData(0xF05E0, fontFamily: _family); // mdi:check-circle
  static const IconData warning_amber_rounded = IconData(0xF0026, fontFamily: _family); // mdi:alert
  static const IconData stop_rounded = IconData(0xF04DB, fontFamily: _family); // mdi:stop
  static const IconData pause_rounded = IconData(0xF03E4, fontFamily: _family); // mdi:pause
  static const IconData lock_outline = IconData(0xF0341, fontFamily: _family); // mdi:lock-outline
  static const IconData lightbulb_outline = IconData(0xF0336, fontFamily: _family); // mdi:lightbulb-outline
  static const IconData folder_open_rounded = IconData(0xF0770, fontFamily: _family); // mdi:folder-open
  static const IconData code_rounded = IconData(0xF0174, fontFamily: _family); // mdi:code-tags
  static const IconData cloud_off_outlined = IconData(0xF0164, fontFamily: _family); // mdi:cloud-off-outline
  static const IconData visibility_outlined = IconData(0xF06D0, fontFamily: _family); // mdi:eye-outline
  static const IconData videocam_off_outlined = IconData(0xF0BDB, fontFamily: _family); // mdi:video-off-outline
  static const IconData videocam_off = IconData(0xF0568, fontFamily: _family); // mdi:video-off
  static const IconData terminal_rounded = IconData(0xF07B7, fontFamily: _family); // mdi:console-line
  static const IconData system_update_alt = IconData(0xF01DA, fontFamily: _family); // mdi:download
  static const IconData playlist_play = IconData(0xF0411, fontFamily: _family); // mdi:playlist-play
  static const IconData lightbulb = IconData(0xF0335, fontFamily: _family); // mdi:lightbulb
  static const IconData error_outline = IconData(0xF05D6, fontFamily: _family); // mdi:alert-circle-outline
  static const IconData delete_outline = IconData(0xF09E7, fontFamily: _family); // mdi:delete-outline
  static const IconData cancel_outlined = IconData(0xF015A, fontFamily: _family); // mdi:close-circle-outline
  static const IconData bug_report_outlined = IconData(0xF0A30, fontFamily: _family); // mdi:bug-outline
  static const IconData warning_rounded = IconData(0xF0026, fontFamily: _family); // mdi:alert
  static const IconData tune = IconData(0xF062E, fontFamily: _family); // mdi:tune
  static const IconData timer_outlined = IconData(0xF051B, fontFamily: _family); // mdi:timer-outline
  static const IconData thermostat_rounded = IconData(0xF0393, fontFamily: _family); // mdi:thermostat
  static const IconData text_fields = IconData(0xF027F, fontFamily: _family); // mdi:format-size
  static const IconData sync = IconData(0xF04E6, fontFamily: _family); // mdi:sync
  static const IconData stop_circle_rounded = IconData(0xF0666, fontFamily: _family); // mdi:stop-circle
  static const IconData sports_score = IconData(0xF023C, fontFamily: _family); // mdi:flag-checkered
  static const IconData settings_outlined = IconData(0xF08BB, fontFamily: _family); // mdi:cog-outline
  static const IconData settings = IconData(0xF0493, fontFamily: _family); // mdi:cog
  static const IconData schedule = IconData(0xF0150, fontFamily: _family); // mdi:clock-outline
  static const IconData remove = IconData(0xF0374, fontFamily: _family); // mdi:minus
  static const IconData radio_button_unchecked = IconData(0xF043D, fontFamily: _family); // mdi:radiobox-blank
  static const IconData radio_button_checked = IconData(0xF043E, fontFamily: _family); // mdi:radiobox-marked
  static const IconData print = IconData(0xF042A, fontFamily: _family); // mdi:printer
  static const IconData playlist_add = IconData(0xF0412, fontFamily: _family); // mdi:playlist-plus
  static const IconData open_in_new = IconData(0xF03CC, fontFamily: _family); // mdi:open-in-new
  static const IconData menu = IconData(0xF035C, fontFamily: _family); // mdi:menu
  static const IconData layers_outlined = IconData(0xF09FE, fontFamily: _family); // mdi:layers-outline
  static const IconData keyboard_arrow_up = IconData(0xF0143, fontFamily: _family); // mdi:chevron-up
  static const IconData keyboard_arrow_down = IconData(0xF0140, fontFamily: _family); // mdi:chevron-down
  static const IconData info_outline = IconData(0xF02FD, fontFamily: _family); // mdi:information-outline
  static const IconData help_outline = IconData(0xF0625, fontFamily: _family); // mdi:help-circle-outline
  static const IconData fingerprint = IconData(0xF0237, fontFamily: _family); // mdi:fingerprint
  static const IconData file_download_outlined = IconData(0xF0966, fontFamily: _family); // mdi:file-download-outline
  static const IconData edit_outlined = IconData(0xF0CB6, fontFamily: _family); // mdi:pencil-outline
  static const IconData drag_handle = IconData(0xF12F0, fontFamily: _family); // mdi:drag-horizontal-variant
  static const IconData download_outlined = IconData(0xF0B8F, fontFamily: _family); // mdi:download-outline
  static const IconData coffee_outlined = IconData(0xF06CA, fontFamily: _family); // mdi:coffee-outline
  static const IconData cloud_sync_outlined = IconData(0xF12D6, fontFamily: _family); // mdi:cloud-sync-outline
  static const IconData cloud_download_outlined = IconData(0xF0B7D, fontFamily: _family); // mdi:cloud-download-outline
  static const IconData cloud_done_rounded = IconData(0xF1BEB, fontFamily: _family); // mdi:cloud-check
  static const IconData close_rounded = IconData(0xF0156, fontFamily: _family); // mdi:close
  static const IconData clear = IconData(0xF0156, fontFamily: _family); // mdi:close
  static const IconData cameraswitch_outlined = IconData(0xF084A, fontFamily: _family); // mdi:camera-switch-outline
  static const IconData arrow_drop_down = IconData(0xF035D, fontFamily: _family); // mdi:menu-down
  static const IconData add_circle_outline = IconData(0xF0419, fontFamily: _family); // mdi:plus-circle-outline
  static const IconData wifi = IconData(0xF05A9, fontFamily: _family); // mdi:wifi
  static const IconData wallpaper_outlined = IconData(0xF0E09, fontFamily: _family); // mdi:wallpaper
  static const IconData visibility_off_outlined = IconData(0xF06D1, fontFamily: _family); // mdi:eye-off-outline
  static const IconData videocam = IconData(0xF0567, fontFamily: _family); // mdi:video
  static const IconData vertical_align_top = IconData(0xF0795, fontFamily: _family); // mdi:arrow-collapse-up
  static const IconData upload_file_outlined = IconData(0xF0A4E, fontFamily: _family); // mdi:file-upload-outline
  static const IconData tune_rounded = IconData(0xF062E, fontFamily: _family); // mdi:tune
  static const IconData translate = IconData(0xF05CA, fontFamily: _family); // mdi:translate
  static const IconData thermostat_outlined = IconData(0xF0393, fontFamily: _family); // mdi:thermostat
  static const IconData system_update_alt_rounded = IconData(0xF01DA, fontFamily: _family); // mdi:download
  static const IconData swap_vert = IconData(0xF04E2, fontFamily: _family); // mdi:swap-vertical
  static const IconData subdirectory_arrow_right_rounded = IconData(0xF060D, fontFamily: _family); // mdi:subdirectory-arrow-right
  static const IconData star_rounded = IconData(0xF04CE, fontFamily: _family); // mdi:star
  static const IconData star_border_rounded = IconData(0xF04D2, fontFamily: _family); // mdi:star-outline
  static const IconData snippet_folder_outlined = IconData(0xF0C83, fontFamily: _family); // mdi:folder-text-outline
  static const IconData smart_button_outlined = IconData(0xF12A8, fontFamily: _family); // mdi:gesture-tap-button
  static const IconData shutter_speed = IconData(0xF05A0, fontFamily: _family); // mdi:webcam
  static const IconData send_rounded = IconData(0xF048A, fontFamily: _family); // mdi:send
  static const IconData send_outlined = IconData(0xF1165, fontFamily: _family); // mdi:send-outline
  static const IconData screen_rotation_outlined = IconData(0xF0475, fontFamily: _family); // mdi:screen-rotation
  static const IconData school_outlined = IconData(0xF1180, fontFamily: _family); // mdi:school-outline
  static const IconData schedule_outlined = IconData(0xF0150, fontFamily: _family); // mdi:clock-outline
  static const IconData remove_circle_outline = IconData(0xF0377, fontFamily: _family); // mdi:minus-circle-outline
  static const IconData radio_button_off = IconData(0xF043D, fontFamily: _family); // mdi:radiobox-blank
  static const IconData qr_code_scanner = IconData(0xF0433, fontFamily: _family); // mdi:qrcode-scan
  static const IconData qr_code_2 = IconData(0xF0432, fontFamily: _family); // mdi:qrcode
  static const IconData push_pin_outlined = IconData(0xF0931, fontFamily: _family); // mdi:pin-outline
  static const IconData print_outlined = IconData(0xF1786, fontFamily: _family); // mdi:printer-outline
  static const IconData print_disabled = IconData(0xF0E5D, fontFamily: _family); // mdi:printer-off
  static const IconData play_circle_outline = IconData(0xF040D, fontFamily: _family); // mdi:play-circle-outline
  static const IconData play_arrow = IconData(0xF040A, fontFamily: _family); // mdi:play
  static const IconData pause = IconData(0xF03E4, fontFamily: _family); // mdi:pause
  static const IconData password_outlined = IconData(0xF0DD6, fontFamily: _family); // mdi:key-outline
  static const IconData palette_outlined = IconData(0xF0E0C, fontFamily: _family); // mdi:palette-outline
  static const IconData open_with_rounded = IconData(0xF0041, fontFamily: _family); // mdi:arrow-all
  static const IconData open_with = IconData(0xF0041, fontFamily: _family); // mdi:arrow-all
  static const IconData notifications_off_outlined = IconData(0xF0A91, fontFamily: _family); // mdi:bell-off-outline
  static const IconData notifications_active_outlined = IconData(0xF009F, fontFamily: _family); // mdi:bell-ring-outline
  static const IconData no_photography = IconData(0xF05DF, fontFamily: _family); // mdi:camera-off
  static const IconData new_releases_outlined = IconData(0xF0394, fontFamily: _family); // mdi:new-box
  static const IconData my_location_rounded = IconData(0xF01A4, fontFamily: _family); // mdi:crosshairs-gps
  static const IconData logout = IconData(0xF0343, fontFamily: _family); // mdi:logout
  static const IconData lock_rounded = IconData(0xF033E, fontFamily: _family); // mdi:lock
  static const IconData local_fire_department = IconData(0xF0238, fontFamily: _family); // mdi:fire
  static const IconData light_mode = IconData(0xF0599, fontFamily: _family); // mdi:weather-sunny
  static const IconData layers_clear_outlined = IconData(0xF09FD, fontFamily: _family); // mdi:layers-off-outline
  static const IconData layers = IconData(0xF0328, fontFamily: _family); // mdi:layers
  static const IconData lan_outlined = IconData(0xF0317, fontFamily: _family); // mdi:lan
  static const IconData keyboard_outlined = IconData(0xF097B, fontFamily: _family); // mdi:keyboard-outline
  static const IconData keyboard_arrow_right = IconData(0xF0142, fontFamily: _family); // mdi:chevron-right
  static const IconData keyboard_arrow_left = IconData(0xF0141, fontFamily: _family); // mdi:chevron-left
  static const IconData insert_drive_file_outlined = IconData(0xF0224, fontFamily: _family); // mdi:file-outline
  static const IconData image_not_supported_outlined = IconData(0xF11D1, fontFamily: _family); // mdi:image-off-outline
  static const IconData hourglass_bottom_rounded = IconData(0xF078C, fontFamily: _family); // mdi:timer-sand-full
  static const IconData home_outlined = IconData(0xF06A1, fontFamily: _family); // mdi:home-outline
  static const IconData format_list_bulleted = IconData(0xF0279, fontFamily: _family); // mdi:format-list-bulleted
  static const IconData font_download_outlined = IconData(0xF06D6, fontFamily: _family); // mdi:format-font
  static const IconData folder_rounded = IconData(0xF024B, fontFamily: _family); // mdi:folder
  static const IconData folder_off_outlined = IconData(0xF19F9, fontFamily: _family); // mdi:folder-off-outline
  static const IconData filter_alt_outlined = IconData(0xF0233, fontFamily: _family); // mdi:filter-outline
  static const IconData favorite = IconData(0xF02D1, fontFamily: _family); // mdi:heart
  static const IconData extension = IconData(0xF0431, fontFamily: _family); // mdi:puzzle
  static const IconData expand_more = IconData(0xF0140, fontFamily: _family); // mdi:chevron-down
  static const IconData edit = IconData(0xF03EB, fontFamily: _family); // mdi:pencil
  static const IconData drag_indicator = IconData(0xF01DB, fontFamily: _family); // mdi:drag
  static const IconData description_outlined = IconData(0xF09EE, fontFamily: _family); // mdi:file-document-outline
  static const IconData description = IconData(0xF0219, fontFamily: _family); // mdi:file-document
  static const IconData delete_sweep_outlined = IconData(0xF0C62, fontFamily: _family); // mdi:delete-sweep-outline
  static const IconData delete_forever_outlined = IconData(0xF0B89, fontFamily: _family); // mdi:delete-forever-outline
  static const IconData dashboard_customize_outlined = IconData(0xF1948, fontFamily: _family); // mdi:view-dashboard-edit-outline
  static const IconData dashboard_customize = IconData(0xF1947, fontFamily: _family); // mdi:view-dashboard-edit
  static const IconData dark_mode = IconData(0xF0594, fontFamily: _family); // mdi:weather-night
  static const IconData crop_square_outlined = IconData(0xF0763, fontFamily: _family); // mdi:square-outline
  static const IconData crop_square = IconData(0xF0764, fontFamily: _family); // mdi:square
  static const IconData crop_portrait = IconData(0xF01A1, fontFamily: _family); // mdi:crop-portrait
  static const IconData colorize = IconData(0xF020A, fontFamily: _family); // mdi:eyedropper
  // No close Material Design Icons match: kept on the built-in Material set.
  static const IconData code_off = Icons.code_off;
  static const IconData cleaning_services_rounded = IconData(0xF00E2, fontFamily: _family); // mdi:broom
  static const IconData chevron_left = IconData(0xF0141, fontFamily: _family); // mdi:chevron-left
  static const IconData cable_rounded = IconData(0xF1394, fontFamily: _family); // mdi:cable-data
  static const IconData bolt_rounded = IconData(0xF140B, fontFamily: _family); // mdi:lightning-bolt
  static const IconData backspace_outlined = IconData(0xF0B5C, fontFamily: _family); // mdi:backspace-outline
  static const IconData auto_awesome_outlined = IconData(0xF0068, fontFamily: _family); // mdi:auto-fix
  static const IconData auto_awesome = IconData(0xF0068, fontFamily: _family); // mdi:auto-fix
  static const IconData account_tree_outlined = IconData(0xF13D2, fontFamily: _family); // mdi:file-tree-outline
  static const IconData ac_unit_rounded = IconData(0xF0717, fontFamily: _family); // mdi:snowflake
}
