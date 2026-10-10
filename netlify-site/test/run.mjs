// Test local des fonctions Netlify avec un faux @netlify/blobs en memoire (node >= 22.6).
// Usage : node --experimental-strip-types test/run.mjs   (depuis netlify-site/)
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "sh-"));
fs.mkdirSync(path.join(tmp, "lib")); fs.mkdirSync(path.join(tmp, "fn"));
fs.writeFileSync(path.join(tmp, "blobs.mjs"), `
const data = new Map();
export const getStore = () => ({
  async get(k) { return data.has(k) ? JSON.parse(data.get(k)) : null; },
  async setJSON(k, v) { data.set(k, JSON.stringify(v)); },
  async *list({ prefix }) { yield { blobs: [...data.keys()].filter(k => k.startsWith(prefix)).map(key => ({ key })) }; },
});
`);
const fix = (s) => s.replace('"@netlify/blobs"', '"../blobs.mjs"').replace(/"\.\.\/lib\/hub\.mts"/g, '"../lib/hub.mts"');
fs.writeFileSync(path.join(tmp, "lib/hub.mts"), fix(fs.readFileSync("netlify/lib/hub.mts", "utf8")));
for (const f of ["ping", "stats", "admin"]) fs.writeFileSync(path.join(tmp, `fn/${f}.mts`), fix(fs.readFileSync(`netlify/functions/${f}.mts`, "utf8")));
globalThis.Netlify = { env: { get: (k) => (k === "ADMIN_TOKEN" ? "SECRET" : undefined) } };
const load = (f) => import(pathToFileURL(path.join(tmp, `fn/${f}.mts`)).href).then((m) => m.default);
const ping = await load("ping"), stats = await load("stats"), admin = await load("admin");

let fails = 0;
const check = (n, ok) => { console.log((ok ? "ok   " : "FAIL ") + n); if (!ok) fails++; };
const post = (body) => ping(new Request("http://x/api/ping", { method: "POST", body: typeof body === "string" ? body : JSON.stringify(body) }));
const j = async (r) => r.json();

let r = await post({ uid: 11, name: "Nova", place: 1, game: "Steal An Egg", script: "SourcesHub", v: 1, t: "start" });
check("start accepted", r.status === 200 && (await j(r)).ok);
r = await post({ uid: 22, name: "Kairo<script>", place: 2, game: "Ride a Pet", script: "SourcesHub", v: 1, t: "start" });
check("second member", r.status === 200);
check("extra field rejected", (await post({ uid: 5, t: "start", evil: 1 })).status === 400);
check("bad uid rejected", (await post({ uid: -1, t: "start" })).status === 400);
check("bad kind rejected", (await post({ uid: 5, t: "x" })).status === 400);
check("garbage rejected", (await post("nope")).status === 400);
check("oversize rejected", (await post("x".repeat(2000))).status === 413);
check("GET on ping refused", (await ping(new Request("http://x/api/ping"))).status === 405);
r = await post({ uid: 11, name: "Nova", game: "Steal An Egg", script: "SourcesHub", v: 1, t: "start" });
check("flood guard skips a start within 3 s", (await j(r)).skipped === true);

const s = await j(await stats());
check("stats: 2 members online, 2 total executions", s.online === 2 && s.members === 2 && s.total === 2 && s.today === 2);
check("stats: by game", s.games.length === 2 && s.games.some((g) => g.game === "Steal An Egg" && g.runs === 1 && g.online === 1));
check("stats: 7 day series", s.last7.length === 7 && s.last7[6].runs === 2);
check("stats public: no names", !JSON.stringify(s).includes("Nova"));

check("admin needs token", (await admin(new Request("http://x/api/admin"))).status === 401);
check("admin wrong token", (await admin(new Request("http://x/api/admin", { headers: { authorization: "Bearer nope" } }))).status === 401);
const a = await j(await admin(new Request("http://x/api/admin", { headers: { authorization: "Bearer SECRET" } })));
check("admin: members + feed", a.members.length === 2 && a.feed.length === 2 && a.members.every((m) => m.online));
check("name sanitized", a.members.some((m) => m.name === "Kairoscript"));
console.log("FAILS", fails);
process.exit(fails ? 1 : 0);
