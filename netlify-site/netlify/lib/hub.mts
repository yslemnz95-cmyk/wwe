import { getStore } from "@netlify/blobs";

export const ONLINE_MS = 150_000; // a member counts as online if the script pinged in the last 2.5 min
const SUMMARY_TTL = 20_000;

export type Ev = { ts: number; t: string; game: string; script: string; v: number };
export type User = {
  uid: number; name: string; first: number; last: number; runs: number;
  game: string; script: string; v: number;
  days: Record<string, number>; games: Record<string, number>; recent: Ev[];
};

export const hub = () => getStore({ name: "sourceshub", consistency: "strong" });
export const dayKey = (ms: number) => new Date(ms).toISOString().slice(0, 10);

export const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });

export async function readUsers(): Promise<User[]> {
  const store = hub();
  const keys: string[] = [];
  for await (const page of store.list({ prefix: "u/", paginate: true })) {
    for (const b of page.blobs) keys.push(b.key);
  }
  const out: User[] = [];
  for (let i = 0; i < keys.length; i += 25) {
    const batch = await Promise.all(keys.slice(i, i + 25).map((k) => store.get(k, { type: "json" }).catch(() => null)));
    for (const u of batch) if (u) out.push(u as User);
  }
  return out;
}

export function summarize(users: User[], now = Date.now()) {
  const today = dayKey(now);
  const days: Record<string, number> = {};
  const games: Record<string, { runs: number; online: number }> = {};
  let total = 0, todayRuns = 0, online = 0;
  for (const u of users) {
    total += u.runs || 0;
    todayRuns += u.days?.[today] || 0;
    const on = now - (u.last || 0) < ONLINE_MS;
    if (on) online++;
    for (const [d, n] of Object.entries(u.days || {})) days[d] = (days[d] || 0) + n;
    for (const [g, n] of Object.entries(u.games || {})) {
      const e = (games[g] ||= { runs: 0, online: 0 });
      e.runs += n;
    }
    if (on && u.game) (games[u.game] ||= { runs: 0, online: 0 }).online++;
  }
  const last7 = Array.from({ length: 7 }, (_, i) => {
    const d = dayKey(now - (6 - i) * 86400_000);
    return { day: d, runs: days[d] || 0 };
  });
  return {
    online, members: users.length, total, today: todayRuns, last7,
    games: Object.entries(games).map(([game, v]) => ({ game, ...v })).sort((a, b) => b.runs - a.runs).slice(0, 12),
    at: now,
  };
}

export async function cachedSummary() {
  const store = hub();
  const cached = (await store.get("summary", { type: "json" }).catch(() => null)) as ReturnType<typeof summarize> | null;
  if (cached && Date.now() - cached.at < SUMMARY_TTL) return cached;
  const fresh = summarize(await readUsers());
  await store.setJSON("summary", fresh).catch(() => {});
  return fresh;
}
