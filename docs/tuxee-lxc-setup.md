# Running inside tuxee on a Proxmox LXC

The target deployment: one LXC on Proxmox, tuxee inside it, many `cws`
workspaces inside tuxee. You get browser-based persistent terminals and file
management for free, and each terminal can even show its workspace's Chrome as
a GUI app in the browser.

## 1. Create the LXC

A plain Debian 12/13 LXC is fine. Suggested sizing for ~4 parallel scraping
Chromes: 2 cores, 4-8 GB RAM. Enable nesting if you plan to run Docker inside
(`pct set <id> --features nesting=1` on the Proxmox host), or install tuxee
natively instead.

## 2. Run tuxee

Docker route (inside the LXC):

```sh
docker run -d --name tuxee -p 80:80 -p 443:443 \
  -e ROOT_PASSWORD='pick-a-password' \
  -v tuxee-state:/var/lib/tuxee \
  agent0ai/tuxee
```

Native route: see tuxee's install docs (`tuxee service install`).

Open `https://<lxc-ip>` and sign in. Every terminal you open is persistent -
it survives logout and page reloads, which is exactly what long scraping runs
want.

## 3. Install Chrome + cws (in a tuxee terminal)

```sh
# Debian slim base:
apt-get update && apt-get install -y chromium git curl
# or Google's build:
# curl -LO https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
# apt-get install -y ./google-chrome-stable_current_amd64.deb

git clone https://github.com/azjhf-dev/tuxee-chrome-workspaces
cd tuxee-chrome-workspaces
sudo install -m755 bin/cws /usr/local/bin/cws
cws doctor
```

## 4. Run workspaces

Headless (the normal case for actors):

```sh
cws create job-1 && cws launch job-1 --memory 1G --cpu 100%
```

Headed, visible in your browser: tuxee gives each terminal a private X display
endpoint. Just launch headed from that terminal and the Chrome window appears
inside the tuxee tab:

```sh
cws create debug-1 && cws launch debug-1 --headed
```

Handy for solving a captcha or logging a profile in once, then stopping and
re-launching the same workspace headless - the profile (cookies, login
sessions) persists in `chrome-profile/` either way.

## 5. Keep state on the LXC disk

Workspaces live under `~/.local/share/chrome-workspaces` of the tuxee user.
In the Docker route, mount a volume at the user's home (or set
`CWS_ROOT=/persistent/path`) so profiles and actor storage survive container
recreation.

## Notes

- tuxee's per-terminal X displays are not a security boundary (its own docs
  say so), and neither is `cws`'s XDG isolation. Trust boundary = the LXC.
- If you want harder separation, run several tuxee containers on the same LXC
  (it is ~20 MB RAM idle) and use `cws` inside each one.
- `--memory/--cpu` limits need `systemd-run` working inside the container;
  under Docker without systemd, `cws` warns and skips limits. Container-level
  limits (`docker run --memory`) still apply.
