// A recording fake for fetch: routes are [method, RegExp on the URL, handler(body, url)].
export function fakeFetch(routes) {
  const calls = [];
  const fn = async (url, init = {}) => {
    const method = init.method || 'GET';
    const body = init.body ? JSON.parse(init.body) : undefined;
    calls.push({ method, url, body });
    const route = routes.find(([m, re]) => m === method && re.test(url));
    if (!route) return new Response(`no route for ${method} ${url}`, { status: 404 });
    const out = await route[2](body, url);
    if (out instanceof Response) return out;
    return new Response(out === null ? null : JSON.stringify(out ?? {}), { status: out === null ? 204 : 200 });
  };
  fn.calls = calls;
  fn.find = (method, re) => calls.filter((c) => c.method === method && re.test(c.url));
  return fn;
}

// A call that never answers until its signal aborts. AbortSignal.timeout's
// timer does not keep Node running, and a real stalled request holds a
// socket that does; the interval stands in for that socket.
export function stall(init, onAbort = () => {}) {
  return new Promise((_, reject) => {
    const keep = setInterval(() => {}, 1000);
    init.signal.addEventListener('abort', () => {
      clearInterval(keep);
      onAbort();
      reject(init.signal.reason);
    });
  });
}

// Workers KV with only the two calls the bot makes.
export function fakeKv(init = {}) {
  const m = new Map(Object.entries(init));
  return { m, get: async (k) => (m.has(k) ? m.get(k) : null), put: async (k, v) => { m.set(k, String(v)); } };
}

// A help forum with client and type tags, plus the bot's status tags.
export const FORUM = {
  id: '900',
  available_tags: [
    { id: 't-retail', name: 'Retail' }, { id: 't-forever', name: 'Forever' },
    { id: 't-bug', name: 'Bug' }, { id: 't-feedback', name: 'Feedback/Request' },
    { id: 's-tri', name: 'Triaged' }, { id: 's-prog', name: 'In progress' },
    { id: 's-fix', name: 'Fixed, next update' }, { id: 's-ship', name: 'Shipped' },
    { id: 's-closed', name: 'Closed' },
  ],
};
