import test from 'node:test';
import assert from 'node:assert/strict';
import { checklistBody, parseChecklist } from '../status/checklist.mjs';

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
