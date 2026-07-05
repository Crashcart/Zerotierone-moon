# ZeroTier Moon — Web Console

A single-page console for the moon, plain **HTML/CSS/JS** — no build step, no
framework, no dependencies. Open it, edit it, serve it from the NAS.

```
web/
├── index.html          # page shell — three tabs
├── style.css           # all styling (theme-aware, light/dark)
├── app.js              # data load + render + actions
├── status.sample.json  # demo data so the page renders offline
└── README.md           # this file
```

## Tabs

- **Dashboard** — moon online/offline, moon ID, uptime, version, endpoints,
  interfaces, and the live peer table.
- **Members** — the network's members with an authorize toggle, plus
  *Update moon* / *Restart moon* actions. (Admin — needs a backend, see below.)
- **Connect** — your own client's info, the orbit command (auto-filled with the
  real moon ID), the install one-liner, and per-OS connect steps.

## Run it locally

It's static, but it `fetch()`es JSON so it needs HTTP (not `file://`):

```sh
cd web
python3 -m http.server 8080
# open http://localhost:8080
```

Out of the box it loads `status.sample.json` and shows a **"Demo data"** banner.

## Wiring the real moon (two knobs, top of `app.js`)

```js
const DATA_URL  = 'status.sample.json';  // → '/api/status'  (live read-only feed)
const ADMIN_API = '';                    // → '/api'          (enables the action buttons)
```

- `DATA_URL` — any URL that returns the JSON shape below. Read-only; the
  Dashboard/Members/Connect views all render from it.
- `ADMIN_API` — base path for the write actions (authorize toggle, update,
  restart). Leave blank to keep the buttons in safe **mock mode** (they toast
  instead of doing anything).

### Data contract (`GET /api/status`)

```jsonc
{
  "generatedAt": 1751731200,            // epoch seconds
  "moon":  { "id", "online", "version", "uptimeSeconds",
             "endpoints": { "lan1", "lan2", "public" } },
  "interfaces": [ { "name", "ip", "subnet", "gateway", "up" } ],
  "peers":      [ { "address", "role", "latencyMs", "version",
                    "paths": [ { "address", "active" } ], "lastSeenSeconds" } ],
  "network":    { "id", "name", "ipPool", "routes": [ { "target", "via" } ] },
  "members":    [ { "address", "name", "authorized",
                    "ipAssignments": [], "online", "lastSeenSeconds" } ],
  "client":     { "address", "ip", "online", "orbitedMoon" }
}
```

Include `"_sample": true` to force the demo banner; omit it for live data.

### Admin endpoints (only when `ADMIN_API` is set)

| Button            | Call                                             |
|-------------------|--------------------------------------------------|
| Authorize toggle  | `POST /api/members/<addr>/authorize` `{authorized}` |
| Update moon       | `POST /api/actions/update`                       |
| Restart moon      | `POST /api/actions/restart`                      |

## Where the data comes from

A small producer on the NAS builds `status.json` from what the moon already
exposes — no new dependencies:

- **Moon / peers** — `docker exec <container> zerotier-cli -j status` and
  `... listpeers`.
- **Members / network** — the self-hosted controller API on the moon:
  `curl -H "X-ZT1-Auth: $(cat authtoken.secret)" localhost:9993/controller/network/<nid>/member`.
- **Client** — the requesting browser's own node, resolved the same way.

A `zmoon status --json` subcommand (writing this document, served as
`/api/status`) is the natural home for that producer. The front-end is already
built against the contract above, so wiring it is: emit the JSON, flip the two
knobs in `app.js`.

> **No secrets in this folder.** `status.sample.json` uses placeholder IDs and
> generic RFC-5737/1918 example IPs only. The real network ID and any auth token
> live on the NAS, never in the repo.
