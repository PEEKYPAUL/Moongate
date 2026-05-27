-- Moongate v0.3.0 — RPC helper functions for Edge Functions
--
-- All Edge Function DB access goes through these SECURITY DEFINER functions.
-- This keeps bytea encoding inside SQL (where decode/encode handle base64)
-- and concentrates business logic next to the data.
--
-- Idempotent (CREATE OR REPLACE). Safe to re-run.

BEGIN;

-- ============================================================================
-- 1. upsert_enrollment_token
--    Pi calls /enroll-prepare → this. Wipes any prior pending enrollment for
--    the same Pi public key, then inserts the new hash + expiry.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.upsert_enrollment_token(
  p_pi_public_key  text,
  p_token_hash_b64 text,
  p_ttl_seconds    int
)
RETURNS timestamptz
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_expires_at timestamptz := now() + (p_ttl_seconds || ' seconds')::interval;
BEGIN
  DELETE FROM enrollment_tokens WHERE pi_public_key = p_pi_public_key;

  INSERT INTO enrollment_tokens (token_hash, pi_public_key, expires_at)
  VALUES (decode(p_token_hash_b64, 'base64'), p_pi_public_key, v_expires_at);

  RETURN v_expires_at;
END;
$$;

COMMENT ON FUNCTION public.upsert_enrollment_token IS
  'Called by Edge Function enroll-prepare. Stores SHA-256(token) + Pi pubkey, replacing any prior pending enrollment.';

-- ============================================================================
-- 2. claim_printer
--    App calls /printer-claim → this. Validates enrollment token (constant-
--    time over not_found / expired / used / pubkey mismatch) and creates the
--    printer row owned by the calling user.
--
--    Returns (printer_id, status) where status is one of:
--      'ok'              — new printer created, printer_id returned
--      'not_found'       — token invalid for any reason (do not differentiate)
--      'already_paired'  — this Pi pubkey is already paired to someone
-- ============================================================================

CREATE OR REPLACE FUNCTION public.claim_printer(
  p_token_hash_b64 text,
  p_pi_public_key  text,
  p_name           text,
  p_user_id        uuid
)
RETURNS table(printer_id uuid, status text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_token       enrollment_tokens%ROWTYPE;
  v_existing_id uuid;
  v_new_id      uuid;
BEGIN
  SELECT * INTO v_token
  FROM enrollment_tokens
  WHERE token_hash = decode(p_token_hash_b64, 'base64');

  IF NOT FOUND
     OR v_token.expires_at < now()
     OR v_token.used_at IS NOT NULL
     OR v_token.pi_public_key <> p_pi_public_key
  THEN
    RETURN QUERY SELECT NULL::uuid, 'not_found'::text;
    RETURN;
  END IF;

  SELECT id INTO v_existing_id
  FROM printers
  WHERE pi_public_key = p_pi_public_key AND revoked_at IS NULL;

  IF v_existing_id IS NOT NULL THEN
    RETURN QUERY SELECT v_existing_id, 'already_paired'::text;
    RETURN;
  END IF;

  INSERT INTO printers (owner_user_id, name, pi_public_key)
  VALUES (p_user_id, p_name, p_pi_public_key)
  RETURNING id INTO v_new_id;

  UPDATE enrollment_tokens
  SET used_at = now(), used_by_user_id = p_user_id
  WHERE pi_public_key = p_pi_public_key;

  RETURN QUERY SELECT v_new_id, 'ok'::text;
END;
$$;

COMMENT ON FUNCTION public.claim_printer IS
  'Called by Edge Function printer-claim. Atomic claim flow with constant-time error path.';

-- ============================================================================
-- 3. get_printer_access
--    App calls /printer-access → this. Returns the printer's encrypted tunnel
--    URL bytes (base64) ONLY if the caller owns the printer and it's not
--    revoked. Returns no rows otherwise — the Edge Function treats no-rows
--    as 404 to avoid distinguishing "doesn't exist" from "not yours".
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_printer_access(
  p_printer_id uuid,
  p_user_id    uuid
)
RETURNS table(
  printer_id            uuid,
  pi_public_key         text,
  tunnel_url_enc_b64    text,
  tunnel_url_nonce_b64  text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT p.id,
         p.pi_public_key,
         encode(p.tunnel_url_enc,   'base64'),
         encode(p.tunnel_url_nonce, 'base64')
  FROM printers p
  WHERE p.id = p_printer_id
    AND p.owner_user_id = p_user_id
    AND p.revoked_at IS NULL;
END;
$$;

COMMENT ON FUNCTION public.get_printer_access IS
  'Called by Edge Function printer-access. Ownership-checked decryption-ready fetch.';

-- ============================================================================
-- 4. record_heartbeat
--    Pi calls /printer-heartbeat → this. Updates the tunnel URL ciphertext
--    + nonce and bumps last_seen. Returns the printer_id if a row was
--    actually updated (so the Edge Function can mint a fresh access token
--    is unnecessary here, but the printer_id is useful for logging).
--
--    Lookup is by pi_public_key (the Pi's identity), not printer_id — the Pi
--    doesn't need to know the printer_id, only its own keypair.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.record_heartbeat(
  p_pi_public_key        text,
  p_tunnel_url_enc_b64   text,
  p_tunnel_url_nonce_b64 text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_printer_id uuid;
BEGIN
  UPDATE printers
  SET tunnel_url_enc   = decode(p_tunnel_url_enc_b64,   'base64'),
      tunnel_url_nonce = decode(p_tunnel_url_nonce_b64, 'base64'),
      last_seen        = now()
  WHERE pi_public_key = p_pi_public_key
    AND revoked_at IS NULL
  RETURNING id INTO v_printer_id;

  RETURN v_printer_id;  -- NULL if no row matched
END;
$$;

COMMENT ON FUNCTION public.record_heartbeat IS
  'Called by Edge Function printer-heartbeat. Updates tunnel URL ciphertext from a Pi-signed payload.';

-- ============================================================================
-- 5. Lock down execution
-- ============================================================================

REVOKE EXECUTE ON FUNCTION public.upsert_enrollment_token(text, text, int)            FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.claim_printer(text, text, text, uuid)               FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_printer_access(uuid, uuid)                      FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.record_heartbeat(text, text, text)                  FROM PUBLIC;

-- Service role retains EXECUTE via default; Edge Functions use service role.
-- We deliberately do NOT grant to authenticated/anon — only Edge Functions
-- should call these.

COMMIT;
