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

-- Repeated presses cycle 1/2 -> 1/3 -> 2/3. Remember the frame we set per
-- window rather than matching geometry: terminals and others round sizes.
local sideState = {}
local steps = {{0.5, "½"}, {1/3, "⅓"}, {2/3, "⅔"}}

local function sameFrame(a, b)
  return math.abs(a.x - b.x) < 2 and math.abs(a.y - b.y) < 2
     and math.abs(a.w - b.w) < 2 and math.abs(a.h - b.h) < 2
end

local function side(name, arrow)
  return function()
    local win = hs.window.focusedWindow()
    if not win then return end
    local prev = sideState[win:id()]
    local i = 1
    if prev and prev.side == name and sameFrame(prev.frame, win:frame()) then
      i = prev.step % #steps + 1
    end
    local w = steps[i][1]
    win:moveToUnit({x = name == "left" and 0 or 1 - w, y = 0, w = w, h = 1})
    sideState[win:id()] = {side = name, step = i, frame = win:frame()}
    alert(arrow .. steps[i][2], win:screen())
  end
end

hs.hotkey.bind(mods, "left",  side("left",  "⬅️ "))
hs.hotkey.bind(mods, "right", side("right", "➡️ "))
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
-- Route links to Chrome and Brave profiles
------------------------------------------------------------------------
require("browser").start(keep)

------------------------------------------------------------------------
-- Nag when gcloud needs a login (after clipboard: chains shutdownCallback)
------------------------------------------------------------------------
require("gcloud").start(keep, alert)

------------------------------------------------------------------------
-- Reload config on save
------------------------------------------------------------------------
keep.configWatcher = hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", hs.reload):start()
alert("Hammerspoon config loaded")
