// Creates (or recolors) the labels the bot and the status workflow use.
//   GITHUB_TOKEN=... node scripts/setup-labels.mjs owner/repo [owner/repo ...]
// Safe to re-run; existing labels keep their issues. Exits 1 if any label failed.
import { LABEL_DEFS } from '../src/core.js';

const token = process.env.GITHUB_TOKEN;
const repos = process.argv.slice(2);
if (!token || !repos.length) { console.error('Usage: GITHUB_TOKEN=... node scripts/setup-labels.mjs owner/repo ...'); process.exit(1); }
const h = { Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json', 'Content-Type': 'application/json' };
let failed = 0;
for (const repo of repos) {
  for (const [name, color, description] of LABEL_DEFS) {
    let r = await fetch(`https://api.github.com/repos/${repo}/labels`, { method: 'POST', headers: h, body: JSON.stringify({ name, color, description }) });
    if (r.status === 422) r = await fetch(`https://api.github.com/repos/${repo}/labels/${encodeURIComponent(name)}`, { method: 'PATCH', headers: h, body: JSON.stringify({ color, description }) });
    if (r.ok) {
      console.log(repo, name, r.status);
    } else {
      failed++;
      console.error(repo, name, r.status, (await r.text().catch(() => '')).slice(0, 200));
    }
  }
}
if (failed) { console.error(`${failed} label(s) failed`); process.exit(1); }
