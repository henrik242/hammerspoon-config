------------------------------------------------------------------------
-- Browser router (replaces Choosy)
------------------------------------------------------------------------
local M = {}

local chrome = "/Applications/Google Chrome.app"
local localState = os.getenv("HOME") .. "/Library/Application Support/Google/Chrome/Local State"

-- Profiles and routing rules live in the gitignored local.lua (see
-- local.example.lua). Without it, every link shows the profile chooser.
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

-- Label from local.lua for a signed-in email. Labels are matched by email
-- rather than Chrome's profile name, since names can repeat. A full email
-- wins over a domain.
local function labelFor(email)
  if not email then return end
  local byDomain
  for label, want in pairs(accounts) do
    if want == email then return label end
    if not want:find("@", 1, true) and email:sub(-#want - 1) == "@" .. want then byDomain = label end
  end
  return byDomain
end

-- Chrome profiles in Chrome's own order: {dir, name, email, label}
local function profiles()
  local state = (hs.json.read(localState) or {}).profile or {}
  local info = state.info_cache or {}
  local list = {}
  for _, dir in ipairs(state.profiles_order or {}) do
    local p = info[dir] or {}
    table.insert(list, {dir = dir, name = p.name or dir, email = p.user_name, label = labelFor(p.user_name)})
  end
  return list
end

local function open(url, dir)
  local task
  task = hs.task.new("/usr/bin/open", function(code, _, stderr)
    keep[task] = nil
    if code ~= 0 then print("browser: open failed: " .. stderr) end
  end, {"-na", chrome, "--args", "--profile-directory=" .. dir, url})
  keep[task] = true
  task:start()
end

local function choose(url)
  local icon = hs.image.imageFromAppBundle("com.google.Chrome")
  local choices = {}
  for _, p in ipairs(profiles()) do
    table.insert(choices, {text = p.label or p.name, subText = p.email, image = icon, dir = p.dir})
  end
  -- Held in an upvalue so it is not collected while visible
  chooser = hs.chooser.new(function(choice)
    if choice then open(url, choice.dir) end
  end)
  chooser:choices(choices):placeholderText(url):show()
end

local function route(_, _, _, url, pid)
  local app = pid and hs.application.applicationForPID(pid)
  local source = app and app:path()
  -- First matching rule wins; if several profiles share its label, the first
  -- in Chrome's order is used
  for _, rule in ipairs(rules) do
    if (not rule.source or rule.source == source) and contains(url, rule.match) then
      for _, p in ipairs(profiles()) do
        if p.label == rule.profile then return open(url, p.dir) end
      end
      print("browser: no Chrome profile labelled " .. rule.profile)
      break
    end
  end
  choose(url)
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
