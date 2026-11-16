# LockDown

Omarchy is built for changing things on a whim — drag the bar to another edge,
reorder its widgets, click the workspace glyph to cycle the layout, nudge a
window with `SUPER + -`. That is a lovely desktop right up to the moment a palm
lands on the bar and your layout is somewhere else.

**LockDown keeps those edits behind one switch.** Locked (the default), the bar
cannot be dragged, its widgets cannot be reordered, the workspaces widget does
not cycle the active layout, and no window-resize key does anything. One chord
allows all of it, and the same chord holds it still again.

```
SUPER + CTRL + ALT + L      allow / hold layout edits
```

It is a regular Omarchy plugin — one plugin, id `io.github.djseng.lockdown`, two entry
points (`kinds: ["bar", "bar-widget"]`) — plus one Hyprland config file for the keys.

## What is held

| Gesture | While locked |
|---|---|
| Drag empty bar space (moves the bar to another edge) | nothing is written, so the bar stays put |
| Drag a bar widget (reorders / removes it) | nothing is written, so the order snaps back |
| Click the **active** workspace glyph (cycles dwindle / scrolling / floating) | does nothing; clicking any *other* workspace still switches to it |
| `SUPER + -` / `SUPER + =` and their 10 SHIFT/ALT/CTRL variants | unbound — the key reaches the app |
| `SUPER +` right-drag on a window | unbound |
| Double-click the bar (cycles its background) | held: the bar keeps the background it locked with, and a change that lands in `shell.json` is written back |

Everything that is not a layout edit keeps working: switching and focusing
workspaces, panels and menus, moving windows between workspaces and monitors,
closing, fullscreen, `SUPER + Tab`, and `SUPER + L` (a chord is deliberate, a
click is not).

## How it is built (and why it survives updates)

Three pieces, none of which patches a file under `/usr/share/omarchy`:

1. **`Bar.qml` — a 120-line mount, not a bar.** Omarchy's bar is itself a plugin
   (`omarchy.bar`). Instead of shipping a copy, this plugin `<Loader>`s the bar
   the running Omarchy ships and hands it a shell object. Whether the bar may
   persist an edit is something the bar asks its shell — so while locked the
   shell it gets has no `mutateShellConfig`, and the bar's own drag machinery
   never starts; a bar move that lands anyway is put back. An `omarchy update`
   therefore brings new bar work straight into LockDown: there is nothing to
   regenerate, re-anchor or merge.
2. **`Workspaces.qml` — one widget, copied.** The active-workspace click spawns
   `omarchy-hyprland-workspace-layout-toggle`, and a plugin cannot intercept a
   command the bar spawns for itself (QML methods are read-only, so `bar.run`
   cannot be wrapped). This is the one place a copy is unavoidable today, so it
   copies the smallest thing that works: Omarchy's 287-line
   `widgets/Workspaces.qml` with the same two-line guard Omarchy's own proposed
   config-lock patch adds. Customizing a built-in widget by cloning it is
   Omarchy's documented way to do this.
3. **`hypr/lockdown.lua` — the keys.** The twelve resize chords are unbound from
   the normal keymap and redefined inside a `customize` Hyprland submap that is
   only entered while unlocked, so while locked they do not exist at all. The
   submap's catchall is non-consuming: it adds the resize chords without taking
   the rest of the keyboard away.

The state is Omarchy's own spelling for this lock — the file
`~/.local/state/omarchy/toggles/config-lock`, which is what
[`omacom/omarchy#18082`](https://github.com/omacom/omarchy/pull/18082) (bar,
workspaces and dock guards) watches, and what the companion
[config-lock widget](https://github.com/Da1NOnlyCheezIt/omarchy-config-lock)
toggles. `omarchy toggle config-lock on|off` drives it too.

## Credits

- **Omarchy** — [omacom/omarchy](https://github.com/omacom/omarchy), MIT,
  © David Heinemeier Hansson. The bar this plugin mounts and the
  `Workspaces.qml` it vendors are Omarchy's.
- **[omacom/omarchy#18082](https://github.com/omacom/omarchy/pull/18082)** —
  "Add config-lock guards for bar, workspaces, and dock", by
  [@Da1NOnlyCheezIt](https://github.com/Da1NOnlyCheezIt). That proposal is where
  the idea of a single shared lock file, its path
  (`~/.local/state/omarchy/toggles/config-lock`), the click-vs-chord split, and
  the exact guard this repo makes in `Workspaces.qml` all come from. If the
  change merges, use it instead of this plugin.
- **[Da1NOnlyCheezIt/omarchy-config-lock](https://github.com/Da1NOnlyCheezIt/omarchy-config-lock)**
  — the companion bar widget for that proposal, which toggles the same flag. It
  works alongside LockDown's switch (either can flip it), and becomes the
  natural UI for this lock once the guards are in the shell.
- **Hyprland** ([hyprwm/Hyprland](https://github.com/hyprwm/Hyprland)) for the
  submap mechanism the resize keys use.

### The exit plan

When #18082 lands, delete the plugin and keep `bin/lockdown` +
`hypr/lockdown.lua`. The flag then does the bar/workspaces/dock half natively,
and only the resize-key submap (which upstream leaves alone) stays local.

## Known gaps

- **The background hold undoes, it does not prevent.** Double-clicking still
  runs `omarchy-bar background cycle`; the bar is handed the background it
  locked with, and the value that lands in `shell.json` is written back a moment
  later, so neither the screen nor the file changes. `omarchy bar background …`
  is held the same way while locked. Upstream #18082 refuses the gesture
  outright.
- **A drag on empty bar space still highlights an edge.** The bar draws that
  preview itself before the release is undone — the bar never moves and nothing
  is written. Dragging a *widget* shows nothing at all: the bar's own check
  (`typeof shell.mutateShellConfig === "function"`) fails while locked, so the
  drag never begins. Upstream #18082 refuses the bar gesture outright.
- **`SUPER + L` still cycles the workspace layout.** Deliberate, and the same
  split upstream chose. To put the chords behind the switch too, add to
  `hypr/lockdown.lua`:

  ```lua
  hl.unbind("SUPER + L")
  hl.unbind("SUPER + ALT + L")
  hl.define_submap("customize", function()
    -- ...the existing binds...
    o.bind("SUPER + L", "Cycle workspace layout", "omarchy-hyprland-workspace-layout-toggle")
    o.bind("SUPER + ALT + L", "Cycle workspace layout back", "omarchy-hyprland-workspace-layout-toggle back")
  end)
  ```

## Dependencies

- **Omarchy 4.5+ (Quattro)** — the shell that hosts bar plugins, and Hyprland 0.56+
  for the Lua `hyprctl dispatch` form (the switch falls back to the legacy
  spelling on older releases).
- **No packages, services, or network access.** Nothing is fetched at runtime and
  no third-party libraries are used.
- **`python3`** is used by `install.sh` only, to edit `shell.json` and
  `hyprland.lua`. The plugin itself never runs it.

## Install

```bash
git clone https://github.com/djseng/lockdown.git
cd lockdown
./install.sh          # copy into ~/.config/omarchy/plugins/
./install.sh --link   # ...or symlink this checkout, for hacking on it
```

`install.sh` writes only user files:

- `~/.config/omarchy/plugins/io.github.djseng.lockdown/` — the plugin: `Bar.qml` (mounts
  Omarchy's bar) and `Workspaces.qml` (the guarded widget)
- `~/.local/bin/lockdown` — the switch
- `~/.config/hypr/lockdown.lua` — the resize-key submap and the one chord
- `~/.config/hypr/hyprland.lua` — adds `require("hypr.lockdown")`
- `~/.config/omarchy/shell.json` — `bar.id`, and the widget id in the layout

It ends by restarting the shell, because a bar plugin is mounted when the shell
starts rather than by switching `bar.id` afterwards.

### The plugin half on its own

```bash
omarchy plugin add https://github.com/djseng/lockdown.git
omarchy bar use io.github.djseng.lockdown    # mount the guarded bar
# then swap the workspaces widget for the plugin's, and restart the shell:
jq --arg id io.github.djseng.lockdown \
   '.bar.layout.left |= map(if .id == "omarchy.workspaces" then .id = $id else . end)' \
   ~/.config/omarchy/shell.json > /tmp/shell.json && mv /tmp/shell.json ~/.config/omarchy/shell.json
omarchy restart shell
```

That installs the bar and the widget; the keybinding half is
`hypr/lockdown.lua` plus an `omarchy restart shell`.

## The switch

```bash
lockdown            # toggle
lockdown unlock     # allow edits
lockdown lock       # hold them (also what a new session starts in)
lockdown status     # locked | unlocked
```

## Uninstall

```bash
omarchy bar reset
rm -f ~/.local/bin/lockdown ~/.config/hypr/lockdown.lua
rm -rf ~/.config/omarchy/plugins/io.github.djseng.lockdown
# delete the require("hypr.lockdown") line from ~/.config/hypr/hyprland.lua
# and put "omarchy.workspaces" back in the bar layout in shell.json
hyprctl reload && omarchy restart shell
```

## Licence

MIT. `Workspaces.qml` is Omarchy's own widget, MIT licensed, © David Heinemeier
Hansson — see `LICENSE`.
