import { createClient } from "@supabase/supabase-js";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";

export const isSupabaseConfigured = Boolean(url && key);
export const supabase = createClient(url || "https://placeholder.supabase.co", key || "placeholder", {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
});

export const EVENT_ID = "birthday-main";
export const BUCKET = "party-photos";
export function publicPhotoUrl(path: string | null | undefined) {
  if (!path) return null;
  return supabase.storage.from(BUCKET).getPublicUrl(path).data.publicUrl;
}
export function sitePath(path = "/") {
  const base = process.env.NEXT_PUBLIC_BASE_PATH ?? (process.env.NODE_ENV === "production" ? "/trivia" : "");
  return `${base}${path}`.replace(/\/+/g, "/");
}
