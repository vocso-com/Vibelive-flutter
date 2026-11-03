# Deep links: opening any screen from the backend

Any screen in the app, and any step of host onboarding, can be opened by a link. The app handles three kinds:

- **A push notification** with a `deeplink` field. Tapping the notification opens the screen.
- **A screen link**, `vibecalling://<screen>?<params>`, for example in an in-app button, a WhatsApp message or an email.
- **A website link**, `https://vibelive.angrymamba.com/app/<screen>?<params>`. It opens the same screen as `vibecalling://<screen>`.

A link opens once the user is signed in and Home is on screen. If they are signed out, it waits until they log in. If a link is unknown, has a missing required parameter, or is host-only and the user is not a host, the app opens Home instead.

The list below is defined in `lib/app/authscreen/helper/campaign_links.dart`, which is the source of truth. Screen names must never be renamed, because live campaigns use them.

## Sending a link in a push

Put the link in the push's `data`. Pushes from the orchestrator already do this.

```json
{ "deeplink": "vibecalling://host-voice" }
```

- **Webview pushes** may carry the page in `url`, `webUrl` or `web_url` instead of in the link.
- **Internal routes:** `data.route: "/me/wallet"` opens an internal route as it is. Prefer the screen names below, which don't change when the app does.

## Screens

| Screen name (aliases) | Opens | Params | Who |
|---|---|---|---|
| `home` (`discover`) | Discover | `topic` (`cat`): a topic tab; `q` opens Search instead | all |
| `search` | Search | `q` | all |
| `history` | Call history tab | | all |
| `chats` (`messages`) | Chats tab (only while chat is on) | | all |
| `chat` | One chat (`/chat/:userId`) | `userid` **required**: the other person's public-user id | all |
| `profile` (`me`) | Profile tab | | all |
| `wallet` | Wallet | `amount` (`prefillAmount`): a pre-filled top-up | all |
| `expert-profile.php` (`expert-profile`, `expert`) | A host's profile, over Discover | `userid` **required** (`documentId`, `handler`) | all |
| `favourites` (`favorites`) | Favourites | | all |
| `referral` (`invite`) | Referral / invite | | all |
| `personal-info` | Personal info | | all |
| `categories` (`topics`, `interests`) | Topics picker | | all |
| `resources` (`category-menu`) | A Resources category | `id` **required** | all |
| `page` | A content page | `slug` **required**, `title` | all |
| `about` | About the app | | all |
| `support` | Support | | all |
| `gst-details` | GST details | | all |
| `blocked-users` | Blocked users | | all |
| `webview` | In-app browser | `url`, `title` | all |
| `login` | Login | | signed out |
| `become-host` (`become-a-host`, `host-onboarding`) | Become a Host: the onboarding for a client, the profile editor for a host | | all |
| `professional-account` | Professional details (old link; prefer `become-host`) | | all |
| `approval` | Approval status | | hosts |
| `expertise` | Expertise (topics) | | hosts |
| `schedule` | Schedule | | hosts |
| `call-rates` | Call rates | | hosts |
| `profile-qr` | Profile QR | | hosts |
| `online-status` (`go-online`, `availability-sheet`) | Home with the host's online / offline sheet open (a client just gets Home). Not the same as `host-availability`, which opens the onboarding Availability step | | all |
| `verification-badge` | Verification badge: the fee | | hosts |
| `verification-badge-info` (`badge`) | Verification badge: about it | | hosts |
| `verification-badge-form` (`badge-form`) | Verification badge: the form | | hosts |
| `verification-badge-status` (`badge-status`) | Verification badge: status | | hosts |

## Host onboarding steps

Each step has its own link. The same link works for everyone:

- **A client** gets the Become a Host flow, opened on that step.
- **An existing host** gets that step on its own, with "Save changes". For `host-preview` and `host-guidelines`, the host gets the flow opened on that step.

| Step | Link |
|---|---|
| Basic profile | `vibecalling://host-basic` |
| Interests | `vibecalling://host-interests` |
| Photos | `vibecalling://host-photos` |
| Voice intro | `vibecalling://host-voice` |
| Video intro (optional; rejected video intros link here) | `vibecalling://host-video` |
| Tagline | `vibecalling://host-tagline` |
| Bio | `vibecalling://host-bio` |
| Call rates | `vibecalling://host-rates` |
| Availability | `vibecalling://host-availability` |
| Preview | `vibecalling://host-preview` |
| Guidelines and submit | `vibecalling://host-guidelines` |

You can also write the step as a parameter: `vibecalling://host-step?step=voice`.

## Examples

```
vibecalling://wallet?amount=199                          Wallet, ₹199 top-up ready
vibecalling://expert-profile?userid=a0wrx21u87k5nbhbf73my94k
vibecalling://home?topic=dating-advice                   Discover on a topic
vibecalling://chat?userid=2143                           the chat with user 2143
vibecalling://host-voice                                 "Add your voice intro"
https://vibelive.angrymamba.com/app/host-voice           the same, as a website link
https://vibelive.angrymamba.com/app/wallet?amount=199
```

## Website links (`/app/...`)

- **Screens live under `/app/`.** A bare `https://vibelive.angrymamba.com/<word>` stays a host's share link, because a host's handle can be any word.
- **Android** opens every path on the domain in the app.
- **iOS** opens only the paths listed in the website's `apple-app-site-association` file. `/app/*` must be added there.

## Messages from the moderation team

The moderation thread in the admin panel (Host review drawer) can link a note to any screen above. The list is the notification composer's own presets (orchestrator Settings), so the two always offer the same screens.

- **The push** opens the linked screen. A note with no link opens the profile editor, as before.
- **The app** also lists the messages on the ME tab ("Messages from the moderation team", `GET /api/me/moderation-notes`). Each message has an **Open** button for its link. A rejection without a link gets **Fix it**, which opens the step to fix.
- **Rejections say what was wrong.** The moderator ticks the text fields (`name`, `handler`, `tagline`, `descriptions`). The push opens the first field's step. In the app, that step shows the team's note at the top, and each named field has a red outline until it is edited.
- **A rejected photo** sends a push to `host-photos`. In the app, that photo gets a red "Not approved" badge, and photos waiting for review show "In review".
- **A rejected voice intro** sends a push to `host-voice`. The Voice step asks the host to record again until they do.

`test/auth/link_parser_test.dart` checks that every backend preset opens a screen.
