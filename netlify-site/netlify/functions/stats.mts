import type { Config } from "@netlify/functions";
import { cachedSummary, json } from "../lib/hub.mts";

export default async () => {
  const s = await cachedSummary();
  return json({ online: s.online, members: s.members, total: s.total, today: s.today, last7: s.last7, games: s.games, at: s.at });
};

export const config: Config = { path: "/api/stats", method: ["GET"] };
