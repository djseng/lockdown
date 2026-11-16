#!/usr/bin/env bash
# LockDown installer for the current user.
#
#   ./install.sh          install
#   ./install.sh --link    same, but symlink this checkout instead of copying it
#
# It never touches /usr/share/omarchy. What it writes:
#   ~/.config/omarchy/plugins/io.github.djseng.lockdown/   the plugin: bar + workspaces widget
#   ~/.local/bin/lockdown                        the switch, on PATH
#   ~/.config/hypr/lockdown.lua                  resize-key submap + one chord
#   ~/.config/hypr/hyprland.lua                  one require() line added
#   ~/.config/omarchy/shell.json                 bar.id + the widget id in the layout
#
# The bar half copies no Omarchy code: it mounts $OMARCHY_PATH/shell/plugins/bar/Bar.qml
# live, so there is nothing to regenerate after an update. The widget half is a copy
# of one 287-line widget file — the same file Omarchy's proposed config-lock guard
# patches (omacom/omarchy#18082) — so it is deletable when that lands.

set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
omarchy_path="${OMARCHY_PATH:-/usr/share/omarchy}"
plugin_id="io.github.djseng.lockdown"
plugins_dir="$HOME/.config/omarchy/plugins"
target="$plugins_dir/$plugin_id"
local_bin="$HOME/.local/bin"
hypr_dir="$HOME/.config/hypr"
link_mode=0

for arg in "$@"; do
  case "$arg" in
  --link) link_mode=1 ;;
  -h | --help)
    sed -n '2,18p' "${BASH_SOURCE[0]}"
    exit 0
    ;;
  *)
    echo "install: unknown option $arg" >&2
    exit 1
    ;;
  esac
done

say() { printf '%s\n' "$*"; }
die() {
  printf 'install: %s\n' "$*" >&2
  exit 1
}

[[ -d $omarchy_path/shell/plugins/bar ]] ||
  die "no Omarchy bar found at $omarchy_path (set OMARCHY_PATH)"

say "==> Installing the plugin into $target"
mkdir -p "$plugins_dir"
if [[ $link_mode -eq 1 ]]; then
  [[ $target -ef $repo ]] || rm -rf "$target"
  ln -sfn "$repo" "$target"
else
  [[ $target -ef $repo ]] && rm -f "$target"
  rm -rf "$target"
  mkdir -p "$target"
  cp -a "$repo/manifest.json" "$repo/Bar.qml" "$repo/Workspaces.qml" "$repo/bin" \
    "$repo/hypr" "$repo/README.md" "$repo/LICENSE" "$target/"
fi
chmod +x "$target/bin/lockdown"

say "==> Linking $local_bin/lockdown"
mkdir -p "$local_bin"
ln -sfn "$target/bin/lockdown" "$local_bin/lockdown"

say "==> Installing $hypr_dir/lockdown.lua"
mkdir -p "$hypr_dir"
cp -f "$repo/hypr/lockdown.lua" "$hypr_dir/lockdown.lua"

if ! grep -q 'require("hypr.lockdown")' "$hypr_dir/hyprland.lua" 2>/dev/null; then
  say "==> Adding require(\"hypr.lockdown\") to $hypr_dir/hyprland.lua"
  cp -f "$hypr_dir/hyprland.lua" "$hypr_dir/hyprland.lua.bak.$(date +%s)"
  python3 - "$hypr_dir/hyprland.lua" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
needle = 'require("hypr.bindings")\n'
add = needle + 'require("hypr.lockdown")\n'
if needle in text:
    text = text.replace(needle, add, 1)
else:
    text = text.rstrip("\n") + '\n\nrequire("hypr.lockdown")\n'
open(path, "w").write(text)
PY
fi

say "==> Pointing the bar and its workspaces widget at LockDown"
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
if ! omarchy bar use "$plugin_id" >/dev/null 2>&1; then
  say "    omarchy bar use declined; writing bar.id directly"
fi
python3 - "$HOME/.config/omarchy/shell.json" "$plugin_id" <<'PY'
import json, os, sys
path, plugin_id = sys.argv[1:3]
data = json.load(open(path)) if os.path.exists(path) else {"version": 1}
bar = data.setdefault("bar", {})
bar["id"] = plugin_id
layout = bar.setdefault("layout", {})
# Ids that mean "the workspaces widget": the built-in, the two ids this plugin
# has shipped under, and its current one. The first one found is rewritten to
# plugin_id; any further copy is dropped so re-running never doubles the row.
widget_ids = {"omarchy.workspaces", "djseng.workspaces", "djseng.lockdown", plugin_id}
placed = False
for entries in layout.values():
    if not isinstance(entries, list):
        continue
    kept = []
    for entry in entries:
        if isinstance(entry, dict) and entry.get("id") in widget_ids:
            if placed:
                continue
            entry["id"] = plugin_id
            placed = True
        kept.append(entry)
    entries[:] = kept
if not placed:
    layout.setdefault("left", []).insert(1, {"id": plugin_id})
json.dump(data, open(path, "w"), indent=2)
open(path, "a").write("\n")
print("    bar.id ->", plugin_id, "| workspaces ->", plugin_id, "" if placed else "(added)")
PY

# Leftovers from earlier builds: a separate widget plugin, a vendored bar with
# its rebuild hook, and two PATH shims that a login shell never resolved.
for stale in "$plugins_dir/djseng.workspaces" \
  "$plugins_dir/djseng.lockdown" \
  "$HOME/.config/omarchy/hooks/post-update.d/lockdown-rebuild.hook" \
  "$local_bin/omarchy-hyprland-workspace-layout-toggle" \
  "$local_bin/omarchy-bar"; do
  [[ -e $stale ]] && mv "$stale" /tmp/ && say "==> Removed stale $(basename "$stale")"
done

hyprctl reload >/dev/null 2>&1 || true
"$local_bin/lockdown" lock >/dev/null 2>&1 || true

# A bar plugin is mounted when the shell starts, so the first install needs one
# restart rather than a bar switch.
say "==> Restarting the shell so the plugin mounts"
omarchy restart shell >/dev/null 2>&1 || true
sleep 3

cat <<DONE

LockDown installed.

  SUPER + CTRL + ALT + L    allow / hold layout edits

Locked (the default): the bar cannot be dragged, bar widgets cannot be
reordered, the workspaces widget does not cycle the active layout, and no
window-resize key does anything. Clicking any other workspace still switches.

Still live while locked, on purpose: SUPER + L (a chord is deliberate, a click
is not) and Omarchy's own commands. Double-clicking the bar still cycles its
background: that command is spawned by the bar itself, and Omarchy's proposed
guard for it (omacom/omarchy#18082) is what closes it.

Uninstall: omarchy bar reset
  rm -f ~/.local/bin/lockdown ~/.config/hypr/lockdown.lua
  rm -rf "$target"
  then delete the require("hypr.lockdown") line from ~/.config/hypr/hyprland.lua
  and put "omarchy.workspaces" back in the bar layout in shell.json
DONE
