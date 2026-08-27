# Push notifications, working plan

Status: DRAFT for review (2026-06-26). Goal: real background notifications on iPhone (and a cleaner mechanism on Android), with **everything we run living in Supabase**, no extra backend platforms. Grounded in how the app, the cloud functions, and the Klipper plugin already work today.

## The plain-English version

Today the phone does the watching: the app quietly keeps itself awake and polls each printer every few seconds for hours. Android allows that; iOS does not, which is why there are no background alerts on iPhone. (Since v0.9.61 that Android watcher also raises the same loud event alerts locally - paused, failed and machine errors with their reasons - so both platforms hear about the same moments; only the delivery differs.)

The iPhone-correct model flips it around. Instead of the phone watching, the **printer tells our Supabase backend when something happens**, and Supabase asks Apple (or Google) to deliver an alert straight to the phone. The phone does not need to be awake or have the app open.

The path is:

```
Pi (Moongate plugin)  →  Supabase function (the one backend we run)  →  Apple / Google  →  phone
```

The tunnel is not involved. The tunnel is only for the phone to reach the printer for live view. Notifications ride on the connection the Pi already makes to Supabase.

## Design principle: one backend

We run exactly **one** backend: Supabase. No Firebase, no second server, no separate notification service.

- **Apple and Google are not servers we run.** They are free delivery endpoints, the only way any app on those phones can receive a background alert. Our Supabase function calls them as the final hop. We never operate or pay for them.
- The only non-Supabase artefacts are **two one-time keys** (an Apple push key, a Google sender credential) that we paste into Supabase's secret store and then forget about. Setup, not ongoing management.

So the whole system, the trigger logic aside (which lives in the plugin we already ship), is the plugin plus Supabase. Nothing else to keep track of.

## Why the cost is fine

The current Supabase cost is driven by things that happen every few seconds (heartbeats, and one orphaned Pi spinning). Push notifications fire only on **real events**: a print starts, finishes, fails (with the reason since plugin 0.6.25), or pauses; the machine errors out or shuts down; or a user macro calls `MOONGATE_NOTIFY`. A handful per print job, not a constant stream - and the custom macro path is rate-limited on the Pi to one send per 10 seconds.

- New database writes: a tiny table of phone addresses, one row per device, updated rarely.
- New function calls: a few per print job.
- Apple/Google delivery: free, unlimited at our scale.

So no new recurring bill. The only money anywhere is the $99/yr Apple membership, which is required to be on the App Store regardless of notifications. If Supabase volume ever grows enough to need a paid tier, Paul is fine upgrading, but notifications are not what would push it there (the orphaned-Pi heartbeat churn is the real driver, already being addressed by the v0.9.33 back-off).

## The pieces

Four small pieces, all either already ours or living in Supabase.

### 1. The phone app (shared Android + iPhone Dart code)
- Ask the OS for permission to send notifications, then get this device's "address": an APNs token on iPhone, an FCM token on Android.
- Save that token to a new Supabase table, tied to the user's existing anonymous account.
- Show the alert when it arrives; tapping it deep-links to the right printer.
- iOS only: enable the "Push Notifications" capability in Xcode (needs the paid Apple account, see sequencing).

### 2. A new Supabase table: `device_push_tokens`
- Columns: `user_id` (the anon UID we already issue), `token`, `platform` (ios/android), `updated_at`.
- Row-level security: a device may only write its own token. Same posture as the rest of the schema (`docs/security.md`).
- Tiny and event-rare, so negligible cost.

### 3. A new Supabase function: `send-push`
- Lives alongside the existing functions (`printer-heartbeat`, `printer-access`, ...). Same Deno pattern, reuses `_shared`.
- Receives a **Pi-signed** "event for printer X" call (the same Ed25519 signature the plugin already uses for heartbeats, so no new auth model and no secrets on the Pi).
- Looks up who owns printer X, finds that user's device tokens, and sends the alert **directly**:
  - iPhone tokens → Apple's APNs HTTP/2 endpoint, authenticated with our Apple push key.
  - Android tokens → Google's FCM HTTP endpoint, authenticated with our Google sender credential.
- Both keys live only as Supabase function secrets, exactly like today's server-side keys (`service_role`, the JWT signing key, the tunnel-URL key). Nothing sensitive reaches the Pi or the app.

### 4. The Klipper plugin watcher (`klipper-plugin/moongate_standalone.py`)
- Today the plugin only sends a keep-alive heartbeat every 5 minutes, too slow and too coarse for timely alerts.
- Add a lightweight **state watcher** that notices Moonraker print-state transitions locally (the plugin already runs inside Moonraker, so this is cheap and immediate) and, on a meaningful change, calls `send-push`.
- Meaningful changes only, to avoid noise: **print started**, **print finished**, **print failed / error**, **paused** (optional). Mirrors the alert set the in-app notifier already uses (`print_notification_service.dart`: Printing / Ready / Error / Paused / ...).

## The Apple account dependency, and how we sequence around it

Sending to iPhones needs an **Apple push key**, which requires the **paid ($99/yr) Apple Developer account**. Paul has not paid yet. That does **not** block most of this work, because **Android push is free** and exercises the entire pipeline.

So we build and prove it on Android first, then add the short iOS leg once the account is active.

### Phase A, build the whole pipeline on Android (no Apple account needed)
1. Create the free Google sender credential; store it in Supabase secrets.
2. App: request permission, get the FCM token, store it in the new table.
3. Add the `device_push_tokens` table + migration + RLS.
4. Write the `send-push` function (Pi-signed in, direct to Google out).
5. Add the plugin state-watcher that calls `send-push` on start/finish/fail.
6. Test end to end on the Samsung: start a print, lock the phone, confirm alerts arrive. This already gives Android a better notification path.

### Phase B, add iOS (needs the $99 account)
7. Pay and enrol; create the Apple push key; store it in Supabase secrets.
8. Enable the Push Notifications capability in Xcode; handle the APNs token on the app side.
9. Test the same events on the real iPhone 14 Pro (dev build, or TestFlight once enrolled).

### Phase C, release
10. Ship iOS to the App Store with notifications working, alongside the Android update. Parity launch, as planned in `docs/ios-port-plan.md`.

The key point: **we can build everything, and confirm the design and the cost, before spending a penny.** The $99 only gates the final iOS test.

## Bonus: this fixes the Android always-on notification (#126)

Android's current live notification relies on a foreground service that can feel unkillable (issue #126). Once alerts come from Supabase, the app no longer needs to keep itself awake polling. We can then let the watcher **sleep when idle** and lean on push for state changes, which both fixes #126 and trims polling load. A follow-on once Phase A is solid, not a day-one requirement.

## Security notes
- The Pi authenticates to `send-push` with its existing Ed25519 key. No new secret on the Pi.
- The Apple and Google sending keys live only as Supabase function secrets (`docs/security.md`).
- The token table is RLS-locked to its owner. A leaked token can receive its own alerts only; it cannot read printers or send pushes.
- No personal data in the push payload beyond printer name and state.

## Open decisions for Paul
1. **Retire the Android foreground service** once push works (the #126 fix), or keep it for live-while-open progress? Recommend: keep live progress while the app is open, move *background state alerts* to push.
2. **Event set:** start / finish / fail for v1. Add paused, heating-done, offline later if wanted.
3. **Timing:** build Phase A now (free), pay the $99 and do Phase B only when Phase A is proven. Hold the iOS public release until B passes on the real iPhone.

(Resolved: no Firebase, no extra backend. Everything we run is Supabase, sending directly to Apple and Google.)

## Rough effort
- Phase A: about a week of focused work across app, function, table, and plugin, plus testing.
- Phase B: a day or two once the account and push key exist.
- Phase C: folds into the normal release.
