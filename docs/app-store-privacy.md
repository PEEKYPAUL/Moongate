# App Store submission - privacy answers and reviewer notes

Companion to `docs/privacy-policy.md`. This maps what the app actually does to
Apple's **App Privacy** questionnaire in App Store Connect, plus the **review
notes** to head off rejections. Grounded in a code audit (see
`diagnostics_service.dart`, `supabase_service.dart`, the Supabase functions, and
the dependency list - no analytics/ads/tracking SDKs are present).

## Key facts that shape the answers

- Sign-in is **anonymous** (a random UUID); no name/email/password.
- The **only** data sent off-device that contains device/network details is the
  **opt-in bug report** - nothing is transmitted unless the user taps Submit.
- There are **no analytics, advertising, or tracking SDKs**. Nothing is used to
  track across apps/sites → **no App Tracking Transparency prompt is required**,
  and "Used to Track You" is **No** for every data type.
- "Collect" (Apple's meaning) = transmitted off the device. On-device-only
  items (settings, app-lock PIN hash, biometrics, the QR camera, custom
  background image) are **not** "collected".

## App Privacy questionnaire - recommended answers

Mark these as **Collected**, **Linked to the user** (everything ties to the
anonymous account id), **Not used for tracking**:

| Data type (Apple category) | What it is | Purpose | When |
|---|---|---|---|
| Identifiers → User ID | the anonymous account UUID | App Functionality | always |
| Identifiers → Device ID | the iOS push (APNs) token | App Functionality (notifications) | only if notifications enabled |
| Contact Info → Email Address | the optional "contact" field in a bug report | App Functionality / Support | only if the user types one |
| User Content → Customer Support | the bug-report comment text | App Functionality / Support | only if a report is sent |
| Diagnostics → Other Diagnostic Data | device model/OS, app version, local network addresses, printer connection diagnostics in a bug report | App Functionality / Support | only if a report is sent |
| Other Data | printer names and their local addresses (setup + bug reports) | App Functionality | setup; and in a report |

Everything else → **Not Collected**: Health, Financial, Precise/Coarse
Location, Sensitive Info, Contacts, Browsing/Search History, Purchases, Usage
Data (no analytics), Audio, Photos, etc.

### Note on IP address
Apple's questionnaire has no explicit "IP address" type. Our providers
(Supabase/Cloudflare) log IPs **only** for security, abuse-prevention, and
operations. Data collected solely for those purposes is exempt from the
"collected" disclosure, so it is **not** declared as a collected data type - but
it **is** disclosed in the privacy policy (section 1.5) for transparency.

## Account deletion (Guideline 5.1.1(v)) - DECISION NEEDED

Apps that "support account creation" must offer in-app account/data deletion.
Moongate creates an **anonymous** backend account, which is a grey area, but
review can be strict. Today, data is removed by deleting printers + uninstalling
(the anonymous identity is then auto-cleaned after inactivity).

**Recommendation (low risk path):** add a simple in-app **"Delete my data"**
action that deletes the current anonymous user's records (printers, push tokens)
and clears the local session. It is a small, self-contained feature and removes
this as a possible rejection reason. Decide before submission.

## Reviewer notes (paste into App Review Information → Notes)

> Moongate is a self-hosted 3D-printer dashboard. It connects to the user's own
> Raspberry Pi running Klipper/Moonraker.
>
> - **Sign-in is anonymous** - no account, email, or password. An anonymous id
>   is created automatically so the user's own printers can be associated with
>   their install.
> - **Local Network** permission is used to discover (Bonjour/mDNS,
>   `_moongate._tcp`) and connect directly to the user's printer on their Wi-Fi.
>   Without it, only the remote (tunnel) path works.
> - **Camera** is used only to scan the pairing QR code.
> - **Notifications** are opt-in and report the user's own print status.
> - No analytics, advertising, or tracking. No data is sold or shared for third-
>   party purposes.
> - **Hardware note:** the app controls a physical Klipper/Moonraker 3D printer,
>   so it can't be fully exercised without one. A short screen recording showing
>   pairing (QR scan) and the live dashboard is provided here: [DEMO VIDEO URL].
>   The App Store screenshots also show the main flows. We're happy to provide
>   anything else the review needs.

> Privacy policy: https://peekypaul.github.io/Moongate/privacy-policy.html

## Review lessons

Things App Review has actually rejected, so they are not repeated.

- **Guideline 2.3.10, Accurate Metadata (0.9.67, 14 September 2026).** The
  "What's New" text named Android three times ("brings ... to Android too",
  "Android-only for now", "level with Android"). Apple's note: "Revise the app's
  What's New text to remove Android references." Never name Android, or any
  other platform, in the What's New, the description, the promotional text or
  the screenshots. Say "not available on iPhone yet" or "every phone in the
  house" instead. The fix was metadata only, on the same build: the edited
  What's New was accepted in place while the version sat in Waiting for Review,
  so no new build or upload was needed.

## Still to do before submission
- [x] **Privacy policy hosted** - live at https://peekypaul.github.io/Moongate/privacy-policy.html (GitHub Pages, master `/docs`).
- [x] **Policy placeholders filled** - controller = Moongate, contact = psychoshaft@live.co.uk, effective 26 June 2026.
- [x] **In-app "Delete my data"** - built + merged (#146); `delete-account` function deletes the anon user, cascades wipe the rest.
- [ ] Put the policy URL in **App Store Connect** (App Privacy → Privacy Policy URL) and link it from the README.
- [ ] Record a short **demo video** (pairing + dashboard) for the reviewer and drop its URL into the reviewer notes above (the app needs real hardware).
- [ ] Confirm the **retention periods** in the policy against the live cleanup cron.
- [ ] Deploy the Supabase functions (`register-push-token`, `send-push`, `delete-account`) + apply the push-token migration.
- [ ] Enrol the **$99 Apple Developer Program** (gates push delivery, TestFlight, and submission).
