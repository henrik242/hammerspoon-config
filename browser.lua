------------------------------------------------------------------------
-- Browser router to Chrome/Brave profiles (replaces Choosy)
------------------------------------------------------------------------
local M = {}

local support = os.getenv("HOME") .. "/Library/Application Support/"
-- Chromium browsers, in chooser order
local browsers = {
  {key = "chrome", name = "Chrome", app = "/Applications/Google Chrome.app",
   bundle = "com.google.Chrome", state = support .. "Google/Chrome/Local State"},
  {key = "brave", name = "Brave", app = "/Applications/Brave Browser.app",
   bundle = "com.brave.Browser", state = support .. "BraveSoftware/Brave-Browser/Local State"},
}

-- Profiles and routing rules live in the gitignored local.lua (see
-- local.example.lua). Without it, every link shows a chooser of all profiles.
local config = {}
if hs.fs.attributes(hs.configdir .. "/local.lua") then
  config = require("local").browser or {}
end
local accounts = config.profiles or {}
local rules = config.rules or {}

local function contains(url, list)
  for _, s in ipairs(list) do
    if url:find(s, 1, true) then return true end
  end
end

local keep, chooser

-- Once per load, and deferred so the dialog doesn't hold up the link
local function warnUnreadable(b, err)
  if b.warned then return end
  b.warned = true
  -- macOS denies reading another app's data until Hammerspoon is allowed
  local hint = err:find("No such file", 1, true)
    and "Is " .. b.name .. " installed and started at least once?"
    or "Allow Hammerspoon to access data from other apps (or give it Full Disk Access)," ..
      " then restart Hammerspoon."
  keep[b] = hs.timer.doAfter(0, function()
    keep[b] = nil
    hs.dialog.blockAlert("Can't read " .. b.name .. " profiles", err .. "\n\n" .. hint)
  end)
end

-- Label from local.lua for a profile. Strings match the signed-in email,
-- since profile names can repeat; a full email wins over a domain. Tables
-- ({browser, dir}) match the profile directory, for profiles with no account.
local function labelFor(browser, dir, email)
  local byDomain
  for label, want in pairs(accounts) do
    if type(want) == "table" then
      if want.browser == browser.key and want.dir == dir then return label end
    elseif email and email ~= "" then
      if want == email then return label end
      if not want:find("@", 1, true) and email:sub(-#want - 1) == "@" .. want then byDomain = label end
    end
  end
  return byDomain
end

-- Profiles of all browsers, each in the browser's own order:
-- {browser, dir, name, email, label}
local function profiles()
  local list = {}
  for _, b in ipairs(browsers) do
    local f, err = io.open(b.state)
    if f then
      local ok, json = pcall(hs.json.decode, f:read("a"))
      f:close()
      local state = ok and json and json.profile or {}
      local info = state.info_cache or {}
      for _, dir in ipairs(state.profiles_order or {}) do
        local p = info[dir] or {}
        table.insert(list, {browser = b, dir = dir, name = p.name or dir, email = p.user_name,
          label = labelFor(b, dir, p.user_name)})
      end
    else
      warnUnreadable(b, err)
    end
  end
  return list
end

local function open(url, p)
  local task
  task = hs.task.new("/usr/bin/open", function(code, _, stderr)
    keep[task] = nil
    if code ~= 0 then print("browser: open failed: " .. stderr) end
  end, {"-na", p.browser.app, "--args", "--profile-directory=" .. p.dir, url})
  keep[task] = true
  task:start()
end

local function choose(url, all)
  local list, choices = {}, {}
  -- Only labelled profiles, unless none are configured
  for _, p in ipairs(all) do
    if p.label or not next(accounts) then
      local b = p.browser
      b.icon = b.icon or hs.image.imageFromAppBundle(b.bundle)
      table.insert(list, p)
      table.insert(choices, {text = p.label or p.name, subText = p.email, image = b.icon, i = #list})
    end
  end
  -- Held in an upvalue so it is not collected while visible
  chooser = hs.chooser.new(function(choice)
    if choice then open(url, list[choice.i]) end
  end)
  chooser:choices(choices):placeholderText(url):show()
end

local function route(_, _, _, url, pid)
  local app = pid and hs.application.applicationForPID(pid)
  local source = app and app:path()
  local all = profiles()
  -- First matching rule wins; if several profiles share its label, the first
  -- in chooser order is used
  for _, rule in ipairs(rules) do
    if (not rule.source or rule.source == source) and contains(url, rule.match) then
      for _, p in ipairs(all) do
        if p.label == rule.profile then return open(url, p) end
      end
      print("browser: no profile labelled " .. rule.profile)
      break
    end
  end
  choose(url, all)
end

function M.start(keepTable)
  keep = keepTable
  hs.urlevent.httpCallback = route
  -- Covers https too. macOS asks for confirmation.
  if (hs.urlevent.getDefaultHandler("http") or ""):lower() ~= "org.hammerspoon.hammerspoon" then
    hs.urlevent.setDefaultHandler("http")
  end
end

return M
