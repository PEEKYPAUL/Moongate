-- Moongate v0.4.2 — Optional pi_public_key in claim_printer for manual
-- code entry as a camera-failure fallback.
--
-- v0.3 removed manual pair-code entry from the app on the basis that the
-- QR carried everything (version, pubkey, token) in one scan. The Pi
-- still emits the same human-typeable code via M118 ("MOONGATE CODE:
-- GATE-XXXX-XXXX") — the original intent was that it could be typed if
-- the camera was unavailable. This migration makes that path possible
-- again by allowing the claim to proceed without a pubkey in the
-- request.
--
-- Security analysis (why this is safe to relax):
--   • The token itself is the access secret (10-min TTL, single-use,
--     server-bound to a pi_public_key in enrollment_tokens at
--     enroll-prepare time).
--   • The pubkey from the QR was a defense-in-depth match against the
--     server's stored pubkey — not a separate auth factor. An attacker
--     who has the token already knows everything they'd need; an
--     attacker who lacks the token can't supply a valid pubkey either
--     (claim still fails on the token lookup).
--   • The server still uses enrollment_tokens.pi_public_key as the
--     authoritative key to bind the new printers row, so a malicious
--     client can't claim the wrong Pi by lying about the pubkey.
--
-- When the caller DOES supply a pubkey (the QR-scan path remains the
-- happy default), we still cross-check it against the server-side
-- value as before, so the existing path is byte-for-byte unchanged.

BEGIN;

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
  v_token              enrollment_tokens%ROWTYPE;
  v_existing_id        uuid;
  v_existing_owner     uuid;
  v_new_id             uuid;
  v_effective_pubkey   text;
BEGIN
  SELECT * INTO v_token
  FROM enrollment_tokens
  WHERE token_hash = decode(p_token_hash_b64, 'base64');

  IF NOT FOUND
     OR v_token.expires_at < now()
     OR v_token.used_at IS NOT NULL
  THEN
    RETURN QUERY SELECT NULL::uuid, 'not_found'::text;
    RETURN;
  END IF;

  -- Defense-in-depth check: when the caller supplied a pubkey (QR-scan
  -- path), it must match what the Pi pre-registered. Manual code entry
  -- passes NULL and skips this check — the server-side enrollment row
  -- IS the source of truth for which Pi this token belongs to.
  IF p_pi_public_key IS NOT NULL
     AND v_token.pi_public_key <> p_pi_public_key
  THEN
    RETURN QUERY SELECT NULL::uuid, 'not_found'::text;
    RETURN;
  END IF;

  v_effective_pubkey := v_token.pi_public_key;

  SELECT id, owner_user_id INTO v_existing_id, v_existing_owner
  FROM printers
  WHERE pi_public_key = v_effective_pubkey AND revoked_at IS NULL;

  IF v_existing_id IS NOT NULL THEN
    IF v_existing_owner = p_user_id THEN
      UPDATE enrollment_tokens
      SET used_at = now(), used_by_user_id = p_user_id
      WHERE pi_public_key = v_effective_pubkey;

      RETURN QUERY SELECT v_existing_id, 'ok'::text;
      RETURN;
    END IF;

    RETURN QUERY SELECT v_existing_id, 'already_paired'::text;
    RETURN;
  END IF;

  INSERT INTO printers (owner_user_id, name, pi_public_key)
  VALUES (p_user_id, p_name, v_effective_pubkey)
  RETURNING id INTO v_new_id;

  UPDATE enrollment_tokens
  SET used_at = now(), used_by_user_id = p_user_id
  WHERE pi_public_key = v_effective_pubkey;

  RETURN QUERY SELECT v_new_id, 'ok'::text;
END;
$$;

COMMENT ON FUNCTION public.claim_printer IS
  'Called by Edge Function printer-claim. Atomic claim with idempotent re-pair for same owner; constant-time error path for unauthorized callers. p_pi_public_key is OPTIONAL — when NULL, the server-side enrollment_tokens.pi_public_key is used as the authoritative key (supports manual code entry as a camera-failure fallback).';

COMMIT;
