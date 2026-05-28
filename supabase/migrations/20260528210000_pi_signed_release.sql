-- Moongate v0.4.2 — Pi-signed force-release path.
--
-- Closes the v0.3.1 gap that MOONGATE_RESET_OWNER could only ever clean
-- *local* state. When a user wipes the app (loses their anon UID), the
-- cloud row stays owned by an unreachable user. The next pair attempt from
-- a fresh anon UID then hits 'already_paired' from claim_printer, and the
-- only recovery was manual SQL (which we did twice today).
--
-- With this migration the Pi itself can release the cloud row by signing
-- a request with its existing Ed25519 device key. The signature proves
-- physical access to the Pi — strong enough authority to force-delete
-- the row regardless of who owns it. The Edge Function performs the
-- verification before calling this RPC.

BEGIN;

CREATE OR REPLACE FUNCTION public.release_printer_by_pubkey(
  p_pi_public_key text
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Idempotent. The row may already be gone; the Pi might be retrying
  -- after a transient error, or the user may have triggered the app-side
  -- release flow first.
  DELETE FROM printers          WHERE pi_public_key = p_pi_public_key;
  DELETE FROM enrollment_tokens WHERE pi_public_key = p_pi_public_key;
  RETURN 'ok';
END;
$$;

COMMENT ON FUNCTION public.release_printer_by_pubkey IS
  'Called by Edge Function release-printer on the Pi-signed force-release path. Authentication happens before the RPC call (Ed25519 signature verified against pi_public_key); this RPC is just the delete.';

REVOKE EXECUTE ON FUNCTION public.release_printer_by_pubkey(text) FROM PUBLIC;

COMMIT;
