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

Then it's time for Phase 2: Edge Functions.

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
