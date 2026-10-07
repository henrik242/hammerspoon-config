local mods = {"ctrl", "alt", "cmd"}

-- Objects Hammerspoon must keep alive. Unreferenced tasks/watchers can be
-- garbage collected before they finish, silently dropping their callbacks.
local keep = {}

local function alert(text, screen)
  hs.alert.show(text, {}, screen or hs.screen.mainScreen(), 0.8)
end

------------------------------------------------------------------------
-- Move window to screen above / below
------------------------------------------------------------------------
local function move(dir, label)
  return function()
    local win = hs.window.focusedWindow()
    if not win then return end
    if dir == "up" then
      win:moveOneScreenNorth(false, true)
    else
      win:moveOneScreenSouth(false, true)
    end
    alert(label, win:screen())
  end
end

hs.hotkey.bind(mods, "up",   move("up",   "⬆️ "))
hs.hotkey.bind(mods, "down", move("down", "⬇️ "))

------------------------------------------------------------------------
-- Window layouts
------------------------------------------------------------------------
hs.window.animationDuration = 0

local function fill(unit, label)
  return function()
    local win = hs.window.focusedWindow()
    if not win then return end
    win:moveToUnit(unit)
    alert(label, win:screen())
  end
end

hs.hotkey.bind(mods, "left",  fill(hs.layout.left50,  "⬅️ "))
hs.hotkey.bind(mods, "right", fill(hs.layout.right50, "➡️ "))
hs.hotkey.bind(mods, "+",     fill(hs.layout.maximized, "⏹️"))
hs.hotkey.bind(mods, "-",     fill({x=0.25, y=0.12, w=0.5, h=0.75}, "⏺️"))

------------------------------------------------------------------------
-- Running external commands (GC-safe)
------------------------------------------------------------------------
local blueutil = "/opt/homebrew/bin/blueutil"

local function run(cmd, args, callback)
  local task
  task = hs.task.new(cmd, function(code, stdout, stderr)
    keep[task] = nil
    if code ~= 0 then
      print(string.format("%s %s failed (%d): %s", cmd, table.concat(args, " "), code, stderr))
    end
    if callback then callback(code, stdout, stderr) end
  end, args)
  keep[task] = true
  task:start()
end

------------------------------------------------------------------------
-- Lock: pause Spotify, mute, Bluetooth off, screensaver
------------------------------------------------------------------------
hs.hotkey.bind(mods, "l", function()
  alert("🔒 Locking")

  if hs.spotify.isRunning() then hs.spotify.pause() end

  local out = hs.audiodevice.defaultOutputDevice()
  if out then
    out:setMuted(true)
    out:setOutputVolume(0)
  end

  run(blueutil, {"-p", "0"})

  hs.caffeinate.startScreensaver()
end)

------------------------------------------------------------------------
-- Toggle Bluetooth
------------------------------------------------------------------------
hs.hotkey.bind(mods, "b", function()
  run(blueutil, {"-p"}, function(code, stdout)
    if code ~= 0 then
      alert("blueutil failed – see Console")
      return
    end
    local on = stdout:match("^%s*1") ~= nil
    alert(on and "❌ ᛒ" or "✅ ᛒ")
    run(blueutil, {"-p", on and "0" or "1"})
  end)
end)

------------------------------------------------------------------------
-- Clipboard history
------------------------------------------------------------------------
require("clipboard").start(mods, keep)

------------------------------------------------------------------------
-- Route links to Chrome profiles
------------------------------------------------------------------------
require("browser").start(keep)

------------------------------------------------------------------------
-- Reload config on save
------------------------------------------------------------------------
keep.configWatcher = hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", hs.reload):start()
alert("Hammerspoon config loaded")
