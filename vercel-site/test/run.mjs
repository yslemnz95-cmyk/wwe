// Test local des fonctions Vercel avec un faux @vercel/blob en memoire. Usage : node test/run.mjs (depuis vercel-site/)
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "shv-"));
fs.mkdirSync(path.join(tmp, "api/_lib"), { recursive: true });
fs.writeFileSync(path.join(tmp, "blob.mjs"), `
const data = new Map();
export const get = async (p) => data.has(p) ? { statusCode: 200, stream: new Response(data.get(p)).body } : null;
export const put = async (p, body) => { data.set(p, body); return { pathname: p }; };
export const list = async ({ prefix }) => ({ blobs: [...data.keys()].filter(k => k.startsWith(prefix)).map(pathname => ({ pathname })), hasMore: false });
`);
for (const f of ["api/_lib/hub.js", "api/ping.js", "api/stats.js", "api/admin.js"])
  fs.writeFileSync(path.join(tmp, f), fs.readFileSync(f, "utf8").replace('"@vercel/blob"', '"' + pathToFileURL(path.join(tmp, "blob.mjs")).href + '"'));
fs.writeFileSync(path.join(tmp, "package.json"), '{"type":"module"}');
process.env.ADMIN_TOKEN = "SECRET";
const load = (f) => import(pathToFileURL(path.join(tmp, `api/${f}.js`)).href);
const ping = await load("ping"), stats = await load("stats"), admin = await load("admin");

let fails = 0;
const check = (n, ok) => { console.log((ok ? "ok   " : "FAIL ") + n); if (!ok) fails++; };
const post = (body) => ping.POST(new Request("http://x/api/ping", { method: "POST", body: typeof body === "string" ? body : JSON.stringify(body) }));
const j = (r) => r.json();

let r = await post({ uid: 11, name: "Nova", place: 1, game: "Steal An Egg", script: "SourcesHub", v: 1, t: "start" });
check("start accepted", r.status === 200 && (await j(r)).ok);
check("second member", (await post({ uid: 22, name: "Kairo<script>", place: 2, game: "Ride a Pet", script: "SourcesHub", v: 1, t: "start" })).status === 200);
check("extra field rejected", (await post({ uid: 5, t: "start", evil: 1 })).status === 400);
check("bad uid rejected", (await post({ uid: -1, t: "start" })).status === 400);
check("bad kind rejected", (await post({ uid: 5, t: "x" })).status === 400);
check("garbage rejected", (await post("nope")).status === 400);
check("oversize rejected", (await post("x".repeat(2000))).status === 413);
check("GET on ping refused", (await ping.GET()).status === 405);
check("flood guard skips a start within 3 s", (await j(await post({ uid: 11, name: "Nova", game: "Steal An Egg", script: "SourcesHub", v: 1, t: "start" }))).skipped === true);

const s = await j(await stats.GET());
check("stats: 2 online, 2 members, 2 executions today", s.online === 2 && s.members === 2 && s.total === 2 && s.today === 2);
check("stats: by game", s.games.length === 2 && s.games.some((g) => g.game === "Steal An Egg" && g.runs === 1 && g.online === 1));
check("stats: 7 day series", s.last7.length === 7 && s.last7[6].runs === 2);
check("stats public: no names", !JSON.stringify(s).includes("Nova"));
const A = (h) => admin.GET(new Request("http://x/api/admin", { headers: h }));
check("admin needs token", (await A({})).status === 401);
check("admin wrong token", (await A({ authorization: "Bearer nope" })).status === 401);
const a = await j(await A({ authorization: "Bearer SECRET" }));
check("admin: members + feed", a.members.length === 2 && a.feed.length === 2 && a.members.every((m) => m.online));
check("name sanitized", a.members.some((m) => m.name === "Kairoscript"));
console.log("FAILS", fails);
process.exit(fails ? 1 : 0);
