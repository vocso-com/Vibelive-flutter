# Host onboarding training

Admin → Onboarding lets the team add extra steps to the host onboarding and short clips to its screens. This document describes how it works and what the app and the server agree on.

The app's own 13 onboarding steps are never changed by this feature. Their names, order, deep links, moderation fix links and analytics all stay the same. With training off, or with an app build that predates it, onboarding works exactly as before.

## What the admin sets up

The whole setup is stored as one JSON document in the `api::host-onboarding.host-onboarding-config` single type. `src/utils/host-onboarding.js` validates it on every save; if any field is wrong, nothing is saved and the page shows what to fix.

- **`enabled`**: the master switch.
- **`audience`**: who gets training. `company` means company accounts only (`public-user.is_company_account`), for testing; it is the default. `all` means everyone. The server enforces this: anyone outside the audience gets `enabled: false`, and their results are refused.
- **`existingHosts`** (default off): when on, hosts who already have a profile (approved, live or in review) also get the training, but it is never required for them. Their form shows the clips, and Host Hub on the ME tab shows a "Host training" card. In their full form, the steps show after the screen they are placed after, with "Skip for now". Nothing is asked before their Save.
- **`steps[]`**: training steps, shown full screen between the app's own steps.
  - **Fields every step has:**
    - `id`: stable. Results are kept against it.
    - `kind`: `video` or `quiz`.
    - `enabled`.
    - `title`, `subtitle`.
    - `after`: one of the app's own screens, from `intro` to `preview`. The default is `preview`, which means the step comes just before Guidelines, where the host submits.
    - Steps that share the same `after` appear in list order.
  - **Video step fields:**
    - `video {url, posterUrl, mediaId, durationSec}`: https links only.
    - `autoplay`, `startMuted`, `loop`, `allowSeek`.
    - `mustWatch`: Continue opens only once the video has played to the end.
    - `skippable` + `skipAfterSec`: a Skip button appears after that many seconds of playing. The app shows Skip only when watching is required; otherwise Continue already lets the host go on.
  - **Quiz step fields:**
    - `questions[]`, at most 30. Each has:
      - `text`;
      - `options[]`: 2 to 6 answers;
      - `correct[]`: more than one right answer means "select all that apply";
      - `marks`: 1 to 100, default 1;
      - `explanation`.
    - `passPercent`: the pass mark, as a percentage of the total marks.
    - `maxAttempts`: 0 means no limit. When the attempts run out without a pass, the host still goes on, and moderation shows "not passed". A host can never get stuck in onboarding.
    - `mustPass`: Continue opens only after a pass, or after the attempts run out.
    - `showResult`:
      - Off: the host sees only "answers submitted", and the team checks the result in moderation.
      - Turning it off also forces `mustPass` off, because a host cannot be required to pass a result they never see.
    - `showScore`: off means the host sees only passed or not passed, with no marks, score or percentage.
    - `showAnswers`: after submitting, the host sees the right answers and the explanations.
    - `shuffle`: questions and answers appear in a new order on each attempt.
- **`clips[]`**: short videos on any of the app's onboarding screens, `intro` to `guidelines`. Each clip has:
  - `screen`, `title`;
  - `video`;
  - `autoplay`, `startMuted` (default on), `loop`, `enabled`.
  - A screen can have up to 6 clips. The app shows them as a swipeable frame at the top of that screen's content. The frame scrolls with the page (it is never pinned over the form), and the host can hide it.

Saving fires the type's lifecycle, which sends `CONFIG_UPDATED` on the `app_config` topic with scope `host_onboarding`. Apps that are open then re-read the setup. The server keeps its own copy cached for 30 seconds.

## App API

Every route below answers only a signed-in app user. The Public role holds these actions through the `manualActions` list in `src/index.js`. Neither content type has core routes, and both are on the protected list there.

- **`GET /api/host-onboarding/config`** returns `{ enabled, version, steps, clips, progress }`.
  - Only enabled items are included.
  - Quiz answers are never included.
  - A question's `marks` is included only when the result and the marks are both shown.
  - `progress[stepId]` is `{ status, done, attempts, attemptsLeft, percent?, bestPercent? }`. The status and the numbers are hidden in the same way.
  - If anything fails, the route answers `enabled: false`, so onboarding goes on without training.
- **`POST /api/host-onboarding/steps/:id/watched`** takes `{ seconds, completed, skipped }`.
  - A must-watch video refuses a skip or an early continue with `MUST_WATCH`.
  - Once a video is recorded as watched, it never goes back to skipped.
- **`POST /api/host-onboarding/steps/:id/quiz`** takes `{ answers: { questionId: [optionId] } }`.
  - The server marks the attempt.
  - Once a host passes, they stay passed, and their best percentage is kept.
  - When no attempts are left, it answers `NO_ATTEMPTS_LEFT` (403).
  - The answer contains only what the host may see; see `hostResult()`.
- A step that has since been removed answers `STEP_NOT_FOUND` (404). The app then treats that step as done.

Results are stored one row per user per step in `api::host-onboarding.host-onboarding-result`. They are keyed by the user, because a host has no expert profile until they submit.

## The server never enforces training on submit

Older app builds don't have these steps. If the server required them, those hosts could not submit at all. Instead, moderation shows each host's training: Admin → Moderation → host drawer → "Onboarding training" lists each step with its result, the marks, and "See answers", which shows every answer and whether it was right. "Not done" can also mean the host used an older app version.

## Admin API (type: admin)

- `GET` and `POST /admin-pannel/onboarding/settings`: read and save the whole setup.
- `POST /admin-pannel/onboarding/upload`:
  - Videos: MP4, MOV or WEBM, up to 100 MB.
  - Images: PNG, JPG or WEBP, up to 5 MB.
  - Files go into the media library.
- `GET /admin-pannel/onboarding/hosts/:documentId/training`: one host's results, used by moderation.

## In the app (VibeLive-Flutter)

- **Who sees it:**
  - Hosts going through onboarding for the first time, within the audience.
  - Existing (approved or pending) hosts only when `existingHosts` is on. For them it is always optional: "Skip for now" hides the rest until the app restarts.
  - A section edit in Host Hub shows the clips (when `existingHosts` is on), never the steps.
- **When steps appear:**
  - Continue on a step opens the training placed after it that isn't done yet.
  - Before Submit, everything not yet done comes first. This covers drafts resumed past a step, links into the flow, and steps added later.
  - Backing out of training keeps the host on the step they were on.
- **Clips:** `HostStepWithClips` hands each step's frame to that step's own scroll (`HostStepHeader`, which `HostStepBody` reads), so the frame scrolls with the page. The Welcome screen has its own slot (`IntroStep.media`). A clip plays only while its screen is the current one, and pauses when the app is in the background or during a call.
- **Never blocking:** a setup that can't be read, a video that can't play, or a result that can't be saved never keeps the host from continuing.
- **Strings:** the `hosttraining` i18n namespace, in 9 languages.
- **Tests:** test/ui/host_training_test.dart.
- **Backend tests:** scripts/host-onboarding.test.js (`npm run test:host-onboarding`).
