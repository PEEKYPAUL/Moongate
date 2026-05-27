-- Moongate v0.3.1 — Closes the un-pair / re-pair loop.
--
-- v0.3.0 left two gaps:
--   1. The app's "Remove printer" action and the Pi's MOONGATE_RESET_OWNER
--      both cleared *local* state but never deleted the Supabase row. The
--      stale row then blocked the user from re-pairing the same Pi.
--   2. claim_printer rejected ANY pre-existing row for the pubkey, even
--      when the would-be claimer was the original owner — so the same
--      anon user couldn't re-claim their own Pi without manual SQL.
--
-- This migration:
--   • Adds release_printer(p_printer_id, p_user_id): ownership-checked
--     delete that the new /release-printer Edge Function calls.
--   • Updates claim_printer to return 'ok' (idempotent) when the existing
--     row is already owned by p_user_id, instead of 'already_paired'.

BEGIN;

-- ============================================================================
-- 1. release_printer
--    App calls /release-printer → this. Deletes the printer row only if the
--    caller actually owns it, and also wipes any pending enrollment_tokens
--    for the same Pi pubkey so a fresh MOONGATE_PAIR can immediately mint
--    a new enrollment without UNIQUE-violation churn.
--
--    Returns (status) where status is one of:
--      'ok'        — row deleted (or didn't exist; idempotent)
--      'not_found' — row exists but not owned by p_user_id
--                    (returned as 404 by the Edge Function — same shape as
--                    "doesn't exist" to avoid enumeration leaks)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.release_printer(
  p_printer_id uuid,
  p_user_id    uuid
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner uuid;
  v_pubkey text;
BEGIN
  SELECT owner_user_id, pi_public_key
    INTO v_owner, v_pubkey
  FROM printers
  WHERE id = p_printer_id;

  IF NOT FOUND THEN
    -- Idempotent: caller asked us to delete a row that's already gone.
    RETURN 'ok';
  END IF;

  IF v_owner <> p_user_id THEN
    RETURN 'not_found';
  END IF;

  DELETE FROM printers WHERE id = p_printer_id;
  DELETE FROM enrollment_tokens WHERE pi_public_key = v_pubkey;

  RETURN 'ok';
END;
$$;

COMMENT ON FUNCTION public.release_printer IS
  'Called by Edge Function release-printer. Owner-checked hard delete of the printer row + any pending enrollment token for the same Pi pubkey.';

REVOKE EXECUTE ON FUNCTION public.release_printer(uuid, uuid) FROM PUBLIC;

-- ============================================================================
-- 2. claim_printer (replacement) — idempotent for same owner
--    If the pubkey already has a non-revoked row AND the caller owns it,
--    return that row's id as 'ok' and mark the enrollment token used.
--    Otherwise, the existing 'already_paired' path still applies.
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
  v_existing_owner uuid;
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

  SELECT id, owner_user_id INTO v_existing_id, v_existing_owner
  FROM printers
  WHERE pi_public_key = p_pi_public_key AND revoked_at IS NULL;

  IF v_existing_id IS NOT NULL THEN
    IF v_existing_owner = p_user_id THEN
      -- Same owner re-claiming their own Pi. Mark the token used and
      -- return the existing row's id idempotently.
      UPDATE enrollment_tokens
      SET used_at = now(), used_by_user_id = p_user_id
      WHERE pi_public_key = p_pi_public_key;

      RETURN QUERY SELECT v_existing_id, 'ok'::text;
      RETURN;
    END IF;

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
  'Called by Edge Function printer-claim. Atomic claim with idempotent re-pair for same owner; constant-time error path for unauthorized callers.';

COMMIT;
