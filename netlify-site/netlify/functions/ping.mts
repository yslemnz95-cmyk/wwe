import type { Config } from "@netlify/functions";
import { hub, dayKey, json, type User } from "../lib/hub.mts";

const ALLOWED = new Set(["uid", "name", "place", "game", "script", "v", "t"]);
const clean = (s: unknown, max: number) =>
  typeof s === "string" ? s.replace(/[^\p{L}\p{N} _.\-]/gu, "").slice(0, max) : "";

export default async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method" }, 405);
  let b: Record<string, unknown>;
  try {
    const raw = await req.text();
    if (raw.length > 1024) return json({ error: "too large" }, 413);
    b = JSON.parse(raw);
  } catch {
    return json({ error: "bad request" }, 400);
  }
  if (!b || typeof b !== "object" || Object.keys(b).some((k) => !ALLOWED.has(k))) return json({ error: "bad request" }, 400);
  const uid = b.uid, kind = b.t;
  if (typeof uid !== "number" || !Number.isInteger(uid) || uid <= 0 || uid > 1e13 || (kind !== "start" && kind !== "beat"))
    return json({ error: "bad request" }, 400);

  const name = clean(b.name, 40) || String(uid);
  const game = clean(b.game, 50) || "Unknown game";
  const script = clean(b.script, 40) || "SourcesHub";
  const v = typeof b.v === "number" && Number.isInteger(b.v) ? b.v : 1;
  const now = Date.now();

  const store = hub();
  const key = `u/${uid}`;
  const rec = ((await store.get(key, { type: "json" }).catch(() => null)) as User | null) ||
    { uid, name, first: now, last: 0, runs: 0, game, script, v, days: {}, games: {}, recent: [] };

  // light flood guard (a client sends one start per run and one beat per minute)
  if (now - rec.last < (kind === "start" ? 3_000 : 15_000)) return json({ ok: true, skipped: true });

  rec.name = name; rec.game = game; rec.script = script; rec.v = v; rec.last = now;
  if (kind === "start") {
    rec.runs += 1;
    const d = dayKey(now);
    rec.days[d] = (rec.days[d] || 0) + 1;
    for (const k of Object.keys(rec.days).sort().slice(0, -14)) delete rec.days[k];
    rec.games[game] = (rec.games[game] || 0) + 1;
    rec.recent = [{ ts: now, t: "start", game, script, v }, ...rec.recent].slice(0, 20);
  }
  await store.setJSON(key, rec);
  return json({ ok: true });
};

export const config: Config = { path: "/api/ping", method: ["POST"] };
