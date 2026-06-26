local wezterm = require "wezterm"
local act = wezterm.action

local function is_opencode_pane(pane)
  local title = pane:get_title() or ""
  if title:match("^OC%s*|") then
    return true
  end

  local process = pane:get_foreground_process_name() or ""
  return process:find("opencode", 1, true) ~= nil
end

local function scroll_or_passthrough(amount, passthrough)
  return wezterm.action_callback(function(window, pane)
    if pane:is_alt_screen_active() or is_opencode_pane(pane) then
      window:perform_action(act.SendString(passthrough), pane)
      return
    end

    window:perform_action(act.ScrollByPage(amount), pane)
  end)
end

wezterm.on("format-tab-title", function(tab, _, _, _, _, max_width)
  local pane = tab.active_pane
  local title = pane and pane.title or "shell"

  title = title:gsub("^OC%s*|%s*", "")
  if title == "" then
    title = "shell"
  end

  title = wezterm.truncate_right(title, math.max(1, max_width - 2))
  return { { Text = " " .. title .. " " } }
end)

return {
  font = wezterm.font_with_fallback {
    "FiraCode Nerd Font Mono",
    "Noto Color Emoji",
  },
  font_size = 12.5,
  line_height = 1.05,
  tab_max_width = 32,

  leader = { key = "b", mods = "CTRL", timeout_milliseconds = 1000 },

  keys = {
    { key = "v", mods = "LEADER", action = act.SplitHorizontal { domain = "CurrentPaneDomain" } },
    { key = "s", mods = "LEADER", action = act.SplitVertical { domain = "CurrentPaneDomain" } },
    { key = "V", mods = "LEADER|SHIFT", action = act.SplitPane { direction = "Right", size = { Percent = 25 } } },
    { key = "S", mods = "LEADER|SHIFT", action = act.SplitPane { direction = "Down", size = { Percent = 25 } } },
    { key = "x", mods = "LEADER", action = act.CloseCurrentPane { confirm = true } },
    { key = "z", mods = "LEADER", action = act.TogglePaneZoomState },

    { key = "h", mods = "LEADER", action = act.ActivatePaneDirection "Left" },
    { key = "j", mods = "LEADER", action = act.ActivatePaneDirection "Down" },
    { key = "k", mods = "LEADER", action = act.ActivatePaneDirection "Up" },
    { key = "l", mods = "LEADER", action = act.ActivatePaneDirection "Right" },

    { key = "h", mods = "LEADER|SHIFT", action = act.AdjustPaneSize { "Left", 3 } },
    { key = "j", mods = "LEADER|SHIFT", action = act.AdjustPaneSize { "Down", 3 } },
    { key = "k", mods = "LEADER|SHIFT", action = act.AdjustPaneSize { "Up", 3 } },
    { key = "l", mods = "LEADER|SHIFT", action = act.AdjustPaneSize { "Right", 3 } },

    { key = "u", mods = "CTRL|ALT", action = scroll_or_passthrough(-0.5, "\x1b\x15") },
    { key = "d", mods = "CTRL|ALT", action = scroll_or_passthrough(0.5, "\x1b\x04") },

    { key = "Enter", mods = "ALT", action = act.SendKey { key = "Enter", mods = "NONE" } },
    { key = "F11", mods = "NONE", action = act.ToggleFullScreen },

    { key = "c", mods = "LEADER", action = act.SpawnTab "CurrentPaneDomain" },
    { key = "n", mods = "LEADER", action = act.ActivateTabRelative(1) },
    { key = "p", mods = "LEADER", action = act.ActivateTabRelative(-1) },
  },
}
