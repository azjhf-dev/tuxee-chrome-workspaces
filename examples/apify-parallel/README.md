# Example: parallel Apify actors

One command runs the same actor in N isolated workspaces at once:

```sh
npm --prefix actor install
./run-actors.sh reddit-threads github-trending sg-property
```

What happens per NAME:

1. `cws create NAME` - workspace with its own XDG tree, Chrome profile,
   debug port (9300+) and `apify-storage/` (skipped if it already exists).
2. `cws launch NAME --memory $MEM --cpu $CPU` - headless Chrome for that
   workspace only (defaults: 1 GB, 1 core each; override via env).
3. `cws apify NAME -- node actor/main.js` - the actor runs inside the
   workspace env: it attaches to *its* Chrome over CDP
   (`CHROME_DEBUG_PORT`) and writes datasets to *its* storage
   (`CRAWLEE_STORAGE_DIR`).

Ctrl-C stops the actors and their Chromes; workspaces (profiles + storage)
stay on disk for the next run. `cws destroy NAME --force` wipes one clean.

Different actors per workspace? Point each run at a different directory:

```sh
cws apify reddit-threads -- node actors/reddit/main.js &
cws apify sg-property    -- node actors/property/main.js &
```

Running against Apify platform instead of locally? The workspace isolation
works the same - only storage location changes. Keep `APIFY_TOKEN` out of the
repo; export it in the tuxee terminal or a `.env` you gitignore.
