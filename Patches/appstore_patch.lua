-- appstore_patch.lua : adds an APP STORE tab and themes the Notepad
--
--  APP STORE  Lists the apps published in the GitHub repo's /apps folder
--             (github.com/SenkuSushigami/CrabtechOS-Files/apps), shows a
--             short description for the highlighted one, and installs,
--             updates or removes apps with one key. Installed apps show up
--             in the APPS tab straight away.
--               Up/Down  move          Enter  install / update
--               X        remove        D      choose where to install
--                                             (computer or a floppy)
--               R        refresh list  Backspace  back
--             Touch: tap an app to highlight it, tap again to install.
--
--  NOTEPAD    Now opens inside the same styled frame as the TERMINAL tab
--             (gradient header, side stripe, footer, OS palette) instead of
--             a plain black screen.
--
-- Works on the merged OS file (crabtech). To publish apps, add .lua files to
-- an  apps/  folder in the repo - the store reads that folder.
--
-- Usage:  appstore_patch            (patches "crabtech")
--         appstore_patch myfile     (patches another file name)
-- A backup is saved as <file>.bak first. Safe to run twice.

local arg1 = ({ ... })[1]
local path = shell.resolve(arg1 or "crabtech")
if not fs.exists(path) and fs.exists(path .. ".lua") then path = path .. ".lua" end
if not arg1 and not fs.exists(path) then
  -- fall back to the old name
  local alt = shell.resolve("sanctuary")
  if fs.exists(alt) then path = alt elseif fs.exists(alt .. ".lua") then path = alt .. ".lua" end
end
if not fs.exists(path) then printError("File not found: " .. path) return end

local f = fs.open(path, "r")
local src = f.readAll()
f.close()

if src:find("local function actStore", 1, true) then
  print("Already patched - nothing to do.")
  return
end
if not (src:find("-- styled terminal", 1, true) and src:find("local function actInstalled", 1, true)
    and src:find("local function actNotepad", 1, true)) then
  printError("This patch needs the merged OS file (crabtech.lua).")
  return
end

-- ------------------------------------------------------------
-- Styled frame shared by TERMINAL and NOTEPAD
-- ------------------------------------------------------------
local STYLED = [==[-- styled frame: header, side stripe and footer around a program (terminal, notepad)
local function runStyled(o)
  term.redirect(native)
  local nw, nh = native.getSize()
  local hh = 3

  -- OS palette on the computer's own screen; yellow = prompt, red = errors
  for c, v in pairs(PAL) do pcall(native.setPaletteColour, c, v) end
  pcall(native.setPaletteColour, colors.yellow, 0x9ED3F0)
  pcall(native.setPaletteColour, colors.red, 0xE8708F)

  local bands = { deep, colors.brown, colors.magenta, mid }
  local function bandAt(x, y)
    local i = math.floor((x - (y - 1) * 2 - 1) / (nw / 4)) + 1
    return bands[math.max(1, math.min(4, i))]
  end
  local function tp(x, y, s, fg, b)
    if y < 1 or y > nh or x > nw then return end
    native.setCursorPos(x, y)
    native.setTextColour(fg)
    native.setBackgroundColour(b)
    native.write(s:sub(1, nw - x + 1))
  end
  local function th(x, y, s, fg)
    for i = 1, #s do
      if x + i - 1 <= nw then tp(x + i - 1, y, s:sub(i, i), fg, bandAt(x + i - 1, y)) end
    end
  end

  -- header
  for y = 1, hh do for x = 1, nw do tp(x, y, " ", snow, bandAt(x, y)) end end
  th(4, 1, "COMPUTER " .. os.getComputerID() .. "  \4  " .. (os.getComputerLabel() or "unnamed"), ice)
  tp(3, 2, o.pill, deep, snow)
  th(10, 2, o.title, snow)
  th(10, 3, "m e n u  \187  " .. o.sub, lav)
  local hx = nw - math.max(#o.hintA, #o.hintB)
  th(hx, 2, o.hintA, snow)
  th(hx, 3, o.hintB, lav)

  -- side stripe + footer tag
  for y = hh + 1, nh do tp(1, y, "  ", ice, deep) end
  for y = hh + 2, nh - 2, 6 do tp(1, y, "//", ice, deep) end
  tp(3, nh, string.rep(" ", math.max(0, nw - 2)), grey, pale)
  tp(5, nh, o.footer, grey, pale)

  -- the program lives in a window under the header
  local sw = window.create(native, 3, hh + 1, math.max(10, nw - 2), math.max(3, nh - hh - 1), true)
  term.redirect(sw)
  sw.setBackgroundColour(colors.black)
  sw.setTextColour(colors.white)
  sw.clear()
  sw.setCursorPos(1, 1)
  if o.greeting then
    sw.setTextColour(ice)
    print(o.greeting)
    sw.setTextColour(colors.white)
  end
  pcall(o.run)

  -- back to the OS
  term.redirect(win)
  pcall(native.setPaletteColour, colors.yellow, term.nativePaletteColour(colors.yellow))
  if target == native then
    setPalette()
    win.redraw()
  else
    for c in pairs(PAL) do pcall(native.setPaletteColour, c, term.nativePaletteColour(c)) end
    native.setBackgroundColour(colors.black)
    native.clear()
    native.setCursorPos(1, 1)
  end
end

local function actNotepad()
  runStyled({
    pill = " NOTE ", title = "Notepad", sub = "n o t e p a d",
    hintA = "ctrl = menu", hintB = "save + exit",
    footer = "NOTEPAD  ////  notes.txt  ////  press Ctrl for the menu",
    run = function() shell.run("edit", "notes.txt") end,
  })
end]==]

local TERMINAL = [==[-- styled terminal
local function actTerminal()
  runStyled({
    pill = " TERM ", title = "Terminal", sub = "t e r m i n a l",
    hintA = "type  exit", hintB = "to go back",
    footer = "TERMINAL  ////  type exit to return to the menu",
    greeting = "Type 'exit' to return to the menu.",
    run = function() shell.run("shell") end,
  })
end

]==]

-- ------------------------------------------------------------
-- App store
-- ------------------------------------------------------------
local STORE = [==[-- app store
local STORE = {
  repo   = "SenkuSushigami/CrabtechOS-Files",
  branch = "main",
  dir    = "apps",      -- folder in the repo that holds the apps
}

local function actStore()
  if not http then
    page("APP STORE", function(x1, y1)
      put(x1, y1, "The HTTP API is disabled on this server.", pink, pale)
    end)
    return
  end

  local function rawUrl(p)
    return "https://raw.githubusercontent.com/" .. STORE.repo .. "/" .. STORE.branch
      .. "/" .. p .. "?cb=" .. os.epoch("utc")
  end

  local function get(url, headers)
    local res, err, failed = http.get(url, headers)
    if not res then
      local code = failed and failed.getResponseCode and failed.getResponseCode()
      if failed and failed.close then failed.close() end
      return nil, (code and ("HTTP " .. code .. " ") or "") .. tostring(err or "request failed")
    end
    local body = res.readAll()
    res.close()
    return body
  end

  -- state ------------------------------------------------------------
  local entries, loadErr = {}, nil
  local dests, dsel = {}, 1
  local desc = {}
  local sel, top = 1, 1
  local area = {}
  local status, statusColor = "", mid
  local confirm = nil

  local function say(msg, c) status, statusColor = msg, c or mid end

  -- paint a message on the status line right now (used before slow requests)
  local function flash(msg)
    if not area.sy then return end
    frame(function()
      fill(area.x1, area.sy, area.x2, area.sy, pale)
      put(area.x1, area.sy, msg:sub(1, area.x2 - area.x1 + 1), grey, pale)
    end)
  end

  local function scanDests()
    dests = { { label = "computer", dir = "apps", tag = "pc" } }
    for _, d in ipairs(fs.list("/")) do
      if d:match("^disk") and fs.isDir(d) and not fs.isReadOnly(d) then
        dests[#dests + 1] = { label = "floppy (" .. d .. ")", dir = fs.combine(d, "apps"), tag = d }
      end
    end
    if dsel > #dests then dsel = 1 end
  end

  local function refresh()
    entries, loadErr = {}, nil
    local api = "https://api.github.com/repos/" .. STORE.repo .. "/contents/" .. STORE.dir
      .. "?ref=" .. STORE.branch
    local body, err = get(api, { Accept = "application/vnd.github+json" })
    if not body then
      if tostring(err):find("404", 1, true) then
        loadErr = "No /" .. STORE.dir .. " folder in the repo yet - add .lua apps there."
      else
        loadErr = err
      end
      return
    end
    local data = textutils.unserializeJSON(body)
    if type(data) ~= "table" then loadErr = "Unexpected reply from GitHub." return end
    if data.message then loadErr = tostring(data.message) return end
    for _, e in ipairs(data) do
      if e.type == "file" and type(e.name) == "string" and e.name:match("%.lua$") then
        entries[#entries + 1] = { file = e.name, name = (e.name:gsub("%.lua$", "")), size = e.size or 0 }
      end
    end
    table.sort(entries, function(a, b) return a.name:lower() < b.name:lower() end)
  end

  -- "not installed" / "installed" / "update" plus where it is
  local function state(e)
    local tags, found, outdated = {}, false, false
    for _, d in ipairs(dests) do
      local p = fs.combine(d.dir, e.file)
      if fs.exists(p) and not fs.isDir(p) then
        found = true
        tags[#tags + 1] = d.tag
        if fs.getSize(p) ~= e.size then outdated = true end
      end
    end
    if not found then return "not installed", "" end
    return outdated and "update" or "installed", "[" .. table.concat(tags, ",") .. "]"
  end

  -- first comment lines of the app file = its description
  local function describe(e)
    if desc[e.file] then return desc[e.file] end
    local lines = {}
    local body = get(rawUrl(STORE.dir .. "/" .. e.file))
    if body then
      for line in (body .. "\n"):gmatch("(.-)\r?\n") do
        local c = line:match("^%-%-(.*)$")
        if not c then
          if line:match("%S") then break end
        else
          c = c:gsub("^%s+", "")
          c = c:gsub("%s+$", "")
          if c:match("^=+$") then
            -- separator line, skip
          elseif c == "" then
            if #lines > 0 then break end
          else
            lines[#lines + 1] = c
            if #lines >= 2 then break end
          end
        end
      end
      if #lines == 0 then lines[1] = "(no description)" end
    else
      lines[1] = "(could not load description)"
    end
    desc[e.file] = lines
    return lines
  end

  local function choose(i)
    sel, confirm = i, nil
    local e = entries[sel]
    if e and not desc[e.file] then
      flash("loading description ...")
      describe(e)
    end
  end

  local function install(e)
    local dest = dests[dsel]
    confirm = nil
    flash("downloading " .. e.file .. " ...")
    local body, err = get(rawUrl(STORE.dir .. "/" .. e.file))
    if not body then say("failed: " .. tostring(err), pink) return end
    local fn, perr = load(body, "=" .. e.file)
    if not fn then say("not valid Lua: " .. tostring(perr), pink) return end
    if not fs.exists(dest.dir) then fs.makeDir(dest.dir) end
    local h = fs.open(fs.combine(dest.dir, e.file), "w")
    if not h then say("could not write to " .. dest.label, pink) return end
    h.write(body)
    h.close()
    say("installed " .. e.name .. " to " .. dest.label .. " - open it from APPS", mid)
  end

  local function remove(e)
    local dest = dests[dsel]
    local p = fs.combine(dest.dir, e.file)
    if not fs.exists(p) then
      say(e.name .. " is not on " .. dest.label .. "  (D switches destination)", grey)
      confirm = nil
      return
    end
    if confirm ~= e.file then
      confirm = e.file
      say("press X again to remove " .. e.name .. " from " .. dest.label, pink)
      return
    end
    fs.delete(p)
    confirm = nil
    say("removed " .. e.name .. " from " .. dest.label, mid)
  end

  -- drawing ----------------------------------------------------------
  local function draw(x1, y1, x2, y2)
    local w = x2 - x1 + 1
    area = { x1 = x1, x2 = x2, sy = y2 - 1 }
    put(x1, y1, ("github.com/" .. STORE.repo .. "/" .. STORE.dir):sub(1, w), grey, pale)
    put(x1, y1 + 1, ("install to: " .. dests[dsel].label):sub(1, w), mid, pale)
    put(x1, y2, ("enter install   x remove   d destination   r refresh"):sub(1, w), grey, pale)

    if loadErr then
      put(x1, y1 + 3, loadErr:sub(1, w), pink, pale)
      put(x1, y1 + 4, "press R to try again", grey, pale)
      return
    end
    if #entries == 0 then
      put(x1, y1 + 3, "No apps published yet.", mid, pale)
      return
    end

    local listTop = y1 + 3
    local rows = math.max(1, y2 - 4 - listTop + 1)
    area.ly1, area.rows = listTop, rows
    put(x1 + 2, y1 + 2, "APP", grey, pale)
    put(x1 + 26, y1 + 2, "SIZE", grey, pale)
    put(x1 + 35, y1 + 2, "STATUS", grey, pale)

    if sel < top then top = sel end
    if sel > top + rows - 1 then top = sel - rows + 1 end
    for i = 0, rows - 1 do
      local e = entries[top + i]
      if not e then break end
      local y = listTop + i
      local on = (top + i == sel)
      local bg = on and deep or pale
      fill(x1, y, x2, y, bg)
      put(x1 + 1, y, (on and "\16 " or "  ") .. e.name:sub(1, 22), on and snow or deep, bg)
      put(x1 + 26, y, string.format("%.1f kB", e.size / 1024), on and ice or grey, bg)
      local st, where = state(e)
      local stColor = (st == "update") and pink or (st == "installed" and (on and ice or mid) or (on and ice or grey))
      put(x1 + 35, y, (st .. " " .. where):sub(1, math.max(0, w - 35)), stColor, bg)
    end
    if #entries > rows then
      put(x2 - 6, y1 + 2, (top + rows - 1 < #entries) and "\31 more" or "", mid, pale)
    end

    local lines = desc[(entries[sel] or {}).file] or {}
    put(x1, y2 - 3, (lines[1] or ""):sub(1, w), mid, pale)
    put(x1, y2 - 2, (lines[2] or ""):sub(1, w), grey, pale)
    put(x1, y2 - 1, status:sub(1, w), statusColor, pale)
  end

  -- open: contact GitHub first ---------------------------------------
  frame(function()
    local msg = "Contacting GitHub ..."
    local w = #msg + 8
    local x = math.max(1, math.floor((W - w) / 2) + 1)
    local y = math.max(1, math.floor(H / 2) - 1)
    box(x, y, x + w - 1, y + 2)
    put(x + 4, y + 1, msg, deep, pale)
  end)
  scanDests()
  refresh()
  if entries[1] then describe(entries[1]) end

  page("APP STORE", draw, function(kind, a, b)
    if kind == "key" then
      if a == keys.up then
        if sel > 1 then choose(sel - 1) end
        return "render"
      elseif a == keys.down then
        if sel < #entries then choose(sel + 1) end
        return "render"
      elseif a == keys.enter then
        if entries[sel] then install(entries[sel]) end
        return "render"
      elseif a == keys.x or a == keys.delete then
        if entries[sel] then remove(entries[sel]) end
        return "render"
      elseif a == keys.d then
        dsel = dsel % #dests + 1
        confirm = nil
        say("installing to " .. dests[dsel].label, mid)
        return "render"
      elseif a == keys.r then
        flash("refreshing ...")
        scanDests()
        refresh()
        desc, sel, top, confirm = {}, 1, 1, nil
        if entries[1] then describe(entries[1]) end
        say("list refreshed", mid)
        return "render"
      end
    elseif kind == "click" and area.ly1 and b >= area.ly1 and b < area.ly1 + area.rows then
      local idx = top + (b - area.ly1)
      if entries[idx] then
        if idx == sel then install(entries[idx]) else choose(idx) end
        return "render"
      end
    end
  end)
end

local actions = {]==]

-- ------------------------------------------------------------
-- Apply
-- ------------------------------------------------------------
local function plainEdit(label, old, new)
  local s, t = src:find(old, 1, true)
  if not s then print("skipped : " .. label .. " (not found)") return false end
  src = src:sub(1, s - 1) .. new .. src:sub(t + 1)
  print("patched : " .. label)
  return true
end

local ok = true

-- menu tab
ok = plainEdit("Menu tab", '{ label = "APPS" }, { label = "SETTINGS" }',
  '{ label = "APPS" }, { label = "APP STORE" }, { label = "SETTINGS" }') and ok

-- notepad + shared frame
ok = plainEdit("Notepad theme",
  'local function actNotepad()\n  onComputer(function() shell.run("edit", "notes.txt") end)\nend',
  STYLED) and ok

-- terminal now uses the shared frame
do
  local a = src:find("-- styled terminal\nlocal function actTerminal()", 1, true)
  local b = src:find("-- installed patches tab", 1, true)
  if a and b and b > a then
    src = src:sub(1, a - 1) .. TERMINAL .. src:sub(b)
    print("patched : Terminal uses shared frame")
  else
    print("skipped : Terminal uses shared frame (not found)")
    ok = false
  end
end

-- the store itself, then its action slot
ok = plainEdit("App store", "local actions = {", STORE) and ok
ok = plainEdit("Store action", "local actions = { actGames, actSettings,",
  "local actions = { actGames, actStore, actSettings,") and ok

-- list the patch on the INSTALLED tab (optional)
do
  local s, t = src:find('{ "installed_patch",%s+"this tab",%s+function%(h%) return h%("local function " %.%. "actInstalled"%) end },')
  if s then
    local line = src:sub(s, t)
    src = src:sub(1, t) .. '\n    { "appstore_patch",       "app store, notepad", function(h) return h("local function " .. "actStore") end },' .. src:sub(t + 1)
    print("patched : Installed list")
  else
    print("skipped : Installed list (not found, optional)")
  end
end

if not ok then
  printError("Some edits did not match - file left unchanged.")
  return
end

fs.delete(path .. ".bak")
fs.copy(path, path .. ".bak")
local o = fs.open(path, "w")
o.write(src)
o.close()
print("Done. Backup: " .. path .. ".bak")
print("Add .lua apps to the repo's apps/ folder, then open APP STORE.")
