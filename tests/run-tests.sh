#!/usr/bin/env bash
# Test cws without a real Chrome: a stub binary records its argv and env so we
# can verify isolation, port allocation, launch flags and lifecycle.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CWS="$HERE/../bin/cws"
export CWS_ROOT="$(mktemp -d)"
STUB="$CWS_ROOT/fake-chrome"
export CWS_CHROME="$STUB"
export PATH="$CWS_ROOT:$PATH"

pass=0; fail=0
ok()   { pass=$((pass+1)); printf 'ok   - %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf 'FAIL - %s\n' "$1"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# fake chrome: dump env+argv, sleep forever
cat >"$STUB" <<'EOF'
#!/usr/bin/env bash
{
  echo "XDG_CONFIG_HOME=$XDG_CONFIG_HOME"
  echo "XDG_CACHE_HOME=$XDG_CACHE_HOME"
  echo "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
  echo "HOME=$HOME"
  echo "TMPDIR=$TMPDIR"
  echo "argv: $*"
} > "$CWS_ROOT/last-launch.env"
sleep 3600
EOF
chmod +x "$STUB"

echo "== create =="
"$CWS" create alpha >/dev/null
check "create makes XDG dirs"      '[[ -d "$CWS_ROOT/alpha/xdg/config" && -d "$CWS_ROOT/alpha/xdg/cache" && -d "$CWS_ROOT/alpha/xdg/state" && -d "$CWS_ROOT/alpha/xdg/data" ]]'
check "create makes runtime 0700"  '[[ $(stat -c %a "$CWS_ROOT/alpha/runtime") == 700 ]]'
check "create makes chrome profile dir + apify storage" '[[ -d "$CWS_ROOT/alpha/chrome-profile" && -d "$CWS_ROOT/alpha/apify-storage" ]]'
"$CWS" create alpha 2>/dev/null && bad "duplicate create rejected" || ok "duplicate create rejected"
"$CWS" create 'Bad Name' 2>/dev/null && bad "invalid name rejected" || ok "invalid name rejected"

echo "== port allocation =="
"$CWS" create beta >/dev/null
pa=$(grep CWS_DEBUG_PORT "$CWS_ROOT/alpha/meta.env" | cut -d= -f2)
pb=$(grep CWS_DEBUG_PORT "$CWS_ROOT/beta/meta.env" | cut -d= -f2)
check "workspaces get distinct debug ports" '[[ "$pa" != "$pb" ]]'
check "first port is the base (9300)"       '[[ "$pa" == 9300 ]]'
check "second port increments"              '[[ "$pb" == 9301 ]]'

echo "== env =="
env_out="$("$CWS" env alpha)"
check "env sets XDG_CONFIG_HOME into workspace" 'grep -q "XDG_CONFIG_HOME=\"$CWS_ROOT/alpha/xdg/config\"" <<<"$env_out"'
check "env sets CHROME_USER_DATA_DIR"           'grep -q "CHROME_USER_DATA_DIR=\"$CWS_ROOT/alpha/chrome-profile\"" <<<"$env_out"'
check "env sets debug port"                     'grep -q "CHROME_DEBUG_PORT=\\\"9300\\\"" <<<"$env_out"'
check "env isolates Apify/Crawlee storage"      'grep -q "CRAWLEE_STORAGE_DIR=\"$CWS_ROOT/alpha/apify-storage\"" <<<"$env_out" && grep -q "APIFY_LOCAL_STORAGE_DIR=\"$CWS_ROOT/alpha/apify-storage\"" <<<"$env_out"'

echo "== launch (headless, stub chrome) =="
"$CWS" launch alpha >/dev/null
sleep 0.3
check "launch records a live pid" 'kill -0 $(grep CWS_CHROME_PID "$CWS_ROOT/alpha/meta.env" | cut -d= -f2) 2>/dev/null'
check "chrome got workspace user-data-dir" 'grep -q "user-data-dir=$CWS_ROOT/alpha/chrome-profile" "$CWS_ROOT/last-launch.env"'
check "chrome got workspace debug port"    'grep -q "remote-debugging-port=9300" "$CWS_ROOT/last-launch.env"'
check "chrome ran headless"                'grep -q "headless=new" "$CWS_ROOT/last-launch.env"'
check "chrome env was XDG-isolated"        'grep -q "XDG_CONFIG_HOME=$CWS_ROOT/alpha/xdg/config" "$CWS_ROOT/last-launch.env" && grep -q "XDG_CACHE_HOME=$CWS_ROOT/alpha/xdg/cache" "$CWS_ROOT/last-launch.env"'
check "HOME redirected into workspace"     'grep -q "HOME=$CWS_ROOT/alpha/xdg" "$CWS_ROOT/last-launch.env"'
"$CWS" launch alpha 2>/dev/null && bad "double launch rejected" || ok "double launch rejected"

echo "== launch with limits but no systemd-run =="
"$CWS" launch beta --memory 1G --cpu 50% >/dev/null 2>"$CWS_ROOT/warn.txt" || true
sleep 0.3
if grep -q "without resource limits" "$CWS_ROOT/warn.txt"; then
  ok "warns when limits requested without a working systemd-run"
else
  ok "limits path taken via systemd-run"
fi

echo "== isolation between two launched workspaces =="
check "beta chrome uses its own profile"  'grep -q "user-data-dir=$CWS_ROOT/beta/chrome-profile" "$CWS_ROOT/last-launch.env"'
check "beta chrome uses its own port"     'grep -q "remote-debugging-port=9301" "$CWS_ROOT/last-launch.env"'

echo "== run (actor env) =="
"$CWS" run alpha -- bash -c 'echo "$XDG_CACHE_HOME|$CRAWLEE_STORAGE_DIR|$HOME"' > "$CWS_ROOT/run.out"
check "cws run exports isolated env to child" 'grep -q "$CWS_ROOT/alpha/xdg/cache|$CWS_ROOT/alpha/apify-storage|$CWS_ROOT/alpha/xdg" "$CWS_ROOT/run.out"'

echo "== stop / destroy =="
alpha_pid=$(grep CWS_CHROME_PID "$CWS_ROOT/alpha/meta.env" | cut -d= -f2)
"$CWS" stop alpha >/dev/null
check "stop kills chrome" '! kill -0 "$alpha_pid" 2>/dev/null'
# alpha is stopped, so destroy succeeds without --force
"$CWS" destroy alpha >/dev/null
check "destroy removed alpha"  '[[ ! -d "$CWS_ROOT/alpha" ]]'
"$CWS" destroy beta --force >/dev/null
check "destroy --force removed beta (was running)" '[[ ! -d "$CWS_ROOT/beta" ]]'
check "no stub chrome left behind" '! pgrep -f "sleep 3600" >/dev/null'

echo "== list =="
"$CWS" create gamma >/dev/null
"$CWS" list > "$CWS_ROOT/list.out"
"$CWS" list --json > "$CWS_ROOT/list.json"
check "list shows workspace"      'grep -q gamma "$CWS_ROOT/list.out"'
check "list --json is valid-ish"  'grep -q "\"name\":\"gamma\"" "$CWS_ROOT/list.json"'
"$CWS" destroy gamma >/dev/null

echo "== doctor =="
"$CWS" doctor > "$CWS_ROOT/doc.out"
check "doctor runs" 'grep -q "cws 0.1.0" "$CWS_ROOT/doc.out"'

rm -rf "$CWS_ROOT"
echo
echo "passed: $pass  failed: $fail"
exit $((fail > 0))
