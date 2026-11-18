# Design: what was borrowed, and how

## From opencode v2 workspaces

opencode v2 moved its per-workspace state onto the XDG base-directory spec:
instead of one shared `$HOME`, each workspace roots its own
`XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_CACHE_HOME` and `XDG_STATE_HOME`.
The payoff is that N instances on one machine never fight over config,
credentials, caches or databases, and cleanup is `rm -rf` of one directory.
(opencode's own discussions: rooting data/config/cache/state under one
workspace home without touching the user's real XDG, profile isolation via
directory-override env vars.)

`cws` is that idea, applied to Chrome:

| opencode v2 workspace        | cws workspace                              |
| ---------------------------- | ------------------------------------------ |
| XDG dirs rooted per workspace| same, plus `XDG_RUNTIME_DIR` and `TMPDIR`  |
| per-workspace database       | per-workspace `--user-data-dir`            |
| per-workspace config         | per-workspace Chrome prefs/extensions      |
| delete dir = clean slate     | `cws destroy`                              |

Plus the Chrome-specific bits XDG alone does not give you:

- **Stable per-workspace CDP port** (9300+) so automation can attach to *its*
  Chrome - recorded in `meta.env`, survives restarts.
- **Process lifecycle**: pid tracking, tree-kill on stop/destroy.
- **cgroup resource limits** via `systemd-run --scope` when available.
- **Actor storage isolation**: `CRAWLEE_STORAGE_DIR` /
  `APIFY_LOCAL_STORAGE_DIR` per workspace so two actors never share key-value
  stores, request queues or datasets.
- **`HOME` redirection** as belt-and-braces for tools that ignore XDG.

## From tuxee

[agent0ai/tuxee](https://github.com/agent0ai/tuxee) is a ~60 MB Debian
container whose whole job is being a pleasant Linux box in the browser:
persistent terminals, file managers, and a lazy per-terminal X display that
can render GUI apps (their own example is Chromium) into the tab. It is
explicitly built to be "great for admins, perfect for AI agents" and cheap
enough to run many of on one host.

The composition this repo targets:

```
Proxmox host
└── LXC (2 cores, 4-8 GB)
    └── tuxee container  (terminals + file manager in your browser)
        ├── cws workspace A → chrome :9300 → apify actor A
        ├── cws workspace B → chrome :9301 → apify actor B
        └── cws workspace C → chrome :9302 → apify actor C
```

- One LXC, one tuxee, N actors - the Apify Creator Plan's "concurrent runs"
  map naturally onto workspaces.
- Persistent terminals mean `cws launch` + actor processes survive you
  closing the browser.
- `cws launch --headed` in a tuxee terminal shows that workspace's Chrome in
  the tab for interactive debugging/login, reusing tuxee's per-terminal X
  display. tuxee's docs note apps that hand off to an existing process may
  need their new-instance option - Chrome is exactly such an app, and
  `cws` solves it structurally: separate `--user-data-dir` per workspace
  means Chrome never hands off to another workspace's process.

## What this is not

Neither opencode-style XDG isolation nor tuxee's display separation is a
security sandbox, and this repo does not pretend otherwise. It is an
ergonomics layer: no collisions, clean lifecycle, honest resource limits,
one-command teardown. For untrusted workloads, put an LXC between them.
