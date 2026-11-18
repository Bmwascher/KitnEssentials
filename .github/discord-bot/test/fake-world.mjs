// A stateful fake of the slices of GitHub and Discord the bot uses. Every
// route reads and writes one shared state, so two runs against the same world
// see each other's writes, the way they would on the real services.
import { FORUM } from './fake-fetch.mjs';

const BOT = 'github-actions[bot]';
const GUILD = '800';
const MARK = (thread) => `<!-- discord-thread: ${thread} reporter: 42 -->`;

export function world() {
  const w = {
    repo: 'me/one',
    issues: new Map(),
    prs: new Map(), // number -> { draft, author_association, state, closes: [issue numbers] }
    contains: new Map(), // `${sha}...${target}` -> 'ahead' | 'identical' | 'behind' | 'diverged'
    threads: new Map(), // id -> { id, parent_id, applied_tags, archived, messages: [] }
    calls: [],
    nextId: 1,
    tags: [], // [{ name, commit: { sha }, annotated }], newest first by commit date
    pageSize: 100, // nodes per GraphQL page
    clock: Date.now(), // created_at and updated_at
    hooks: [], // [method, RegExp, fn(call)] run before a matching call is served
    fail: [], // [method, RegExp, Response | Error, times]
    runs: new Map(), // workflow run id -> { status, run_attempt, created_at }
  };
  w.start = w.clock;

  w.issue = (n, over = {}) => {
    const thread = over.thread || String(700 + n);
    const i = {
      number: n, state: 'open', state_reason: null, labels: new Set(['from-discord']), updated_at: new Date(w.clock).toISOString(),
      body: `## Report\n\n> hi\n\n${MARK(thread)}`, comments: [], events: [], ...over,
    };
    if (over.labels) i.labels = new Set(over.labels);
    delete i.thread;
    w.issues.set(n, i);
    if (!w.threads.has(thread)) w.thread(thread);
    return i;
  };
  w.thread = (id, over = {}) => {
    // A post with the forum's or the server's id would answer as the forum, or hide a link built from the wrong id.
    if (id === FORUM.id || id === GUILD) throw new Error(`fake world: post ${id} is the forum's or the server's id; give it another`);
    const t = { id, parent_id: FORUM.id, applied_tags: ['t-retail', 't-bug', 's-tri'], archived: true, messages: [], ...over };
    w.threads.set(id, t);
    return t;
  };
  w.record = (n, body, login = BOT) => {
    const id = w.nextId++;
    const c = { id, user: { login }, body, created_at: new Date(w.clock).toISOString(), html_url: `https://github.com/${w.repo}/issues/${n}#issuecomment-${id}` };
    w.issues.get(n).comments.push(c);
    return c;
  };
  // `closer` is what GraphQL names as the closer: { pr: sha } for a merged PR
  // (whose REST event carries no commit; `merged: false` for one that was
  // not) or { commit: sha }, with `repo` to put it in another repository.
  // `duplicateOf` is the issue number (or { body, labels, repo }) it duplicates.
  w.close = (n, reason = 'completed', commit = null, closer = null, duplicateOf = null) => {
    const i = w.issues.get(n);
    i.state = 'closed';
    i.state_reason = reason;
    i.events.push({ id: w.nextId++, event: 'closed', commit_id: commit, closer, duplicateOf });
  };
  w.tagOf = (threadId) => {
    const id = w.threads.get(threadId).applied_tags.at(-1);
    return FORUM.available_tags.find((t) => t.id === id).name;
  };
  w.said = (threadId) => w.threads.get(threadId).messages.map((m) => m.content);

  const view = (i) => ({
    number: i.number, state: i.state, state_reason: i.state_reason, body: i.body,
    labels: [...i.labels].map((name) => ({ name })),
  });
  const json = (obj, status = 200) => new Response(obj === null ? null : JSON.stringify(obj), { status: obj === null ? 204 : status });
  const page = (url) => Number((/[?&]page=(\d+)/.exec(url) || [0, 1])[1]);
  const per = (url) => Number((/[?&]per_page=(\d+)/.exec(url) || [0, 30])[1]);
  const slice = (all, url) => all.slice((page(url) - 1) * per(url), page(url) * per(url));
  // A GraphQL connection page; the cursor is the next index.
  const gqlPage = (all, after) => {
    const from = Number(after || 0);
    const nodes = all.slice(from, from + w.pageSize);
    return { nodes, pageInfo: { hasNextPage: from + w.pageSize < all.length, endCursor: String(from + w.pageSize) } };
  };

  const routes = [
    ['GET', /\/repos\/me\/one\/issues\/(\d+)$/, (m) => {
      const i = w.issues.get(Number(m[1]));
      return i ? json(view(i)) : json({ message: 'nf' }, 404);
    }],
    ['GET', /\/repos\/me\/one\/issues\?.*labels=([^&]+)/, (m, url) => {
      const label = decodeURIComponent(m[1]);
      const state = (/[?&]state=(\w+)/.exec(url) || [0, 'open'])[1];
      const since = (/[?&]since=([^&]+)/.exec(url) || [0, ''])[1];
      const all = [...w.issues.values()]
        .filter((i) => i.labels.has(label) && (state === 'all' || i.state === state) && (!since || i.updated_at >= decodeURIComponent(since)))
        .map(view);
      return json(slice(all, url));
    }],
    ['GET', /\/repos\/me\/one\/issues\/(\d+)\/comments/, (m, url) => json(slice(w.issues.get(Number(m[1])).comments, url))],
    ['POST', /\/repos\/me\/one\/issues\/(\d+)\/comments$/, (m, url, body) => {
      const c = w.record(Number(m[1]), body.body);
      return json({ id: c.id });
    }],
    ['GET', /\/repos\/me\/one\/issues\/(\d+)\/events/, (m, url) => json(slice(w.issues.get(Number(m[1])).events, url))],
    ['POST', /\/repos\/me\/one\/issues\/(\d+)\/labels$/, (m, url, body) => {
      const i = w.issues.get(Number(m[1]));
      for (const l of body.labels) i.labels.add(l);
      return json([...i.labels].map((name) => ({ name })));
    }],
    ['DELETE', /\/repos\/me\/one\/issues\/(\d+)\/labels\/(.+)$/, (m) => {
      const i = w.issues.get(Number(m[1]));
      const l = decodeURIComponent(m[2]);
      if (!i.labels.has(l)) return json({ message: 'Label does not exist' }, 404);
      i.labels.delete(l);
      return json([]);
    }],
    ['GET', /\/repos\/me\/one\/compare\/([0-9a-f]+)\.\.\.(.+)$/, (m) => {
      const status = w.contains.get(`${m[1]}...${decodeURIComponent(m[2])}`) || 'behind';
      return json({ status });
    }],
    // A workflow run: one set in `w.runs`, else a finished first attempt
    // from the world's start.
    ['GET', /\/repos\/me\/one\/actions\/runs\/(\d+)$/, (m) => json(w.runs.get(m[1])
      || { id: Number(m[1]), status: 'completed', run_attempt: 1, created_at: new Date(w.start).toISOString() })],
    ['GET', /\/repos\/me\/one\/issues\/comments\/(\d+)$/, (m) => {
      for (const i of w.issues.values()) {
        const c = i.comments.find((x) => x.id === Number(m[1]));
        if (c) return json(c);
      }
      return json({ message: 'nf' }, 404);
    }],
    ['PATCH', /\/repos\/me\/one\/issues\/comments\/(\d+)$/, (m, url, body) => {
      for (const i of w.issues.values()) {
        const c = i.comments.find((x) => x.id === Number(m[1]));
        if (c) { c.body = body.body; return json({ id: c.id }); }
      }
      return json({ message: 'nf' }, 404);
    }],
    ['POST', /api\.github\.com\/graphql$/, (m, url, body) => {
      const v = body.variables;
      if (/refs\(refPrefix/.test(body.query)) {
        const all = w.tags.map((t) => ({
          name: t.name,
          target: t.annotated ? { __typename: 'Tag', oid: `tag-${t.name}`, target: { oid: t.commit.sha } } : { __typename: 'Commit', oid: t.commit.sha },
        }));
        return json({ data: { repository: { refs: gqlPage(all, v.after) } } });
      }
      if (/closedByPullRequestsReferences/.test(body.query)) {
        const all = [...w.prs.values()].filter((p) => p.closes.includes(v.number) && p.state === 'OPEN')
          .map((p) => ({ isDraft: !!p.draft, state: p.state, authorAssociation: p.author_association }));
        return json({ data: { repository: { issue: { closedByPullRequestsReferences: gqlPage(all, v.after) } } } });
      }
      if (/closingIssuesReferences/.test(body.query)) {
        const p = w.prs.get(v.number);
        const all = (p ? p.closes : []).map((c) => (typeof c === 'number' ? { number: c, repository: { nameWithOwner: 'me/one' } } : c));
        return json({ data: { repository: { pullRequest: p ? { closingIssuesReferences: gqlPage(all, v.after) } : null } } });
      }
      if (/ClosedEvent/.test(body.query)) {
        const last = w.issues.get(v.number).events.filter((e) => e.event === 'closed').at(-1);
        const c = last && last.closer;
        const repository = { nameWithOwner: (c && c.repo) || 'me/one' };
        const closer = !c ? null
          : c.pr ? { __typename: 'PullRequest', merged: c.merged !== false, mergeCommit: { oid: c.pr }, repository }
            : { __typename: 'Commit', oid: c.commit, repository };
        const d = last && last.duplicateOf;
        const dupIssue = typeof d === 'number' ? w.issues.get(d) : d;
        const dupLabels = [...(dupIssue && dupIssue.labels ? dupIssue.labels : [])].map((name) => ({ name }));
        const duplicateOf = dupIssue ? { body: dupIssue.body, labels: { nodes: dupLabels }, repository: { nameWithOwner: dupIssue.repo || 'me/one' } } : null;
        return json({ data: { repository: { issue: { timelineItems: { nodes: last ? [{ closer, duplicateOf }] : [] } } } } });
      }
      return json({ errors: [{ message: 'unknown query' }] });
    }],
    ['GET', /discord\.com\/api\/v10\/channels\/(\d+)$/, (m) => {
      if (m[1] === FORUM.id) return json(FORUM);
      const t = w.threads.get(m[1]);
      if (!t) return json({ message: 'Unknown Channel' }, 404);
      // The server id differs from the forum id (900), so a link built from the wrong one fails.
      return json({ id: t.id, guild_id: GUILD, parent_id: t.parent_id, applied_tags: [...t.applied_tags], thread_metadata: { archived: t.archived } });
    }],
    ['PATCH', /discord\.com\/api\/v10\/channels\/(\d+)$/, (m, url, body) => {
      const t = w.threads.get(m[1]);
      if (!t) return json({ message: 'Unknown Channel' }, 404);
      if (body.applied_tags) t.applied_tags = body.applied_tags;
      if (body.archived === false) t.archived = false;
      return json({});
    }],
    // One message: the post's starter (`starter` on the thread, its id the
    // thread's), or a message the bot sent there (ids count from 1).
    ['GET', /discord\.com\/api\/v10\/channels\/(\d+)\/messages\/(\d+)$/, (m) => {
      const t = w.threads.get(m[1]);
      const msg = t && (m[2] === t.id ? t.starter : t.messages[Number(m[2]) - 1]);
      return msg ? json({ id: m[2], ...msg }) : json({ message: 'Unknown Message' }, 404);
    }],
    ['POST', /discord\.com\/api\/v10\/channels\/(\d+)\/messages$/, (m, url, body) => {
      const t = w.threads.get(m[1]);
      if (!t) return json({ message: 'Unknown Channel' }, 404);
      t.messages.push(body);
      return json({ id: String(t.messages.length) });
    }],
  ];

  w.fetch = async (url, init = {}) => {
    const method = init.method || 'GET';
    const body = init.body ? JSON.parse(init.body) : undefined;
    const call = { method, url, body };
    w.calls.push(call);
    for (const [hm, re, fn] of w.hooks) if (hm === method && re.test(url)) await fn(call);
    const f = w.fail.find(([fm, re, , times]) => fm === method && re.test(url) && times > 0);
    if (f) {
      f[3]--;
      if (f[2] instanceof Error) throw f[2];
      return f[2].clone();
    }
    for (const [rm, re, fn] of routes) {
      const m = rm === method && re.exec(url);
      if (m) return fn(m, url, body);
    }
    return json({ message: `no route for ${method} ${url}` }, 404);
  };
  w.find = (method, re) => w.calls.filter((c) => c.method === method && re.test(c.url));
  return w;
}

export const shippedIn = (tag, shas) => `Shipped in ${tag}.\n\n<!-- discord-shipped-in: ${tag} fixes: ${shas.join(',')} -->`;
