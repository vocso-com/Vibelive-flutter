# Analytics events (Firebase + Meta)

Every screen and user action in the VibeLive Flutter app is sent to **Firebase Analytics** and **Meta (Facebook) App Events**. This file lists every event and what it carries. It is for anyone building reports, funnels, or ad conversions.

Code: `lib/core/analytics/` (`analytics.dart` sends events, `screen_tracker.dart` logs screens, `analytics_identity.dart` sets who the user is, `events/*.dart` holds each area's events) and `lib/app/callscreen/helper/call_analytics.dart` (calls).

## Key funnels

| funnel | events in order |
|---|---|
| Sign-in | `login` screen → `login_method_selected` → `otp_requested` → `auth_success` → `sign_up` (new account) or `login` (returning user) → `onboarding_completed` |
| Sign-in method | `sign_up` / `login` / `auth_success` carry `method` = `phone` / `email` / `google` / `apple` |
| Become a Host | `host_onboarding_started` → `host_ob_intro_viewed` → `host_ob_basic_viewed` → … → `host_ob_guidelines_completed` → `host_onboarding_submitted` (one viewed and one completed event per step, 12 steps) |
| Call (client) | `view_expert` → `call_button_tapped` → `call_initiated` → `call_ringing` → `call_accepted` → `call_started` → `call_ended`; drop-offs: `call_initiate_failed`, `call_cancelled`, `call_not_answered`, `call_rejected`, `call_failed` |
| Call (host) | `call_incoming` → `call_accepted` → `call_started` → `call_ended`; drop-offs: `call_declined`, `call_missed`, `call_failed` |
| Top-up | `wallet_opened` → `add_money_opened` → `add_money_amount_selected` → `initiate_payment` → `payment_success` (or `payment_failed` / `payment_abandoned`) |

## Meta conversion events (for ad optimization)

| Meta event | sent when |
|---|---|
| `fb_mobile_complete_registration` | a new account is created (once per user) |
| `fb_mobile_content_view` | a host profile is opened (value = per-minute rate) |
| `fb_mobile_search` | a search returns results |
| `fb_mobile_add_to_wishlist` | a host is added to favourites |
| `fb_mobile_initiated_checkout`, `fb_mobile_add_payment_info` | a top-up or badge payment starts; `fb_mobile_initiated_checkout` also when a call is booked (`content_type: call_booking`) |
| Purchase (`logPurchase`, INR) | a top-up or badge payment succeeds (once per transaction) |
| `fb_mobile_rate` | a call is rated or reviewed |
| `SubmitApplication` | a host application is submitted |
| `fb_mobile_tutorial_completion` | the intro slides are finished |
| `Contact` | support is contacted |
| custom: `first_call_completed`, `first_topup`, `expert_signup`, `call_started`, `call_ended`, … | every custom event below also reaches Meta under the same name |


## How tracking works

- Every event goes to **both** Firebase Analytics and Meta (Facebook) App Events through one class, `Analytics` (`lib/core/analytics/analytics.dart`). Where a Meta standard event or a Firebase recommended event exists, it is sent as well (noted in the tables).
- Event names reuse the RN app's names wherever RN had one (`sign_up`, `login`, `view_expert`, `call_started`, `payment_success`, …). Both apps share the same Firebase project and Meta app, so reports continue across the update.
- No personal data goes into event parameters: no phone numbers, emails, client names, OTPs, or typed text. Ids, counts, and booleans only. The user's email, phone, name, gender, and date of birth go to Meta only through **advanced matching** (`setUserData`), which the SDK hashes on the device.
- Automatic events: Firebase logs `first_open`, `session_start`, `user_engagement`, `app_update` on its own. Meta logs install, app launch, and sessions on its own (auto-logging is on).

## Screens (`screen_view`)

Every page, Home tab, onboarding step, sheet, and dialog sends a screen view. It goes to Firebase as its native `screen_view` and to Meta as a custom `screen_view` event with `screen_name`. Code: `lib/core/analytics/screen_tracker.dart`.

| screen_name | what |
|---|---|
| splash | splash / intro |
| login | sign-in options (sub-views: login_mobile, login_email, login_otp_mobile, login_otp_email, login_phone_required) |
| onboarding_age_gate, onboarding_language | 18+ gate, language pick |
| home_discover, home_history, home_me | the three Home tabs |
| search | search |
| call, incoming_call | call screen, incoming ring |
| wallet | wallet |
| personal_info, gst_details, favourites, blocked_users, referral | Me sub-pages |
| categories, category_menu, dynamic_page (slug), about_app, support, webview (url) | resources / CMS |
| host_onboarding (+ host_onboarding_<step> per step) | Become a Host |
| host_profile_edit, host_expertise, host_schedule, host_call_rates | host edits a section |
| host_approval_status, host_profile_qr | host hub |
| verification_badge, verification_badge_form, verification_badge_fee, verification_badge_status | blue-tick badge |
| `*_sheet` | every bottom sheet / dialog (names in each area's table) |
| route_<path> | any route added later that has no name yet |

## User identity (`lib/core/analytics/analytics_identity.dart`)

On sign-in, profile change, and sign-out:

- **User id** (documentId) on Firebase (`setUserId`) and Meta (`setUserID`).
- **Firebase user properties:** `user_role` (client / host), `host_approved`, `is_company`, `gender`, `app_language`.
- **Meta advanced matching:** email, phone (91…), first name, gender (m/f), date of birth (YYYYMMDD), country `in`, and `externalId` = user id.
- `logout` {reason: user | session_expired}, then the ids are cleared on both platforms.

## Calls (`lib/app/callscreen/helper/call_analytics.dart`)

Every call event comes from one observer on the call's state, so calls answered from CallKit, a push, the Android notification, or the app are all counted the same way.

Common params on every call event: `call_id`, `call_type` (audio | video), `role` (caller | receiver), `host_id` and `expert_id` (the same value, caller side; `expert_id` is RN's name), `peer_id`, `category`, `instant_call`, `company_call`.

| event | when | extra params |
|---|---|---|
| call_initiated | caller: the call was created on the server, ringing starts | |
| book_consultation | caller: the server accepted the call (not busy), once per call (RN name); with Meta `fb_mobile_initiated_checkout` {content_id, content_type: call_booking, category, currency} | expert_id, category |
| call_incoming | receiver: the ring is shown | locked, auto_accept |
| call_ringing | caller: the host's phone is ringing | |
| call_accepted | the call was answered (both sides) | ring_seconds |
| call_started | connected, the timer is running (RN name) | rate_per_min |
| call_ended | a connected call finished (RN name); Meta value = duration in seconds | end_reason, duration_seconds, duration_minutes, duration_bucket (under_1m, 1_5m, 5_15m, 15_30m, over_30m), rate_per_min |
| call_cancelled | caller hung up before an answer | end_reason, ring_seconds |
| call_not_answered | caller: nobody answered in time | end_reason, ring_seconds |
| call_rejected | caller: the host declined / the server ended it before connect | end_reason, ring_seconds |
| call_declined | receiver declined (in the app, on CallKit, or decline + block / report) | end_reason, ring_seconds, source |
| call_missed | receiver never answered (caller cancelled, ring timed out, answered on another device) | end_reason, ring_seconds |
| call_failed | could not connect (join failed, the other side never joined, network) | end_reason, ring_seconds, was_accepted |
| first_call_started / first_call_completed | the user's first call as a caller (once per user, per install) | as call_started / call_ended |
| host_first_call_started / host_first_call_completed | a host's first received call | as above |

`end_reason` values: user_hangup, remote_hangup, remote_dropped, remote_ended, admin_ended, balance_exhausted, network_lost, token_expired, no_answer, peer_never_joined, join_failed, other_device, answered_elsewhere, system_ui, declined, caller_cancelled, ring_timeout, safety_block, safety_report, sign_out.

## Sign-in, onboarding, intro, push and deep links

Files: `lib/core/analytics/events/auth_events.dart` (AuthEvents), `lib/core/analytics/events/app_events.dart` (AppEvents).
All events go to Firebase + Meta through `Analytics.log` unless noted. `method` ∈ `phone | email | google | apple`.

### Sign-in
| event | when | params | Meta standard / Firebase recommended |
|---|---|---|---|
| login_method_selected | mobile / email sheet opened, Google / Apple tapped, or a social user is sent to the mobile sheet | method, source (`options` / `switch` / `phone_required`) | |
| login_sheet_closed | mobile / email sheet closed without signing in | method, otp_sent | |
| login_input_invalid | SEND OTP / Verify refused locally | method, field (`phone` / `email` / `code`) | |
| login_terms_required | SEND OTP with the terms box unticked | method | |
| login_terms_toggled | terms checkbox tapped | accepted | |
| phone_hint_result | Android SIM-number picker answered | picked | |
| legal_link_opened | Terms / Privacy / Guidelines opened | doc (`terms` / `privacy` / `guidelines`), source (`login_options` / `login_form` / `terms_page`) | |
| otp_requested | a code was sent (or the cooldown brought back the still-valid code) | method, cooldown_resume? | |
| otp_request_failed | /otp/request failed | method, error | |
| otp_resent | Resend worked | method | |
| otp_resend_failed | Resend failed | method, error | |
| otp_autofilled | the whole code arrived at once | method, source (`sms_retriever` / `keyboard`) | |
| otp_verify_failed | wrong / expired code, or verify error | method, error | |
| otp_change_identifier | "Change" / Back on the code step | method | |
| social_login_started | Google / Apple tapped | provider | |
| social_login_cancelled | provider sheet closed without an account | provider | |
| social_login_failed | provider error or backend refused the token | provider, error, stage (`provider` / `server`) | |
| social_phone_required | backend wants a verified mobile from this social user | provider | |
| terms_consent_shown / terms_consent_accepted / terms_consent_declined | one-time T&C consent after a Google / Apple sign-in | provider | (decline also logs `logout` with reason `terms_declined`) |
| referral_code_field_opened | "Have a referral code?" tapped | — | |
| referral_code_valid / referral_code_invalid | a referral code was checked | source (`typed` / `link` / `install_referrer`) | |
| auth_success | any successful sign-in | method, source (`referral` / `app`), is_new_user, otp_bypass?, phone_verified? | |
| sign_up | new account (no name yet), once per user per install | method, source, otp_bypass?, phone_verified? | Firebase recommended `sign_up`; Meta `fb_mobile_complete_registration` {fb_registration_method, source} |
| login | returning user, once per user + method per app session | method, source, otp_bypass?, phone_verified? | Firebase recommended `login` |
| login_failed | whitelisted (bypass) number got tokens but the sign-in could not finish | method, error, otp_bypass | |

A social user who has to verify a mobile is logged with method = the provider (`google` / `apple`) and `phone_verified: true`.

### Onboarding (after sign-in)
| event | when | params | |
|---|---|---|---|
| age_gate_date_picker | the date wheel closed | confirmed | |
| age_gate_submitted | date of birth sent, or refused locally | result (`allowed` / `blocked` / `needs_date` / `unknown` / `invalid` / `error`), error? | |
| age_gate_blocked_shown | the "under 18" terminal state shown | — | |
| onboarding_language_toggled | language chip toggled | selected, count | |
| language_selected | expert-language step saved | language (comma-joined language documentIds), count, source=`onboarding` | |
| onboarding_language_skipped | Skip / "Continue to the app" / step not asked | reason (`skip` / `load_error` / `not_asked`) | |
| onboarding_language_failed | saving the step failed | error | |
| onboarding_completed | onboarding step → Home, once per user per install | steps (`age_gate` / `language`) | |
| onboarding_sign_out | "Not you? Sign out" on a step | screen (`age_gate` / `language`) | (then `logout` reason `user`) |

User property `app_language` (en / hi) is set at startup and on every language change (LocaleController).

### Intro slides (signed out, after splash)
| event | when | params | |
|---|---|---|---|
| intro_started | first slide shown | — | Firebase `tutorial_begin` |
| intro_slide_viewed | each slide shown | index, slide (`talk` / `pay` / `choose`) | |
| intro_skipped | Skip | index, slide | |
| intro_completed | Get started on the last slide | slides | Firebase `tutorial_complete`; Meta `fb_mobile_tutorial_completion` |

### Launch
| event | when | params |
|---|---|---|
| app_launched | once per cold start, when the splash knows the next screen | signed_in, role (`host` / `client`), next_screen (screen name), launch_source (`normal` / `call`) |

### Notifications (non-call delivery; every tap)
| event | when | params |
|---|---|---|
| push_received | a non-call push reached the app (foreground or background isolate) | kind (`campaign` / `wallet` / `verification` / `milestone` / `general`), type, campaign_id?, foreground, has_deeplink |
| push_shown | the app drew a banner for it | kind, type, campaign_id?, background |
| push_opened | any notification tap (calls included) | destination (`campaign` / `wallet` / `verification` / `referral` / `call_history` = missed call / `incoming_call` / `ongoing_call` / `callback` / `route` / `link` / `none`), type, campaign_id?, screen?, has_deeplink |

`campaign_id` = `campaignId` / `campaign_id` / `notificationTrackingId` / `trackingId` of the push data.

### Links
| event | when | params |
|---|---|---|
| deeplink_received | the OS handed the app a link (not from a push) | source (`scheme` / `web` / `share`), signed_in, parked, has_referral |
| deeplink_opened | a link actually opened a screen | screen (screen name, or `host_profile` / `external_browser`), source (`share` / `campaign` / `push`), link_type (share path or campaign screen), fallback_home, external |
| install_referrer | Android Play install referrer read, once per install | has_code, intent (`refer` / `invite` / `hostProfile`) |

### Update notice
| event | when | params |
|---|---|---|
| update_prompt_shown | notice on screen (once per notice) | version, forced |
| update_tapped | Update tapped (store opened) | version, forced |
| update_dismissed | Later / Back | version |

### Screens added (ScreenTracker.view / sheets)
- Login steps: `login`, `login_mobile`, `login_email`, `login_otp_mobile`, `login_otp_email`, `login_phone_required`
- Terms: `terms` (read-only), `terms_consent` (social consent, param provider); the step under it is logged again on close
- Age gate: `onboarding_age_blocked`; sheet `age_date_picker_sheet`
- Intro slides: `intro_talk`, `intro_pay`, `intro_choose`
- Update overlay: `update_notice` (param forced)

## Home, Discover, search and host profile

Helpers: `lib/core/analytics/events/discover_events.dart` (`DiscoverEvents`). All go to Firebase + Meta unless noted.

### Screens (sub-screens and sheets)
- Home tabs: `home_discover`, `home_history`, `home_me` (ScreenTracker.setSubScreen('/home', …) on every tab change)
- Sheets / dialogs: `host_profile_sheet`, `host_profile_menu_sheet`, `host_profile_share_sheet`,
  `host_influencer_sheet`, `host_report_sheet`, `filter_sheet`, `call_safety_prompt`

### Events
| event | when | params | Meta standard / Firebase recommended |
|---|---|---|---|
| nav_tab_tapped | bottom-dock tab tapped | tab, reselect | |
| top_bar_button_tapped | Discover/Me/History header button | button (search, filter, wallet, back, me_menu), tab | |
| discover_topic_selected | topic chip tapped (user) | kind (all/popular/topic), topic, position | |
| talk_now_tapped | "Talk now" button | blocked_by_call | |
| status_opened | a host's circle in the Home status row | host_id, position, seen | |
| promo_banner_viewed | a promo banner came on screen (once per banner per session) | banner_id, placement (`home`/`wallet`), position, template (`spotlight`, `offer`, `full_image`, `glass`, `minimal`, `countdown`, `custom`) | |
| promo_banner_tapped | a promo banner was tapped | banner_id, placement, action (`app`/`url`/`none`), template | |
| promo_banner_dismissed | a closable promo banner was closed | banner_id, placement | |
| promo_code_copied | a banner's coupon code was copied | banner_id, placement, template | |
| promo_popup_shown | an app-open popup came on screen (screen `promo_popup_<template>`) | popup_id, template (`offer_card`, `poster`, `celebration`, `bottom_sheet`, `countdown`, `spotlight`, `announcement`, `fullscreen`), show_count (times on this phone), cause (`launch`/`resume`) | |
| promo_popup_cta_tapped | the popup's main button (poster: the image) | popup_id, template, action (`app`/`url`/`none`) | |
| promo_popup_closed | the popup closed without its button | popup_id, template, how (`close_button`/`secondary`/`backdrop`/`back`/`expired`), seconds_open | |
| promo_popup_code_copied | the popup's coupon code was copied | popup_id, template | |
| promo_popup_skipped | a popup was due this app open but did not show | popup_id, template, reason (`busy`: a sheet / other screen over Home; `call`; `update_notice`; `external_open`: a notification or link opened the app; `image_failed`) | |
| status_visit_profile | Visit profile under a status | host_id | |
| status_add_tapped | a host's own circle or its "+" (record a status) | has_live | |
| host_card_tapped | feed card / Call Now on a card | host_id, action (open/call), position, tab, topic, is_online, featured, filtered, audio_rate, source=discover | |
| discover_refreshed | pull-to-refresh / Discover re-tapped at top / Try again | trigger (pull, tab_reselect, retry), tab | |
| discover_load_more | infinite scroll asks for next page | page, loaded | |
| discover_empty_shown | tab / filter has no hosts | tab, topic, filtered | |
| discover_load_error | feed failed to load | tab, error | |
| filter_opened | filter sheet opened | source (discover/search), active_count | |
| filter_applied | Apply | source, languages_count, languages, has_topic, topic | |
| filter_cleared | Clear all, then closed | source | |
| filter_dismissed | closed without applying | source | |
| filter_chip_removed | active filter chip ✕ | source, kind (language/topic), value | |
| search | once per settled query (not per keystroke) | search_term, results_count, categories_count, trigger (typing/submit/category/link) | Meta `fb_mobile_search` {fb_search_string, fb_content_type=host, fb_success}; name = Firebase recommended `search` (RN parity) |
| search_no_results | settled query with nothing | search_term | |
| search_failed | search request failed | search_term, error | |
| search_result_tapped | host row in results | host_id, position, results_count, filtered | |
| search_category_tapped | category / category-by-location row | kind (category/location), category, position | |
| search_cleared | ✕ in the search field (non-empty) | – | |
| search_open_failed | result's full profile could not load | error | |
| view_expert | host profile sheet open, once full profile known (RN parity) | expert_id, category, price, video_price, source, is_online, rating, verified, is_own | Meta `fb_mobile_content_view` {fb_content_type=host_profile, fb_content_id, fb_currency=INR, category, source}, valueToSum = audio rate (not for own profile) |
| host_profile_closed | sheet closed | host_id, source, seconds_open, photos_viewed, photo_count | |
| profile_photo_preview_opened | gallery middle tap → full preview | host_id, index, photo_count | |
| profile_bio_toggled | bio Read more / less | expanded | |
| profile_influencer_opened | influencer badge tapped | host_id | |
| voice_intro_played / voice_intro_stopped / voice_intro_completed / voice_intro_failed | voice intro row | host_id, seconds / error | |
| profile_reviews_more_tapped | reviews "See more" | host_id, loaded, total | |
| favourite_added / favourite_removed | heart in photo preview | host_id, source=photo_preview | Meta `fb_mobile_add_to_wishlist` on add |
| favourite_failed | favourite request failed | host_id, adding, error | |
| profile_share_opened | share button in profile top bar | host_id | |
| profile_shared | share via OS / copy link / QR (top bar sheet or photo preview) | host_id, method (system/copy_link/qr) | Firebase recommended `share` {method, content_type=host_profile, item_id} |
| profile_link_tapped | social / website link (chips, influencer sheet) | host_id, kind (instagram/facebook/snapchat/website), source, opened | |
| call_button_tapped | audio / video button on profile | host_id, call_type, rate, source, is_company | |
| call_precheck_result | where pre-call checks ended | host_id, call_type, result (passed/own_profile/signed_out/incomplete_profile/balance_gate/safety_cancelled), enough_balance | |
| call_prompt_answered | login / update-profile alert before a call | prompt (login/update_profile), accepted | |
| balance_gate_shown / balance_gate_topup_tapped | (existing, RN parity) | expert_id, required, balance, gap / suggested_amount | |
| balance_gate_transfer_tapped | gate's Transfer earnings | expert_id, gap | (transfer sheet opened with source=balance_gate) |
| balance_gate_dismissed | gate closed without choice | expert_id, gap | |
| safety_prompt_answered | "Before you connect" | call_type, result (accepted/cancelled) | |
| profile_menu_choice | ⋮ menu closed | host_id, action (report/block/dismissed) | |
| host_report_reason_selected | report category chip | host_id, reason (category id) | |
| host_report_blocked | submit held back | host_id, problem (signed_out/no_target/no_reason) | |
| host_report_submitted | report sent | host_id, reason, has_note, note_length, source=profile_sheet | |
| host_report_failed | report failed | host_id, reason, error, source | |
| host_block | block from profile | host_id, step (confirmed/cancelled/success/failed/no_target), error, source | |
| top_warn_shown | profile/host warning bar shows (once per type per session) | type, missing_count | |
| top_warn_tapped | warning bar tapped | type, route | |
| offline_banner_shown / offline_banner_hidden | "No internet" strip | seconds_offline | |

`showHostProfile(context, host, source: …)` now takes a `source` (default `other`). Set here: discover, search, deeplink.
Callers outside this area still send `other`: callscreen/call/callback_sheet.dart, callscreen/history/history_actions.dart,
client/favourites/helper/favourites_actions.dart (could pass `callback`, `history`, `favourites`).

## Call screens, post-call and call history

### Call UI, post-call, safety, permissions, call log 

Helpers: `lib/core/analytics/events/call_ui_events.dart` (`CallUiEvents`). Call context params on most events
(from `callInfoOf(session)`): `call_id`, `call_type` (audio|video), `role` (caller|receiver), `host_id`, `phase`, `instant_call`.
Lifecycle events (call_initiated … call_failed) are in `CallAnalytics`, not here.

| event | when | params | Meta standard / Firebase recommended |
|---|---|---|---|
| call_mute_toggled | mic button on the call screen | call ctx, muted | |
| call_speaker_toggled | speaker button | call ctx, enabled | |
| call_camera_toggled | own camera on/off (video) | call ctx, enabled | |
| call_camera_flipped | flip camera (video) | call ctx, front | |
| call_hangup_tapped | red hang-up button (not system UI) | call ctx, elapsed_seconds | |
| call_minimized | header back during a live call | call ctx | |
| call_return_tapped | "return to call" bar on Home | call ctx | |
| call_video_swapped | small video tile tapped | call ctx, swapped | |
| call_capture_shielded | iOS screen recording/mirroring started, call hidden | — | |
| call_safety_panel_opened | header flag opens "Something wrong?" | call ctx | |
| call_safety_panel_closed | flag again or X | call ctx | |
| call_safety_confirm | block/report confirm answered | action (block\|report), source (incoming\|after_call), confirmed, call ctx | |
| call_safety_action | block/report done | action, source (in_call\|incoming\|after_call), outcome (done\|no_target\|failed), call ctx | |
| call_accept_tapped | in-app Accept on the incoming screen | call ctx | |
| call_decline_tapped | in-app Decline | call ctx | |
| incoming_safety_tapped | "Block/Report this caller" row tapped | call ctx, action | |
| call_attempt | user starts a call (flow level, after profile checks) | call_type, source (host_profile\|callback), host_id, rate_per_min | |
| call_initiate_failed | no call started | reason (missing_participants\|permission_denied\|host_busy\|insufficient_balance\|host_offline\|blocked\|network\|api_error\|call_in_progress\|exception), call_type, source, host_id, error | |
| instant_call_requested | Talk Now tapped (flow) | call_type | |
| instant_call_failed | Talk Now could not start | call_type, reason (as above), error | |
| instant_call_host_assigned | ring moved to next host (cascade) | call_id, attempt | |
| instant_call_matched | a host answered | call_id, peer_id | |
| instant_call_no_host | server gave up (also tags CallAnalytics reason no_answer) | call_id, attempts | |
| instant_call_cancelled | caller hung up before an answer | call_id, attempts | |
| call_permission_requested | system mic(+camera) prompt answered | permission (mic\|mic_camera), result (granted\|denied\|blocked\|unknown), context (outgoing\|call\|system_accept) | |
| call_permission_alert | "permission needed" alert after refusal | permission, blocked, opened_settings | |
| call_permission_bar_shown | red/amber "mic is off" bar appears | permission, state, screen (call\|incoming) | |
| call_permission_bar_tapped | bar tapped | permission, state, result, screen | |
| call_permission_primed | hosts: mic+camera asked once after sign-in | mic, camera | |
| bluetooth_permission_result | Android 12+ BLUETOOTH_CONNECT answered | granted | |
| device_permission_needed | host on Xiaomi/Samsung/Oppo/OnePlus misses OEM permission | brand, missing, count | |
| device_permission_opened | "Enable permissions" → brand settings | brand | |
| device_permission_snoozed | "Don't show again" (24 h) | — | |
| call_summary_shown | ended screen | call ctx, next (feedback\|exit), connected, duration_seconds | |
| call_feedback_rating | star tapped on the rating sheet | call ctx, rating | |
| call_feedback_submitted | rating sent (success/failed) | call ctx, rating, has_comment, comment_length, result, error | Meta `fb_mobile_rate` (valueToSum = stars) on success |
| call_feedback_skipped | Skip / backdrop / back | call ctx, rating | |
| callback_shown | host nudge sheet shown | host_id, category | |
| callback_call_tapped | Voice/Video call-back | call_type, host_id, rate_per_min | |
| callback_profile_tapped | host card in the sheet | host_id | |
| callback_dismissed | X or backdrop | method (close\|backdrop), host_id | |
| call_history_loaded | page 1 shown (once per mount) | count, has_more | |
| call_history_empty | "No call history" shown | — | |
| call_history_load_failed | page 1 failed (retry shown) | error | |
| call_history_load_more | next page requested | count | |
| call_history_load_more_failed | next page failed | error | |
| call_history_refreshed | pull to refresh | result, error | |
| call_history_row_tapped | row tapped (opens host profile) | direction, outcome, call_type, peer_id | |
| call_history_profile_failed | "Unable to open profile" | error | |
| call_history_menu_opened | ⋮ menu | can_rate, is_host, peer_id | |
| call_history_menu_action | menu choice | action (rate\|profile\|report\|dismissed), peer_id | |
| call_report_reason_selected | report category chip | category_id | |
| call_report_submitted | report sent / failed | result, category_id, has_note, peer_id, error | |
| call_report_closed | report sheet closed with X | category_id | |
| call_review_rating | star tapped in "Rate this Call" | rating | |
| call_review_submitted | review saved / failed | result, rating, has_comment, host_id, call_id, error | Meta `fb_mobile_rate` on success |
| call_review_skipped | Skip or X | rating, has_comment | |
| host_nudge_sent | host NUDGE (ask client to call back) | result, client_id, error | |

Sheets / dialogs named (ScreenTracker): `call_feedback_sheet`, `callback_sheet`, `call_history_menu`,
`call_report_sheet`, `call_review_sheet`. In-page view: `call_safety_panel`.

## Host: onboarding funnel, hub, badge, availability

Helpers: `lib/core/analytics/events/host_events.dart` (`HostEvents`). Funnel tracker: `lib/app/hosthub/onboarding/helper/host_funnel.dart` (`HostFunnel`).
Common params: `mode` = `new` | `resume` | `edit` | `existing_host`; `source` = `become_host` | `host_hub` | `deeplink` | `?source=` query value; `step` = HostStep name; `step_number` = 1..12.

### "Become a Host" funnel (one event name per step → funnels in Firebase AND Meta)
Steps in order: intro(1), basic(2), interests(3), photos(4), voice(5), tagline(6), bio(7), rates(8), availability(9), preview(10), guidelines(11), submitted(12).

| event | when | params | Meta standard / Firebase recommended |
|---|---|---|---|
| host_onboarding_started | flow opened (once per open) | mode, start_step, step_number, source | |
| host_ob_<step>_viewed (×12) | step shown (first view on open + each real step change; no rebuild dupes) | step, step_number, mode, source | |
| host_ob_<step>_completed (×12) | Continue passed validation + handle check and moved on; intro = "Get started"; guidelines = application submitted (or existing host saved); submitted = "Explore" tapped | step, step_number, mode, source | |
| host_onboarding_step_back | Back to the previous step (not an exit) | step, step_number, mode | |
| host_onboarding_validation_failed | Continue / Save refused | step, issue (i18n key), mode | |
| host_handle_taken | handle already used (Continue on basic, or a profile save) | mode | |
| host_preview_edit_tapped | preview "Edit" link | section | |
| host_onboarding_submitted | application went in | category, topics_count, photos_count, has_voice_intro, audio_rate, video_rate, source | Meta `SubmitApplication` |
| expert_signup (RN) | same moment, once per user per install | category | |
| host_onboarding_submit_failed | submit API failed | error, failed_step | |
| host_onboarding_exited | screen left (any way) | last_step, step_number, completed, mode, source | |
| host_profile_section_saved | existing host: "Save changes" on a step, or `all` on the last step | step, mode | |
| host_profile_section_save_failed | that save failed | step, error | |
| specialization_selected (RN) | interests completed in new/resume flow, or interests saved by a host | expert_id, category_ids, category_names, categories_count, source (`onboarding`/`settings`) | |
| call_rates_updated (RN) | rates saved by a host (section or save-all) | expert_id, audio_rate, video_rate | |
| schedule_updated (RN) | availability saved by a host | expert_id, mode (online/offline/scheduled) | |

Sub-screens: each step is `host_onboarding_<step>` on the route it is open on (`ScreenTracker.setSubScreen`).

### Step details
| event | when | params |
|---|---|---|
| host_topic_toggled | interest chip tapped | topic (catalog value), selected, count |
| host_topics_cleared | "Clear" | count |
| location_autofill (owned by Me fork, shared helper) | basic step GPS fill | source=`host_onboarding`, trigger, result |
| host_photo_source_chosen | gallery / camera picked | origin |
| host_photo_pick_failed | picker error (permission / no camera) | origin |
| host_photo_added | photo picked | origin, count |
| host_photo_uploaded / host_photo_upload_failed | upload result | count / error |
| host_photo_retried, host_photo_removed, host_photo_made_primary | tile actions | removed: count |
| host_voice_record_started / host_voice_recorded | recording started / kept | recorded: seconds |
| host_voice_too_short | under the minimum | seconds |
| host_voice_record_failed | start or stop failed | stage |
| host_voice_permission_denied | mic refused | |
| host_voice_played / host_voice_play_failed | playback | recording (`new`/`saved`) |
| host_voice_discarded | new recording dropped | |
| host_voice_uploaded / host_voice_upload_failed | background upload | seconds / error |
| host_ai_enhance_used | AI enhance (button currently hidden) | field, result, error |
| host_ai_enhance_undone | "Undo" | field |
| host_suggestion_used | prompt suggestion "Use" | field, position |
| host_call_type_toggled | audio/video switch | call_type, enabled |
| host_earnings_viewed | "see what you earn" | audio_rate, video_rate |
| host_availability_mode_selected | mode switch in the availability step | mode |
| host_time_slot_saved | weekly slot added/edited | day, edited |
| host_guidelines_opened | guidelines sheet | |
| host_guidelines_agreed | agreement checkbox | agreed |

### Host hub / approval / moderation
| event | when | params |
|---|---|---|
| host_hub_item_tapped | Host Hub row | item (pro_details, expertise, schedule, rates, approval, verification) |
| host_approval_viewed | approval screen, once per status | status (pending/approved/live/rejected/not_sent), missing_count |
| host_approval_requested | send / send again | resend |
| host_approval_blocked_incomplete | sections missing | missing_count |
| host_approval_request_sent / _failed | result | result / error |
| host_approval_missing_tapped | a missing section | section |
| host_approval_explore_tapped | explore CTA | status |
| host_go_live_tapped / host_went_live / host_go_live_failed | go online after approval | error |
| host_review_card_tapped | ME tab review card CTA | status |
| host_moderation_banners_shown | moderation notices shown | count, kinds |
| host_moderation_messages_shown | messages card shown (per count) | count |
| host_moderation_messages_expanded | more / less | expanded |
| host_moderation_message_tapped | message action | action (link/fix) |

### Verification badge
| event | when | params | Meta / Firebase |
|---|---|---|---|
| badge_status_viewed | badge / status screen, per step | step, review | |
| badge_primary_tapped | bottom button | step, review | |
| badge_locked_viewed | not eligible yet | screen | |
| badge_fee_viewed | fee screen shown | amount | |
| badge_fee_pay_tapped | "Pay now" | amount | Meta `fb_mobile_initiated_checkout` (valueToSum), Firebase `begin_checkout` |
| badge_fee_checkout_opened | Razorpay opened | amount, order_id | |
| badge_fee_cancelled | closed without paying | amount, reason | |
| badge_fee_failed | gateway / API failure | amount, error | |
| badge_fee_paid | paid + confirmed, once per payment | amount, payment_id, order_id | Meta Purchase (`metaPurchase`), Firebase `purchase` {currency INR, value, transaction_id, item_name verification_badge} |
| badge_fee_pending | paid, confirmation pending | amount | |
| badge_fee_already_paid / badge_fee_waived / badge_fee_error | edge paths | error | |
| badge_form_step_saved | identity / social step saved | step | |
| badge_form_validation_failed | step refused | step, issue | |
| badge_form_back | back a step | step | |
| badge_doc_type_selected | doc type picked | doc_type | |
| badge_doc_uploaded / badge_doc_upload_failed | ID photo | side, error | |
| badge_influencer_toggled / badge_influencer_declined | influencer checkbox / confirm declined | enabled | |
| badge_form_submitted + verification_submitted (RN) | application submitted | influencer, platform / user_id, category | |
| badge_form_submit_failed | submit failed | error | |
Sub-screens: `verification_badge_form_identity`, `verification_badge_form_social`.

### QR, availability, ME tab host widgets
| event | when | params |
|---|---|---|
| host_qr_opened | /me/profile-qr | has_link |
| host_availability_sheet_opened | availability sheet | source (navbar_pill, …), current |
| host_status_changed | online / offline (timed) picked | status (online/offline/scheduled), duration (30m/1h/2h/till_9am/indefinite), source |
| host_status_saved / host_status_save_failed | server result | status, error |
| host_auto_back_online | offline timer ended | |
| host_working_hours_tapped | "my working hours" | |
| host_status_pill_tapped | dock pill | status |
| host_earnings_card_tapped | dashboard earnings card | |
| host_dashboard_referral_tapped | dashboard referral card | |
| host_unlock_promo_shown / host_unlock_promo_dismissed | one-time "Become a Host unlocked" row | |

### Sheets named (screen views)
host_photo_source_sheet, host_earnings_sheet, host_guidelines_sheet, host_state_picker_sheet, host_district_picker_sheet, host_language_picker_sheet, host_time_range_sheet, badge_doc_type_sheet, host_availability_sheet.

## Payments and wallet

### Payments (wallet, top-up, checkout, offers, transfer, payout account)

Helpers: `lib/core/analytics/events/payment_events.dart` (`PaymentEvents`). All events go to Firebase + Meta unless marked.
RN names kept: `wallet_opened`, `initiate_payment`, `payment_success`, `payment_failed`, `payment_abandoned`,
`checkout_failed_to_open`, `first_topup_offer_shown/tapped`, `abandon_offer_shown/accepted`.

| event | when | params | Meta standard / Firebase recommended |
|---|---|---|---|
| wallet_opened | every wallet balance load (open, pull-to-refresh, after a payment) — RN | user_id, balance | |
| wallet_action_tapped | balance card / header button | action (`add_money`/`transfer`/`bank`), balance | |
| wallet_refreshed | pull to refresh on the history | tab | |
| wallet_profile_incomplete | "complete your profile" alert answered | step (`add`/`pay`), result (`update_profile`/`cancel`) | |
| add_money_opened | Add Money screen opened | source (`wallet`/`prefill`/`first_topup_offer`/`abandon_offer`), prefill_amount, bonus_kind, bonus_percent, preset_count | |
| topup_bonus_shown | a bonus is previewed on the amount cards | kind (`first_topup`/`comeback`), percent | |
| add_money_amount_selected | amount card tapped | amount, kind (`preset`/`prefill`), action (`selected`/`deselected`), bonus_percent, position | |
| add_money_pay_tapped | "Proceed to pay" | amount, gst_percent, total, bonus | |
| add_money_closed | Add Money left without an order | selected_amount | |
| payment_order_created | backend created the order | amount, gateway (`razorpay`/`payu`), order_id | |
| payment_order_failed | order creation failed (alert) | amount, error | |
| initiate_payment | order made, checkout about to open — RN | amount, payment_method, order_id | Meta `fb_mobile_add_payment_info` + `fb_mobile_initiated_checkout` (valueToSum amount); Firebase `begin_checkout` {currency, value, transaction_id, item_category} + `add_payment_info` {currency, value, payment_type} |
| checkout_opened | a checkout UI opened | gateway (`razorpay_native`/`razorpay_web`/`payu_web`), amount, order_id | |
| payment_abandoned | person closed Razorpay unpaid — RN | order_id, amount, error_code, description | |
| checkout_failed_to_open | Razorpay never opened — RN | order_id, amount, error_code, description | |
| payment_external_wallet | Razorpay handed off to an external wallet app | order_id, amount, wallet | |
| payment_verification_result | backend verify answer | result (`success`/`pending`/`failed`/`error`), order_id, amount, error | |
| payment_success | top-up paid + verified, once per txn — RN | amount, payment_method, currency | Meta Purchase (`logPurchase`, INR) + Firebase `purchase` {currency, value, transaction_id, payment_type, item_category} — both once per txn |
| first_topup | the user's first successful top-up ever (once per install per user) | amount, payment_method, currency | |
| payment_pending | paid but not confirmed yet | order_id, amount, reason | |
| payment_failed | gateway / verification failure, once per txn — RN | reason, payment_method, amount | |
| web_checkout_opened | WebView checkout opened (also a `web_checkout` screen view) | kind (`razorpay`/`payu`) | |
| web_checkout_ended | WebView checkout closed | kind, result (`paid`/`failed`/`closed`/`polled_paid`/`polled_failed`), reason | |
| payment_status_shown | wallet result card shown | status (`success`/`pending`/`failure`), source (`wallet`), amount | |
| payment_status_closed | wallet result card closed | status, source | |
| payment_celebration_shown | success burst landed (coin + haptic) — any payment card | | |
| first_topup_offer_shown | first top-up sheet shown — RN | percent, suggested_amount | |
| first_topup_offer_option | amount picked inside that sheet | amount, percent | |
| first_topup_offer_tapped | sheet CTA — RN | percent, amount | |
| first_topup_offer_dismissed | sheet closed without choosing | percent | |
| abandon_offer_shown | exit-intent offer after a dismissed checkout — RN | order_id, amount, percent | |
| abandon_offer_accepted | offer accepted — RN | order_id, amount, percent | |
| abandon_offer_dismissed | offer declined | order_id, amount, percent | |
| transactions_tab_selected | history tab switched | tab (`all`/`cash`/`earnings`) | |
| transactions_load_more | next page requested | tab, page | |
| transactions_empty | a tab loaded empty (once per tab per wallet visit) | tab | |
| transactions_load_failed | a page failed | tab, page, error | |
| transaction_invoice_tapped | "Invoice" on a row | type (`topup`/`paid`/`received`/`walletTransfer`), result (`opened`/`shown_url`/`not_ready_<status>`/`failed`), error | |
| transfer_sheet_opened | earnings → cash sheet opened | source (`wallet`; null from the call balance gate), earnings, cash | |
| transfer_amount_preset | quick amount chip | percent (100 = Max) | |
| transfer_invalid | confirm refused locally | reason (`below_min`/`exceeds_earnings`), amount | |
| transfer_warning | "cash is call credit" confirm answered | result (`accepted`/`cancelled`), amount | |
| transfer_submitted | transfer sent | amount, gst_percent | |
| transfer_success | transfer done | amount | |
| transfer_failed | transfer failed | amount, error | |
| transfer_sheet_closed | sheet closed | result (`done`/`closed`) | |
| bank_sheet_opened | payout account sheet opened | state (`form`/`pending`/`verified`/`error`) | |
| bank_form_invalid | local validation stopped submit | fields (names only), count | |
| bank_details_submitted | form submitted | has_upi | |
| bank_details_saved | saved | has_upi | |
| bank_details_save_failed | save failed | error | |
| bank_doc_picked | a proof photo (passbook/cheque, PAN front, PAN back) chosen | doc, origin (`gallery`/`camera`), picked | |
| bank_doc_uploaded | proof photo uploaded | doc | |
| bank_doc_upload_failed | proof photo upload failed | doc, error | |
| bank_status_viewed | saved account status shown | status (`pending`/`verified`), has_upi | |
| bank_support_tapped | "contact support" to change the account | mail_opened | Meta `Contact` {topic: bank_account} |

Not applicable: the Add Money screen has no free-typed custom amount (cards only), so there is no "custom amount / invalid amount" event; Razorpay's success payload carries no method, so `payment_method` stays the gateway (`razorpay`/`payu`), as in RN.

#### Sheets / dialogs named (screen views)
`add_money_sheet`, `payment_status_dialog` (also used by the verification-badge fee), `transfer_sheet`, `bank_sheet`,
`first_topup_offer_sheet`, `abandon_offer_sheet`, `balance_gate_sheet`; in-page view `web_checkout` {kind}.

## Me tab, settings, profile pages and resources

Helpers: `lib/core/analytics/events/me_events.dart` (`MeEvents`, `PersonalInfoEvents`, `AccountListEvents`, `ReferralEvents`, `ResourceEvents`, `UiEvents`). All events go to Firebase + Meta via `Analytics.log` unless noted.

### ME tab & settings

| event | when | params | Meta standard / Firebase recommended |
|---|---|---|---|
| profile_open (RN) | every visit to the ME tab | user_id, is_expert, screen=`me` | |
| me_item_tapped | any row / card / chip on the ME tab or its ⋮ menu | item (`personal`, `qr`, `become_host`, `share`, `wallet`, `resources`, `professional_details`, `verification_badge_prompt`, `profile_qr`, `referral_activity`, `logout`…), section (`wallet`, `identity`, `hub`, `host_status`, `resources`, `menu_sheet`, `badge_chip`, `profile_preview`, `referral_card`) | |
| me_section_switched | host: Dashboard ⇄ Settings | section (`dashboard`/`settings`) | |
| me_refreshed | pull-to-refresh on ME | — | |
| me_avatar_tapped | avatar opens the photo preview | is_expert | |
| theme_changed | theme segment changed (+ user property `app_theme`) | theme (`system`/`light`/`dark`) | |
| language_changed | app language picked in Settings (+ user property `app_language`) | from, to (`en`/`hi`/`bn`/`mr`/`te`/`ta`/`gu`/`ur`/`kn`/`or`/`ml`/`pa`) | |
| own_profile_shared | own host profile link shared | source (`me_list`, `me_menu`, `profile_preview`, `resources`), host_id | Firebase `share` {method, content_type=`own_profile`, item_id} |
| own_profile_share_unavailable | share tapped, no link yet | source | |
| own_profile_link_copied | copy link in the photo preview | source | |
| become_host_tapped | "Become a Host" (ME list, ⋮ menu, resources) | source, eligible, missing_count | |
| become_host_locked_action | "fill Personal Info first" dialog answered | action (`fill_info`/`cancel`) | |
| logout_tapped | logout tapped | source (`me_menu`, `resources`) | |
| logout_confirmed / logout_cancelled | logout confirm dialog answered (⋮ menu has no confirm: tapped + confirmed together) | source | (`logout` itself: AnalyticsIdentity) |
| delete_account_tapped / _confirmed / _cancelled | Account privacy → Delete account | — | |

### Personal Info (`/me/personal-info`, screen view automatic)

| event | when | params | |
|---|---|---|---|
| personal_info_save_tapped | Save tapped | fields_changed (`name,email,…` names only), changed_count | |
| personal_info_invalid | validation stopped the save | issue (`name`, `emailMissing`, `emailInvalid`, `mobileMissing`, `mobileInvalid`, `state`, …) | |
| personal_info_saved | save succeeded | fields_changed, changed_count, first_completion | |
| personal_info_save_failed | save failed | error | |
| user_signup (RN) | first save that completes registration, once per user per install | category=`user` | |
| personal_info_left | back from the screen | unsaved_changes | |
| profile_photo_tapped / _updated / _cancelled / _failed | photo change flow | source=`gallery`; failed: stage (`pick`/`upload`), error | |
| location_autofill | auto fill on open or "Use current location" (also host onboarding's basic step, without source) | trigger (`auto`/`tap`), result (`filled`/`state_only`/`failed`), reason (`denied`, `deniedForever`, `serviceOff`, `unavailable`, `notFound`, `api`), source | |
| geo_picker_selected | a state / district picked | level (`state`/`district`), source (`personal_info`/`gst`) | |
| geo_picker_needs_state | district tapped before a state | source | |
| gender_selected | gender chip changed | gender | |

### GST, favourites, blocked users, host categories

| event | when | params | |
|---|---|---|---|
| gst_edit_toggled | Edit on a submitted GST record | editing | |
| gst_registration_set | registered toggle | registered | |
| gst_declaration_toggled | declaration checkbox | confirmed | |
| gst_document_picked | certificate / logo picker | document (`certificate`/`logo`), picked | |
| gst_save_tapped / gst_invalid / gst_saved / gst_save_failed | save flow (no GST number or business data) | registered / error_count / error | |
| favourites_viewed | favourites list loaded (once per visit) | count, empty | |
| favourite_opened | a favourite tapped (opens the host sheet) | host_id, position, source=`favourites` | |
| favourite_removed / favourite_remove_failed | trash on a favourite | host_id / error, source | |
| favourites_refreshed | header refresh | — | |
| blocked_users_viewed | blocked list loaded (once per visit) | count | |
| unblock_tapped / unblock_cancelled / user_unblocked / unblock_failed | unblock flow | user_id (+ error) | |
| category_toggled | host categories: a category picked / unpicked | category (id), selected, count | |
| category_searched | a search started (not per keystroke) | query_length | |
| specialization_selected (RN) | categories saved | expert_id, category_ids, category_names, categories_count, source=`categories` | |
| categories_none_picked / categories_save_failed | save without picks / failed | error | |

### Referral

| event | when | params | |
|---|---|---|---|
| referral_opened (RN) | referral dashboard first shown (once per visit) | referral_code, joined_count, share_count | |
| referral_shared (RN) | code / link shared (referral screen, ME invite card: Invite All, WhatsApp) | referral_code, share_method (`system_share`/`whatsapp`), source (`referral_screen`/`invite_card`) | Firebase `share` {method, content_type=`referral`, item_id} |
| referral_code_copied | COPY on the invite card | referral_code, source | |
| referral_code_unavailable | share with no code | source | |
| referral_refreshed | refresh / pull | — | |
| referral_invite_card_shown | ME "Invite & Earn" card shown (once per session) | referral_code | |

### Resources (profile menus, CMS pages, links, support, webview)

| event | when | params | |
|---|---|---|---|
| resource_item_tapped | any category-menu row | item (row id, e.g. `gst`, `support`, `logout`, `page-…`), action (`route`, `share`, `dropdown`, `logout`, `delete_account`), menu | |
| resource_dropdown_toggled | Account privacy dropdown | item, open | |
| page_load_failed | CMS page failed / missing slug | slug, error | |
| page_empty | CMS page with no content | slug | |
| page_refreshed | header refresh on a CMS page | slug | |
| support_fallback_shown | support page fell back to app-config contacts (once per session) | — | |
| support_contact_tapped | email / phone / WhatsApp on the support page | channel | Meta `Contact` {channel} |
| link_opened | a link in a CMS page or support contact | source (`cms_page`/`support`), scheme, domain (web only), opened | |
| webview_opened | `/webview` opened the page | result (`opened`/`failed`/`offline`/`invalid`), domain, mode (`in_app`/`external`) | |
| webview_retry | reload / retry | domain | |

### Shared components (app-wide)

| event | when | params | |
|---|---|---|---|
| share_sheet_result | every OS share sheet (AppShare) | content_type (`own_profile`, `referral`, `text`, …), result (`shared`/`dismissed`/`unavailable`/`copied`) | |
| qr_code_shown | profile QR dialog opened | source (when the caller passes it) | |
| image_preview_opened | photo preview opened | preview (name) | |
| image_preview_action | preview action | preview, action (`favorite`, `share`, `copy_link`, `qr`) | |
| dialog_action | EVERY CAlert dialog answered | dialog (screen name), action (`primary`/`secondary`/`dismissed`) | |
| error_alert_shown | every error alert (CAlert.error) | error (`Analytics.errorCode`) | |

### Sheets / dialogs named (screen views)
- `me_menu_sheet` (ME ⋮ menu)
- `geo_state_picker_sheet`, `geo_district_picker_sheet` (Personal Info + GST)
- `qr_code_sheet` (all callers)
- `image_preview` (default) / `own_profile_preview` (ME avatar); other callers can pass `analyticsName`
- every `CAlert` dialog: `alert_<title key>` (e.g. `alert_resources_logout_title`), `error_alert` for error alerts, `alert` for literal text; callers can pass `analyticsName`
- Pages are automatic: `personal_info`, `gst_details`, `favourites`, `blocked_users`, `referral`, `categories`, `category_menu`, `dynamic_page` (+slug), `about_app`, `support`, `webview` (+url).

### Not present in the app (nothing to track)
- Settings language switch (language only on the onboarding screen — fork A), notification toggles, rate-app row.
- Referral: no copy button and no tap on referred users on the referral screen (copy lives on the ME invite card).
