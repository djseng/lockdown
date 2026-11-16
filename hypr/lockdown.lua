-- LockDown -- layout-editing keys wait for one chord.
--
-- Omarchy is built for changing things on a whim, which is lovely until a palm
-- lands on the keyboard or the bar. LockDown keeps the layout-editing half of
-- the desktop behind a switch:
--
--   SUPER + CTRL + ALT + L   allow / hold layout edits
--
-- The switch is a file (see bin/lockdown):
-- `~/.local/state/omarchy/toggles/config-lock`, the same flag Omarchy's own
-- proposed config-lock guards watch (omacom/omarchy#18082). Unlocking also
-- enters the "customize" Hyprland submap below, and the window-resize keys
-- exist only inside it -- so while locked they are not bound at all and a stray
-- chord reaches the app instead of resizing a window. While unlocked everything
-- else keeps working normally: the submap's catchall is non-consuming.

local home = os.getenv("HOME") or ""

local switch = home .. "/.local/bin/lockdown"
local probe = io.open(switch, "r")
if probe then
  probe:close()
else
  switch = home .. "/.config/omarchy/plugins/io.github.djseng.lockdown/bin/lockdown"
end

o.bind("SUPER + CTRL + ALT + L", "LockDown: allow / hold layout edits", switch .. " toggle")

-- A session that ends while unlocked must not start unlocked: Hyprland resets
-- the submap, so the flag is what would be left stale.
if not lockdown_start_hooked then
  lockdown_start_hooked = true
  hl.on("hyprland.start", function()
    hl.exec_cmd(switch .. " lock")
  end)
end

-- The resize keys already exist in Omarchy's default bindings; take them out of
-- the normal keymap first, so they live only in the submap below.
local size_keys = {
  "SUPER + code:20",
  "SUPER + code:21",
  "SUPER + SHIFT + code:20",
  "SUPER + SHIFT + code:21",
  "SUPER + ALT + code:20",
  "SUPER + ALT + code:21",
  "SUPER + SHIFT + ALT + code:20",
  "SUPER + SHIFT + ALT + code:21",
  "SUPER + CTRL + code:20",
  "SUPER + CTRL + code:21",
  "SUPER + CTRL + SHIFT + code:20",
  "SUPER + CTRL + SHIFT + code:21",
  "SUPER + mouse:273",
}

for _, key in ipairs(size_keys) do
  hl.unbind(key)
end

hl.define_submap("customize", function()
  -- Window resizing, from Omarchy's own tiling binds. None of these exist while
  -- locked.
  o.bind("SUPER + code:20", "Expand window left", hl.dsp.window.resize({ x = -100, y = 0, relative = true }))
  o.bind("SUPER + code:21", "Shrink window left", hl.dsp.window.resize({ x = 100, y = 0, relative = true }))
  o.bind("SUPER + SHIFT + code:20", "Shrink window up", hl.dsp.window.resize({ x = 0, y = -100, relative = true }))
  o.bind("SUPER + SHIFT + code:21", "Expand window down", hl.dsp.window.resize({ x = 0, y = 100, relative = true }))

  o.bind("SUPER + ALT + code:20", "Expand window left a little", hl.dsp.window.resize({ x = -25, y = 0, relative = true }))
  o.bind("SUPER + ALT + code:21", "Shrink window left a little", hl.dsp.window.resize({ x = 25, y = 0, relative = true }))
  o.bind("SUPER + SHIFT + ALT + code:20", "Shrink window up a little", hl.dsp.window.resize({ x = 0, y = -25, relative = true }))
  o.bind("SUPER + SHIFT + ALT + code:21", "Expand window down a little", hl.dsp.window.resize({ x = 0, y = 25, relative = true }))

  o.bind("SUPER + CTRL + code:20", "Expand window left a lot", hl.dsp.window.resize({ x = -300, y = 0, relative = true }))
  o.bind("SUPER + CTRL + code:21", "Shrink window left a lot", hl.dsp.window.resize({ x = 300, y = 0, relative = true }))
  o.bind("SUPER + CTRL + SHIFT + code:20", "Shrink window up a lot", hl.dsp.window.resize({ x = 0, y = -300, relative = true }))
  o.bind("SUPER + CTRL + SHIFT + code:21", "Expand window down a lot", hl.dsp.window.resize({ x = 0, y = 300, relative = true }))

  -- Right-drag a window to resize it.
  o.bind("SUPER + mouse:273", "Resize window", hl.dsp.window.resize(), { mouse = true })

  -- Holding them still again, from the same chord that allowed them.
  o.bind("SUPER + CTRL + ALT + L", "LockDown: hold layout edits", switch .. " lock")

  -- Everything not named here still reaches the normal bindings.
  o.bind("catchall", "Pass through", hl.dsp.no_op(), { non_consuming = true })
end)
