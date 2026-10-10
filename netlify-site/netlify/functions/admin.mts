import type { Config } from "@netlify/functions";
import { readUsers, json, ONLINE_MS } from "../lib/hub.mts";

const same = (a: string, b: string) => {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
};

export default async (req: Request) => {
  const secret = Netlify.env.get("ADMIN_TOKEN") || "";
  const auth = req.headers.get("authorization") || "";
  const tok = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  if (!secret || !same(tok, secret)) {
    await new Promise((r) => setTimeout(r, 400));
    return json({ error: "unauthorized" }, 401);
  }
  const now = Date.now();
  const users = await readUsers();
  const members = users
    .map((u) => ({ uid: u.uid, name: u.name, runs: u.runs, first: u.first, last: u.last, game: u.game, script: u.script, v: u.v, online: now - u.last < ONLINE_MS }))
    .sort((a, b) => b.last - a.last);
  const feed = users
    .flatMap((u) => (u.recent || []).map((e) => ({ ...e, uid: u.uid, name: u.name })))
    .sort((a, b) => b.ts - a.ts)
    .slice(0, 150);
  return json({ members, feed, at: now });
};

export const config: Config = { path: "/api/admin", method: ["GET"] };
