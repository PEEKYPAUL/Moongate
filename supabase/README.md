# Moongate v0.3.0 — Supabase Setup

This directory contains everything needed to set up the Supabase side of v0.3.0.
Design rationale: see [`docs/v0.3-supabase-design.md`](../docs/v0.3-supabase-design.md).

> **All work is local-only until smoke test passes.** Do not push this branch
> to GitHub. Do not deploy these Edge Functions to a production project that
> v0.2.x users depend on.

---

## What you'll do in Phase 1

1. Confirm or create a Supabase project
2. Apply `migrations/20260526120000_v03_initial.sql` (schema + RLS + cron)
3. Generate a master encryption key and set it in the Edge Functions environment
4. Run verification queries to confirm RLS isolates users
5. Dry-run the cleanup cron function

Phase 2 (Edge Functions) is a separate task and lives at `supabase/functions/`
once we get there.

---

## 1. Supabase project

You said you have a Supabase account linked via GitHub. Open
<https://supabase.com/dashboard/projects> and either:

- **Use an existing project** that's safe to dedicate to Moongate v0.3.0, or
- **Create a new one**: "New Project" → name it `moongate-v03` → choose a
  region close to you → wait ~2 min for provisioning

Once it's ready, copy these from `Project Settings → API`:

- **Project URL** — e.g. `https://abc123xyz.supabase.co`
- **`anon` public key** — safe to embed in the Flutter APK
- **`service_role` key** — **never** put in the APK; Edge Functions only

You'll also need the **project ref** (the `abc123xyz` part from the URL) for
the CLI flow below.

---

## 2. Apply the migration

You have two options. Pick one — they do the same thing.

### Option A — Supabase CLI (recommended if you'll iterate)

```powershell
# install once (if you don't have it)
scoop install supabase   # or: choco install supabase, or npm i -g supabase

# from C:\dev\Moongate
supabase login
supabase link --project-ref <your-project-ref>
supabase db push
```

`supabase db push` reads `supabase/migrations/` and applies anything new.
Re-running is safe — the migration is idempotent.

### Option B — Paste into the SQL Editor (zero setup)

1. Open your project's **SQL Editor** in the Supabase dashboard
2. Open `supabase/migrations/20260526120000_v03_initial.sql` in any editor
3. Copy the entire file contents
4. Paste into a new SQL query in the dashboard
5. Click **Run**

You should see `Success. No rows returned.` once.

---

## 3. Verify the migration

In the SQL Editor (or `supabase db remote query "..."`), run each block.

### 3.1 Tables exist

```sql
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('printers', 'enrollment_tokens');
```

Expect two rows.

### 3.2 RLS is on

```sql
SELECT relname, relrowsecurity, relforcerowsecurity
FROM pg_class
WHERE relname IN ('printers', 'enrollment_tokens');
```

Both rows should show `relrowsecurity = t`.

### 3.3 Cron job scheduled

```sql
SELECT jobname, schedule, active
FROM cron.job
WHERE jobname = 'moongate-cleanup-inactive';
```

Should show `15 3 * * *`, `active = t`.

### 3.4 Cleanup function dry-run

```sql
SET client_min_messages = NOTICE;
SELECT public.moongate_cleanup_inactive();
```

You should see `NOTICE: moongate_cleanup: 0 stale, 0 revoked, 0 tokens` in
the output (empty tables, nothing to clean).

---

## 4. Generate and set the master encryption key

The Edge Functions will encrypt every tunnel URL before writing it to the
`printers` table. The key for that AES-256-GCM operation is **never** in
the database, **never** in the APK, **never** in git. It lives only in the
Edge Functions environment as `MOONGATE_TUNNEL_URL_KEY`.

### 4.1 Generate locally

From PowerShell:

```powershell
cd C:\dev\Moongate
.\supabase\scripts\generate-master-key.ps1
```

This prints a base64-encoded 32-byte random key to the console. **Treat it
like a password.** Save it to your password manager.

> If you regenerate the key after the system is live, every existing
> `tunnel_url_enc` row becomes unreadable. Don't rotate casually.

### 4.2 Set it in Supabase

Dashboard → **Edge Functions** → **Manage secrets** → add:

| Key | Value |
|---|---|
| `MOONGATE_TUNNEL_URL_KEY` | (the base64 string from step 4.1) |

Save.

---

## 5. Verifying RLS isolates users (cross-tenant test)

This is the most important verification — it proves the architectural
guarantee that Bob can never see Alice's printers.

Run this in the SQL Editor (it uses the service role under the hood, so we
have to temporarily impersonate anon users):

```sql
-- Create two anonymous users (mimics two app installs)
SELECT auth.uid() AS before;   -- shows whoever you're logged in as

-- Create two fake users via the admin path. In production these come from
-- supabase.auth.signInAnonymously() on the phones.
-- (We can't easily fake auth.uid() from the SQL Editor, so the real test
-- is run via the Phase 4 app or curl in Phase 2. The query below at least
-- confirms the policy exists.)

SELECT polname, polcmd, pg_get_expr(polqual, polrelid) AS using_expr
FROM pg_policy
WHERE polrelid = 'public.printers'::regclass;
```

Expect one row: `select own printers`, `SELECT`,
`((owner_user_id = auth.uid()) AND (revoked_at IS NULL))`.

**Full cross-tenant test happens in Phase 2 with curl** — once `/claim` is
deployed, we'll register two printers under two different anon users and
confirm each session only sees its own.

---

## 6. What to do when this all passes

Update `docs/v0.3-supabase-design.md` §14 with any decisions you made along
the way (project ref, key creation date, etc. — though **not the key value**).

Then it's time for Phase 2: Edge Functions (next section).

---

## Phase 2 — Edge Functions

This phase deploys the five Edge Functions that mediate everything between
the app, the Pi, and Postgres.

| Function | Caller | JWT required? |
|---|---|---|
| `enroll-prepare`   | Pi  | No (function does its own checks) |
| `printer-claim`    | App | Yes (anon Supabase JWT)            |
| `printer-access`   | App | Yes (anon Supabase JWT)            |
| `printer-heartbeat`| Pi  | No (Ed25519 signature on payload)  |
| `jwks`             | Pi  | No (intentionally public)          |

Source lives at `supabase/functions/`. Shared helpers in `_shared/`.

### Phase 2.1 — Apply the RPC helpers migration

A second migration adds Postgres RPC functions that the Edge Functions call.
This keeps `bytea` encoding inside SQL and concentrates business logic
near the data.

- Open Supabase dashboard → **SQL Editor** → **New query**
- Paste the contents of `supabase/migrations/20260526120001_rpc_helpers.sql`
- Click **Run**
- Expect `Success. No rows returned.`

Verify:
```sql
SELECT proname
FROM pg_proc
WHERE proname IN ('upsert_enrollment_token', 'claim_printer',
                  'get_printer_access', 'record_heartbeat')
ORDER BY proname;
```
Expect four rows.

### Phase 2.2 — Generate the JWT signing key

The Edge Functions sign short-lived access tokens with **EdDSA (Ed25519)**.
The private key lives only in Supabase secrets. The public key is exposed
via the `/jwks` Edge Function so the Pi can fetch it.

From a PowerShell window:

```powershell
cd C:\dev\Moongate
node .\supabase\scripts\generate-jwt-signing-key.js
```

This prints a JSON Web Key (JWK) for the private key. **Treat it as a
secret.** Save it in your password manager.

> Rotating this key invalidates every in-flight access token. The app
> simply requests a new token, so user-visible impact is small, but don't
> rotate casually.

### Phase 2.3 — Set the signing key as a secret

Supabase dashboard → **Edge Functions** → **Manage secrets** → add:

| Name | Value |
|---|---|
| `MOONGATE_JWT_SIGNING_KEY` | (the entire JWK JSON string from Phase 2.2) |

Click **Save**. You now have two Edge Function secrets:
- `MOONGATE_TUNNEL_URL_KEY` (from Phase 1)
- `MOONGATE_JWT_SIGNING_KEY` (just added)

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are
auto-populated by Supabase — you do NOT add those.

### Phase 2.4 — Log in to the Supabase CLI

```powershell
supabase login
```

A browser window opens. Sign in to Supabase. The CLI stores a token at
`~/.supabase/access-token` (or similar) for subsequent commands.

### Phase 2.5 — Get your project ref

Open your project in the dashboard. The URL looks like:

    https://supabase.com/dashboard/project/abcxyz123/...

The `abcxyz123` part is your **project ref**. Tell Claude what it is.

### Phase 2.6 — Deploy (handled by Claude)

With the CLI logged in and the project ref known, Claude runs:

```powershell
supabase functions deploy enroll-prepare    --project-ref <ref> --no-verify-jwt
supabase functions deploy printer-claim     --project-ref <ref>
supabase functions deploy printer-access    --project-ref <ref>
supabase functions deploy printer-heartbeat --project-ref <ref> --no-verify-jwt
supabase functions deploy jwks              --project-ref <ref> --no-verify-jwt
```

`--no-verify-jwt` disables Supabase's automatic gateway JWT check for the
endpoints that handle their own auth (Pi-signed payloads or public JWKS).
`printer-claim` and `printer-access` keep the gateway check on for
defence-in-depth even though they also re-verify the JWT internally.

### Phase 2.7 — Smoke tests (curl)

After deploy, we run a few curl tests from Claude's side to confirm each
function responds correctly. The full sequence (Claude will execute):

```powershell
# Replace <PROJECT_REF> and <ANON_KEY> with your values.
$BASE  = "https://<PROJECT_REF>.supabase.co/functions/v1"
$ANON  = "<ANON_KEY>"

# 1. jwks should return our public key
Invoke-RestMethod "$BASE/jwks"

# 2. enroll-prepare with bad input → 400
Invoke-RestMethod -Method POST -Uri "$BASE/enroll-prepare" `
    -Headers @{ apikey = $ANON } `
    -Body '{}' -ContentType 'application/json'

# 3. enroll-prepare with valid bogus pubkey → 200 (registers a token hash)
$pubkey = [Convert]::ToBase64String((1..32 | ForEach-Object { [byte]0 }))
$hash   = [Convert]::ToBase64String((1..32 | ForEach-Object { [byte]0 }))
Invoke-RestMethod -Method POST -Uri "$BASE/enroll-prepare" `
    -Headers @{ apikey = $ANON } `
    -Body (@{ pi_public_key=$pubkey; token_hash=$hash } | ConvertTo-Json) `
    -ContentType 'application/json'

# 4. printer-claim without JWT → 401
Invoke-RestMethod -Method POST -Uri "$BASE/printer-claim" `
    -Headers @{ apikey = $ANON } `
    -Body '{}' -ContentType 'application/json'
```

Claude will run these and confirm Phase 2 is done.

---

## Troubleshooting

**`ERROR: extension "pg_cron" is not available`**
→ pg_cron requires Pro tier on some Supabase plan generations. Free tier
usually has it, but if your project doesn't, you can either upgrade or
move the cleanup job to a GitHub Action that calls a `/cleanup` Edge
Function on a schedule. Tell me and I'll write the fallback.

**`ERROR: permission denied for schema cron`**
→ The migration is being applied by a role without `cron` schema access.
Use `supabase db push` (which uses the migration role) or paste into the
SQL Editor as the project owner.

**`ERROR: column "tunnel_url_enc" violates not-null constraint`**
→ You're applying an older revision of the migration. Pull the latest
file and re-apply — the current schema makes those columns nullable.

**Cron job didn't run overnight**
→ Check `SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 5;`
to see the most recent attempts and their status/error messages.
