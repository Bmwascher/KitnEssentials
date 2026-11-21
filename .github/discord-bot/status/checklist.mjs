// The staff checklist forum: one thread per bot issue in a staff-only forum,
// mirroring the issue. The thread's record is one bot comment on the issue.

const link = (guildId, threadId) => `https://discord.com/channels/${guildId}/${threadId}`;
const norm = (c) => String((c && c.body) || '').replace(/\r\n?/g, '\n');
const field = (body, name) => (new RegExp(`<!--\\s*discord-checklist-${name}:\\s*(.+?)\\s*-->`).exec(body) || [])[1] || null;

// The record. `state` is the thread's id, or `pending` (no thread yet) or
// `creating` (a create may have gone out). `forumId` is the forum the create
// was sent to, so a lost answer is searched for there; `since` is when that
// try began, `issueUrl` the issue's address then (a transfer changes it),
// and `archived` the key of the close the bot archived the thread for.
export function checklistBody({ state, guildId, forumId = '', since, issueUrl, archived = null }) {
  const thread = /^\d+$/.test(String(state));
  return [
    `Staff checklist thread: ${thread ? link(guildId, state) : 'opening'}`,
    '',
    `<!-- discord-checklist: ${state} guild: ${guildId || 'none'} -->`,
    ...(forumId ? [`<!-- discord-checklist-forum: ${forumId} -->`] : []),
    `<!-- discord-checklist-since: ${since} -->`,
    `<!-- discord-checklist-issue: ${issueUrl} -->`,
    ...(archived ? [`<!-- discord-checklist-archived: ${archived} -->`] : []),
  ].join('\n');
}

export function parseChecklist(c) {
  const body = norm(c);
  const m = /<!--\s*discord-checklist:\s*(\d+|pending|creating)\s+guild:\s*(\d+|none)\s*-->/.exec(body);
  if (!m) return null;
  const threadId = /^\d+$/.test(m[1]) ? m[1] : null;
  const guildId = m[2] === 'none' ? '' : m[2];
  return {
    id: c.id, url: c.html_url || '', state: m[1], threadId, guildId,
    // False for a thread id staff put in the marker by hand: the visible
    // line does not link it yet.
    linked: !!threadId && body.startsWith(`Staff checklist thread: ${link(guildId, threadId)}\n`),
    forumId: field(body, 'forum') || '', since: Number(field(body, 'since')) || 0, issueUrl: field(body, 'issue'), archived: field(body, 'archived'),
  };
}
