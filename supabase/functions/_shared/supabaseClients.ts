// Two Supabase clients per function invocation:
//   - userClient(authHeader): scoped to the caller's JWT, RLS applies
//   - adminClient():           service role, RLS bypassed (used for RPC calls)
//
// In practice every Edge Function in this project uses adminClient() to call
// SECURITY DEFINER RPC functions that enforce their own auth (the function
// receives the user_id as a parameter that the Edge Function extracted
// from the verified JWT).

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL              = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY         = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

export function userClient(authHeader: string): SupabaseClient {
  return createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth:   { persistSession: false, autoRefreshToken: false },
  });
}

export function adminClient(): SupabaseClient {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/**
 * Verify the request's Authorization header and return the authenticated user.
 * Returns null if no/invalid header, expired token, or unknown user.
 */
export async function getUserFromRequest(req: Request) {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return null;
  try {
    const client = userClient(authHeader);
    const { data, error } = await client.auth.getUser();
    if (error || !data?.user) return null;
    return data.user;
  } catch {
    return null;
  }
}
