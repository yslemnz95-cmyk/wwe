import { cachedSummary, json } from "./_lib/hub.js";

export async function GET() {
  const s = await cachedSummary();
  return json({ online: s.online, members: s.members, total: s.total, today: s.today, last7: s.last7, games: s.games, at: s.at });
}
