# Moongate Privacy Policy

**Effective date:** 26 June 2026
**Last updated:** 26 June 2026

Moongate ("the app", "we", "us") is a free, source-available app for monitoring and
controlling your own Klipper/Moonraker 3D printers from your phone. This policy
explains exactly what data the app handles, why, where it goes, and your
choices. It is written to be accurate to what the app actually does - nothing
more is collected than is described here.

**Data controller:** Moongate
**Contact:** psychoshaft@live.co.uk

---

## The short version

- We do **not** show ads, and we do **not** use any analytics, advertising, or
  tracking SDKs. The app does not track you across other apps or websites.
- We do **not** sell, rent, or share your personal data with anyone for their
  own purposes.
- You sign in **anonymously**. We never ask for your name, email, or a password
  to use the app.
- Most of what the app does happens **directly between your phone and your own
  printer** (over your local network or an encrypted tunnel). Our servers broker
  the connection; they are not in the path of your camera feed or print files in
  a way that stores them.
- The only time we receive details about your device or network is if **you
  choose to send a bug report**.

---

## 1. Information the app handles

### 1.1 Anonymous account identifier
To remember which printers are yours, the app signs you in **anonymously** with
our backend (Supabase) the first time it launches. This creates a random
identifier (a UUID). It contains **no** name, email, phone number, or password,
and it is not linked to your real-world identity. The session is stored securely
on your device (iOS Keychain / Android Keystore).

### 1.2 Printer setup data
When you pair a printer, we store, associated with your anonymous identifier:
- a **printer name** you choose;
- the printer's (Raspberry Pi's) **public key**, used to verify it;
- the printer's current remote-access (Cloudflare tunnel) URL, stored
  **encrypted**;
- a "last seen" timestamp.

This is the minimum needed to reconnect you to your own printers from anywhere.

### 1.3 Bug reports (only if you choose to send one)
The app has an optional "Report a problem" feature. **Nothing is sent unless you
tap to submit a report.** If you do, the report includes:
- the **comment** you write, and any **contact detail you choose to add** (for
  example an email, so we can reply - this is optional and entirely up to you);
- your **device model and operating-system version**, and the **app version**;
- your phone's **local (private) network addresses** and whether you appear to
  be on a private network - used to diagnose connection problems;
- your **printer names and their local addresses**, the results of local
  printer discovery, and connection status;
- your **anonymous identifier** (to correlate the report with your printer
  records).

This information exists to make pairing and connection failures diagnosable. It
is sent to our backend and stored so we can investigate the issue.

### 1.4 Push notification token (iOS, if you enable notifications)
If you turn on print notifications on iOS, your device registers with Apple and
we store the resulting **push token**, associated with your anonymous
identifier, so our backend can send you alerts when a print starts, finishes, or
fails. The token is a delivery address for your device; it is not your identity.

### 1.5 Automatically logged technical data
Like most internet services, our backend providers (Supabase and Cloudflare)
automatically record standard technical request logs - including your device's
**IP address** - for security, abuse prevention, and operational reliability.
These logs are short-lived and are not used to build a profile of you or to
track you across other services.

### 1.6 Information that never leaves your device
The following are kept **only on your device** and are never transmitted to us:
- your **app-lock PIN** (stored only as a salted hash) and biometric unlock
  (Face ID / Touch ID / fingerprint is handled entirely by your operating
  system; we never see your biometric data);
- your **settings** (theme, layout, language, poll interval, and similar) and
  any **custom dashboard background image** you pick;
- the **camera**, which is used only to scan a pairing QR code; images are
  processed on-device and not stored or transmitted.

## 2. How your printer data flows

Moongate is a "middleman" for remote access, not a data warehouse:
- On your **local network**, the app talks **directly** to your printer.
- **Remotely**, the app reaches your printer through a **Cloudflare tunnel** the
  printer itself opens. Our backend's role is to hand your app the current
  (encrypted) tunnel address and a short-lived access token; the actual printer
  status, **webcam feed, and print files travel between your phone and your
  printer**, not into our storage.

## 3. Who processes data on our behalf

We rely on a small number of service providers. We do not sell data to anyone,
and none of these are advertising or data-broker services:

- **Supabase** - our backend: anonymous sign-in, the database of your printers,
  bug reports, and push tokens, and the server functions that broker access.
- **Cloudflare** - provides the secure tunnel that carries traffic between your
  phone and your printer for remote access.
- **Apple Push Notification service** - delivers print notifications to your
  iPhone (only if you enable notifications). The notification content is limited
  to your printer's name and print status.
- **GitHub** - on the **Android early-access (APK) build only**, the app fetches
  a small file to check whether a newer version is available; this reveals your
  device's IP address to GitHub as part of an ordinary web request. (The Google
  Play and App Store builds update through their store and never perform this
  check.)

These providers may process and store data on servers located in other
countries, including outside your own. Where this involves transferring personal
data internationally, it is done under the providers' own data-protection
safeguards.

## 4. Permissions we request and why

- **Camera** - to scan the pairing QR code. Nothing else.
- **Local network** (iOS) - to discover and connect directly to printers on your
  Wi-Fi.
- **Notifications** (iOS) - only if you opt in to print notifications.
- **Face ID / Touch ID / biometrics** - only if you turn on the optional app
  lock; authentication is performed by your operating system.

## 5. How long we keep data

- **Printer records** are deleted automatically after about six weeks without
  activity (no contact from the printer).
- **Unpaired/removed printers** are permanently deleted shortly after removal
  (within about a week).
- **The anonymous identifier** itself holds no personal data (it is just a random
  id). It may persist after your printers are gone, but you can erase it and
  everything tied to it at any time with **"Delete my data"** in the app.
- **Bug reports** are retained so we can investigate and track issues; tell us
  (using the contact above) if you want a report you submitted deleted.
- **Local data** on your device remains until you delete it or uninstall the app.

## 6. Your choices and rights

Because we don't collect your name or email, most data is tied only to an
anonymous identifier. You can:
- **Delete everything** with **"Delete my data"** in the app's menu - this
  immediately erases your anonymous account and removes your printers,
  notification tokens, and related records from our servers.
- **Stop remote data** by removing individual printers; uninstalling the app
  removes the local session, and your printer records are then deleted after the
  inactivity period above.
- **Disable notifications** at any time in the app's menu.
- **Decline or revoke permissions** (camera, local network, notifications) in
  your device settings; some features will simply stop working.

Depending on where you live (for example under the EU/UK GDPR or California's
CCPA), you may have rights to access, correct, or delete personal data and to
object to processing. Because submitted bug reports are the main place free-text
or contact details might appear, contact us at the address above to exercise
these rights and we will act on requests we can verify.

## 7. Children

Moongate is a tool for operating 3D-printing hardware and is not directed to
children. We do not knowingly collect personal data from children.

## 8. Security

- All client access is scoped by database row-level security so you can only
  reach your own records.
- The printer's remote-access URL is stored **encrypted**, and printers
  authenticate to the backend with a per-device cryptographic key.
- Your session and app-lock secret are held in your device's secure storage.
- The app's source is public, so these claims can be independently verified.

## 9. Changes to this policy

If we change what data the app handles, we will update this policy and its
effective date. Material changes will be noted in the app's release notes.

## 10. Contact

Questions or requests about this policy or your data:
psychoshaft@live.co.uk
