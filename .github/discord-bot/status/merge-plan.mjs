// The merge-plan comment on a pull request that closes, references or links
// an issue the bot filed: which issues merging closes, and the bot's current
// message for each step. It links issues and copies no report.
import { MESSAGES, STATUS } from '../src/core.js';

export const MARKER = '<!-- discord-merge-plan -->';
const RELEASE_PLACEHOLDER = '(release tag)';
const KEYWORD = '(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)';
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
// `#N`, `owner/repo#N` for this repo, or this repo's issue URL, right after a
// keyword's whitespace; the only capturing group is the number.
const refIn = (repo) => `(?:#|${esc(repo)}#|https://github\\.com/${esc(repo)}/issues/)(\\d+)\\b`;
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
