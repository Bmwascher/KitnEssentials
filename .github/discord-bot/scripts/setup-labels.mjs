// Creates (or recolors) the labels the bot and the status workflow use.
//   GITHUB_TOKEN=... node scripts/setup-labels.mjs owner/repo [owner/repo ...]
// Safe to re-run; existing labels keep their issues.
const LABELS = [
  ['from-discord', '2da44e', 'Filed from a Discord forum post'],
  ['type: bug', 'd73a4a', 'Something is broken'],
  ['type: feature', '0075ca', 'Feature request or feedback'],
  ['client: retail', 'bfbfbf', 'Retail client'],
  ['client: forever', 'bfbfbf', 'WoW: Forever client'],
  ['client: all', 'bfbfbf', 'Both clients'],
  ['needs-info', 'fbca04', 'Waiting on the reporter for details'],
  ['pending-release', 'f9a03f', 'Fixed in dev, ships with the next release tag'],
  ['shipped', '0e8a16', 'Released'],
];
const token = process.env.GITHUB_TOKEN;
const repos = process.argv.slice(2);
if (!token || !repos.length) { console.error('Usage: GITHUB_TOKEN=... node scripts/setup-labels.mjs owner/repo ...'); process.exit(1); }
const h = { Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json', 'Content-Type': 'application/json' };
for (const repo of repos) {
  for (const [name, color, description] of LABELS) {
    let r = await fetch(`https://api.github.com/repos/${repo}/labels`, { method: 'POST', headers: h, body: JSON.stringify({ name, color, description }) });
    if (r.status === 422) r = await fetch(`https://api.github.com/repos/${repo}/labels/${encodeURIComponent(name)}`, { method: 'PATCH', headers: h, body: JSON.stringify({ color, description }) });
    console.log(repo, name, r.status);
  }
}
