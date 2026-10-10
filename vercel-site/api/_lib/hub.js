import { get, put, list } from "@vercel/blob";

export const ONLINE_MS = 150_000; // member counts as online if the script pinged in the last 2.5 min
const SUMMARY_TTL = 20_000;
const opts = { access: "private", useCache: false };

export const dayKey = (ms) => new Date(ms).toISOString().slice(0, 10);

export const json = (data, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });

export async function readJson(pathname) {
  try {
    const r = await get(pathname, opts);
    if (!r || r.statusCode !== 200) return null;
    return JSON.parse(await new Response(r.stream).text());
  } catch {
    return null;
  }
}

export const writeJson = (pathname, value) =>
  put(pathname, JSON.stringify(value), {
    access: "private",
    allowOverwrite: true,
    addRandomSuffix: false,
    contentType: "application/json",
    cacheControlMaxAge: 60,
  });

export async function readUsers() {
  const paths = [];
  let cursor;
  do {
    const page = await list({ prefix: "u/", limit: 1000, cursor });
    for (const b of page.blobs) paths.push(b.pathname);
    cursor = page.hasMore ? page.cursor : undefined;
  } while (cursor);
  const out = [];
  for (let i = 0; i < paths.length; i += 25) {
    const batch = await Promise.all(paths.slice(i, i + 25).map(readJson));
    for (const u of batch) if (u) out.push(u);
  }
  return out;
}

export function summarize(users, now = Date.now()) {
  const today = dayKey(now);
  const days = {};
  const games = {};
  let total = 0, todayRuns = 0, online = 0;
  for (const u of users) {
    total += u.runs || 0;
    todayRuns += u.days?.[today] || 0;
    const on = now - (u.last || 0) < ONLINE_MS;
    if (on) online++;
    for (const [d, n] of Object.entries(u.days || {})) days[d] = (days[d] || 0) + n;
    for (const [g, n] of Object.entries(u.games || {})) (games[g] ||= { runs: 0, online: 0 }).runs += n;
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
  const cached = await readJson("summary.json");
  if (cached && Date.now() - cached.at < SUMMARY_TTL) return cached;
  const fresh = summarize(await readUsers());
  await writeJson("summary.json", fresh).catch(() => {});
  return fresh;
}
