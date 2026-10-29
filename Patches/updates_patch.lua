-- updates_patch.lua : adds an UPDATES tab - update the OS and apply patches from GitHub
--
--  The UPDATES tab checks the GitHub repo
--  (github.com/SenkuSushigami/CrabtechOS-Files) and lists:
--
--    OS file      crabtech.lua in the repo vs the OS you are running
--    Boot screen  startup.lua in the repo vs the one on this computer
--    Patches      every .lua file in the repo's  patches/  folder
--                 (applied in file-name order, so name them 01_..., 02_...)
--
--    Up/Down  move          Enter  update / apply the highlighted item
--    A        apply every new or changed patch
--    R        refresh        T      restart (after something was applied)
--    Backspace  back         Touch: tap to highlight, tap again to apply
--
--  Safety: a patch that leaves the OS file unreadable is rolled back
--  automatically, replacing the OS file or boot screen keeps a .bak copy,
--  and what has been applied is remembered in  /.crabtech_updates .
--  Patch output is shown in the same styled frame as the terminal.
--
--  Patch files are ordinary patch scripts: they receive the OS file path as
--  their first argument, exactly like the patches used to build this OS.
--
-- Usage:  updates_patch            (patches "crabtech")
--         updates_patch myfile     (patches another file name)
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

if src:find("local function actUpdates", 1, true) then
  print("Already patched - nothing to do.")
  return
end
if not (src:find("local function actInstalled", 1, true) and src:find("local function page(", 1, true)) then
  printError("This patch needs the merged OS file (crabtech.lua).")
  return
end

local UPDATES = [==[-- updates tab
local UPDATES = {
  repo       = "SenkuSushigami/CrabtechOS-Files",
  branch     = "main",
  patches    = "patches",       -- folder in the repo that holds patch scripts
  osRemote   = "crabtech.lua",  -- the OS file in the repo
  bootRemote = "startup.lua",   -- the boot screen in the repo
}

local function actUpdates()
  if not http then
    page("UPDATES", function(x1, y1)
      put(x1, y1, "The HTTP API is disabled on this server.", pink, pale)
    end)
    return
  end

  local STATE = ".crabtech_updates"
  local TMPDIR = ".crabtech_tmp"
  local osPath = shell.getRunningProgram()

  local function rawUrl(p)
    return "https://raw.githubusercontent.com/" .. UPDATES.repo .. "/" .. UPDATES.branch
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

  local function readFile(p)
    local h = fs.open(p, "r")
    if not h then return nil end
    local s = h.readAll()
    h.close()
    return s
  end

  local function writeFile(p, s)
    local d = fs.getDir(p)
    if d ~= "" and not fs.exists(d) then fs.makeDir(d) end
    local h = fs.open(p, "w")
    if not h then return false end
    h.write(s)
    h.close()
    return true
  end

  -- what has been applied so far --------------------------------------
  local state = { patches = {} }
  do
    local s = readFile(STATE)
    local t = s and textutils.unserialize(s)
    if type(t) == "table" then
      state.os, state.boot = t.os, t.boot
      if type(t.patches) == "table" then state.patches = t.patches end
    end
  end
  local function saveState() writeFile(STATE, textutils.serialize(state)) end

  -- ui state ----------------------------------------------------------
  local rows, loadErr, patchNote = {}, nil, nil
  local desc = {}
  local sel, top = 1, 1
  local area = {}
  local status, statusColor = "", mid
  local confirm, needRestart = nil, false

  local function say(msg, c) status, statusColor = msg, c or mid end

  local function flash(msg)
    if not area.sy then return end
    frame(function()
      fill(area.x1, area.sy, area.x2, area.sy, pale)
      put(area.x1, area.sy, msg:sub(1, area.x2 - area.x1 + 1), grey, pale)
    end)
  end

  -- GitHub listing ----------------------------------------------------
  local function api(dir)
    local u = "https://api.github.com/repos/" .. UPDATES.repo .. "/contents"
      .. (dir ~= "" and ("/" .. dir) or "") .. "?ref=" .. UPDATES.branch
    local body, err = get(u, { Accept = "application/vnd.github+json" })
    if not body then return nil, err end
    local data = textutils.unserializeJSON(body)
    if type(data) ~= "table" then return nil, "unexpected reply from GitHub" end
    if data.message then return nil, tostring(data.message) end
    return data
  end

  local function pending(r)
    return r.status == "update available" or r.status == "new" or r.status == "changed"
  end

  local function refresh()
    rows, loadErr, patchNote = {}, nil, nil
    local root, err = api("")
    if not root then loadErr = err return end
    local byName = {}
    for _, e in ipairs(root) do if e.type == "file" then byName[e.name] = e end end

    local function fileRow(kind, title, remote, localPath, note)
      local e = byName[remote]
      if not e then return end
      local isFile = fs.exists(localPath) and not fs.isDir(localPath)
      local st
      if state[kind] then
        st = (state[kind] == e.sha) and "up to date" or "update available"
      else
        st = (isFile and fs.getSize(localPath) == e.size) and "up to date" or "update available"
      end
      rows[#rows + 1] = { kind = kind, title = title, remote = remote, path = localPath,
        sha = e.sha, status = st, note = note }
    end
    fileRow("os", "OS file (" .. UPDATES.osRemote .. ")", UPDATES.osRemote, osPath,
      "Replaces the OS with the latest from GitHub (a .bak copy is kept).")
    fileRow("boot", "Boot screen (" .. UPDATES.bootRemote .. ")", UPDATES.bootRemote, "startup.lua",
      "Replaces the boot screen with the latest from GitHub (a .bak copy is kept).")

    local plist, perr = api(UPDATES.patches)
    if plist then
      local names = {}
      for _, e in ipairs(plist) do
        if e.type == "file" and type(e.name) == "string" and e.name:match("%.lua$") then names[#names + 1] = e end
      end
      table.sort(names, function(a, b) return a.name < b.name end)
      for _, e in ipairs(names) do
        local st = "new"
        if state.patches[e.name] then st = (state.patches[e.name] == e.sha) and "applied" or "changed" end
        rows[#rows + 1] = { kind = "patch", title = e.name, remote = e.name, sha = e.sha, status = st }
      end
      if #names == 0 then patchNote = "No patches published yet." end
    elseif tostring(perr):find("404", 1, true) then
      patchNote = "No /" .. UPDATES.patches .. " folder in the repo yet."
    else
      patchNote = "Patch list failed: " .. tostring(perr)
    end
  end

  -- first comment lines of a patch script = its description
  local function describe(r)
    if r.kind ~= "patch" then return { r.note or "" } end
    if desc[r.remote] then return desc[r.remote] end
    local lines = {}
    local body = get(rawUrl(UPDATES.patches .. "/" .. r.remote))
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
    desc[r.remote] = lines
    return lines
  end

  local function choose(i)
    sel, confirm = i, nil
    local r = rows[sel]
    if r and r.kind == "patch" and not desc[r.remote] then
      flash("loading description ...")
      describe(r)
    end
  end

  -- applying ----------------------------------------------------------
  local function applyFile(r)
    if r.kind == "os" and confirm ~= r.remote then
      confirm = r.remote
      say("press Enter again to replace the OS file (restart needed)", pink)
      return
    end
    confirm = nil
    flash("downloading " .. r.remote .. " ...")
    local body, err = get(rawUrl(r.remote))
    if not body then say("failed: " .. tostring(err), pink) return end
    local fn, perr = load(body, "=" .. r.remote)
    if not fn then say("not valid Lua: " .. tostring(perr), pink) return end
    if fs.exists(r.path) then
      fs.delete(r.path .. ".bak")
      fs.copy(r.path, r.path .. ".bak")
    end
    if not writeFile(r.path, body) then say("could not write " .. r.path, pink) return end
    state[r.kind] = r.sha
    saveState()
    r.status = "up to date"
    needRestart = true
    say("updated " .. r.path .. " - press T to restart", mid)
  end

  local function applyPatches(list)
    local applied, failed = 0, 0
    local function run()
      local rawPrint, rawErr = _G.print, _G.printError
      for _, r in ipairs(list) do
        print()
        print("== " .. r.remote)
        local log = {}
        local function capture(orig)
          return function(...)
            local t = {}
            for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
            log[#log + 1] = table.concat(t, " ")
            return orig(...)
          end
        end

        local body, err = get(rawUrl(UPDATES.patches .. "/" .. r.remote))
        local fn = body and load(body, "=" .. r.remote)
        if not body then
          print("download failed: " .. tostring(err))
          failed = failed + 1
        elseif not fn then
          print("not valid Lua - skipped")
          failed = failed + 1
        else
          local before = readFile(osPath)
          local tmp = TMPDIR .. "/" .. r.remote
          writeFile(tmp, body)
          _G.print, _G.printError = capture(rawPrint), capture(rawErr)
          pcall(shell.run, "/" .. tmp, "/" .. osPath)
          _G.print, _G.printError = rawPrint, rawErr
          fs.delete(tmp)

          local after = readFile(osPath)
          local text = table.concat(log, "\n")
          if after and before and after ~= before then
            if load(after, "=" .. osPath) then
              state.patches[r.remote] = r.sha
              saveState()
              r.status = "applied"
              applied = applied + 1
              needRestart = true
              print("-> applied")
            else
              writeFile(osPath, before)
              print("-> broke the OS file, rolled back")
              failed = failed + 1
            end
          elseif text:find("Already patched", 1, true) then
            state.patches[r.remote] = r.sha
            saveState()
            r.status = "applied"
            applied = applied + 1
            print("-> already applied")
          else
            print("-> no changes made")
            failed = failed + 1
          end
        end
      end
      if fs.exists(TMPDIR) and #fs.list(TMPDIR) == 0 then fs.delete(TMPDIR) end
      print()
      print(("Done: %d applied, %d failed."):format(applied, failed))
      write("Press any key to continue ... ")
      os.pullEvent("key")
    end

    local first = list[1] and list[1].remote or ""
    if runStyled then
      runStyled({
        pill = " PATCH ", title = "Updates", sub = "u p d a t e s",
        hintA = "applying", hintB = (#list == 1) and first:sub(1, 14) or (#list .. " patches"),
        footer = "UPDATES  ////  applying patches from GitHub",
        run = run,
      })
    else
      onComputer(run)
    end

    if failed == 0 and applied > 0 then
      say(applied .. " patch(es) applied - press T to restart", mid)
    elseif applied > 0 then
      say(applied .. " applied, " .. failed .. " failed - press T to restart", pink)
    elseif failed > 0 then
      say(failed .. " failed - OS file unchanged", pink)
    end
  end

  local function pendingPatches()
    local list = {}
    for _, r in ipairs(rows) do
      if r.kind == "patch" and pending(r) then list[#list + 1] = r end
    end
    return list
  end

  -- drawing -----------------------------------------------------------
  local function draw(x1, y1, x2, y2)
    local w = x2 - x1 + 1
    area = { x1 = x1, x2 = x2, sy = y2 - 1 }
    put(x1, y1, ("github.com/" .. UPDATES.repo .. "  (" .. UPDATES.branch .. ")"):sub(1, w), grey, pale)
    put(x1, y2, ("enter apply   a apply all   r refresh   t restart"):sub(1, w), grey, pale)

    if loadErr then
      put(x1, y1 + 2, loadErr:sub(1, w), pink, pale)
      put(x1, y1 + 3, "press R to try again", grey, pale)
      return
    end

    local n = 0
    for _, r in ipairs(rows) do if pending(r) then n = n + 1 end end
    if needRestart then
      put(x1, y1 + 1, "restart needed - press T", pink, pale)
    elseif n > 0 then
      put(x1, y1 + 1, n .. " update(s) available", pink, pale)
    else
      put(x1, y1 + 1, "everything is up to date", mid, pale)
    end

    local statusX = x2 - 17
    local listTop = y1 + 3
    local rowsVisible = math.max(1, y2 - 4 - listTop + 1)
    area.ly1, area.rows = listTop, rowsVisible
    put(x1 + 2, y1 + 2, "ITEM", grey, pale)
    put(statusX, y1 + 2, "STATUS", grey, pale)

    if sel < top then top = sel end
    if sel > top + rowsVisible - 1 then top = sel - rowsVisible + 1 end
    for i = 0, rowsVisible - 1 do
      local r = rows[top + i]
      if not r then break end
      local y = listTop + i
      local on = (top + i == sel)
      local bg = on and deep or pale
      fill(x1, y, x2, y, bg)
      put(x1 + 1, y, ((on and "\16 " or "  ") .. r.title):sub(1, statusX - x1 - 2), on and snow or deep, bg)
      local good = (r.status == "up to date" or r.status == "applied")
      put(statusX, y, r.status, good and (on and ice or mid) or pink, bg)
    end
    if #rows > rowsVisible then
      put(x2 - 6, y1 + 2, (top + rowsVisible - 1 < #rows) and "\31 more" or "", mid, pale)
    end
    if patchNote then put(x1, listTop + math.min(#rows, rowsVisible), patchNote:sub(1, w), grey, pale) end

    local lines = rows[sel] and describe(rows[sel]) or {}
    put(x1, y2 - 3, (lines[1] or ""):sub(1, w), mid, pale)
    put(x1, y2 - 2, (lines[2] or ""):sub(1, w), grey, pale)
    put(x1, y2 - 1, status:sub(1, w), statusColor, pale)
  end

  -- open: contact GitHub first ----------------------------------------
  frame(function()
    local msg = "Checking for updates ..."
    local w = #msg + 8
    local x = math.max(1, math.floor((W - w) / 2) + 1)
    local y = math.max(1, math.floor(H / 2) - 1)
    box(x, y, x + w - 1, y + 2)
    put(x + 4, y + 1, msg, deep, pale)
  end)
  refresh()

  local function activate(r)
    if r.kind == "patch" then applyPatches({ r }) else applyFile(r) end
  end

  page("UPDATES", draw, function(kind, a, b)
    if kind == "key" then
      if a == keys.up then
        if sel > 1 then choose(sel - 1) end
        return "render"
      elseif a == keys.down then
        if sel < #rows then choose(sel + 1) end
        return "render"
      elseif a == keys.enter then
        if rows[sel] then activate(rows[sel]) end
        return "render"
      elseif a == keys.a then
        local list = pendingPatches()
        if #list == 0 then say("no pending patches", grey) else applyPatches(list) end
        return "render"
      elseif a == keys.r then
        flash("checking ...")
        refresh()
        desc, sel, top, confirm = {}, 1, 1, nil
        say("list refreshed", mid)
        return "render"
      elseif a == keys.t then
        if needRestart then os.reboot() else say("no restart needed", grey) end
        return "render"
      end
    elseif kind == "click" and area.ly1 and b >= area.ly1 and b < area.ly1 + area.rows then
      local idx = top + (b - area.ly1)
      if rows[idx] then
        if idx == sel then activate(rows[idx]) else choose(idx) end
        return "render"
      end
    end
  end)
end

local actions = {]==]

local function plainEdit(label, old, new)
  local s, t = src:find(old, 1, true)
  if not s then print("skipped : " .. label .. " (not found)") return false end
  src = src:sub(1, s - 1) .. new .. src:sub(t + 1)
  print("patched : " .. label)
  return true
end

local ok = true
ok = plainEdit("Menu button", '{ label = "INSTALLED" }', '{ label = "UPDATES" }, { label = "INSTALLED" }') and ok
ok = plainEdit("Updates page", "local actions = {", UPDATES) and ok
ok = plainEdit("Button action", "actTerminal, actInstalled,", "actTerminal, actUpdates, actInstalled,") and ok

-- list this patch on the INSTALLED tab (optional)
do
  local s, t = src:find('{ "installed_patch",%s+"this tab",%s+function%(h%) return h%("local function " %.%. "actInstalled"%) end },')
  if s then
    src = src:sub(1, t) .. '\n    { "updates_patch",        "updates tab",        function(h) return h("local function " .. "actUpdates") end },' .. src:sub(t + 1)
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
print("Publish patch scripts in the repo's patches/ folder, then open UPDATES.")
