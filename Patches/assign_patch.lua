-- assign_patch.lua : click a task from a list, click a computer, done
--
-- Adds an ASSIGN button (bottom-right of the TASKS tab, or press A) that opens
-- a two-column screen:
--
--     TASKS (from the GitHub apps folder)        SEND TO
--       count                                      ANY idle computer
--       hello                                      ALL computers
--       ...                                        #2 miner     idle
--                                                  #3 farm      busy +1
--
--   1. tap a task       2. tap the computer it should run on
--
-- The task is assigned straight away - no typing. Stay on the screen to
-- assign more; Backspace goes back to the TASKS tab, where the new tasks
-- show up. [^] [v] (or Up/Down) scroll a long task list. If GitHub cannot be
-- reached the list falls back to the apps folders on this computer.
-- Tasks run with no arguments - use F in the TASKS tab when you need them.
--
-- Needs the TASKS tab (tasks_patch).
--
-- Usage:  assign_patch            (patches "crabtech")
--         assign_patch myfile     (patches another file name)
-- A backup is saved as <file>.bak first. Safe to run twice.

local arg1 = ({ ... })[1]
local path = shell.resolve(arg1 or "crabtech")
if not fs.exists(path) and fs.exists(path .. ".lua") then path = path .. ".lua" end
if not arg1 and not fs.exists(path) then
  local alt = shell.resolve("sanctuary")
  if fs.exists(alt) then path = alt elseif fs.exists(alt .. ".lua") then path = alt .. ".lua" end
end
if not fs.exists(path) then printError("File not found: " .. path) return end

local f = fs.open(path, "r")
local src = f.readAll()
f.close()

if src:find("local function assignTask", 1, true) then
  print("Already patched - nothing to do.")
  return
end
if not src:find("-- tasks v3: signed messages", 1, true) then
  printError("This patch needs the current TASKS tab - run tasks_patch first.")
  return
end

local ASSIGN = [==[  -- ASSIGN: tap a task from the list, then tap the computer that should run it
  local function assignTask()
    if needKey() then return end
    flash("loading the task list ...")
    local files = tkRemoteList()
    local source = "GitHub apps folder"
    if not files then files, source = tkLocalList(), "local apps folders" end
    local sel, top = nil, 1
    local note, noteColor = "", grey
    local a2 = {}

    local function targetRows()
      local rows = { { kind = "any", label = "ANY idle computer" }, { kind = "all", label = "ALL computers" } }
      for _, wk in ipairs(tkOnline(db)) do
        rows[#rows + 1] = { kind = "w", id = wk.id, w = wk, label = "#" .. wk.id .. "  " .. tostring(wk.label or "") }
      end
      return rows
    end

    local function resolve(row)
      if row.kind == "any" then
        local id = tkPickAny(db)
        return id and { id } or nil
      elseif row.kind == "all" then
        local ids = {}
        for _, wk in ipairs(tkOnline(db)) do ids[#ids + 1] = wk.id end
        return #ids > 0 and ids or nil
      end
      return { row.id }
    end

    local function paint(msg)
      if not a2.sy then return end
      frame(function()
        fill(a2.x1, a2.sy, a2.x2, a2.sy, pale)
        put(a2.x1, a2.sy, msg:sub(1, a2.x2 - a2.x1 + 1), grey, pale)
      end)
    end

    local function assign(file, row)
      local ids = resolve(row)
      if not ids then note, noteColor = "no computer online - go back and press S to scan", pink return end
      local spec
      if file.remote then
        spec = { name = file.name, kind = "github", file = file.file, args = {} }
      else
        local code = tkReadFile(file.path)
        if not code or #code > 100000 then note, noteColor = "could not send " .. file.name, pink return end
        if not load(code, "=" .. file.name) then note, noteColor = file.name .. " is not valid Lua", pink return end
        spec = { name = file.name, kind = "lua", code = code, args = {} }
      end
      paint("sending " .. file.name .. " ...")
      local n = tkSubmit(db, ids, spec)
      tkPoll(db)
      if n == #ids then note, noteColor = "sent " .. file.name .. " to " .. row.label, mid
      elseif n > 0 then note, noteColor = "sent to " .. n .. " of " .. #ids .. " computers", pink
      else note, noteColor = "no computer accepted " .. file.name, pink end
    end

    page("ASSIGN TASK", function(x1, y1, x2, y2)
      local w = x2 - x1 + 1
      local half = math.floor(w / 2)
      local rows = math.max(1, y2 - y1 - 3)
      a2 = { x1 = x1, x2 = x2, sy = y2 - 1, lx1 = x1, lx2 = x1 + half - 2, rx1 = x1 + half, rx2 = x2,
             y0 = y1 + 2, rows = rows, ay = y1 + 1 }
      put(x1, y1, (sel and ("task: " .. files[sel].name .. "   now tap a computer") or "tap a task, then tap a computer"):sub(1, w),
        sel and mid or grey, pale)
      put(a2.lx1, y1 + 1, ("TASKS  (" .. source .. ")"):sub(1, a2.lx2 - a2.lx1 - 8), deep, pale)
      put(a2.lx2 - 7, y1 + 1, "[^] [v]", mid, lav)
      put(a2.rx1, y1 + 1, "SEND TO", deep, pale)

      if sel then
        if sel < top then top = sel end
        if sel > top + rows - 1 then top = sel - rows + 1 end
      end
      top = clamp(top, 1, math.max(1, #files - rows + 1))
      if #files == 0 then put(a2.lx1 + 1, y1 + 2, "no apps found", grey, pale) end
      for i = 0, rows - 1 do
        local fl = files[top + i]
        if not fl then break end
        local y = y1 + 2 + i
        local on = (top + i == sel)
        local bg = on and deep or pale
        fill(a2.lx1, y, a2.lx2, y, bg)
        put(a2.lx1 + 1, y, ((on and "\16 " or "  ") .. fl.name .. (fl.tag or "")):sub(1, a2.lx2 - a2.lx1 - 1), on and snow or deep, bg)
      end

      local trows = targetRows()
      for i = 1, math.min(#trows, rows) do
        local r = trows[i]
        local y = y1 + 1 + i
        local bg = sel and lav or pale
        fill(a2.rx1, y, a2.rx2, y, bg)
        put(a2.rx1 + 1, y, r.label:sub(1, math.max(1, a2.rx2 - a2.rx1 - 12)), sel and deep or grey, bg)
        if r.kind == "w" then
          put(a2.rx2 - 9, y, r.w.busy and ("busy +" .. (r.w.queue or 0)) or "idle", mid, bg)
        end
      end
      put(a2.x1, a2.sy, note:sub(1, w), noteColor, pale)
      put(x1, y2, ("tap a task, then a computer   [^] [v] scroll   backspace back"):sub(1, w), grey, pale)
    end, function(kind, a, b)
      if kind == "key" then
        if a == keys.up and #files > 0 then sel = math.max(1, (sel or 2) - 1) note = "" return "render" end
        if a == keys.down and #files > 0 then sel = math.min(#files, (sel or 0) + 1) note = "" return "render" end
      elseif kind == "click" and a2.y0 then
        if b == a2.ay and a >= a2.lx2 - 7 and a <= a2.lx2 then
          local step = math.max(1, a2.rows - 1)
          if a <= a2.lx2 - 3 then top = math.max(1, top - step) else top = top + step end
          return "render"
        elseif a >= a2.lx1 and a <= a2.lx2 and b >= a2.y0 and b < a2.y0 + a2.rows then
          local idx = top + (b - a2.y0)
          if files[idx] then sel, note = idx, "" end
          return "render"
        elseif a >= a2.rx1 and a <= a2.rx2 and b >= a2.y0 and b < a2.y0 + a2.rows then
          local row = targetRows()[b - a2.y0 + 1]
          if row then
            if sel then assign(files[sel], row) else note, noteColor = "tap a task first", pink end
          end
          return "render"
        end
      end
    end)
  end

  local function runCommand()
]==]

local ok = true
local function edit(label, old, new, optional)
  local s, t = src:find(old, 1, true)
  if not s then
    print("skipped : " .. label .. " (not found)" .. (optional and ", optional" or ""))
    if not optional then ok = false end
    return
  end
  src = src:sub(1, s - 1) .. new .. src:sub(t + 1)
  print("patched : " .. label)
end

edit("Assign screen", "  local function runCommand()\n", ASSIGN)
edit("Button", "    put(x1, y2, hint:sub(1, w), grey, pale)", [==[    local btn = " ASSIGN "
    area.abtn = { x1 = x2 - #btn + 1, x2 = x2, y = y2 }
    put(x2 - #btn + 1, y2, btn, snow, deep)
    put(x1, y2, hint:sub(1, math.max(0, w - #btn - 1)), grey, pale)]==])
edit("Key A", '      elseif a == keys.s then scan() return "render"',
  '      elseif a == keys.a then assignTask() return "render"\n      elseif a == keys.s then scan() return "render"')
edit("Tap on the button", '    elseif kind == "click" then\n      if area.cy and b >= area.cy and b < area.cy + area.cn then',
  '    elseif kind == "click" then\n      if area.abtn and b == area.abtn.y and a >= area.abtn.x1 and a <= area.abtn.x2 then\n        assignTask()\n        return "render"\n      elseif area.cy and b >= area.cy and b < area.cy + area.cn then')
edit("Hint", '"enter run   f file from GitHub   s scan   k key   tab tasks"', '"enter run   f file   a assign   s scan   k key   tab tasks"', true)

-- list this patch on the INSTALLED tab (optional)
do
  local s, t = src:find('{ "tasks_patch",%s+"offload tasks",%s+function%(h%) return h%("%-%- tasks tab " %.%. "%(offload%)"%) end },')
  if s then
    src = src:sub(1, t) .. '\n    { "assign_patch",         "click to assign",    function(h) return h("local function " .. "assignTask") end },' .. src:sub(t + 1)
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
