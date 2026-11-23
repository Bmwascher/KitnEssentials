// The merge-plan comment on a pull request that closes, references or links
// an issue the bot filed: which issues merging closes, and the bot's current
// message for each step. It links issues and copies no report.
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { MESSAGES, STATUS, timedFetch } from '../src/core.js';
import { githubClient } from '../src/github.js';
import { eligible, TRUSTED, BOT_LOGIN } from './status.mjs';

export const MARKER = '<!-- discord-merge-plan -->';
const RELEASE_PLACEHOLDER = '(release tag)';
const KEYWORD = '(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)';
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
// `#N` or `owner/repo#N` for this repo, the forms GitHub documents for
// closing keywords, right after a keyword's whitespace; the only capturing
// group is the number. An issue URL is not read: what follows its number can
// make it name another issue.
const refIn = (repo) => `(?:#|${esc(repo)}#)(\\d+)\\b`;
const numbers = (body, re) => [...new Set([...body.matchAll(re)].map((m) => Number(m[1])))];

// This repo's issues a closing keyword names: for a PR into another branch,
// where GitHub lists none, and for one GitHub does not list on the default
// branch.
export const closingKeywordRefs = (body, repo) => numbers(body, new RegExp(`\\b${KEYWORD}:?\\s+${refIn(repo)}`, 'gi'));
// This repo's issues a `Refs` (or `Ref`) names, one per keyword.
export const refsKeywordRefs = (body, repo) => numbers(body, new RegExp(`\\brefs?:?\\s+${refIn(repo)}`, 'gi'));

// Only a link that stands alone counts: it starts the text or follows
// whitespace, and ends at whitespace or the end. A character touching it
// (`717-old`, a sentence's period, another URL holding it) could change the
// post it names, so such a link names none; a link that stands alone names
// exactly the post its URL names, Markdown around it or not. The id is a
// Discord id's shape, 1 to 20 digits, so it always makes a valid date.
const THREAD_LINK = /(?<=^|\s)https:\/\/(?:ptb\.|canary\.)?discord(?:app)?\.com\/channels\/\d+\/(\d{1,20})(?:\/\d{1,20})?(?=\s|$)/g;
export const threadLinks = (body) => [...new Set([...body.matchAll(THREAD_LINK)].map((m) => m[1]))];

// A code span no backtick inside `s` can end early, so a branch name never
// turns into a link or a mention. Git allows no line break in a branch name.
const code = (s) => {
  const run = Math.max(0, ...(s.match(/`+/g) || []).map((x) => x.length));
  const fence = '`'.repeat(run + 1);
  const pad = /^`|`$/.test(s) ? ' ' : '';
  return `${fence}${pad}${s}${pad}${fence}`;
};
const nums = (list) => list.map((x) => `#${x.n}`).join(', ');
// Heads-up lines state what the PR closes; what the bot sends, and when, is
// the README's to say, since a re-run of an older run can still owe a message.
const closedLine = (ref) => `${ref} is already closed.`;

// One open closing issue's previews: the text a new note of each step gets.
// When a message goes out is the README's to say, not this comment's.
const section = (repo, defaultBranch, c) => [
  `**#${c.n}** closes when this PR merges. The bot's current message for each step:`,
  `- Ready for review, by an author with a role on this repo (**${STATUS.inProgress}**):`,
  `  > ${MESSAGES.inProgress()}`,
  `- Merged into ${code(defaultBranch)} (**${STATUS.fixed}**):`,
  `  > ${MESSAGES.fixed()}`,
  `- A release tag that holds the merge commit (**${STATUS.shipped}**), with that tag in place of ${RELEASE_PLACEHOLDER}; a tag that starts with a digit gets a v:`,
  `  > ${MESSAGES.shipped(repo, RELEASE_PLACEHOLDER)}`,
  `- Only part of the fix? Change the closing word before #${c.n} to \`Refs\`, remove any link to #${c.n} in the Development sidebar, and keep fix, close and resolve before #${c.n} out of commit messages.`,
];

// `closing`, `unlisted`, `refs` and `linked` are [{ n, open }]; `unlisted`
// holds the issues the description's closing keywords name on the default
// base that GitHub does not list as closing. `crossRepo` is
// [{ repo, n, open }]; `state` is open, merged or closedUnmerged.
export function renderPlan({ repo, defaultBranch, base, draft, trusted, state, closing, unlisted, refs, linked, crossRepo }) {
  if (state === 'merged') {
    // A merged PR's closing references include issues closed before it, and
    // nothing here tells which closed each one, so the text is conditional.
    if (!closing.length) {
      return `${MARKER}\n\nMerged into ${code(base)}. It closed no Discord-filed issue of this repo through its description or links; closing keywords in commit messages are not read here.`;
    }
    return [
      MARKER,
      `Merged into ${code(base)}, naming ${nums(closing)} as closing. GitHub closes each of these issues that was still open; what the bot then does is in \`.github/discord-bot/README.md\`.`,
      'If this merge is reverted before a release, reopen each issue it closed the same day; otherwise the release announces the fix as out.',
    ].join('\n\n');
  }
  if (state === 'closedUnmerged') return `${MARKER}\n\nClosed without merging, so this PR closes no issue.`;
  if (!closing.length && !unlisted.length && !refs.length && !linked.length && !crossRepo.length) {
    return `${MARKER}\n\nThis PR no longer closes, references or links a Discord-filed issue.`;
  }
  const wrongBase = base !== defaultBranch;
  const open = closing.filter((c) => c.open);
  const out = [MARKER, '', '### Discord reports this PR touches'];
  if (!wrongBase) for (const c of open) out.push('', ...section(repo, defaultBranch, c));
  const heads = [];
  if (wrongBase && open.length) {
    heads.push(`This PR targets ${code(base)}, not ${code(defaultBranch)}: GitHub will not close ${nums(open)} when it merges. Change the base, then edit and save the description once.`);
  }
  // An outside author's PR never counts toward In progress, draft or not.
  if (!wrongBase && open.length && !trusted) {
    heads.push("This PR's author has no role on this repo, so this PR never counts toward In progress.");
  } else if (!wrongBase && open.length && draft) {
    heads.push('This PR is a draft: it counts toward In progress only once it is ready for review.');
  }
  heads.push(...closing.filter((c) => !c.open).map((c) => closedLine(`#${c.n}`)));
  heads.push(...unlisted.map((u) => (u.open
    ? `The description says it closes #${u.n}, but GitHub does not list #${u.n} as closing, so merging will not close it, unless a commit message does. Edit and save the description once: a base change alone does not make GitHub read it again.`
    : closedLine(`#${u.n}`))));
  heads.push(...crossRepo.map((x) => (x.open
    ? `This PR closes ${x.repo}#${x.n}, a Discord report in another repo. That repo's status workflow, if it runs, cannot see this repo's fix or its releases. Transfer the issue to this repo before merging, or make the fix in that repo.`
    : closedLine(`${x.repo}#${x.n}`))));
  heads.push(...linked.map((l) => (l.open
    ? `This PR links the Discord post tracked as #${l.n} but does not close it, unless a commit message does. Add \`Fixes #${l.n}\` on its own line when the fix is ready, or \`Refs #${l.n}\` while it is unfinished.`
    : closedLine(`#${l.n}`))));
  heads.push(...refs.map((r) => (r.open
    ? `#${r.n} is referenced, not closed: merging this PR does not close it, unless a commit message does. Change \`Refs #${r.n}\` to \`Fixes #${r.n}\` when the fix is ready.`
    : closedLine(`#${r.n}`))));
  if (heads.length) out.push('', '**Heads-up:**', ...heads.map((h) => `- ${h}`));
  out.push('', '_The bot updates this comment when the PR is opened, edited, marked ready, converted to draft, reopened or closed. When each message goes out, and when it does not, is in `.github/discord-bot/README.md`._');
  return out.join('\n');
}

const CALL_MS = 15000;
// Every call of a run ends this long after it starts, far inside the job's
// time limit: a job that reaches that limit is canceled, and so is the
// whole run, so a slow run must end here, logged and green.
const PLAN_MS = 60 * 1000;
// The PR as it is now, the repo's default branch and the issues the PR will
// close, from one read. Only a first attempt's open, closed or merged state
// comes from the event instead.
const PLAN_QUERY = `query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    defaultBranchRef { name }
    pullRequest(number: $number) {
      body baseRefName isDraft state authorAssociation
      closingIssuesReferences(first: 100) {
        pageInfo { hasNextPage }
        nodes { number state body repository { nameWithOwner } labels(first: 100) { nodes { name } } } } } } }`;

// The one comment, kept by merge-plan runs alone, one at a time per PR.
// `update` returns the comment's id, or null when the PR needs none.
function mergePlanRunner({ gh, repo }) {
  const [owner, name] = repo.split('/');
  const sameRepo = (x) => x.repository.nameWithOwner.toLowerCase() === repo.toLowerCase();

  async function read(number) {
    const r = await gh.call('POST', '/graphql', { query: PLAN_QUERY, variables: { owner, name, number } });
    if (r.errors && r.errors.length) throw new Error(`GitHub GraphQL: ${r.errors[0].message}`);
    const { defaultBranchRef, pullRequest: pr } = r.data.repository;
    const conn = pr.closingIssuesReferences;
    if (conn.pageInfo.hasNextPage) throw new Error('more than 100 closing references: the merge plan is not updated');
    const filed = conn.nodes.filter((x) => eligible({ labels: x.labels.nodes, body: x.body }));
    return {
      state: pr.state === 'MERGED' ? 'merged' : pr.state === 'CLOSED' ? 'closedUnmerged' : 'open',
      body: pr.body, base: pr.baseRefName, draft: pr.isDraft, trusted: TRUSTED.has(pr.authorAssociation), defaultBranch: defaultBranchRef.name,
      closing: filed.filter(sameRepo).map((x) => ({ n: x.number, open: x.state === 'OPEN' })),
      listed: conn.nodes.filter(sameRepo).map((x) => x.number),
      crossRepo: filed.filter((x) => !sameRepo(x)).map((x) => ({ repo: x.repository.nameWithOwner, n: x.number, open: x.state === 'OPEN' })),
    };
  }

  // The bot issues among `ns` that `taken` does not hold yet. A number that
  // is no issue (404, or 410 for a deleted one) is passed over; a PR read
  // through the issues API is never a bot issue.
  async function lookUp(ns, taken) {
    const out = [];
    for (const n of ns) {
      if (taken.has(n)) continue;
      let issue;
      try {
        issue = await gh.getIssue(repo, n);
      } catch (e) {
        if (e.github && (e.github.status === 404 || e.github.status === 410)) continue;
        throw e;
      }
      // Reading a transferred issue follows GitHub's redirect, so the answer
      // is the issue in its new repo, no longer this repo's #n.
      if (issue.pull_request || !eligible(issue) || issue.html_url.toLowerCase() !== `https://github.com/${repo}/issues/${n}`.toLowerCase()) continue;
      taken.add(n);
      out.push({ n, open: issue.state === 'open' });
    }
    return out;
  }

  // Every marked comment by the bot, from every page. A create GitHub applied
  // after its call timed out can leave a second one; each is edited to the
  // same text at the next run.
  async function marked(number) {
    const out = [];
    for (let page = 1; ; page++) {
      const batch = await gh.call('GET', `/repos/${repo}/issues/${number}/comments?per_page=100&page=${page}`);
      out.push(...batch.filter((c) => c.user && c.user.login === BOT_LOGIN && c.body.includes(MARKER)));
      if (batch.length < 100) return out;
    }
  }

  // A read just after a close can still show the PR open, so a first attempt
  // passes the event's state; a re-run replays an old event and passes none.
  async function update(number, state) {
    const current = await read(number);
    const pr = { ...current, state: state || current.state };
    let { closing } = pr;
    const unlisted = [];
    const refs = [];
    const linked = [];
    if (pr.state === 'open') {
      // GitHub lists no closing references for a PR into another branch.
      if (pr.base !== pr.defaultBranch) closing = await lookUp(closingKeywordRefs(pr.body, repo), new Set());
      // Every number GitHub lists, bot issue or not, needs no read.
      const taken = new Set([...closing.map((c) => c.n), ...pr.listed]);
      // On the default base, a closing keyword GitHub does not list: a base
      // change alone does not make GitHub read the description again.
      if (pr.base === pr.defaultBranch) unlisted.push(...(await lookUp(closingKeywordRefs(pr.body, repo), taken)));
      refs.push(...(await lookUp(refsKeywordRefs(pr.body, repo), taken)));
      for (const post of threadLinks(pr.body)) {
        const issue = await gh.findByThread(repo, post);
        // The listing behind findByThread matches the label in any letter
        // case; the status job's rule wants it exact.
        if (!issue || !eligible(issue) || taken.has(issue.number)) continue;
        taken.add(issue.number);
        linked.push({ n: issue.number, open: issue.state === 'open' });
      }
    }
    const text = renderPlan({
      repo, defaultBranch: pr.defaultBranch, base: pr.base, draft: pr.draft, trusted: pr.trusted, state: pr.state,
      closing, unlisted, refs, linked, crossRepo: pr.crossRepo,
    });
    const existing = await marked(number);
    for (const c of existing) {
      if (c.body !== text) await gh.call('PATCH', `/repos/${repo}/issues/comments/${c.id}`, { body: text });
    }
    if (existing.length) return existing[0].id;
    // A merge GitHub lists as closing a bot issue here gets its merged text
    // even when no earlier run left a comment; a PR closed unmerged only
    // updates one.
    const shows = closing.length || unlisted.length || refs.length || linked.length || pr.crossRepo.length;
    const creates = pr.state === 'open' ? shows : pr.state === 'merged' && closing.length;
    if (!creates) return null;
    return (await gh.call('POST', `/repos/${repo}/issues/${number}/comments`, { body: text })).id;
  }

  return { update };
}

// One PR event's merge plan. It never throws: a failure is logged, and the
// job stays green.
export async function planRun({ payload, env, fetchImpl = fetch, log = console.log }) {
  // The bot token is the sign the bot is set up, as for the status job; the
  // plan itself calls no Discord API.
  if (!env.DISCORD_BOT_TOKEN) {
    log('DISCORD_BOT_TOKEN is not set: skipping the merge plan');
    return;
  }
  const f = timedFetch(fetchImpl, CALL_MS, Date.now() + PLAN_MS);
  const runner = mergePlanRunner({ gh: githubClient(env.GITHUB_TOKEN, f), repo: payload.repository.full_name });
  try {
    const p = payload.pull_request;
    const first = (Number(env.GITHUB_RUN_ATTEMPT) || 1) === 1;
    const id = await runner.update(p.number, first ? (p.merged ? 'merged' : p.state === 'closed' ? 'closedUnmerged' : 'open') : null);
    log(id ? `merge plan comment ${id} is up to date` : 'this PR needs no merge plan comment');
  } catch (e) {
    log(`merge plan comment not updated: ${e.message.slice(0, 300)}`);
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] || '').href) {
  await planRun({ payload: JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8')), env: process.env });
}
