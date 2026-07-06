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

// ── Data source ──────────────────────────────────────────────────────────────
// When served by web/server.py (`zmoon web`), /api/status answers and the
// action buttons go live. Opened as a plain static file it falls back to the
// committed sample and the buttons stay in safe mock mode. No config needed.
const LIVE_URL   = '/api/status';
const SAMPLE_URL = 'status.sample.json';
let   LIVE       = false;   // set true once the backend answers
let   DATA_URL   = SAMPLE_URL;

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
async function detectBackend() {
  try {
    const res = await fetch(LIVE_URL, { cache: 'no-store' });
    if (res.ok) { LIVE = true; DATA_URL = LIVE_URL; return; }
  } catch { /* no backend — static mode */ }
  LIVE = false; DATA_URL = SAMPLE_URL;
}

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

  // Mode card — checkbox only enabled against a live backend
  const isMoon = s.moonMode !== false;
  const toggle = $('#moon-toggle');
  toggle.checked = isMoon;
  toggle.disabled = !LIVE;
  const modeTag = $('#mode-tag');
  modeTag.dataset.mode = isMoon ? 'moon' : 'client';
  modeTag.textContent = isMoon ? 'MOON' : 'CLIENT';

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

  // Connect commands — fill in the real moon id + network id
  if (moon.id) {
    $('#orbit-cmd').textContent = `zerotier-cli orbit ${moon.id} ${moon.id}`;
  }
  if (net.id) {
    $('#join-cmd').textContent = `zerotier-cli join ${net.id}`;
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
  if (!LIVE) { toast('Mock mode — run “zmoon web” on the NAS to enable actions'); return false; }
  try {
    const res = await fetch(`/api${path}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (res.status === 403) { toast('Actions disabled — set WEB_ADMIN_PASSWORD in .env'); return false; }
    if (res.status === 401) { toast('Not authorized'); return false; }
    if (!res.ok) throw new Error(res.status);
    toast('Done');
    return true;
  } catch (err) {
    toast(`Failed: ${err.message}`);
    return false;
  }
}

// Update: kick off the deploy, then stream the log into a console overlay.
async function runUpdate() {
  if (!LIVE) { toast('Mock mode — run “zmoon web” on the NAS to enable updates'); return; }
  const branch = state?.updateBranch;   // server default used when omitted
  openConsole('Updating from repo…');
  try {
    const res = await fetch('/api/actions/update', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(branch ? { branch } : {}),
    });
    if (res.status === 403) { consoleLine('Actions disabled — set WEB_ADMIN_PASSWORD in .env'); return; }
    if (res.status === 401) { consoleLine('Not authorized.'); return; }
    if (res.status === 409) { consoleLine('An update is already running — attaching to its log…'); }
    else if (!res.ok) { consoleLine(`Failed to start: HTTP ${res.status}`); return; }
    pollLog();
  } catch (err) {
    consoleLine(`Failed to start update: ${err.message}`);
  }
}

async function pollLog() {
  try {
    const res = await fetch('/api/actions/log', { cache: 'no-store' });
    const data = await res.json();
    setConsole(data.log || '');
    if (data.running) {
      setTimeout(pollLog, 1500);
    } else {
      consoleDone();
      setTimeout(() => { detectBackend().then(load); }, 1500);
    }
  } catch (err) {
    consoleLine(`Lost connection to updater: ${err.message} (the moon may be restarting)`);
    consoleDone();
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
    if (e.target.id === 'moon-toggle') { onModeToggle(e.target); return; }
    const t = e.target.closest('[data-authorize]');
    if (!t) return;
    adminPost(`/members/${t.dataset.authorize}/authorize`, { authorized: t.checked })
      .then((ok) => { if (!ok) t.checked = !t.checked; });   // revert on failure/mock
  });
  document.addEventListener('click', (e) => {
    const t = e.target.closest('[data-action]');
    if (!t) return;
    if (t.dataset.action === 'update') {
      if (confirm('Pull the latest code from the repo and reinstall the moon?')) runUpdate();
      return;
    }
    if (t.dataset.action === 'restart') {
      if (confirm('Restart the moon container?')) {
        adminPost('/actions/restart').then((ok) => { if (ok) setTimeout(load, 2000); });
      }
      return;
    }
  });

  $('#refresh-btn').addEventListener('click', () => detectBackend().then(load));
  initTheme();
}

// ── Moon/client mode toggle ──────────────────────────────────────────────────
// Promoting to moon: one confirm dialog. Demoting to client is deliberately
// hard to do by accident: the operator must TYPE the Moon ID exactly — a stray
// click, misclick, or Enter-mash cannot demote a working moon.
async function onModeToggle(box) {
  const wantMoon = box.checked;
  const revert = () => { box.checked = !wantMoon; };
  if (!LIVE) { revert(); toast('Mock mode — run “zmoon web” on the NAS'); return; }

  let confirmText = '';
  if (wantMoon) {
    if (!confirm('Enable MOON mode? This node becomes a root anchor and clients can orbit it.')) { revert(); return; }
  } else {
    const moonId = state?.moon?.id || '';
    const expected = moonId || 'DEMOTE';
    const typed = prompt(
      `DEMOTE this moon to a plain client?\n\n` +
      `Every device orbiting it will lose its root anchor.\n` +
      `Moon files are kept, so re-enabling restores the same Moon ID.\n\n` +
      `Type ${moonId ? `the Moon ID (${moonId})` : `DEMOTE`} to confirm:`);
    if (typed === null || typed.trim().toLowerCase() !== expected.toLowerCase()) {
      revert();
      if (typed !== null) toast('Confirmation did not match — mode unchanged');
      return;
    }
    confirmText = typed.trim();
  }

  openConsole(wantMoon ? 'Switching to MOON mode…' : 'Demoting to CLIENT mode…');
  try {
    const res = await fetch('/api/actions/mode', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ moon: wantMoon, confirm: confirmText }),
    });
    if (res.status === 403) { consoleLine('Actions disabled — set WEB_ADMIN_PASSWORD in .env'); revert(); return; }
    if (res.status === 401) { consoleLine('Not authorized.'); revert(); return; }
    if (res.status === 428) { consoleLine('Server rejected the confirmation — mode unchanged.'); revert(); return; }
    if (res.status === 409) { consoleLine('Another job is running — try again when it finishes.'); revert(); return; }
    if (!res.ok) { consoleLine(`Failed: HTTP ${res.status}`); revert(); return; }
    pollLog();
  } catch (err) {
    consoleLine(`Failed to change mode: ${err.message}`);
    revert();
  }
}

// ── Update console overlay ───────────────────────────────────────────────────
function openConsole(title) {
  let ov = $('#console-overlay');
  if (!ov) {
    ov = document.createElement('div');
    ov.id = 'console-overlay';
    ov.innerHTML = `
      <div class="console-box">
        <div class="console-head">
          <span id="console-title"></span>
          <button class="icon-btn" id="console-close" disabled title="Close">✕</button>
        </div>
        <pre id="console-out" aria-live="polite"></pre>
      </div>`;
    document.body.appendChild(ov);
    $('#console-close').addEventListener('click', () => ov.remove());
  }
  $('#console-title').textContent = title;
  $('#console-out').textContent = '';
  $('#console-close').disabled = true;
  ov.hidden = false;
}
function setConsole(text) {
  const out = $('#console-out');
  if (!out) return;
  out.textContent = text;
  out.scrollTop = out.scrollHeight;
}
function consoleLine(line) {
  const out = $('#console-out');
  if (out) { out.textContent += (out.textContent ? '\n' : '') + line; out.scrollTop = out.scrollHeight; }
}
function consoleDone() {
  consoleLine('\n— finished —');
  const btn = $('#console-close');
  if (btn) btn.disabled = false;
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
detectBackend().then(load);
