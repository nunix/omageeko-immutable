-- Keep only your personal keybinding overrides here. Add new bindings with
-- o.bind or replace defaults with o.rebind.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Change an existing binding. o.rebind takes the same arguments as o.bind.
-- This example replaces the default file manager with Flea.
-- o.rebind("SUPER + SHIFT + F", "File manager", { launch = "flea" })

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- Logitech MX Keys examples:
-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, { panel = "omarchy.emojis" })

-- omageeko (21K6S0A00C): MX thumb wheel cycles this monitor's workspaces 1-10,
-- wrapping around, plus one free workspace (see docs/touchpad-and-mouse.md).
-- These capture horizontal scrolling everywhere; use "SUPER + mouse_left" /
-- "SUPER + mouse_right" instead to keep it in apps.
o.bind("mouse_left", "Previous workspace (carousel)", "omarchy-hyprland-workspace-carousel left")
o.bind("mouse_right", "Next workspace (carousel)", "omarchy-hyprland-workspace-carousel right")

-- omageeko (21K6S0A00C): swap the workspace's two columns in one go (a split
-- column and a single window trade sides). Replaces Omarchy's group focus on
-- these keys; Super + Alt + Tab and Super + Alt + wheel still cycle a group.
o.rebind("SUPER + CTRL + LEFT", "Swap columns", "omarchy-hyprland-window-swap-columns left")
o.rebind("SUPER + CTRL + RIGHT", "Swap columns", "omarchy-hyprland-window-swap-columns right")

-- omageeko (21K6S0A00C): screenshot like Trigger › Capture › Screenshot (and PRINT):
-- drag a rectangle (or snap to a window), then copy/save/edit
o.bind("SUPER + SHIFT + S", "Screenshot", "omarchy-capture-screenshot")

-- omageeko (21K6S0A00C): reset the workspace's splits to even halves (columns,
-- then rows inside them) after resizing; the key is \| on the US layout
o.bind("SUPER + backslash", "Even out window splits", "omarchy-hyprland-window-equalize-splits")

-- omageeko (21K6S0A00C): restart the desktop shell (bar, menus, panels), as
-- `omarchy restart shell` / Update › Process › Shell, e.g. after a Qt update
o.bind("SUPER + SHIFT + K", "Restart shell", "omarchy-restart-shell")

-- omageeko (21K6S0A00C): clipboard history (Omarchy's themed clipboard panel,
-- also on Super+Ctrl+V and the bar's clipboard icon): pick an entry to paste it
o.bind("SUPER + SHIFT + V", "Clipboard manager", { panel = "omarchy.clipboard" })
