/* ZeroTier Moon web console — plain JS, no framework, no build step.
 *
 * DATA MODEL
 * ──────────
 * The whole UI is driven by one JSON document. In development it loads the
 * committed sample (status.sample.json). On the NAS, point DATA_URL at a live
 * endpoint that emits the same shape (see web/README.md for the contract and a
 * sample generator that reads `zerotier-cli` + the controller API).
 *
 * ACTIONS (Members tab) POST to the ADMIN_API endpoints. Until a backend exists
 * they no-op with a toast — every call is wrapped so the page never breaks when
 * there is nothing listening.
 */

// ── Config: where live data comes from. Swap these on the NAS. ──────────────
const DATA_URL  = 'status.sample.json';   // TODO(nas): '/api/status'
const ADMIN_API = '';                     // TODO(nas): '/api'  (empty = mock mode)

const $  = (sel, el = document) => el.querySelector(sel);
const $$ = (sel, el = document) => [...el.querySelectorAll(sel)];

let state = null;   // last-loaded status document

// ── Formatting helpers ──────────────────────────────────────────────────────
const fmtDuration = (s) => {
  if (s == null) return '—';
  const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
  if (d) return `${d}d ${h}h`;
  if (h) return `${h}h ${m}m`;
  return `${m}m`;
};
const fmtAgo = (s) => (s == null ? '—' : s < 60 ? 'just now' : s < 3600 ? `${Math.floor(s/60)}m ago`
  : s < 86400 ? `${Math.floor(s/3600)}h ago` : `${Math.floor(s/86400)}d ago`);
const fmtLatency = (ms) => (ms == null || ms < 0 ? '—' : `${ms} ms`);
const esc = (v) => String(v ?? '').replace(/[&<>"]/g, (c) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));

// ── Data load + render ───────────────────────────────────────────────────────
async function load() {
  try {
    const res = await fetch(DATA_URL, { cache: 'no-store' });
    if (!res.ok) throw new Error(res.status);
    state = await res.json();
    render(state);   // render() sets the demo banner from state._sample
  } catch (err) {
    setConn('offline');
    $('#demo-banner').hidden = false;
    $('#demo-banner').textContent = `Could not load ${DATA_URL} (${err.message}). Serve this folder over HTTP.`;
  }
}

function setConn(stateStr) {
  const pill = $('#conn-pill');
  pill.dataset.state = stateStr;
  pill.textContent = stateStr === 'online' ? '● Online' : stateStr === 'offline' ? '● Offline' : '…';
}

function render(s) {
  const moon = s.moon || {};
  setConn(moon.online ? 'online' : 'offline');
  $('#demo-banner').hidden = !s._sample;
  if (s.moon?.subtitle) $('#moon-subtitle').textContent = s.moon.subtitle;

  // Hero
  $('#moon-dot').dataset.state = moon.online ? 'online' : 'offline';
  $('#moon-id').textContent    = moon.id || '—';
  $('#moon-state').textContent = moon.online ? 'Online' : 'Offline';
  $('#moon-version').textContent = moon.version || '—';
  $('#moon-uptime').textContent  = fmtDuration(moon.uptimeSeconds);
  $('#moon-peercount').textContent = (s.peers || []).length;

  // Endpoints
  const eps = moon.endpoints || {};
  $('#endpoints-list').innerHTML = [
    ['LAN 1', eps.lan1], ['LAN 2', eps.lan2], ['Public', eps.public || 'not set'],
  ].map(kvRow).join('');

  // Interfaces
  $('#interfaces-list').innerHTML = (s.interfaces || []).map((i) =>
    `<li><span class="k">${esc(i.name)}</span><span class="v">${esc(i.ip)}/${esc((i.subnet||'').split('/')[1]||'')} ${i.up ? '●' : '○'}</span></li>`
  ).join('') || emptyRow('No interfaces reported');

  // Peers
  $('#peers-table tbody').innerHTML = (s.peers || []).map((p) => `
    <tr>
      <td class="mono">${esc(p.address)}</td>
      <td><span class="tag" data-role="${esc(p.role)}">${esc(p.role || '—')}</span></td>
      <td>${fmtLatency(p.latencyMs)}</td>
      <td class="mono">${esc(p.version || '—')}</td>
      <td>${(p.paths || []).filter((x) => x.active).length}/${(p.paths || []).length}</td>
      <td>${fmtAgo(p.lastSeenSeconds)}</td>
    </tr>`).join('') || `<tr><td colspan="6" class="muted">No peers</td></tr>`;

  // Network
  const net = s.network || {};
  $('#network-list').innerHTML = [
    ['Network ID', net.id || 'not set'], ['Name', net.name || '—'],
    ['IP pool', net.ipPool || '—'],
    ['Routes', (net.routes || []).map((r) => r.via ? `${r.target} via ${r.via}` : r.target).join(', ') || '—'],
  ].map(kvRow).join('');

  // Members
  $('#members-table tbody').innerHTML = (s.members || []).map((m) => `
    <tr data-member="${esc(m.address)}">
      <td class="mono">${esc(m.address)}</td>
      <td>${esc(m.name || '—')}</td>
      <td class="mono">${esc((m.ipAssignments || []).join(', ') || '—')}</td>
      <td><span class="tag" data-on="${!!m.online}">${m.online ? 'yes' : 'no'}</span></td>
      <td>${fmtAgo(m.lastSeenSeconds)}</td>
      <td><input type="checkbox" class="toggle" ${m.authorized ? 'checked' : ''} data-authorize="${esc(m.address)}"></td>
    </tr>`).join('') || `<tr><td colspan="6" class="muted">No members</td></tr>`;

  // Client
  const c = s.client || {};
  $('#client-list').innerHTML = [
    ['Your node', c.address || 'unknown'],
    ['Overlay IP', c.ip || '—'],
    ['Orbiting this moon', c.orbitedMoon ? 'yes' : 'no'],
    ['Status', c.online ? 'connected' : 'not connected'],
  ].map(kvRow).join('');

  // Connect commands — fill in the real moon id
  if (moon.id) {
    $('#orbit-cmd').textContent = `zerotier-cli orbit ${moon.id} ${moon.id}`;
  }

  // Footer
  $('#updated-at').textContent = s.generatedAt
    ? `Updated ${new Date(s.generatedAt * 1000).toLocaleString()}`
    : 'Updated —';
}

const kvRow    = ([k, v]) => `<li><span class="k">${esc(k)}</span><span class="v">${esc(v)}</span></li>`;
const emptyRow = (msg)    => `<li><span class="k">${esc(msg)}</span><span class="v"></span></li>`;

// ── Admin actions (Members tab) ──────────────────────────────────────────────
async function adminPost(path, body) {
  if (!ADMIN_API) { toast('Mock mode — no backend wired (see web/README.md)'); return false; }
  try {
    const res = await fetch(`${ADMIN_API}${path}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (!res.ok) throw new Error(res.status);
    toast('Done');
    return true;
  } catch (err) {
    toast(`Failed: ${err.message}`);
    return false;
  }
}

// ── UI wiring ────────────────────────────────────────────────────────────────
function initTabs() {
  $$('.tab').forEach((tab) => tab.addEventListener('click', () => {
    $$('.tab').forEach((t) => t.setAttribute('aria-selected', String(t === tab)));
    $$('.panel').forEach((p) => { p.hidden = p.id !== `tab-${tab.dataset.tab}`; });
  }));
}

function initActions() {
  // Copy buttons
  $$('[data-copy]').forEach((btn) => btn.addEventListener('click', async () => {
    const text = $(btn.dataset.copy).textContent;
    try { await navigator.clipboard.writeText(text); toast('Copied'); }
    catch { toast('Copy failed'); }
  }));

  // Authorize toggles + moon actions (delegated)
  document.addEventListener('change', (e) => {
    const t = e.target.closest('[data-authorize]');
    if (!t) return;
    adminPost(`/members/${t.dataset.authorize}/authorize`, { authorized: t.checked })
      .then((ok) => { if (!ok) t.checked = !t.checked; });   // revert on failure/mock
  });
  document.addEventListener('click', (e) => {
    const t = e.target.closest('[data-action]');
    if (!t) return;
    if (t.dataset.action === 'restart' && !confirm('Restart the moon container?')) return;
    adminPost(`/actions/${t.dataset.action}`).then((ok) => { if (ok) setTimeout(load, 2000); });
  });

  $('#refresh-btn').addEventListener('click', load);
  initTheme();
}

function initTheme() {
  const root = document.documentElement;
  const saved = localStorage.getItem('ztmoon-theme');
  if (saved) root.dataset.theme = saved;
  $('#theme-btn').addEventListener('click', () => {
    const order = ['auto', 'light', 'dark'];
    const next = order[(order.indexOf(root.dataset.theme) + 1) % order.length];
    root.dataset.theme = next;
    localStorage.setItem('ztmoon-theme', next);
    toast(`Theme: ${next}`);
  });
}

let toastTimer;
function toast(msg) {
  let el = $('.toast');
  if (!el) { el = document.createElement('div'); el.className = 'toast'; document.body.appendChild(el); }
  el.textContent = msg;
  el.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.remove('show'), 1800);
}

// ── Boot ─────────────────────────────────────────────────────────────────────
initTabs();
initActions();
load();
