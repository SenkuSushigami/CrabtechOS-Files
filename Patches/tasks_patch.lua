-- tasks_patch.lua : adds a TASKS tab - offload work to other computers
--
--  The TASKS tab sends programs and commands to other computers on your
--  network (wired modems/cables or wireless modems) and shows their output.
--  Those computers run  worker.lua  (included) - one worker per computer.
--
--  Set up
--    1. Put a modem on this computer and on each worker computer.
--       (Wired modems must be right-clicked so they connect to the network.)
--    2. On each worker:   worker key <secret>     then     worker
--                         (worker install  starts it automatically at boot)
--    3. In the OS:  TASKS tab -> K -> type the SAME secret.
--    4. Press S to scan. Workers that answer show up under COMPUTERS.
--
--  Using it
--    COMPUTERS   ANY idle computer   picks the least busy worker for you
--                ALL computers       runs the task on every worker
--                #12 label ...      one specific computer
--      Enter  run a command there        F  send a task file
--      S      scan again                 K  set the shared key
--    TASKS (Tab switches pane)
--      Enter  show the output            X  cancel a running task
--      C      clear finished tasks       R  refresh now
--    Touch: tap a row to select it, tap again to use it.
--
--  Task files are ordinary Lua programs kept in a folder named  tasks  on
--  this computer (or /disk/tasks on a floppy). They run on the worker with
--  the arguments you type.
--
--  Security: messages are signed with the shared key (HMAC-SHA256) and carry
--  a timestamp, so computers without the key, replays and edited messages
--  are ignored. Anyone WITH the key can run code on every worker.
--
--  Works on the merged OS file (crabtech). The tab is added above INSTALLED.
--
-- Usage:  tasks_patch            (patches "crabtech")
--         tasks_patch myfile     (patches another file name)
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

if src:find("-- tasks tab (offload)", 1, true) then
  print("Already patched - nothing to do.")
  return
end
if not (src:find("local function actInstalled", 1, true) and src:find("local function page(", 1, true)) then
  printError("This patch needs the merged OS file (crabtech.lua).")
  return
end

local BLOCK = [==[-- tasks tab (offload)
local actTasks
do
-- CORE BEGIN
local tkProtocol = "crabtech.task"
local tkKeyFile  = ".crabtech_key"
local tkDbFile   = ".crabtech_tasks"

-- ---- signing: SHA-256 / HMAC (messages are signed with the shared key) ----
local tkK256 = {
  0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
  0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
  0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
  0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
  0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
  0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
  0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
  0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
}

local function tkU32(n)
  return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256,
    math.floor(n / 256) % 256, n % 256)
end

local function tkSha256(msg)
  local bxor, band, bnot, rshift, rrotate = bit32.bxor, bit32.band, bit32.bnot, bit32.rshift, bit32.rrotate
  local h0, h1, h2, h3 = 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a
  local h4, h5, h6, h7 = 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
  local len = #msg
  msg = msg .. "\128" .. string.rep("\0", (55 - len) % 64)
    .. tkU32(math.floor(len * 8 / 4294967296)) .. tkU32((len * 8) % 4294967296)
  local w = {}
  for chunk = 1, #msg, 64 do
    for i = 0, 15 do
      local a, b, c, d = msg:byte(chunk + i * 4, chunk + i * 4 + 3)
      w[i + 1] = a * 16777216 + b * 65536 + c * 256 + d
    end
    for i = 17, 64 do
      local x, y = w[i - 15], w[i - 2]
      local s0 = bxor(rrotate(x, 7), rrotate(x, 18), rshift(x, 3))
      local s1 = bxor(rrotate(y, 17), rrotate(y, 19), rshift(y, 10))
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) % 4294967296
    end
    local a, b, c, d, e, f, g, h = h0, h1, h2, h3, h4, h5, h6, h7
    for i = 1, 64 do
      local S1 = bxor(rrotate(e, 6), rrotate(e, 11), rrotate(e, 25))
      local ch = bxor(band(e, f), band(bnot(e), g))
      local t1 = (h + S1 + ch + tkK256[i] + w[i]) % 4294967296
      local S0 = bxor(rrotate(a, 2), rrotate(a, 13), rrotate(a, 22))
      local maj = bxor(band(a, b), band(a, c), band(b, c))
      local t2 = (S0 + maj) % 4294967296
      h, g, f, e, d, c, b, a = g, f, e, (d + t1) % 4294967296, c, b, a, (t1 + t2) % 4294967296
    end
    h0, h1, h2, h3 = (h0 + a) % 4294967296, (h1 + b) % 4294967296, (h2 + c) % 4294967296, (h3 + d) % 4294967296
    h4, h5, h6, h7 = (h4 + e) % 4294967296, (h5 + f) % 4294967296, (h6 + g) % 4294967296, (h7 + h) % 4294967296
  end
  return tkU32(h0) .. tkU32(h1) .. tkU32(h2) .. tkU32(h3) .. tkU32(h4) .. tkU32(h5) .. tkU32(h6) .. tkU32(h7)
end

local function tkHex(s)
  return (s:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

local function tkHmac(key, msg)
  if #key > 64 then key = tkSha256(key) end
  key = key .. string.rep("\0", 64 - #key)
  local ipad, opad = {}, {}
  for i = 1, 64 do
    local b = key:byte(i)
    ipad[i] = string.char(bit32.bxor(b, 0x36))
    opad[i] = string.char(bit32.bxor(b, 0x5c))
  end
  return tkHex(tkSha256(table.concat(opad) .. tkSha256(table.concat(ipad) .. msg)))
end

local function tkSame(a, b)
  if #a ~= #b then return false end
  local d = 0
  for i = 1, #a do d = bit32.bor(d, bit32.bxor(a:byte(i), b:byte(i))) end
  return d == 0
end

-- a signed message: { p = serialized payload, s = hmac(key, p) }
local function tkSeal(key, payload)
  local p = textutils.serialize(payload)
  return { p = p, s = tkHmac(key, p) }
end

-- returns the payload, or nil when the signature or timestamp is wrong
local function tkOpen(key, env)
  if type(env) ~= "table" or type(env.p) ~= "string" or type(env.s) ~= "string" then return nil end
  if not tkSame(env.s, tkHmac(key, env.p)) then return nil end
  local pl = textutils.unserialize(env.p)
  if type(pl) ~= "table" or type(pl.ts) ~= "number" then return nil end
  if math.abs(os.epoch("utc") / 1000 - pl.ts) > 120 then return nil end
  return pl
end

local function tkReadFile(p)
  local h = fs.open(p, "r")
  if not h then return nil end
  local s = h.readAll()
  h.close()
  return s
end

local function tkWriteFile(p, s)
  local h = fs.open(p, "w")
  if not h then return false end
  h.write(s)
  h.close()
  return true
end

local function tkKey()
  local s = tkReadFile(tkKeyFile)
  if not s then return nil end
  s = s:gsub("%s+$", "")
  if s == "" then return nil end
  return s
end

local function tkOpenModems()
  local n = 0
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" then
      if not rednet.isOpen(name) then rednet.open(name) end
      n = n + 1
    end
  end
  return n
end

local function tkNonce()
  return tostring(os.epoch("utc")) .. "-" .. tostring(math.random(0, 999999999))
end

-- send a signed request to some computers (or "all" = broadcast) and collect
-- the signed replies; other events that arrive meanwhile are put back
local function tkRpc(targets, payload, timeout)
  local key = tkKey()
  if not key then return {} end
  local nonce = tkNonce()
  payload.n, payload.ts = nonce, os.epoch("utc") / 1000
  local env = tkSeal(key, payload)
  local want
  if targets == "all" then
    rednet.broadcast(env, tkProtocol)
  else
    want = 0
    for _, id in ipairs(targets) do rednet.send(id, env, tkProtocol) want = want + 1 end
    if want == 0 then return {} end
  end
  local replies, got, held = {}, 0, {}
  local timer = os.startTimer(timeout or 1.5)
  while true do
    local ev = { os.pullEvent() }
    if ev[1] == "rednet_message" and ev[4] == tkProtocol then
      local pl = tkOpen(key, ev[3])
      if pl and pl.re == nonce and not replies[ev[2]] then
        replies[ev[2]] = pl
        got = got + 1
        if want and got >= want then break end
      end
    elseif ev[1] == "timer" and ev[2] == timer then
      break
    else
      held[#held + 1] = ev
    end
  end
  os.cancelTimer(timer)
  for _, ev in ipairs(held) do os.queueEvent((table.unpack or unpack)(ev)) end
  return replies
end

-- the list of known computers and submitted tasks is kept in a small file
local function tkLoad()
  local s = tkReadFile(tkDbFile)
  local db = s and textutils.unserialize(s)
  if type(db) ~= "table" then db = {} end
  db.workers = type(db.workers) == "table" and db.workers or {}
  db.tasks = type(db.tasks) == "table" and db.tasks or {}
  db.rr = db.rr or 0
  return db
end

local function tkSave(db)
  while #db.tasks > 40 do table.remove(db.tasks, 1) end
  tkWriteFile(tkDbFile, textutils.serialize(db))
end

local function tkActive(state) return state == "queued" or state == "running" end

local function tkHasActive(db)
  for _, t in ipairs(db.tasks) do if tkActive(t.state) then return true end end
  return false
end

local function tkNote(db, id, info)
  if type(info) ~= "table" then return end
  local w = db.workers[id] or {}
  w.id, w.online = id, true
  w.label = info.label or ("#" .. id)
  w.busy, w.queue, w.free, w.running = info.busy, info.queue or 0, info.free, info.running
  db.workers[id] = w
end

-- find computers: broadcast a signed ping, everyone with the key answers
local function tkScan(db)
  for _, w in pairs(db.workers) do w.online = false end
  local replies = tkRpc("all", { t = "ping" }, 1.5)
  local n = 0
  for id, r in pairs(replies) do
    if r.t == "pong" then tkNote(db, id, r.info) n = n + 1 end
  end
  tkSave(db)
  return n
end

local function tkOnline(db)
  local list = {}
  for _, w in pairs(db.workers) do if w.online then list[#list + 1] = w end end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

-- the least busy online computer (ties are shared out in turn)
local function tkPickAny(db)
  local list = tkOnline(db)
  if #list == 0 then return nil end
  local best, bestLoad = {}, nil
  for _, w in ipairs(list) do
    local load = (w.queue or 0) + (w.busy and 1 or 0)
    if bestLoad == nil or load < bestLoad then best, bestLoad = { w }, load
    elseif load == bestLoad then best[#best + 1] = w end
  end
  db.rr = db.rr + 1
  return best[(db.rr - 1) % #best + 1].id
end

-- send one task to each computer in ids; returns how many accepted it
local function tkSubmit(db, ids, spec)
  local accepted = 0
  for _, id in ipairs(ids) do
    local task = {
      id = "t" .. os.epoch("utc") .. "-" .. math.random(1000, 9999),
      name = spec.name, kind = spec.kind, cmd = spec.cmd, code = spec.code, args = spec.args or {},
    }
    local r = tkRpc({ id }, { t = "run", task = task }, 2)[id]
    local rec = { id = task.id, name = spec.name, worker = id, kind = spec.kind, t0 = os.epoch("utc"), state = "queued" }
    if r and r.t == "accepted" then
      accepted = accepted + 1
      tkNote(db, id, r.info)
    else
      rec.state = "failed"
      rec.tail = (r and r.t == "rejected") and "the computer rejected the task" or "no answer from the computer"
      if not r and db.workers[id] then db.workers[id].online = false end
    end
    db.tasks[#db.tasks + 1] = rec
  end
  tkSave(db)
  return accepted
end

-- ask each computer how its unfinished tasks are doing; true if anything changed
local function tkPoll(db)
  local byWorker = {}
  for _, t in ipairs(db.tasks) do
    if tkActive(t.state) then
      byWorker[t.worker] = byWorker[t.worker] or {}
      table.insert(byWorker[t.worker], t.id)
    end
  end
  local changed = false
  for wid, ids in pairs(byWorker) do
    local r = tkRpc({ wid }, { t = "status", ids = ids }, 1.5)[wid]
    if r and r.t == "status" and type(r.tasks) == "table" then
      tkNote(db, wid, r.info)
      for _, t in ipairs(db.tasks) do
        local s = (t.worker == wid) and r.tasks[t.id]
        if s then
          local state = (s.state == "unknown") and "lost" or s.state
          if state ~= t.state or s.secs ~= t.secs then changed = true end
          t.state, t.ok, t.secs, t.tail = state, s.ok, s.secs, s.tail
        end
      end
    else
      if db.workers[wid] and db.workers[wid].online then changed = true end
      if db.workers[wid] then db.workers[wid].online = false end
    end
  end
  if changed then tkSave(db) end
  return changed
end

local function tkResult(t)
  local r = tkRpc({ t.worker }, { t = "result", id = t.id }, 2)[t.worker]
  if r and r.t == "result" and type(r.output) == "string" then return r.output, r.state end
  return nil
end

local function tkCancel(db, t)
  local r = tkRpc({ t.worker }, { t = "cancel", id = t.id }, 1.5)[t.worker]
  if r and r.t == "cancelled" and r.ok then
    t.state = "cancelled"
    tkSave(db)
    return true
  end
  return false
end
-- CORE END

-- tasks tab
actTasks = function()
  math.randomseed(os.epoch("utc"))
  local db = tkLoad()
  local modems = tkOpenModems()
  local focus = "c"                       -- "c" computers, "t" tasks
  local csel, ctop, tsel, ttop = 1, 1, 1, 1
  local status, statusColor = "", mid
  local area = {}
  local ticks = 0

  local function say(msg, c) status, statusColor = msg, c or mid end

  local function flash(msg)
    if not area.sy then return end
    frame(function()
      fill(area.x1, area.sy, area.x2, area.sy, pale)
      put(area.x1, area.sy, msg:sub(1, area.x2 - area.x1 + 1), grey, pale)
    end)
  end

  local function computerRows()
    local rows = { { kind = "any" }, { kind = "all" } }
    local ids = {}
    for id in pairs(db.workers) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do rows[#rows + 1] = { kind = "w", id = id, w = db.workers[id] } end
    return rows
  end

  local function taskRows()
    local rows = {}
    for i = #db.tasks, 1, -1 do rows[#rows + 1] = db.tasks[i] end
    return rows
  end

  -- text input on the computer's own keyboard
  local function ask(title, prompt, secret)
    local answer
    local function run()
      print(title)
      print()
      write(prompt .. " ")
      answer = read(secret and "*" or nil)
    end
    if runStyled then
      runStyled({
        pill = " TASK ", title = "Tasks", sub = "t a s k s",
        hintA = "type + enter", hintB = "empty = cancel",
        footer = "TASKS  ////  input on the computer keyboard", run = run,
      })
    else
      onComputer(run)
    end
    if answer == nil or answer == "" then return nil end
    return answer
  end

  -- task files: /tasks and /disk*/tasks
  local function taskFiles()
    local out = {}
    local function scan(dir, tag)
      if fs.isDir(dir) then
        for _, f in ipairs(fs.list(dir)) do
          local p = fs.combine(dir, f)
          if not fs.isDir(p) and f:match("%.lua$") then
            out[#out + 1] = { name = (f:gsub("%.lua$", "")), path = p, tag = tag }
          end
        end
      end
    end
    scan("tasks", "")
    for _, d in ipairs(fs.list("/")) do
      if d:match("^disk") and fs.isDir(d) then scan(fs.combine(d, "tasks"), "  [" .. d .. "]") end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
  end

  local function pickTaskFile()
    local files = taskFiles()
    local chosen, psel, ptop = nil, 1, 1
    page("TASK FILES", function(x1, y1, x2, y2)
      put(x1, y1, "Lua files in /tasks (and /disk*/tasks) - enter sends one", grey, pale)
      if #files == 0 then
        put(x1, y1 + 2, "No task files yet - put .lua programs in a folder named tasks", mid, pale)
        return
      end
      local rows = math.max(1, y2 - (y1 + 2))
      if psel < ptop then ptop = psel end
      if psel > ptop + rows - 1 then ptop = psel - rows + 1 end
      for i = 0, rows - 1 do
        local f = files[ptop + i]
        if not f then break end
        local on = (ptop + i == psel)
        local bg = on and deep or pale
        fill(x1, y1 + 2 + i, x2, y1 + 2 + i, bg)
        put(x1 + 1, y1 + 2 + i, ((on and "\16 " or "  ") .. f.name .. f.tag):sub(1, x2 - x1 - 1), on and snow or deep, bg)
      end
    end, function(kind, a)
      if kind ~= "key" then return end
      if a == keys.up and psel > 1 then psel = psel - 1 return "render" end
      if a == keys.down and psel < #files then psel = psel + 1 return "render" end
      if a == keys.enter then
        chosen = files[psel]
        return "close"
      end
    end)
    return chosen
  end

  local function selectedTargets()
    local row = computerRows()[csel]
    if not row then return nil, "nothing selected" end
    if row.kind == "any" then
      local id = tkPickAny(db)
      if not id then return nil, "no computer online - press S to scan" end
      return { id }, "any idle computer (#" .. id .. ")"
    elseif row.kind == "all" then
      local ids = {}
      for _, w in ipairs(tkOnline(db)) do ids[#ids + 1] = w.id end
      if #ids == 0 then return nil, "no computer online - press S to scan" end
      return ids, "all " .. #ids .. " computers"
    end
    if not row.w.online then return nil, "#" .. row.id .. " is offline - press S to scan" end
    return { row.id }, "#" .. row.id .. " " .. tostring(row.w.label or "")
  end

  local function send(ids, spec, label)
    flash("sending " .. spec.name .. " ...")
    local n = tkSubmit(db, ids, spec)
    tkPoll(db)
    if n == #ids then say("sent " .. spec.name .. " to " .. label, mid)
    elseif n > 0 then say("sent to " .. n .. " of " .. #ids .. " computers", pink)
    else say("no computer accepted the task", pink) end
    focus, tsel, ttop = "t", 1, 1
  end

  local function needKey()
    if tkKey() then return false end
    say("set the shared key first (press K)", pink)
    return true
  end

  local function runCommand()
    if needKey() then return end
    local ids, label = selectedTargets()
    if not ids then say(label, pink) return end
    local cmd = ask("Run a command on " .. label, "Command:")
    if cmd then send(ids, { name = cmd:sub(1, 40), kind = "cmd", cmd = cmd }, label) end
  end

  local function runFile()
    if needKey() then return end
    local ids, label = selectedTargets()
    if not ids then say(label, pink) return end
    local file = pickTaskFile()
    if not file then return end
    local code = tkReadFile(file.path)
    if not code then say("could not read " .. file.path, pink) return end
    if #code > 100000 then say(file.name .. " is too big to send (100 kB max)", pink) return end
    local argText = ask("Send " .. file.name .. " to " .. label, "Arguments (optional):")
    local list = {}
    for word in (argText or ""):gmatch("%S+") do list[#list + 1] = word end
    send(ids, { name = file.name, kind = "lua", code = code, args = list }, label)
  end

  local function setKey()
    local k = ask("Shared key (the same key must be set on every worker)", "Key:", true)
    if not k then return end
    tkWriteFile(tkKeyFile, k)
    say("key saved - press S to scan for computers", mid)
  end

  local function scan()
    flash("scanning ...")
    modems = tkOpenModems()
    if needKey() then return end
    local n = tkScan(db)
    csel, ctop = math.min(csel, #computerRows()), 1
    say(n .. " computer(s) answered", n > 0 and mid or pink)
    tkPoll(db)
  end

  local function viewOutput(t)
    flash("fetching output ...")
    local text, state = tkResult(t)
    if text then
      t.tail = text:sub(-400)
      if state and state ~= "unknown" then t.state = state end
    else
      text = t.tail or "(no output available - is the computer online?)"
    end
    local lines = {}
    for line in (text .. "\n"):gmatch("(.-)\r?\n") do lines[#lines + 1] = line end
    if #lines > 1 and lines[#lines] == "" then lines[#lines] = nil end
    local top = 1
    page("TASK OUTPUT", function(x1, y1, x2, y2)
      put(x1, y1, (t.name .. "   #" .. t.worker .. "   " .. t.state):sub(1, x2 - x1 + 1), mid, pale)
      local rows = math.max(1, y2 - (y1 + 1))
      top = clamp(top, 1, math.max(1, #lines - rows + 1))
      for i = 0, rows - 1 do
        local l = lines[top + i]
        if not l then break end
        put(x1, y1 + 1 + i, l:sub(1, x2 - x1 + 1), deep, pale)
      end
      if #lines > rows then put(x2 - 10, y1, top .. "/" .. #lines, grey, pale) end
    end, function(kind, a)
      if kind ~= "key" then return end
      if a == keys.up then top = math.max(1, top - 1) return "render" end
      if a == keys.down then top = top + 1 return "render" end
    end)
  end

  local function cancelTask(t)
    if not tkActive(t.state) then say("that task has already finished", grey) return end
    if tkCancel(db, t) then say("cancelled " .. t.name, mid)
    else say("could not cancel - is the computer online?", pink) end
  end

  local function clearFinished()
    local keep, removed = {}, 0
    for _, t in ipairs(db.tasks) do
      if tkActive(t.state) then keep[#keep + 1] = t else removed = removed + 1 end
    end
    db.tasks = keep
    tkSave(db)
    tsel, ttop = 1, 1
    say("cleared " .. removed .. " finished task(s)", mid)
  end

  -- drawing ---------------------------------------------------------
  local function stateColor(state, on)
    if state == "done" or state == "running" then return on and ice or mid end
    if state == "queued" then return on and ice or grey end
    return pink
  end

  local function draw(x1, y1, x2, y2)
    local w = x2 - x1 + 1
    area = { x1 = x1, x2 = x2, sy = y2 - 1 }

    if modems == 0 then
      put(x1, y1, "No modem on this computer.", pink, pale)
      put(x1, y1 + 1, "Attach a wired or wireless modem, then reopen this tab.", grey, pale)
      return
    end

    local keyOk = tkKey() ~= nil
    local online = #tkOnline(db)
    put(x1, y1, (online .. " computer(s) online"):sub(1, w), online > 0 and mid or grey, pale)
    local ks = keyOk and "key: set" or "key: NOT SET - press K"
    put(x2 - #ks + 1, y1, ks, keyOk and mid or pink, pale)

    local remaining = math.max(2, y2 - y1 - 4)
    local crows = computerRows()
    local cn = math.max(2, math.min(#crows, math.floor(remaining / 2)))
    local tn = math.max(1, remaining - cn)
    local cy = y1 + 2
    local ty = cy + cn + 1
    area.cy, area.cn, area.ty, area.tn = cy, cn, ty, tn

    put(x1, y1 + 1, "COMPUTERS", focus == "c" and deep or grey, pale)
    put(x1, ty - 1, "TASKS", focus == "t" and deep or grey, pale)

    csel = clamp(csel, 1, #crows)
    if csel < ctop then ctop = csel end
    if csel > ctop + cn - 1 then ctop = csel - cn + 1 end
    for i = 0, cn - 1 do
      local r = crows[ctop + i]
      if not r then break end
      local y = cy + i
      local isSel = (ctop + i == csel)
      local on = isSel and focus == "c"
      local bg = on and deep or pale
      fill(x1, y, x2, y, bg)
      local name, stat
      if r.kind == "any" then name, stat = "ANY idle computer", "auto"
      elseif r.kind == "all" then name, stat = "ALL computers", online .. " online"
      else
        name = "#" .. r.id .. "  " .. tostring(r.w.label or "")
        if r.w.online then stat = r.w.busy and ("busy +" .. (r.w.queue or 0)) or "idle" else stat = "offline" end
      end
      put(x1 + 1, y, ((isSel and "\16 " or "  ") .. name):sub(1, math.max(1, w - 17)), on and snow or deep, bg)
      local col = (r.kind == "w" and not r.w.online) and pink or (on and ice or mid)
      put(x2 - 14, y, stat:sub(1, 14), col, bg)
    end

    local trows = taskRows()
    if #trows == 0 then
      put(x1 + 2, ty, "no tasks yet - press Enter on a computer to run something", grey, pale)
    else
      tsel = clamp(tsel, 1, #trows)
      if tsel < ttop then ttop = tsel end
      if tsel > ttop + tn - 1 then ttop = tsel - tn + 1 end
      for i = 0, tn - 1 do
        local t = trows[ttop + i]
        if not t then break end
        local y = ty + i
        local isSel = (ttop + i == tsel)
        local on = isSel and focus == "t"
        local bg = on and deep or pale
        fill(x1, y, x2, y, bg)
        put(x1 + 1, y, ((isSel and "\16 " or "  ") .. t.name):sub(1, math.max(1, w - 30)), on and snow or deep, bg)
        put(x2 - 27, y, ("#" .. t.worker):sub(1, 6), on and ice or grey, bg)
        put(x2 - 20, y, t.state:sub(1, 10), stateColor(t.state, on), bg)
        put(x2 - 8, y, t.secs and (t.secs .. "s") or "", on and ice or grey, bg)
      end
    end

    put(x1, y2 - 1, status:sub(1, w), statusColor, pale)
    local hint = (focus == "c")
      and "enter run   f task file   s scan   k key   tab tasks"
      or "enter output   x cancel   c clear   r refresh   tab computers"
    put(x1, y2, hint:sub(1, w), grey, pale)
  end

  -- open: look for computers ----------------------------------------
  frame(function()
    local msg = "Looking for computers ..."
    local bw = #msg + 8
    local bx = math.max(1, math.floor((W - bw) / 2) + 1)
    local by = math.max(1, math.floor(H / 2) - 1)
    box(bx, by, bx + bw - 1, by + 2)
    put(bx + 4, by + 1, msg, deep, pale)
  end)
  if modems > 0 and tkKey() then
    tkScan(db)
    tkPoll(db)
  elseif modems > 0 then
    say("no shared key yet - press K to set one", pink)
  end

  page("TASKS", draw, function(kind, a, b)
    if kind == "tick" then
      ticks = ticks + 1
      if modems > 0 and ticks % 3 == 0 and tkHasActive(db) and tkKey() then
        if tkPoll(db) then return "render" end
      end
      return nil
    end
    if modems == 0 then return nil end

    if kind == "key" then
      if a == keys.tab then focus = (focus == "c") and "t" or "c" return "render"
      elseif a == keys.up then
        if focus == "c" then csel = math.max(1, csel - 1) else tsel = math.max(1, tsel - 1) end
        return "render"
      elseif a == keys.down then
        if focus == "c" then csel = csel + 1 else tsel = tsel + 1 end
        return "render"
      elseif a == keys.enter then
        if focus == "c" then runCommand()
        else local t = taskRows()[tsel] if t then viewOutput(t) end end
        return "render"
      elseif a == keys.f then runFile() return "render"
      elseif a == keys.s then scan() return "render"
      elseif a == keys.k then setKey() return "render"
      elseif a == keys.r then
        flash("refreshing ...")
        tkPoll(db)
        say("refreshed", mid)
        return "render"
      elseif a == keys.x then
        local t = taskRows()[tsel]
        if focus == "t" and t then cancelTask(t) end
        return "render"
      elseif a == keys.c then
        if focus == "t" then clearFinished() end
        return "render"
      end
    elseif kind == "click" then
      if area.cy and b >= area.cy and b < area.cy + area.cn then
        local idx = ctop + (b - area.cy)
        if computerRows()[idx] then
          if focus == "c" and idx == csel then runCommand() else focus, csel = "c", idx end
          return "render"
        end
      elseif area.ty and b >= area.ty and b < area.ty + area.tn then
        local idx = ttop + (b - area.ty)
        local t = taskRows()[idx]
        if t then
          if focus == "t" and idx == tsel then viewOutput(t) else focus, tsel = "t", idx end
          return "render"
        end
      end
    end
  end)
end
end

local actions = {]==]

local ok = true
local function plainEdit(label, old, new)
  local s, t = src:find(old, 1, true)
  if not s then print("skipped : " .. label .. " (not found)") ok = false return end
  src = src:sub(1, s - 1) .. new .. src:sub(t + 1)
  print("patched : " .. label)
end

plainEdit("Menu button", '{ label = "INSTALLED" }', '{ label = "TASKS" }, { label = "INSTALLED" }')
plainEdit("Tasks tab", "local actions = {", BLOCK)
plainEdit("Button action", "actInstalled, actCredits }", "actTasks, actInstalled, actCredits }")

-- list this patch on the INSTALLED tab (optional)
do
  local s, t = src:find('{ "installed_patch",%s+"this tab",%s+function%(h%) return h%("local function " %.%. "actInstalled"%) end },')
  if s then
    src = src:sub(1, t) .. '\n    { "tasks_patch",          "offload tasks",      function(h) return h("-- tasks tab " .. "(offload)") end },' .. src:sub(t + 1)
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
print("Next: put worker.lua on the other computers (see the notes at the top of tasks_patch).")
