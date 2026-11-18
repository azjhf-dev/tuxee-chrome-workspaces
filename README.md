# tuxee-chrome-workspaces

Run many isolated Chrome instances - and therefore many parallel Apify/Crawlee
actors - on a single Linux box or LXC container, without profiles, caches,
cookies, state or debug ports ever colliding.

One dependency: `bash`. Chrome/Chromium and (optionally) `systemd-run` for
resource limits.

## Where the idea comes from

**opencode v2 workspaces (XDG isolation).** opencode v2 isolates each
workspace by rooting the XDG base directories (`XDG_CONFIG_HOME`,
`XDG_DATA_HOME`, `XDG_CACHE_HOME`, `XDG_STATE_HOME`) inside the workspace
instead of sharing `$HOME`. Same machine, many identities, zero collisions.
`cws` applies exactly that model to Chrome: every workspace gets its own XDG
tree, plus its own `--user-data-dir`, remote-debugging port, tmpdir, runtime
dir and Apify/Crawlee storage dir.

**tuxee** ([agent0ai/tuxee](https://github.com/agent0ai/tuxee)) is a tiny
Debian container (~60 MB image, ~20 MB RAM idle) that gives you persistent
terminals and a file manager in the browser, and can even display Linux GUI
apps (Chromium included) in a browser tab, one private X display per terminal.
It is the cheap workload unit this tool is designed to run inside: one tuxee
container on one Proxmox LXC, many `cws` workspaces inside it. See
[docs/tuxee-lxc-setup.md](docs/tuxee-lxc-setup.md).

## Install

```sh
git clone https://github.com/azjhf-dev/tuxee-chrome-workspaces
cd tuxee-chrome-workspaces
sudo install -m755 bin/cws /usr/local/bin/cws   # or just use ./bin/cws
cws doctor
```

## Quickstart

```sh
cws create reddit-scraper
cws create pg-scraper

cws launch reddit-scraper --memory 1G --cpu 100%      # headless by default
cws launch pg-scraper    --memory 1G --cpu 100%

cws list
# NAME                     PORT     RUNNING  CREATED
# reddit-scraper           9300     yes      2026-11-18T03:00:00Z
# pg-scraper               9301     yes      2026-11-18T03:00:11Z

# run anything inside a workspace (env is fully isolated):
cws run reddit-scraper -- node my-actor.js

cws stop reddit-scraper
cws destroy pg-scraper --force
```

Headed mode exists for tuxee GUI terminals: `cws launch NAME --headed` shows
the browser in your tuxee tab (each tuxee terminal already has a private X
display - see the docs).

## Parallel Apify actors

Each workspace exports `APIFY_LOCAL_STORAGE_DIR` and `CRAWLEE_STORAGE_DIR`
pointing at its own storage, plus `CHROME_DEBUG_PORT` so your actor can attach
to its own Chrome over CDP. A complete runnable example lives in
[examples/apify-parallel](examples/apify-parallel):

```sh
cd examples/apify-parallel
./run-actors.sh reddit-threads github-trending sg-property
```

Three workspaces, three Chromes, three actors, one LXC.

## What a workspace actually is

```
~/.local/share/chrome-workspaces/reddit-scraper/
  xdg/config        XDG_CONFIG_HOME
  xdg/data          XDG_DATA_HOME
  xdg/cache         XDG_CACHE_HOME
  xdg/state         XDG_STATE_HOME (+ chrome.log)
  runtime           XDG_RUNTIME_DIR (0700)
  tmp               TMPDIR
  chrome-profile    --user-data-dir (cookies, history, extensions)
  apify-storage     CRAWLEE_STORAGE_DIR / APIFY_LOCAL_STORAGE_DIR
  meta.env          name, created-at, stable debug port, chrome pid
```

`HOME` is also redirected into the workspace during `launch`/`run`, so even
tools that ignore XDG stay inside.

## Resource limits

`--memory 1G --cpu 150%` uses `systemd-run --scope` (cgroup v2) when it works;
on containers where systemd-run exists but can't create scopes, `cws` probes
it, warns, and launches without limits instead of failing. Chrome-level
limits (`--js-flags=--max-old-space-size=...`) can be passed after `--`.

## Tests

```sh
bash tests/run-tests.sh
```

30 checks against a stub Chrome: creation, XDG isolation, port allocation,
launch flags, lifecycle, cleanup. No real browser needed.

## Honest limitations

- **This is collision-avoidance, not a security sandbox.** Workspaces share
  the kernel, network and user. For hard isolation run separate LXC
  containers (one tuxee each) - `cws` then keeps the Chromes inside each LXC
  clean. tuxee's own docs say the same about its display separation.
- `cws launch` defaults to `--no-sandbox` because most LXCs/containers lack
  the user-namespace setup Chrome's sandbox needs. Export `CWS_NO_SANDBOX=0`
  on hosts where the sandbox works.
- Debug ports are localhost CDP endpoints. Anything that can talk to
  localhost:93xx controls that Chrome. Keep the box private or firewall it.
- Resource limits require a working `systemd-run` (root on the LXC is fine).

## License

MIT - see [LICENSE](LICENSE).
