------------------------------------------------------------------------
-- Nag when gcloud needs `gcloud auth login`
------------------------------------------------------------------------
local M = {}

local gcloud = "/opt/homebrew/bin/gcloud"
local interval = 30 * 60
local snoozeKey = "gcloudSnoozeUntil"
local options = {"Login", "Delay check 1 hr", "Delay check 12 hrs", "Delay check 24 hrs"}
local delays = {[options[2]] = 1, [options[3]] = 12, [options[4]] = 24}

local keep, alert, busy, dialog

-- Hammerspoon's PATH lacks Homebrew, which the gcloud wrapper needs
local function task(cmd, args, callback)
  local t
  t = hs.task.new(cmd, function(code, stdout, stderr)
    keep[t] = nil
    callback(code, stdout, stderr)
  end, args)
  local env = t:environment()
  env.PATH = "/opt/homebrew/bin:" .. (env.PATH or "/usr/bin:/bin")
  t:setEnvironment(env)
  keep[t] = true
  t:start()
  return t
end

local check

local function snooze(hours)
  hs.settings.set(snoozeKey, os.time() + hours * 3600)
end

-- NSAlert via JXA in a task, since hs.dialog.blockAlert has only two buttons
-- and blocks Hammerspoon, and AppleScript dialogs have at most three
local alertJs = [[
ObjC.import("AppKit")
function run(argv) {
  const app = $.NSApplication.sharedApplication
  app.setActivationPolicy($.NSApplicationActivationPolicyAccessory)
  app.activateIgnoringOtherApps(true)
  const a = $.NSAlert.alloc.init
  a.icon = $.NSWorkspace.sharedWorkspace.iconForFile("/Applications/Hammerspoon.app")
  a.messageText = argv[0]
  a.informativeText = argv[1]
  argv.slice(2).forEach(b => a.addButtonWithTitle(b))
  return argv[a.runModal - 1000 + 2]
}
]]

local function ask(msg)
  local args = {"-l", "JavaScript", "-e", alertJs, "gcloud", msg}
  for _, o in ipairs(options) do table.insert(args, o) end
  dialog = task("/usr/bin/osascript", args, function(_, stdout)
    dialog = nil
    local choice = stdout:gsub("%s+$", "")
    if choice == "Login" then
      alert("gcloud: logging in in the browser")
      task(gcloud, {"auth", "login", "--brief"}, function(code, _, stderr)
        busy = false
        if code == 0 then
          alert("gcloud: logged in")
        else
          print("gcloud auth login failed: " .. stderr)
          alert("gcloud login failed - see Console")
        end
      end)
      return
    end
    -- Killed or failed counts as the shortest delay
    snooze(delays[choice] or 1)
    busy = false
  end)
end

function check()
  if busy then return end
  if os.time() < (hs.settings.get(snoozeKey) or 0) then return end
  busy = true
  task(gcloud, {"auth", "print-access-token"}, function(code, _, stderr)
    -- Only nag when gcloud asks for a login; network errors etc. just log
    if code ~= 0 and stderr:find("auth login", 1, true) then
      ask("gcloud needs you to log in again.")
      return
    end
    if code ~= 0 then print("gcloud check failed: " .. stderr) end
    busy = false
  end)
end

function M.start(k, alertFn)
  keep, alert = k, alertFn
  keep.gcloudTimer = hs.timer.doEvery(interval, check)
  -- Laptop may have slept past token expiry
  keep.gcloudWake = hs.caffeinate.watcher.new(function(event)
    if event == hs.caffeinate.watcher.systemDidWake then
      keep.gcloudWakeDelay = hs.timer.doAfter(30, check)
    end
  end):start()
  keep.gcloudStartup = hs.timer.doAfter(5, check)
  -- Don't leave an orphaned dialog behind on reload
  local prev = hs.shutdownCallback
  hs.shutdownCallback = function()
    if dialog then dialog:terminate() end
    if prev then prev() end
  end
end

return M
