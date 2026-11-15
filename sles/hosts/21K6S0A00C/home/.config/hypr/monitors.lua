-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all

-- Monitor scale is Hyprland's scale for the output. It sizes everything
-- Wayland-native, accepts fractions (1.6, 1.75), and applies immediately.
-- "auto" lets Hyprland pick per display.
local omarchy_monitor_scale = "auto"
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })

-- Desk layout, left to right: DP-8 (C27G7) | DP-9 + HDMI-A-1 (Odyssey G9 halves,
-- picture-by-picture). DP-9 anchors the layout at 0x0; the laptop panel sits
-- below the center. Omarchy's internal-monitor toggle (loaded after this file)
-- still decides whether eDP-1 is on; this only sets where it goes when enabled.
hl.monitor({ output = "DP-9", mode = "preferred", position = "0x0", scale = omarchy_monitor_scale })
hl.monitor({ output = "DP-8", mode = "preferred", position = "auto-center-left", scale = omarchy_monitor_scale })
hl.monitor({ output = "HDMI-A-1", mode = "preferred", position = "auto-center-right", scale = omarchy_monitor_scale })
hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto-center-down", scale = omarchy_monitor_scale })

-- Workspaces are per screen since Omarchy 4.5: each one has its own 1-10
-- (default/hypr/monitor-workspaces.lua), so none are pinned here.

-- Configure a specific monitor.
-- hl.monitor({ output = "DP-2", mode = "2560x1440@144", position = "0x0", scale = 1 })

-- Portrait/rotated secondary monitor (transform: 1 = 90°, 3 = 270°).
-- hl.monitor({ output = "DP-2", mode = "preferred", position = "auto", scale = 1, transform = 1 })

-- GDK scale is GDK_SCALE, the factor GTK draws its own UI at. It's what
-- sizes X11/XWayland windows, which Omarchy leaves unscaled so they stay
-- crisp instead of being stretched by the compositor. GTK only honors whole
-- numbers, so use the nearest integer to the monitor scale, and restart an
-- app for a change to reach it.
local omarchy_gdk_scale = 2
hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
