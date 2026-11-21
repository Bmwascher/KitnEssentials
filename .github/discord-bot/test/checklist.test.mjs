import test from 'node:test';
import assert from 'node:assert/strict';
import { checklistBody, parseChecklist } from '../status/checklist.mjs';
import { run } from '../status/status.mjs';
import { world, BOT_USER } from './fake-world.mjs';

const comment = (body, id = 5) => ({ id, body, html_url: `https://github.com/me/one/issues/17#issuecomment-${id}`, created_at: '2026-11-20T00:00:00Z' });

test('CH1: a checklist record reads back as written', () => {
  const url = 'https://github.com/me/one/issues/17';
  for (const [why, rec] of [
    ['pending', { state: 'pending', guildId: '', forumId: '', since: 1000, issueUrl: url }],
    ['creating, with its forum', { state: 'creating', guildId: '800', forumId: '950', since: 2000, issueUrl: url }],
    ['a thread, no key', { state: '123', guildId: '800', forumId: '950', since: 3000, issueUrl: url }],
    ['a thread archived for a close', { state: '123', guildId: '800', forumId: '950', since: 3000, issueUrl: url, archived: "Won't fix:77" }],
  ]) {
    const body = checklistBody(rec);
    for (const b of [body, body.replace(/\n/g, '\r\n')]) {
      const r = parseChecklist(comment(b));
      assert.deepEqual({ state: r.state, guildId: r.guildId, forumId: r.forumId, since: r.since, issueUrl: r.issueUrl, archived: r.archived },
        { archived: null, ...rec }, why);
      assert.equal(r.threadId, /^\d+$/.test(rec.state) ? rec.state : null, why);
      assert.equal(r.linked, !!r.threadId, why);
    }
  }
  const byHand = checklistBody({ state: 'creating', guildId: '800', forumId: '950', since: 1, issueUrl: url }).replace('discord-checklist: creating', 'discord-checklist: 123');
  assert.deepEqual([parseChecklist(comment(byHand)).threadId, parseChecklist(comment(byHand)).linked], ['123', false], 'an id put in by hand is not linked yet');
  assert.match(checklistBody({ state: '123', guildId: '800', since: 1, issueUrl: url }), /^Staff checklist thread: https:\/\/discord\.com\/channels\/800\/123\n/);
  assert.match(checklistBody({ state: 'pending', guildId: '', since: 1, issueUrl: url }), /^Staff checklist thread: opening\n/);
  assert.equal(parseChecklist(comment('Notification attempted: x\n\n<!-- discord-told: fixed-a -->')), null, 'a message note is no record');
});

// ---- The thread follows GitHub ----------------------------------------------------

const DAY = 24 * 60 * 60 * 1000;
const env = { GITHUB_TOKEN: 'gh', DISCORD_BOT_TOKEN: 'bot', RELEASE_TAG_PATTERN: '^v\\d', CHECKLIST_FORUM_ID: '950' };
const repository = { full_name: 'me/one', default_branch: 'dev' };
const go = (w, eventName, payload, over = {}, out = []) => run({
  eventName, payload: { repository, ...payload }, env: { ...env, ...over }, fetchImpl: w.fetch, log: (s) => out.push(s), now: () => w.clock,
});
// The checklist job for an issue event.
const job = (w, action = 'opened', { n = 17, extra = {}, out = [], over = {} } = {}) => go(w, 'issues', { action, issue: { number: n }, ...extra }, { CHECKLIST_ONLY: '1', ...over }, out);
const label = { extra: { label: { name: 'accepted' } } };
const pr = (w, number, action = 'opened') => go(w, 'pull_request_target', { action, pull_request: { number } });
const tagPush = (w, name, over = {}, out = []) => go(w, 'push', { ref: `refs/tags/${name}`, created: true, after: `obj-${name}`, head_commit: { id: `c-${name}` } }, over, out);
const ckThreads = (w) => [...w.threads.values()].filter((t) => t.parent_id === '950');
const ours = (w) => ckThreads(w).filter((t) => t.starter && t.starter.author.id === BOT_USER);
const ckName = (w, t) => t.applied_tags.map((id) => (w.ckForum.available_tags.find((x) => x.id === id) || {}).name).filter(Boolean);
const botComments = (w, n) => w.issues.get(n).comments.filter((c) => c.user.login === 'github-actions[bot]');
const recordOf = (w, n = 17) => botComments(w, n).map(parseChecklist).find(Boolean) || null;
const closeId = (w, n = 17) => w.issues.get(n).events.filter((e) => e.event === 'closed').at(-1).id;
const threadUrl = (id) => new RegExp(`discord\\.com/api/v10/channels/${id}$`);
// A checklist thread the bot opened for #n, with its record on the issue.
function seed(w, n = 17, over = {}, key = null) {
  const t = w.ckThread(n, over);
  w.record(n, checklistBody({ state: t.id, guildId: '800', since: w.clock, issueUrl: `https://github.com/me/one/issues/${n}`, archived: key }));
  return t;
}
const fail500 = () => new Response('{"message":"x"}', { status: 500 });
// The next PATCH of the thread whose body `when` picks answers `status` and changes nothing, once.
function failPatch(w, id, when, status = 500) {
  let done = false;
  w.hooks.push(['PATCH', threadUrl(id), async (call) => {
    if (done || !when(call.body)) return;
    done = true;
    w.fail.push(['PATCH', threadUrl(id), new Response('{"message":"x"}', { status }), 1]);
  }]);
}
// The next PATCH of the thread whose body `when` picks lands, and its answer is lost (500), once.
function landThenFail(w, id, when) {
  let done = false;
  w.hooks.push(['PATCH', threadUrl(id), async (call) => {
    if (done || !when(call.body)) return;
    done = true;
    const t = w.threads.get(id);
    if (call.body.applied_tags) t.applied_tags = call.body.applied_tags;
    if (call.body.archived === false) t.archived = false;
    if (call.body.archived === true) {
      t.archived = true;
      t.archivedAt = w.clock;
    }
    w.fail.push(['PATCH', threadUrl(id), fail500(), 1]);
  }]);
}
// The next comment edit whose body `when` picks answers 500, once.
function failRecord(w, when) {
  let done = false;
  const re = /api\.github\.com\/repos\/me\/one\/issues\/comments\/\d+$/;
  w.hooks.push(['PATCH', re, async (call) => {
    if (done || !when(call.body.body)) return;
    done = true;
    w.fail.push(['PATCH', re, fail500(), 1]);
  }]);
}
// No call sits between a checklist thread's last read and its tag write.
function readThenWrite(w) {
  w.calls.forEach((c, i) => {
    const m = c.method === 'PATCH' && c.body && c.body.applied_tags && /discord\.com\/api\/v10\/channels\/(\d+)$/.exec(c.url);
    if (!m || !w.threads.has(m[1]) || w.threads.get(m[1]).parent_id !== '950') return;
    const prev = w.calls[i - 1];
    assert.equal(`${prev.method} ${prev.url}`, `GET https://discord.com/api/v10/channels/${m[1]}`, 'the thread read comes just before its tag write');
  });
}

test('CH4: the thread follows GitHub through a PR, its merge, a release, each close and a reopen, and keeps a staff tag', async () => {
  const w = world();
  w.issue(17);
  const t = seed(w, 17, { applied_tags: ['c-tri', 'c-staff'] });
  w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17] });
  await pr(w, 5);
  assert.deepEqual(ckName(w, t), ['Needs QA', 'In progress'], 'a PR');
  w.prs.get(5).state = 'MERGED';
  w.close(17, 'completed', 'aaaaaaa1');
  await job(w, 'closed');
  assert.deepEqual([ckName(w, t), t.archived], [['Needs QA', 'Fixed'], false], 'a merge');
  w.tags = [{ name: 'v5.0.1', commit: { sha: 'c-v5.0.1' } }];
  w.contains.set('aaaaaaa1...c-v5.0.1', 'ahead');
  await tagPush(w, 'v5.0.1');
  assert.deepEqual([ckName(w, t), t.archived], [['Needs QA', 'Shipped'], true], 'a release');
  for (const [reason, want] of [['completed', 'Done'], ['not_planned', "Won't fix"], ['duplicate', 'Duplicate']]) {
    Object.assign(w.issues.get(17), { state: 'open', state_reason: 'reopened' });
    await job(w, 'reopened');
    assert.deepEqual([ckName(w, t), t.archived], [['Needs QA', 'Triaged'], false], `a reopen before ${reason}`);
    w.close(17, reason);
    await job(w, 'closed');
    assert.deepEqual([ckName(w, t), t.archived], [['Needs QA', want], true], reason);
  }
  readThenWrite(w);
});

test('CH4: Accepted follows the label on an open issue, only into a free slot, and a full thread keeps every staff tag', async () => {
  const w = world();
  const i = w.issue(17);
  const t = seed(w, 17, { applied_tags: ['c-tri'] });
  i.labels.add('accepted');
  await job(w, 'labeled', label);
  assert.deepEqual(ckName(w, t), ['Triaged', 'Accepted'], 'labeled');
  i.labels.delete('accepted');
  await job(w, 'unlabeled', label);
  assert.deepEqual(ckName(w, t), ['Triaged'], 'unlabeled');
  i.labels.add('accepted');
  await job(w, 'labeled', label);
  w.close(17, 'not_planned');
  await job(w, 'closed');
  assert.deepEqual(ckName(w, t), ["Won't fix"], 'closed while labeled');
  readThenWrite(w);
  {
    // GitHub label names match in any case, as the workflow's `if` does.
    const u = world();
    u.issue(17).labels.add('Accepted');
    const s = seed(u, 17, { applied_tags: ['c-tri'] });
    await job(u, 'labeled', { extra: { label: { name: 'Accepted' } } });
    assert.deepEqual(ckName(u, s), ['Triaged', 'Accepted'], 'the label in another letter case');
  }

  for (const [why, applied, labeled, forumLacks, line] of [
    ['no free slot for Accepted', ['c-staff', 'c-s2', 'c-s3', 'c-s4', 'c-tri'], true, null, /#17: no free tag slot for Accepted on the checklist thread/],
    ['five staff tags and no status', ['c-staff', 'c-s2', 'c-s3', 'c-s4', 'c-s5'], false, null, /#17: no free tag slot for "Triaged" on the checklist thread/],
    ['a forum with no Accepted tag', ['c-tri'], true, 'Accepted', /#17: the checklist forum has no Accepted tag/],
  ]) {
    const v = world();
    if (labeled) v.issue(17).labels.add('accepted');
    else v.issue(17);
    if (forumLacks) v.ckForum.available_tags = v.ckForum.available_tags.filter((x) => x.name !== forumLacks);
    const u = seed(v, 17, { applied_tags: [...applied] });
    const out = [];
    await job(v, labeled ? 'labeled' : 'reopened', { ...(labeled ? label : {}), out });
    assert.deepEqual(u.applied_tags, applied, `${why}: no tag dropped`);
    assert.match(out.join('\n'), line, why);
  }
});

test('CH4: a tag staff add while the bot reads the forum is kept, and a record in another account\'s comment is not the bot\'s', async () => {
  const w = world();
  w.issue(17);
  const t = seed(w, 17, { applied_tags: ['c-tri'] });
  w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17] });
  let added = false;
  w.hooks.push(['GET', /discord\.com\/api\/v10\/channels\/950$/, async () => {
    if (added) return;
    added = true;
    t.applied_tags.push('c-staff');
  }]);
  await pr(w, 5);
  assert.deepEqual(ckName(w, t), ['Needs QA', 'In progress']);
  readThenWrite(w);

  // The status tag is taken from the forum between the write and the read-back.
  const x = world();
  x.issue(17);
  const s = seed(x, 17, { applied_tags: ['c-tri'] });
  x.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17] });
  let taken = false;
  x.hooks.push(['PATCH', threadUrl(s.id), async () => {
    if (taken) return;
    taken = true;
    x.ckForum.available_tags = x.ckForum.available_tags.filter((tag) => tag.name !== 'In progress');
  }]);
  const out = [];
  await assert.rejects(go(x, 'pull_request_target', { action: 'opened', pull_request: { number: 5 } }, {}, out), /checklist thread\(s\) not updated for #17/);
  assert.match(out.join('\n'), /#17: staff checklist: checklist forum has no "In progress" tag/, 'the read-back sees the tag gone');
  readThenWrite(x);

  const v = world();
  v.issue(17);
  const u = v.ckThread(17, { applied_tags: ['c-tri'] });
  v.record(17, checklistBody({ state: u.id, guildId: '800', since: v.clock, issueUrl: 'https://github.com/me/one/issues/17' }), 'someone');
  v.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17] });
  await pr(v, 5);
  assert.deepEqual(ckName(v, u), ['Triaged'], 'a copied marker is not the bot\'s record');

  // Staff put another thread's id in the marker while a run is under way:
  // the run writes nothing, and the new id is never saved as linked.
  const y = world();
  y.issue(17);
  y.close(17, 'not_planned');
  const a = seed(y, 17, { applied_tags: ['c-tri'] });
  const b = y.ckThread(99);
  let swapped = false;
  y.hooks.push(['GET', /api\.github\.com\/repos\/me\/one\/issues\/comments\/\d+$/, async () => {
    if (swapped) return;
    swapped = true;
    const c = botComments(y, 17).find((x) => parseChecklist(x));
    c.body = c.body.replace(`discord-checklist: ${a.id}`, `discord-checklist: ${b.id}`);
  }]);
  await assert.rejects(job(y, 'closed'), /the staff checklist record changed during this run/);
  const after = recordOf(y);
  assert.deepEqual([after.threadId, after.linked, y.find('PATCH', threadUrl(a.id)).length, y.find('PATCH', threadUrl(b.id)).length], [b.id, false, 0, 0]);

  // The same change landing after the archive, just before the key save:
  // the save reads the record first and writes nothing over the change.
  const z = world();
  z.issue(17);
  z.close(17, 'not_planned');
  const p = seed(z, 17, { applied_tags: ['c-wont'] });
  const q = z.ckThread(99);
  let moved = false;
  z.hooks.push(['PATCH', threadUrl(p.id), async (call) => {
    if (moved || call.body.archived !== true) return;
    moved = true;
    const c = botComments(z, 17).find((x) => parseChecklist(x));
    c.body = c.body.replace(`discord-checklist: ${p.id}`, `discord-checklist: ${q.id}`);
  }]);
  await assert.rejects(job(z, 'closed'), /the staff checklist record changed during this run/);
  assert.deepEqual([recordOf(z).threadId, recordOf(z).linked], [q.id, false], 'the staff change stands');
});

// ---- Archiving ----------------------------------------------------------------------

test('CH5: a failed archive, or a failed key save after it, is put right by the next job', async () => {
  for (const [why, fail, afterFirst] of [
    ['the archive write fails', (w, t) => failPatch(w, t.id, (b) => b.archived === true), [false, null]],
    ['the key save fails', (w) => failRecord(w, (b) => /discord-checklist-archived/.test(b)), [true, null]],
  ]) {
    const w = world();
    w.issue(17);
    const t = seed(w, 17, { applied_tags: ['c-tri'] });
    w.close(17, 'not_planned');
    fail(w, t);
    await assert.rejects(job(w, 'closed'), /checklist thread not updated for #17/, why);
    assert.deepEqual([t.archived, recordOf(w).archived], afterFirst, why);
    const writes = w.find('PATCH', threadUrl(t.id)).length;
    await job(w, 'closed');
    assert.deepEqual([t.archived, recordOf(w).archived], [true, `Won't fix:${closeId(w)}`], `${why}: the next job puts it right`);
    if (why === 'the key save fails') assert.equal(w.find('PATCH', threadUrl(t.id)).length, writes, `${why}: no second archive write`);
    readThenWrite(w);
  }
});

test('CH5: a staff reopen stays open until the issue closes again, and an archive for a close a reopen overtook is undone', async () => {
  const w = world();
  const i = w.issue(17);
  const t = seed(w, 17, { applied_tags: ['c-tri'] });
  w.close(17, 'not_planned');
  await job(w, 'closed');
  assert.equal(t.archived, true);
  // A staff reply opens the thread; a stale Accepted tag gives a repair to make.
  t.archived = false;
  t.applied_tags = ['c-wont', 'c-acc'];
  await job(w, 'labeled', label);
  assert.deepEqual([ckName(w, t), t.archived], [["Won't fix"], false], 'a job with no new close, and a tag repair, leave it open');
  Object.assign(i, { state: 'open', state_reason: 'reopened' });
  await job(w, 'reopened');
  w.close(17, 'not_planned');
  await job(w, 'closed');
  assert.equal(t.archived, true, 'closed again for the same reason: archived again');
  // The issue reopens; a release run then archives the thread for the old close.
  Object.assign(i, { state: 'open', state_reason: 'reopened' });
  await job(w, 'reopened');
  const rec = botComments(w, 17).find((c) => parseChecklist(c));
  rec.body = checklistBody({ ...parseChecklist(rec), archived: `Won't fix:${closeId(w)}` });
  t.archived = true;
  await job(w, 'labeled', label);
  assert.deepEqual([ckName(w, t), t.archived, recordOf(w).archived], [['Triaged'], false, null], 'the late archive is undone');
  readThenWrite(w);
});

test('CH5: a bot tag change keeps the archive state, and a write that may have left a finished thread open leaves its archive owed', async () => {
  // An open issue's thread archived for inactivity stays archived through a PR's retag and a label's.
  {
    const w = world();
    const i = w.issue(17);
    const t = seed(w, 17, { applied_tags: ['c-tri'], archived: true });
    w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17] });
    await pr(w, 5);
    assert.deepEqual([ckName(w, t), t.archived], [['In progress'], true], 'a PR');
    i.labels.add('accepted');
    await job(w, 'labeled', label);
    assert.deepEqual([ckName(w, t), t.archived], [['In progress', 'Accepted'], true], 'a label');
    readThenWrite(w);
  }
  // The same, with the retag landing and its answer lost: the re-archive still goes out.
  {
    const w = world();
    w.issue(17);
    const t = seed(w, 17, { applied_tags: ['c-tri'], archived: true });
    w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17] });
    landThenFail(w, t.id, (b) => b.archived === false);
    await assert.rejects(pr(w, 5), /checklist thread\(s\) not updated for #17/);
    assert.deepEqual([ckName(w, t), t.archived], [['In progress'], true], 'an inactive thread is archived again');
    readThenWrite(w);
  }
  // A finished, archived thread whose Accepted tag is stale stays archived.
  {
    const w = world();
    w.issue(17);
    w.close(17, 'not_planned');
    const t = seed(w, 17, { applied_tags: ['c-wont', 'c-acc'], archived: true }, `Won't fix:${closeId(w)}`);
    await job(w, 'closed');
    assert.deepEqual(w.find('PATCH', threadUrl(t.id)).map((c) => c.body), [{ applied_tags: ['c-wont'], archived: false }, { archived: true }]);
    assert.equal(t.archived, true);
    readThenWrite(w);
  }
  // A failed write to a finished, archived thread: the run fails; the key is
  // cleared only when the thread may be left open, so a refusal, or a
  // re-archive that landed, never lets a later staff reply be archived over;
  // the next job settles it.
  for (const [why, fail, keyKept] of [
    ['the re-archive fails', (w, t) => failPatch(w, t.id, (b) => b.archived === true), false],
    ['the re-archive lands, its answer lost: the read after it shows it archived', (w, t) => landThenFail(w, t.id, (b) => b.archived === true), true],
    ['the re-archive fails, and so does the read after it', (w, t) => {
      failPatch(w, t.id, (b) => b.archived === true);
      let once = false;
      w.hooks.push(['PATCH', threadUrl(t.id), async (call) => {
        if (once || call.body.archived !== true) return;
        once = true;
        w.fail.push(['GET', threadUrl(t.id), fail500(), 1]);
      }]);
    }, false],
    ['the tag write lands, its answer lost: the re-archive still goes out', (w, t) => landThenFail(w, t.id, (b) => b.archived === false), true],
    ['the tag write lands, its answer lost, and the re-archive fails', (w, t) => {
      landThenFail(w, t.id, (b) => b.archived === false);
      failPatch(w, t.id, (b) => b.archived === true);
    }, false],
    ['Discord refuses the tag write', (w, t) => failPatch(w, t.id, (b) => b.archived === false, 403), true],
  ]) {
    const w = world();
    w.issue(17);
    w.close(17, 'not_planned');
    const key = `Won't fix:${closeId(w)}`;
    const t = seed(w, 17, { applied_tags: ['c-wont', 'c-acc'], archived: true }, key);
    fail(w, t);
    await assert.rejects(job(w, 'closed'), /checklist thread not updated for #17/, why);
    assert.deepEqual([t.archived, recordOf(w).archived], keyKept ? [true, key] : [false, null], why);
    await job(w, 'closed');
    assert.deepEqual([ckName(w, t), t.archived, recordOf(w).archived], [["Won't fix"], true, key], `${why}: the next job settles it`);
    readThenWrite(w);
  }
  // A closed issue whose close event the read does not show yet: no write, and the archive stays.
  {
    const w = world();
    const i = w.issue(17);
    w.close(17, 'not_planned');
    const key = `Won't fix:${closeId(w)}`;
    const t = seed(w, 17, { applied_tags: ['c-wont'], archived: true }, key);
    i.events = [];
    await assert.rejects(job(w, 'closed'), /the issue is closed but its close event is not readable yet/);
    assert.deepEqual([w.find('PATCH', threadUrl(t.id)), t.archived, recordOf(w).archived], [[], true, key]);
  }
  // Closed again after a reopen, while the event list lags: the earlier
  // close is older than the issue's close time, or a listed reopen came
  // after it, so it is not taken for the current one, and a thread staff
  // reopened after its archive is left as it is.
  for (const [why, lagging, gap] of [
    ['the new close is not listed yet', 1, 5 * 60 * 1000],
    ['the reopen and the new close are not listed yet', 2, 5 * 60 * 1000],
    // Inside the close-time slack only the listed reopen tells the two closes apart.
    ['closed again 15 s later, the new close not listed yet', 1, 15 * 1000],
  ]) {
    const w = world();
    const i = w.issue(17);
    w.close(17, 'not_planned');
    const key = `Won't fix:${closeId(w)}`;
    const t = seed(w, 17, { applied_tags: ['c-wont'] }, key);
    w.clock += gap;
    i.events.push({ id: 990001, event: 'reopened', created_at: new Date(w.clock).toISOString() });
    w.close(17, 'not_planned');
    i.events.splice(-lagging);
    await assert.rejects(job(w, 'closed'), /the issue is closed but its close event is not readable yet/, why);
    assert.deepEqual([w.find('PATCH', threadUrl(t.id)), t.archived, recordOf(w).archived], [[], false, key], why);
  }
  // The forum lacks the needed status tag: no tag write, and the archive still follows GitHub.
  {
    const w = world();
    w.issue(17);
    w.close(17, 'not_planned');
    w.ckForum.available_tags = w.ckForum.available_tags.filter((x) => x.name !== "Won't fix");
    const t = seed(w, 17, { applied_tags: ['c-tri', 'c-acc'], archived: true });
    await assert.rejects(job(w, 'closed'), /checklist forum has no "Won't fix" tag/);
    assert.deepEqual(w.find('PATCH', threadUrl(t.id)), [], 'no write to the thread');
    assert.deepEqual([t.applied_tags, t.archived, recordOf(w).archived], [['c-tri', 'c-acc'], true, `Won't fix:${closeId(w)}`]);
  }
});

// ---- Never in the way ---------------------------------------------------------------

test('CH7: a checklist failure never stops the player\'s message, and fails the run at its end', async () => {
  for (const [why, setup, line] of [
    // The error body names a staff tag: only the request and its status reach the log.
    ['no access to the forum', (w) => w.fail.push(['GET', /discord\.com\/api\/v10\/channels\/950$/, new Response('{"message":"Missing Access","tag":"Needs QA"}', { status: 403 }), 99]), /-> 403/],
    // An answer that is not JSON keeps the bot's note on it, and never its body.
    ['the forum answers with no JSON', (w) => w.fail.push(['GET', /discord\.com\/api\/v10\/channels\/950$/, new Response('<html>Needs QA</html>', { status: 200 }), 99]), /-> 200 \(the answer was not JSON\)/],
    ['the forum lacks the Shipped tag', (w) => { w.ckForum.available_tags = w.ckForum.available_tags.filter((x) => x.name !== 'Shipped'); }, /checklist forum has no "Shipped" tag/],
    ['the thread was deleted', (w, t) => w.threads.delete(t.id), /staff checklist thread is gone/],
  ]) {
    const w = world();
    w.issue(17, { labels: ['from-discord', 'pending-release'] });
    w.close(17, 'completed', 'aaaaaaa1');
    const t = seed(w, 17, { applied_tags: ['c-fix'] });
    setup(w, t);
    w.tags = [{ name: 'v5.0.1', commit: { sha: 'c-v5.0.1' } }];
    w.contains.set('aaaaaaa1...c-v5.0.1', 'ahead');
    const out = [];
    await assert.rejects(tagPush(w, 'v5.0.1', { GITHUB_RUN_ID: '555' }, out), /checklist thread\(s\) not updated for #17/, why);
    assert.match(out.join('\n'), line, why);
    assert.doesNotMatch(out.join('\n'), /Needs QA/, `${why}: no staff tag name in the log`);
    const outNow = () => w.said('717').filter((m) => /Out now in/.test(m)).length;
    assert.equal(outNow(), 1, `${why}: the player is told`);
    assert.ok(w.issues.get(17).comments.some((c) => /^Delivery confirmed: \*\*Out now/.test(c.body)), `${why}: and the note confirms it`);
    await assert.rejects(tagPush(w, 'v5.0.1', { GITHUB_RUN_ID: '555', GITHUB_RUN_ATTEMPT: '2' }), /checklist/, why);
    assert.equal(outNow(), 1, `${why}: a re-run sends nothing twice`);
  }
});

test('CH7: a release run settles the thread when its ship record fails, and names both failure lists when both fail', async () => {
  for (const [why, setup, want, settled] of [
    ['the ship record write fails', (w) => w.fail.push(['POST', /issues\/17\/comments$/, fail500(), 1]),
      /^could not update issue\(s\) #17; see above$/, true],
    // The run's own compare proves the tag holds the fix; its proof stands in.
    ['the ship record write fails while the tag list does not show the tag yet', (w) => {
      w.tags = [];
      w.fail.push(['POST', /issues\/17\/comments$/, fail500(), 1]);
    }, /^could not update issue\(s\) #17; see above$/, true],
    // The release lookup (the run's first GraphQL call) fails after the
    // compare: the proof saved at the compare still shows Shipped.
    ['the release lookup fails', (w) => w.fail.push(['POST', /graphql$/, fail500(), 1]),
      /^could not update issue\(s\) #17; see above$/, true],
    ['the post and the checklist both fail', (w) => {
      w.fail.push(['GET', /discord\.com\/api\/v10\/channels\/717$/, fail500(), 99]);
      w.fail.push(['GET', /discord\.com\/api\/v10\/channels\/950$/, new Response('{"message":"Missing Access"}', { status: 403 }), 99]);
    }, /^could not update issue\(s\) #17; see above; checklist thread\(s\) not updated for #17; see above$/, false],
  ]) {
    const w = world();
    w.issue(17, { labels: ['from-discord', 'pending-release'] });
    w.close(17, 'completed', 'aaaaaaa1');
    const t = seed(w, 17, { applied_tags: ['c-fix'] });
    w.tags = [{ name: 'v5.0.1', commit: { sha: 'c-v5.0.1' } }];
    w.contains.set('aaaaaaa1...c-v5.0.1', 'ahead');
    setup(w);
    await assert.rejects(tagPush(w, 'v5.0.1'), (e) => want.test(e.message), why);
    if (settled) assert.deepEqual([ckName(w, t), t.archived], [['Shipped'], true], `${why}: the thread is still settled`);
  }
});

test('CH7: a failed first issue read on a PR run, or a failed owed-note scan on a re-run, still leaves the thread settled', async () => {
  {
    const w = world();
    w.issue(17);
    const t = seed(w, 17, { applied_tags: ['c-tri'] });
    w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17] });
    w.fail.push(['GET', /api\.github\.com\/repos\/me\/one\/issues\/17$/, fail500(), 1]);
    await assert.rejects(pr(w, 5), /could not update issue\(s\) #17; see above/);
    assert.deepEqual(ckName(w, t), ['In progress'], 'the PR run\'s first read failed');
  }
  {
    // The PR's linked issue is already closed: the player side leaves it, the checklist does not.
    const w = world();
    w.issue(17);
    w.close(17, 'completed', 'aaaaaaa1');
    const t = seed(w, 17, { applied_tags: ['c-tri'] });
    w.prs.set(5, { author_association: 'MEMBER', state: 'MERGED', closes: [17] });
    await pr(w, 5, 'closed');
    assert.deepEqual(ckName(w, t), ['Fixed'], 'a closed linked issue');
  }
  {
    const w = world();
    w.issue(17, { labels: ['from-discord', 'pending-release'] });
    w.close(17, 'completed', 'aaaaaaa1');
    const t = seed(w, 17, { applied_tags: ['c-fix'] });
    w.tags = [{ name: 'v5.0.1', commit: { sha: 'c-v5.0.1' } }];
    w.contains.set('aaaaaaa1...c-v5.0.1', 'ahead');
    // The re-run's scan is the run's only read of every from-discord issue.
    w.fail.push(['GET', /issues\?state=all&.*labels=from-discord/, fail500(), 1]);
    await assert.rejects(tagPush(w, 'v5.0.1', { GITHUB_RUN_ID: '555', GITHUB_RUN_ATTEMPT: '2' }), /the re-run's owed-note scan failed/);
    assert.deepEqual([ckName(w, t), t.archived], [['Shipped'], true], 'the re-run\'s scan failed');
  }
});

test('CH2: a re-run of the checklist job sends nothing, though its run owes a player message on another issue', async () => {
  const w = world();
  w.issue(17);
  seed(w, 17, { applied_tags: ['c-tri'] });
  w.issue(18);
  w.close(18, 'completed', 'aaaaaaa1');
  w.record(18, 'Notification attempted: **Fixed!** x\n\n<!-- discord-told: fixed-aaaaaaa1 -->\n<!-- discord-told-status: Fixed, next update -->\n<!-- discord-told-run: 555 -->');
  await job(w, 'reopened', { over: { GITHUB_RUN_ID: '555', GITHUB_RUN_ATTEMPT: '2' } });
  assert.deepEqual(w.said('718'), []);
});

test('CH2: with the forum set, the checklist job makes no call for any event but its own', async () => {
  for (const [why, eventName, payload] of [
    ['a PR event', 'pull_request_target', { action: 'opened', pull_request: { number: 5 } }],
    ['another label', 'issues', { action: 'labeled', issue: { number: 17 }, label: { name: 'needs-info' } }],
    ['an unlabeled event with no label', 'issues', { action: 'unlabeled', issue: { number: 17 } }],
    ['an edited issue', 'issues', { action: 'edited', issue: { number: 17 } }],
  ]) {
    const w = world();
    w.issue(17);
    const out = [];
    await go(w, eventName, payload, { CHECKLIST_ONLY: '1' }, out);
    assert.deepEqual(w.calls, [], why);
    assert.match(out.join('\n'), /not a checklist event/, why);
  }
});

// ---- Opening ----------------------------------------------------------------------

test('CH2: the checklist job opens one thread for a filed issue, with its record and first message, and a second job opens nothing', async () => {
  const w = world();
  w.issue(17, { labels: ['from-discord', 'type: bug', 'client: retail'], title: '[KE][Retail][Bags] Bank *tab* icons' });
  await job(w);
  await job(w);
  assert.equal(ckThreads(w).length, 1);
  const t = ckThreads(w)[0];
  assert.equal(t.name, '#17 [KE][Retail][Bags] Bank *tab* icons');
  assert.deepEqual(ckName(w, t), ['Triaged']);
  assert.equal(t.starter.content, [
    '**\\[KE\\]\\[Retail\\]\\[Bags\\] Bank \\*tab\\* icons**',
    'Issue: https://github.com/me/one/issues/17',
    'Player post: https://discord.com/channels/800/717',
    'type: bug · client: retail',
    'The bot sets the status and Accepted tags from GitHub; every other tag is yours.',
  ].join('\n'));
  assert.deepEqual(t.starter.allowed_mentions, { parse: [] });
  const rec = recordOf(w);
  assert.deepEqual([rec.threadId, rec.guildId], [t.id, '800']);
  assert.match(botComments(w, 17).find((c) => c.id === rec.id).body, new RegExp(`^Staff checklist thread: https://discord\\.com/channels/800/${t.id}\\n`));
});

test('CH2: only the checklist job opens a thread; the status job, a PR run and a release run update one that exists', async () => {
  const w = world();
  w.issue(17);
  w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17] });
  await go(w, 'issues', { action: 'opened', issue: { number: 17 } });
  await pr(w, 5);
  assert.equal(ckThreads(w).length, 0, 'the status job and a PR run open nothing');
  await job(w);
  const t = ckThreads(w)[0];
  assert.deepEqual(ckName(w, t), ['In progress'], 'opened in step with GitHub as it is');
  w.prs.get(5).state = 'MERGED';
  w.close(17, 'completed', 'aaaaaaa1');
  // A released issue with no record: the release opens nothing for it.
  w.issue(18);
  w.close(18, 'completed', 'bbbbbbb1');
  w.tags = [{ name: 'v5.0.1', commit: { sha: 'c-v5.0.1' } }];
  w.contains.set('aaaaaaa1...c-v5.0.1', 'ahead');
  w.contains.set('bbbbbbb1...c-v5.0.1', 'ahead');
  await tagPush(w, 'v5.0.1');
  assert.deepEqual([ckName(w, t), t.archived], [['Shipped'], true], 'a release moves it to Shipped and archives it');
  assert.deepEqual([recordOf(w, 18), ckThreads(w).length], [null, 1], 'and opens no thread for an issue with none');
});

test('CH2: with the forum unset, a non-bot issue, a missing status tag or a refused create, no thread is opened', async () => {
  {
    const w = world();
    w.issue(17);
    await job(w, 'opened', { over: { CHECKLIST_FORUM_ID: '' } });
    assert.deepEqual(w.calls, [], 'unset');
  }
  {
    const w = world();
    w.issue(17, { labels: [] });
    await job(w);
    assert.deepEqual(w.calls.map((c) => `${c.method} ${c.url}`), ['GET https://api.github.com/repos/me/one/issues/17'], 'a non-bot issue is read no further');
  }
  {
    const w = world();
    w.issue(17);
    w.ckForum.available_tags = w.ckForum.available_tags.filter((x) => x.name !== 'Triaged');
    await assert.rejects(job(w), /checklist forum has no "Triaged" tag/);
    assert.equal(ckThreads(w).length, 0, 'a missing status tag');
  }
  {
    const w = world();
    w.issue(17);
    w.fail.push(['POST', /channels\/950\/threads$/, new Response('{"message":"x"}', { status: 400 }), 1]);
    await assert.rejects(job(w), /-> 400/);
    assert.equal(recordOf(w).state, 'pending', 'a refused create made nothing');
    await job(w);
    assert.equal(ckThreads(w).length, 1);
    assert.equal(w.find('GET', /threads\/active$/).length, 0, 'the next job opens at once, with no search');
  }
  {
    // A refused create whose set-back write fails too: the refusal's cause,
    // which may name the permission to fix, is kept beside it.
    const w = world();
    w.issue(17);
    w.fail.push(['POST', /channels\/950\/threads$/, new Response('{"message":"x"}', { status: 403 }), 1]);
    failRecord(w, (b) => /discord-checklist: pending/.test(b));
    await assert.rejects(job(w), /-> 403; setting the record back to pending failed too: /);
    assert.equal(recordOf(w).state, 'creating');
  }
});

test('CH2: a forum setting with spaces around its id is read as the id', async () => {
  const w = world();
  w.issue(17);
  await job(w, 'opened', { over: { CHECKLIST_FORUM_ID: ' 950 ' } });
  assert.deepEqual([ckThreads(w).length, recordOf(w).forumId], [1, '950']);
});

test('CH2: every checklist job settles the whole thread, whatever event started it', async () => {
  {
    const w = world();
    const i = w.issue(17);
    const t = seed(w, 17, { applied_tags: ['c-tri'] });
    w.close(17, 'not_planned');
    i.labels.add('accepted');
    await job(w, 'labeled', label);
    assert.deepEqual([ckName(w, t), t.archived], [["Won't fix"], true], 'a close whose job was dropped for a label\'s');
  }
  {
    const w = world();
    const i = w.issue(17);
    w.close(17, 'not_planned');
    const t = seed(w, 17, { applied_tags: ['c-wont'], archived: true }, `Won't fix:${closeId(w)}`);
    Object.assign(i, { state: 'open', state_reason: 'reopened' });
    i.labels.add('accepted');
    await job(w, 'labeled', label);
    assert.deepEqual([ckName(w, t), t.archived], [['Triaged', 'Accepted'], false], 'a reopen whose job was dropped for a label\'s');
  }
  {
    const w = world();
    const i = w.issue(17);
    w.close(17, 'not_planned');
    i.labels.add('accepted');
    await job(w, 'labeled', label);
    const t = ckThreads(w)[0];
    assert.deepEqual([ckName(w, t), t.archived, recordOf(w).archived], [["Won't fix"], true, `Won't fix:${closeId(w)}`], 'a label job on a closed issue with no thread');
  }
  {
    const w = world();
    w.issue(17);
    w.close(17, 'completed', 'aaaaaaa1');
    w.tags = [{ name: 'v5.0.1', commit: { sha: 'c-v5.0.1' } }];
    w.contains.set('aaaaaaa1...c-v5.0.1', 'ahead');
    await job(w, 'closed');
    assert.deepEqual(ckName(w, ckThreads(w)[0]), ['Shipped']);
    assert.equal(w.issues.get(17).comments.filter((c) => /discord-shipped-in/.test(c.body)).length, 0, 'no ship record written');
  }
});

// ---- A lost create answer -----------------------------------------------------------

// The thread is made, and the record write that saves its id fails.
const loseAnswer = (w) => failRecord(w, (b) => /<!-- discord-checklist: \d+ guild/.test(b));
const failArchived = (w, times = 99) => w.fail.push(['GET', /threads\/archived\/public/, fail500(), times]);
const staffStarter = (content = 'staff') => ({ starter: { author: { id: '5' }, content } });
const hangUp = (w, times = 1) => w.fail.push(['POST', /channels\/950\/threads$/, new Error('socket hang up'), times]);

test('CH3: a job that lost its create answer is followed by one that finds the thread by its first message', async () => {
  for (const [why, between, refused] of [
    ['active and unrenamed', () => {}],
    ['renamed', (w, t) => { t.name = 'renamed by staff'; }],
    ['archived', (w, t) => { t.archived = true; t.archivedAt = w.clock; }],
    ['a day later', (w) => { w.clock += DAY; }],
    ['the issue transferred since', (w) => { w.issues.get(17).html_url = 'https://github.com/me/two/issues/9'; }],
    // The create went to forum 960, and the setting is 950 now: the thread is
    // found in 960, and the tag write after it is refused there.
    ['the forum setting changed since', (w, t) => {
      t.parent_id = '960';
      const c = botComments(w, 17).find((x) => parseChecklist(x));
      c.body = c.body.replace('discord-checklist-forum: 950', 'discord-checklist-forum: 960');
    }, /is in channel 960, not the checklist forum/],
  ]) {
    const w = world();
    w.issue(17);
    loseAnswer(w);
    await assert.rejects(job(w), /checklist thread not updated for #17/, why);
    assert.deepEqual([recordOf(w).state, recordOf(w).forumId], ['creating', '950'], why);
    const t = ckThreads(w)[0];
    between(w, t);
    const next = job(w);
    if (refused) await assert.rejects(next, refused, why);
    else await next;
    // Counted in every forum: the forum-change row moves the thread out of 950.
    assert.equal(w.find('POST', /channels\/\d+\/threads$/).length, 1, `${why}: no second create`);
    assert.equal(recordOf(w).threadId, t.id, why);
  }
});

test('CH3: a create that lands with its answer lost is taken by the next job, and only one create is ever sent', async () => {
  const w = world();
  w.issue(17);
  let landed = false;
  w.hooks.push(['POST', /channels\/950\/threads$/, async (call) => {
    if (landed) return;
    landed = true;
    w.ckThread(17, { name: call.body.name, applied_tags: [...call.body.applied_tags], starter: { author: { id: BOT_USER }, content: call.body.message.content } });
    w.fail.push(['POST', /channels\/950\/threads$/, fail500(), 1]);
  }]);
  await assert.rejects(job(w), /-> 500/);
  assert.equal(recordOf(w).state, 'creating', 'a 500 may have landed: the record is not set back');
  await job(w);
  assert.deepEqual([ours(w).length, recordOf(w).threadId, w.find('POST', /channels\/950\/threads$/).length], [1, ours(w)[0].id, 1]);
});

test('CH3: with no single bot thread to take, nothing is created and the record stays not confirmed, eight days on too', async () => {
  for (const [why, first, between] of [
    ['the archived read fails', loseAnswer, (w) => failArchived(w)],
    ['21 threads made since the try', loseAnswer, (w) => { for (let k = 0; k < 21; k++) w.ckThread(99, staffStarter()); }],
    ['an archived listing that goes on past the pages', loseAnswer, (w) => {
      w.archivePage = 1;
      for (let k = 0; k < 3; k++) w.ckThread(99, { archived: true, archivedAt: w.clock + k, ...staffStarter() });
    }],
    // The lost thread matches, then a later candidate's read fails: a partial
    // read counts no match.
    ['a candidate read failing after a match', loseAnswer, (w) => {
      const s = w.ckThread(99, staffStarter());
      w.fail.push(['GET', new RegExp(`channels/${s.id}/messages/${s.id}$`), fail500(), 99]);
    }],
    ['the create never reached Discord', hangUp, () => {}],
    ['two bot threads name the issue', loseAnswer, (w) => { w.ckThread(17); }],
    ['a staff thread cites the issue, and no bot thread does', hangUp, (w) => { w.ckThread(17, staffStarter('Issue: https://github.com/me/one/issues/17')); }],
    // The record's forum line edited to hold a space, and the listing refused
    // with a body naming a staff tag: only the request and its status are told.
    ['a forum line with a space, its listing refused', loseAnswer, (w) => {
      const c = botComments(w, 17).find((x) => parseChecklist(x));
      c.body = c.body.replace('discord-checklist-forum: 950', 'discord-checklist-forum: 950 x');
      w.fail.push(['GET', /threads\/archived\/public/, new Response('{"message":"Missing Access","tag":"Needs QA"}', { status: 403 }), 99]);
    }],
  ]) {
    const w = world();
    w.issue(17);
    first(w);
    await assert.rejects(job(w), /checklist/, why);
    between(w);
    const made = ckThreads(w).length;
    for (const wait of [0, 8 * DAY]) {
      w.clock += wait;
      await assert.rejects(job(w), (e) => /staff checklist thread not confirmed \(.+\); see the sweep/.test(e.message) && !/Needs QA/.test(e.message), why);
      assert.deepEqual([ckThreads(w).length, recordOf(w).state], [made, 'creating'], `${why}: nothing created`);
    }
  }
});

test('CH3: staff recovery: the one bot thread left is taken, and a deleted record opens a new thread', async () => {
  {
    const w = world();
    w.issue(17);
    loseAnswer(w);
    await assert.rejects(job(w));
    const first = ours(w)[0];
    w.clock += 1000;
    const second = w.ckThread(17);
    await assert.rejects(job(w), /not confirmed/);
    w.threads.delete(second.id);
    await job(w);
    assert.deepEqual([recordOf(w).threadId, ours(w).length], [first.id, 1], 'staff deleted the newer');
  }
  {
    const w = world();
    w.issue(17);
    hangUp(w);
    await assert.rejects(job(w));
    await assert.rejects(job(w), /not confirmed/);
    const comments = w.issues.get(17).comments;
    comments.splice(comments.findIndex((c) => c.id === recordOf(w).id), 1);
    await job(w);
    assert.equal(ours(w).length, 1, 'staff deleted the record comment');
    assert.equal(recordOf(w).threadId, ours(w)[0].id);
  }
});

test('CH3: an issue that stops being the bot\'s during the search, the forum read or the creating save gets no thread, one that moves on is planned from the newest read, and a first try opens at once in a busy forum', async () => {
  {
    const w = world();
    w.issue(17);
    loseAnswer(w);
    await assert.rejects(job(w));
    w.hooks.push(['GET', /discord\.com\/api\/v10\/channels\/\d+\/messages\/\d+$/, async () => { w.issues.get(17).labels.delete('from-discord'); }]);
    const writes = w.find('PATCH', /issues\/comments\/\d+$/).length;
    await job(w);
    assert.deepEqual([recordOf(w).state, w.find('PATCH', /issues\/comments\/\d+$/).length], ['creating', writes], 'stopped qualifying during the search');
  }
  {
    const w = world();
    w.issue(17);
    let once = false;
    w.hooks.push(['GET', /discord\.com\/api\/v10\/channels\/950$/, async () => {
      if (once) return;
      once = true;
      w.issues.get(17).labels.delete('from-discord');
    }]);
    await job(w);
    assert.deepEqual([recordOf(w).state, ckThreads(w).length, w.find('PATCH', /issues\/comments\/\d+$/).length], ['pending', 0, 0], 'stopped qualifying during the forum read');
  }
  // The `creating` save is a request of its own: GitHub is read again after
  // it, and a stop there sets the record back, since no create went out.
  for (const [why, change, fails] of [
    ['stopped qualifying during the creating save', (w) => w.issues.get(17).labels.delete('from-discord'), null],
    ['closed during the creating save, its event not listed yet', (w) => {
      w.close(17, 'not_planned');
      w.issues.get(17).events = [];
    }, /the issue is closed but its close event is not readable yet/],
  ]) {
    const w = world();
    w.issue(17);
    let once = false;
    w.hooks.push(['PATCH', /issues\/comments\/\d+$/, async (call) => {
      if (once || !/discord-checklist: creating/.test(call.body.body)) return;
      once = true;
      change(w);
    }]);
    if (fails) await assert.rejects(job(w), fails, why);
    else await job(w);
    assert.deepEqual([recordOf(w).state, ckThreads(w).length], ['pending', 0], `${why}: no thread, and the record set back`);
  }
  {
    // Closed as not planned during the forum read, its close readable, in a
    // forum with no Won't fix tag: the thread is planned from the newer read,
    // so none is made.
    const w = world();
    w.issue(17);
    w.ckForum.available_tags = w.ckForum.available_tags.filter((x) => x.name !== "Won't fix");
    let once = false;
    w.hooks.push(['GET', /discord\.com\/api\/v10\/channels\/950$/, async () => {
      if (once) return;
      once = true;
      w.close(17, 'not_planned');
    }]);
    await assert.rejects(job(w), /checklist forum has no "Won't fix" tag/);
    assert.deepEqual([recordOf(w).state, ckThreads(w).length], ['pending', 0], 'moved on during the forum read');
  }
  {
    const w = world();
    w.issue(17);
    for (let k = 0; k < 21; k++) w.ckThread(99, staffStarter());
    await job(w);
    assert.equal(ours(w).length, 1, 'a busy forum');
    assert.equal(w.find('GET', /threads\/active$/).length, 0, 'a first try does not search');
  }
});

test('CH3: a thread id staff put in the record by hand is taken only when its first message is the bot\'s for this issue', async () => {
  for (const [why, pick, ok, visible] of [
    ['the lost thread', (w) => ours(w)[0], true],
    ['another thread in the forum', (w) => w.ckThread(99, staffStarter()), false],
    ['a bot thread for this issue outside the forum the create went to', (w) => w.ckThread(17, { parent_id: '960' }), false],
    // Staff edit the visible line to link it too: only the bot's own line marks a record checked.
    ['another thread in the forum, with the visible line edited to link it', (w) => w.ckThread(99, staffStarter()), false, true],
  ]) {
    const w = world();
    w.issue(17);
    loseAnswer(w);
    await assert.rejects(job(w));
    const t = pick(w);
    const c = botComments(w, 17).find((x) => parseChecklist(x));
    c.body = c.body.replace('discord-checklist: creating', `discord-checklist: ${t.id}`);
    if (visible) c.body = c.body.replace('Staff checklist thread: opening', `Staff checklist thread: https://discord.com/channels/800/${t.id}`);
    const writes = w.find('PATCH', threadUrl(t.id)).length;
    if (ok) {
      await job(w);
      const rec = botComments(w, 17).find((x) => parseChecklist(x));
      assert.match(rec.body, new RegExp(`^Staff checklist thread: https://discord\\.com/channels/800/${t.id}\\n`), `${why}: the visible line links it`);
    } else {
      await assert.rejects(job(w), /is not the bot's thread for this issue/, why);
      assert.equal(w.find('PATCH', threadUrl(t.id)).length, writes, `${why}: no write to it`);
    }
  }
});

test('CH3: a record whose marker no longer parses stops the job before any write, and no second thread is made', async () => {
  for (const [why, mend] of [
    // Staff paste the thread's link in place of "creating".
    ['a pasted link in the marker', (body) => body.replace('discord-checklist: creating', 'discord-checklist: https://discord.com/channels/800/123')],
    // Staff delete the hidden lines; the visible line is left.
    ['the hidden lines deleted', (body) => body.split('\n\n')[0]],
  ]) {
    const w = world();
    w.issue(17);
    loseAnswer(w);
    await assert.rejects(job(w));
    const c = botComments(w, 17).find((x) => parseChecklist(x));
    c.body = mend(c.body);
    const comments = w.issues.get(17).comments.length;
    await assert.rejects(job(w), /the staff checklist record \(.+\) cannot be read/, why);
    assert.deepEqual([w.issues.get(17).comments.length, w.find('POST', /channels\/\d+\/threads$/).length], [comments, 1], `${why}: no new record, no second create`);
  }
});

test('CH3: a hand-entered id whose thread read fails for another reason is kept for a re-run', async () => {
  const w = world();
  w.issue(17);
  loseAnswer(w);
  await assert.rejects(job(w));
  const t = ours(w)[0];
  const c = botComments(w, 17).find((x) => parseChecklist(x));
  c.body = c.body.replace('discord-checklist: creating', `discord-checklist: ${t.id}`);
  w.fail.push(['GET', threadUrl(t.id), fail500(), 1]);
  await assert.rejects(job(w), (e) => /-> 500/.test(e.message) && !/not the bot's thread/.test(e.message));
  assert.deepEqual([recordOf(w).threadId, recordOf(w).linked], [t.id, false], 'the id is left for a re-run');
  await job(w);
  assert.equal(recordOf(w).linked, true, 'and the re-run takes it');
});

test('CH2: a closed issue whose close event is not readable yet gets no record, no thread and no adoption', async () => {
  {
    const w = world();
    const i = w.issue(17);
    w.close(17, 'not_planned');
    i.events = [];
    await assert.rejects(job(w, 'closed'), /the issue is closed but its close event is not readable yet/);
    assert.deepEqual([recordOf(w), ckThreads(w).length], [null, 0], 'no record');
  }
  {
    const w = world();
    const i = w.issue(17);
    loseAnswer(w);
    await assert.rejects(job(w));
    w.close(17, 'not_planned');
    i.events = [];
    await assert.rejects(job(w, 'closed'), /the issue is closed but its close event is not readable yet/);
    assert.deepEqual([recordOf(w).state, w.find('GET', /threads\/active$/).length], ['creating', 0], 'a creating record: no search, no adoption');
  }
  {
    // The issue closes during the create's forum read, its event not listed yet.
    const w = world();
    const i = w.issue(17);
    let once = false;
    w.hooks.push(['GET', /discord\.com\/api\/v10\/channels\/950$/, async () => {
      if (once) return;
      once = true;
      w.close(17, 'not_planned');
      i.events = [];
    }]);
    await assert.rejects(job(w), /the issue is closed but its close event is not readable yet/);
    assert.deepEqual([recordOf(w).state, ckThreads(w).length], ['pending', 0], 'closed during the forum read');
  }
});

test('CH3: a found thread is recorded and archived even when the forum lacks the status tag', async () => {
  const w = world();
  w.issue(17);
  loseAnswer(w);
  await assert.rejects(job(w));
  const first = ours(w)[0];
  w.close(17, 'not_planned');
  w.ckForum.available_tags = w.ckForum.available_tags.filter((x) => x.name !== "Won't fix");
  await assert.rejects(job(w, 'closed'), /checklist forum has no "Won't fix" tag/);
  assert.deepEqual([recordOf(w).threadId, first.archived, recordOf(w).archived], [first.id, true, `Won't fix:${closeId(w)}`]);
});

// ---- The sweep --------------------------------------------------------------------

const sweep = (w, mode, out = []) => run({
  eventName: 'schedule', payload: {}, env: { ...env, SWEEP_MODE: mode, GITHUB_REPOSITORY: 'me/one' }, fetchImpl: w.fetch, log: (s) => out.push(s), now: () => w.clock,
});
const lineOf = (out, n) => out.find((l) => l.startsWith(`#${n}: `)) || '';
const discordLink = (id) => `https://discord\\.com/channels/800/${id}`;

test('CH8: report mode lists each checklist problem with its link and what staff should check', async () => {
  const w = world();
  const url = (n) => `https://github.com/me/one/issues/${n}`;
  const body = (n, state, over = {}) => checklistBody({ state, guildId: '800', since: w.clock, issueUrl: url(n), ...over });
  w.issue(17);
  w.issue(18);
  w.record(18, body(18, 'pending'));
  // A lost create answer for an issue that was #19 in another repository
  // when its create went out, and is #9 here since its transfer.
  w.issue(9);
  w.record(9, body(19, 'creating', { forumId: '950', issueUrl: 'https://github.com/me/old/issues/19' }));
  w.issue(23);
  w.close(23, 'not_planned');
  const t23 = seed(w, 23, { applied_tags: ['c-wont'], archived: true });
  w.issue(24);
  w.close(24, 'not_planned');
  const t24 = seed(w, 24, { applied_tags: ['c-wont'] });
  w.issue(25);
  w.close(25, 'not_planned');
  const key25 = `Won't fix:${closeId(w, 25)}`;
  Object.assign(w.issues.get(25), { state: 'open', state_reason: 'reopened' });
  const t25 = seed(w, 25, { applied_tags: ['c-tri'], archived: true }, key25);
  // Gone, on a finished issue whose archive is owed: no repair is promised.
  w.issue(26);
  w.close(26, 'not_planned');
  const t26 = seed(w, 26, { applied_tags: ['c-wont'] });
  w.threads.delete(t26.id);
  w.issue(27).labels.add('accepted');
  const t27 = seed(w, 27, { applied_tags: ['c-wont'] });
  w.issue(28).labels.add('accepted');
  const t28 = seed(w, 28, { applied_tags: ['c-staff', 'c-s2', 'c-s3', 'c-s4', 'c-tri'] });
  w.issue(29);
  w.close(29, 'not_planned');
  // Archived for an earlier close; the issue closed again after a reopen whose job was dropped.
  w.issue(30);
  w.close(30, 'not_planned');
  const old30 = `Won't fix:${closeId(w, 30)}`;
  w.close(30, 'not_planned');
  const t30 = seed(w, 30, { applied_tags: ['c-wont'], archived: true }, old30);
  // The wanted status beside a stale one, with Accepted due: the writer's plan has room.
  w.issue(31).labels.add('accepted');
  const t31 = seed(w, 31, { applied_tags: ['c-tri', 'c-wont', 'c-staff', 'c-s2', 'c-s3'] });
  // Five staff tags and no status.
  w.issue(32);
  const t32 = seed(w, 32, { applied_tags: ['c-staff', 'c-s2', 'c-s3', 'c-s4', 'c-s5'] });
  // Closed, with the close event not readable yet.
  w.issue(33);
  w.close(33, 'not_planned');
  const t33 = seed(w, 33, { applied_tags: ['c-wont'], archived: true }, `Won't fix:${closeId(w, 33)}`);
  w.issues.get(33).events = [];
  // The same with no record: a first open failed on it.
  w.issue(34);
  w.close(34, 'not_planned');
  w.issues.get(34).events = [];
  // A record whose marker no longer parses.
  w.issue(35);
  w.record(35, 'Staff checklist thread: opening\n\n<!-- discord-checklist: oops guild: 800 -->');
  w.clock += 11 * 60 * 1000;
  const out = [];
  await sweep(w, 'report', out);
  for (const [n, re] of [
    [17, /no staff checklist thread \(the issue's next event, a close, a reopen, or the accepted label added or removed, opens one\)/],
    [18, /staff checklist thread not opened \(https:\/\/github\.com\/me\/one\/issues\/18#issuecomment-\d+\): the issue's next event opens it/],
    [9, new RegExp('staff checklist thread not confirmed \\(https://github\\.com/me/one/issues/9#issuecomment-\\d+\\): the issue\'s next event, or a re-run of its failed checklist job, looks for it\\. '
      + `If this stays, look in the checklist forum ${discordLink('950')} for the bot's threads whose first message names https://github\\.com/me/old/issues/19 or https://github\\.com/me/one/issues/9\\. `
      + 'With more than one, keep the oldest and delete the rest, and the next event takes it\\. '
      + 'If the job still fails \\(too many threads made since, or the listing stops short\\), put the thread\'s id in place of "creating" in that comment, and the next event checks it and takes it\\. '
      + 'If there is none, delete that comment only once you are sure no thread there is this issue\'s: a thread whose first message was deleted can be, and its name started "#19 " unless someone renamed it\\. '
      + 'Then the next event opens a new thread\\. If you are not sure, leave the comment, and this line stays')],
    [23, new RegExp(`checklist archive owed \\(${discordLink(t23.id)}\\): the issue is Won't fix; a fix-mode sweep or the issue's next run archives it\\. If staff want it open, reply in it after that`)],
    [24, new RegExp(`checklist archive owed \\(${discordLink(t24.id)}\\)`)],
    [25, new RegExp(`checklist archived for a close that no longer holds \\(${discordLink(t25.id)}\\): the issue is Triaged now`)],
    [26, /staff checklist thread is gone \(https:\/\/github\.com\/me\/one\/issues\/26#issuecomment-\d+\): if it was deleted by mistake, delete that record comment and the issue's next event opens a new one/],
    [27, new RegExp(`checklist tags Won't fix -> Triaged, Accepted, keeping 0 staff tag\\(s\\) \\(${discordLink(t27.id)}\\)`)],
    [28, new RegExp(`no free tag slot for Accepted on the checklist thread \\(${discordLink(t28.id)}\\)`)],
    [30, new RegExp(`checklist archive owed \\(${discordLink(t30.id)}\\)`)],
    [31, new RegExp(`checklist tags Triaged, Won't fix -> Triaged, Accepted, keeping 3 staff tag\\(s\\) \\(${discordLink(t31.id)}\\)`)],
    [32, new RegExp(`no free tag slot for "Triaged" on the checklist thread \\(${discordLink(t32.id)}\\)`)],
    [33, new RegExp(`the issue is closed but its close event is not readable yet: the checklist thread \\(${discordLink(t33.id)}\\) is checked at the next sweep`)],
    [34, /the issue is closed but its close event is not readable yet: the checklist thread is checked at the next sweep/],
    [35, new RegExp('the staff checklist record \\(https://github\\.com/me/one/issues/35#issuecomment-\\d+\\) cannot be read: mend it so its hidden marker line reads "<!-- discord-checklist: THREAD-ID guild: SERVER-ID -->", with the thread\'s id and its server\'s id\\. '
      + 'If you are not sure a thread was made for it, put "creating" in place of THREAD-ID, and the issue\'s next event looks for one\\. '
      + 'Put "pending" there, or delete the comment, only once you are sure no thread was made for it; the issue\'s next event then opens one')],
  ]) assert.match(lineOf(out, n), re, `#${n}`);
  assert.doesNotMatch(lineOf(out, 26), /archive owed/, 'a gone thread gets its recovery, not a repair promise');
  assert.doesNotMatch(lineOf(out, 33), /no longer holds/, 'an unreadable close is never taken as a reopen');
  assert.doesNotMatch(out.join('\n'), /Needs QA|\bS[2-5]\b/, 'no staff tag name reaches the log');
  assert.doesNotMatch(lineOf(out, 29), /checklist/, 'a closed issue with no record is not listed');

  const v = world();
  v.ckForum.available_tags = v.ckForum.available_tags.filter((x) => x.name !== 'Accepted' && x.name !== "Won't fix");
  v.issue(17).labels.add('accepted');
  const u17 = seed(v, 17, { applied_tags: ['c-tri'] });
  v.issue(18);
  v.close(18, 'not_planned');
  const u18 = seed(v, 18, { applied_tags: ['c-tri'], archived: true }, `Won't fix:${closeId(v, 18)}`);
  v.issue(19);
  const u19 = seed(v, 19, { parent_id: '900', applied_tags: ['s-tri'] });
  // A thread id staff put in a `creating` record by hand.
  v.issue(20);
  const u20 = v.ckThread(20, { applied_tags: ['c-wont'] });
  v.record(20, checklistBody({ state: 'creating', guildId: '800', forumId: '950', since: v.clock, issueUrl: 'https://github.com/me/one/issues/20' })
    .replace('discord-checklist: creating', `discord-checklist: ${u20.id}`));
  // The same in a `pending` record, which names no server yet.
  v.issue(21);
  const u21 = v.ckThread(21, { applied_tags: ['c-tri'] });
  v.record(21, checklistBody({ state: 'pending', guildId: '', since: v.clock, issueUrl: 'https://github.com/me/one/issues/21' })
    .replace('discord-checklist: pending', `discord-checklist: ${u21.id}`));
  const vout = [];
  await sweep(v, 'report', vout);
  for (const [n, re] of [
    [17, new RegExp(`checklist forum has no Accepted tag \\(${discordLink(u17.id)}\\)`)],
    [18, new RegExp(`checklist forum has no "Won't fix" tag \\(${discordLink(u18.id)}\\): add it, spelled as the README lists it`)],
    [19, new RegExp(`staff checklist thread ${discordLink(u19.id)} is not in the checklist forum: if CHECKLIST_FORUM_ID changed by mistake, set it back\\. `
      + 'If it changed on purpose, archive or delete that thread as staff prefer, then delete that record comment \\(https://github\\.com/me/one/issues/19#issuecomment-\\d+\\), and the issue\'s next event opens a new thread in the forum set now')],
    [20, new RegExp(`staff checklist thread ${discordLink(u20.id)} was put in its record by hand \\(https://github\\.com/me/one/issues/20#issuecomment-\\d+\\): the issue's next event checks that it is the bot's thread for this issue and takes it`)],
    [21, new RegExp(`staff checklist thread ${u21.id} was put in its record by hand \\(https://github\\.com/me/one/issues/21#issuecomment-\\d+\\)`)],
  ]) assert.match(lineOf(vout, n), re, `#${n}`);

  // Fix mode leaves a hand-entered thread to the issue's next checklist job.
  const u = world();
  u.issue(20);
  const h20 = u.ckThread(20, { applied_tags: ['c-wont'] });
  u.record(20, checklistBody({ state: 'creating', guildId: '800', forumId: '950', since: u.clock, issueUrl: 'https://github.com/me/one/issues/20' })
    .replace('discord-checklist: creating', `discord-checklist: ${h20.id}`));
  await sweep(u, 'fix');
  assert.deepEqual(u.find('PATCH', threadUrl(h20.id)), [], 'fix mode writes nothing to a hand-entered thread');
});

test('CH8: fix mode repairs tags and the archive, opens no thread, and posts no record or note', async () => {
  const w = world();
  w.issue(17);
  w.threads.get('717').applied_tags = ['t-retail'];
  w.issue(23);
  w.close(23, 'not_planned');
  seed(w, 23, { applied_tags: ['c-wont'], archived: true });
  w.issue(27).labels.add('accepted');
  const t27 = seed(w, 27, { applied_tags: ['c-wont'] });
  w.issue(30);
  w.close(30, 'not_planned');
  const old30 = `Won't fix:${closeId(w, 30)}`;
  w.close(30, 'not_planned');
  const t30 = seed(w, 30, { applied_tags: ['c-wont'] }, old30);
  const out = [];
  await sweep(w, 'fix', out);
  assert.equal(w.tagOf('717'), 'Triaged', 'the post is repaired');
  assert.match(lineOf(out, 17), /no staff checklist thread/, 'and the missing thread listed');
  assert.equal(ckThreads(w).length, 3, 'no thread is opened');
  assert.equal(w.find('POST', /issues\/\d+\/comments$/).length, 0, 'no record or note is posted');
  assert.equal(recordOf(w, 23).archived, `Won't fix:${closeId(w, 23)}`, 'the archive key is saved');
  assert.deepEqual([ckName(w, t27), t27.archived], [['Triaged', 'Accepted'], false], 'the tags are repaired');
  assert.deepEqual([t30.archived, recordOf(w, 30).archived], [true, `Won't fix:${closeId(w, 30)}`], 'a later close is archived and keyed');
});

test('CH8: the post and the thread are swept apart, and every failure is kept', async () => {
  for (const [why, postFails, threadFails] of [['the thread read fails', false, true], ['the post read fails', true, false], ['both reads fail', true, true]]) {
    const w = world();
    w.issue(17);
    w.close(17, 'not_planned');
    const t = seed(w, 17, { applied_tags: ['c-tri'] });
    if (postFails) w.fail.push(['GET', /discord\.com\/api\/v10\/channels\/717$/, new Response('{"message":"x"}', { status: 403 }), 1]);
    // The error body names a staff tag; only the request and status are logged.
    if (threadFails) w.fail.push(['GET', threadUrl(t.id), new Response('{"message":"Missing Access","tag":"Needs QA"}', { status: 403 }), 1]);
    const out = [];
    await assert.rejects(sweep(w, 'fix', out), /could not update issue\(s\) #17; see above/, why);
    assert.doesNotMatch(out.join('\n'), /Needs QA/, `${why}: no staff tag name in the log`);
    const line = lineOf(out, 17);
    assert.match(line, new RegExp(`checklist archive owed \\(${discordLink(t.id)}\\)`), `${why}: a GitHub-based line is kept`);
    if (threadFails) assert.match(line, new RegExp(`staff checklist thread not read \\(${discordLink(t.id)}\\): Discord GET /channels/${t.id} -> 403`), `${why}: the line holds its cause`);
    const failure = out.filter((l) => l.startsWith('#17: ')).at(-1);
    if (postFails) assert.match(failure, /Discord post not read/, `${why}: the failure names the post`);
    if (threadFails) assert.match(failure, /staff checklist thread not read/, `${why}: and the thread`);
    assert.equal(w.tagOf('717'), postFails ? 'Triaged' : 'Closed', `${why}: the post is repaired unless unread`);
    assert.deepEqual([ckName(w, t), t.archived], [["Won't fix"], true], `${why}: the thread is repaired`);
  }
});

test('CH8: a failed player-side step in fix mode stops the post\'s repair, never the thread\'s, and with the checklist off ends the issue as before', async () => {
  // The ship record write fails.
  for (const over of [{}, { CHECKLIST_FORUM_ID: '' }]) {
    const on = !('CHECKLIST_FORUM_ID' in over);
    const w = world();
    w.issue(17);
    w.close(17, 'completed', 'aaaaaaa1');
    const t = seed(w, 17, { applied_tags: ['c-fix'] });
    w.tags = [{ name: 'v5.0.1', commit: { sha: 'c-v5.0.1' } }];
    w.contains.set('aaaaaaa1...c-v5.0.1', 'ahead');
    w.fail.push(['POST', /issues\/17\/comments$/, fail500(), 1]);
    // A note with a run: the failed ship record stops the repair, not the note judging.
    w.record(17, 'Notification attempted: x\n\n<!-- discord-told: shipped-a -->\n<!-- discord-told-status: Shipped -->\n<!-- discord-told-run: 4242 -->');
    const out = [];
    await assert.rejects(run({
      eventName: 'schedule', payload: {}, env: { ...env, ...over, SWEEP_MODE: 'fix', GITHUB_REPOSITORY: 'me/one' }, fetchImpl: w.fetch, log: (s) => out.push(s), now: () => w.clock,
    }), /could not update issue\(s\) #17; see above/);
    // The player-side mutations: label writes, the post's tags and messages,
    // and comments other than the failed ship record and the checklist
    // record. GraphQL reads (a POST) are not writes.
    const playerWrites = w.calls.filter((c) => c.method !== 'GET' && (/\/issues\/17\/labels/.test(c.url)
      || /discord\.com\/api\/v10\/channels\/717(\/messages)?$/.test(c.url)
      || (/\/issues\/17\/comments$/.test(c.url) && !/discord-shipped-in/.test(c.body.body))
      || (/\/issues\/comments\/\d+$/.test(c.url) && !/discord-checklist/.test(c.body.body))));
    assert.deepEqual(playerWrites, [], `${on ? 'on' : 'off'}: no label, post or note write after the failure`);
    assert.equal(w.find('POST', /\/issues\/17\/comments$/).length, 1, 'the ship record was tried once');
    if (on) {
      assert.match(lineOf(out, 17), new RegExp(`checklist archive owed \\(${discordLink(t.id)}\\)`));
      assert.match(out.filter((l) => l.startsWith('#17: ')).at(-1), /ship record not written/);
      assert.deepEqual([ckName(w, t), t.archived], [['Shipped'], true], 'the thread is still repaired');
      assert.match(lineOf(out, 17), /owed message "x" is no longer true/, 'the notes are still judged');
    }
  }
  // A note's run cannot be read.
  {
    const w = world();
    w.issue(17);
    const t = seed(w, 17, { applied_tags: ['c-tri', 'c-acc'] });
    w.record(17, 'Notification attempted: x\n\n<!-- discord-told: fixed-a -->\n<!-- discord-told-status: Fixed, next update -->\n<!-- discord-told-run: 4242 -->');
    w.fail.push(['GET', /actions\/runs\/4242$/, fail500(), 99]);
    const out = [];
    await assert.rejects(sweep(w, 'fix', out), /could not update issue\(s\) #17; see above/);
    assert.match(out.filter((l) => l.startsWith('#17: ')).at(-1), /run of .+ not read/);
    assert.deepEqual(ckName(w, t), ['Triaged'], 'the thread is still repaired');
  }
  // A note's message cannot be worked out: the In progress message reads the issue's events.
  {
    const w = world();
    w.issue(17);
    w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17] });
    const t = seed(w, 17, { applied_tags: ['c-tri', 'c-acc'] });
    w.record(17, 'Notification attempted: x\n\n<!-- discord-told: progress-a -->\n<!-- discord-told-status: In progress -->');
    w.fail.push(['GET', /issues\/17\/events/, fail500(), 99]);
    const out = [];
    await assert.rejects(sweep(w, 'fix', out), /could not update issue\(s\) #17; see above/);
    assert.match(out.filter((l) => l.startsWith('#17: ')).at(-1), /message of .+ not read/);
    assert.deepEqual(ckName(w, t), ['In progress'], 'the thread is still repaired');
  }
});

test('CH8: a checklist line alone never moves the post', async () => {
  const w = world();
  w.issue(17);
  // A stale Accepted tag: the issue has no `accepted` label.
  const t = seed(w, 17, { applied_tags: ['c-tri', 'c-acc'] });
  // A PR makes the post's status due after the sweep read the post.
  w.hooks.push(['GET', threadUrl(t.id), async () => { w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17] }); }]);
  const out = [];
  await sweep(w, 'fix', out);
  assert.match(lineOf(out, 17), new RegExp(`checklist tags Triaged, Accepted -> Triaged, keeping 0 staff tag\\(s\\) \\(${discordLink(t.id)}\\)`));
  assert.equal(w.tagOf('717'), 'Triaged');
});
