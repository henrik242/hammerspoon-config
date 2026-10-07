------------------------------------------------------------------------
-- Clipboard history
------------------------------------------------------------------------
local M = {}

local max = 1000
-- Larger entries are skipped; the whole history is saved on every copy
local maxBytes = 100000
-- Each entry is { text = ..., app = bundle ID of the app copied from }
-- Entries differing only in surrounding whitespace count as duplicates
local function key(s)
  return s:match("^%s*(.-)%s*$")
end

-- Load, converting old plain-string entries and dropping duplicates (newest first)
local items, seen = {}, {}
for _, v in ipairs(hs.settings.get("clipHistory") or {}) do
  if type(v) == "string" then v = { text = v } end
  if not seen[key(v.text)] then
    seen[key(v.text)] = true
    table.insert(items, v)
  end
end
seen = nil
local last = hs.pasteboard.changeCount()
-- Change count of our own paste, which should keep the entry's original app
local own

-- Skip entries password managers mark as secret or temporary
local function concealed()
  for _, t in ipairs(hs.pasteboard.pasteboardTypes() or {}) do
    if t == "org.nspasteboard.ConcealedType" or t == "org.nspasteboard.TransientType" then
      return true
    end
  end
end

local function record()
  local n = hs.pasteboard.changeCount()
  if n == last then return end
  last = n
  if concealed() then return end
  local s = hs.pasteboard.getContents()
  if not s or s:match("^%s*$") or #s > maxBytes then return end
  local front = hs.application.frontmostApplication()
  local app = front and front:bundleID()
  local k = key(s)
  for i, v in ipairs(items) do
    if key(v.text) == k then
      if n == own then app = v.app end
      table.remove(items, i)
      break
    end
  end
  table.insert(items, 1, { text = s, app = app })
  while #items > max do table.remove(items) end
  hs.settings.set("clipHistory", items)
end

-- string.lower only handles ASCII
local function fold(s)
  return (s:lower():gsub("Æ", "æ"):gsub("Ø", "ø"):gsub("Å", "å"))
end

local style = {
  font = { name = hs.styledtext.defaultFonts.system.name, size = 13 },
  color = { list = "System", name = "labelColor" },
  paragraphStyle = { lineBreak = "truncateTail" },
}
-- The chooser scales icons to fit a 36px-wide column as tall as the row, so
-- pad a small arrow to shrink it. Wider than tall keeps the scale fixed at
-- the column width, so the arrow is the same size in one- and two-line rows.
local arrow = hs.canvas.new({ w = 36, h = 24 }):appendElements({
  type = "text", text = "→", textSize = 11, textAlignment = "center",
  textColor = { white = 0.5 }, frame = { x = 0, y = 4, w = 36, h = 16 },
}):imageFromCanvas()

-- App icons padded the same way, cached per bundle ID (false = no icon)
local icons = {}
local function icon(bundle)
  if not bundle then return arrow end
  if icons[bundle] == nil then
    local img = hs.image.imageFromAppBundle(bundle)
    icons[bundle] = img and hs.canvas.new({ w = 36, h = 24 }):appendElements({
      type = "image", image = img, frame = { x = 9, y = 3, w = 18, h = 18 },
    }):imageFromCanvas() or false
  end
  return icons[bundle] or arrow
end

-- Search text and display row per entry, built once instead of per keystroke.
-- Kept outside the entries so they don't end up in hs.settings.
local cache = setmetatable({}, { __mode = "k" })
local function prepared(item)
  local c = cache[item]
  if not c then
    local s = item.text
    local line = s:gsub("%s+", " ")
    local cut = utf8.offset(line, 151)
    if cut then line = line:sub(1, cut - 1) end
    c = {
      hay = fold(s),
      row = { text = hs.styledtext.new(line, style), image = icon(item.app), full = s },
    }
    cache[item] = c
  end
  return c
end

-- Every word in the query must appear somewhere in the entry, in any order
local function choices(query)
  local words = {}
  for w in fold(query or ""):gmatch("%S+") do table.insert(words, w) end
  local result = {}
  for _, item in ipairs(items) do
    local c = prepared(item)
    local ok = true
    for _, w in ipairs(words) do
      if not c.hay:find(w, 1, true) then ok = false break end
    end
    if ok then table.insert(result, c.row) end
  end
  return result
end

local chooser = hs.chooser.new(function(choice)
  if not choice then return end
  hs.pasteboard.setContents(choice.full)
  own = hs.pasteboard.changeCount()
  hs.eventtap.keyStroke({"cmd"}, "v")
end)
chooser:rows(25)
chooser:queryChangedCallback(function(q) chooser:choices(choices(q)) end)

function M.start(mods, keep)
  keep.clipTimer = hs.timer.doEvery(0.5, record)
  -- A chooser left open across a reload gets orphaned and can't be closed
  hs.shutdownCallback = function() chooser:hide() end
  hs.hotkey.bind(mods, "v", function()
    chooser:query("")
    chooser:choices(choices(""))
    chooser:show()
  end)
end

return M
