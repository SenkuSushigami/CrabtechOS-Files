-- ============================================================
--  AE2 Dashboard  --  Crabtech OS app
--  (CC:Tweaked + Advanced Peripherals ME Bridge)
--
--  Install : put this file in an "apps" folder, either
--              /apps/ae2Dashboard.lua          (on the computer)
--              /disk/apps/ae2Dashboard.lua     (on a floppy)
--            then open  APPS  in the OS menu.
--  Floppy  : the app saves its settings next to itself, so graph
--            toggles travel with the floppy (falls back to the
--            computer if the disk is read-only).
--  Direct  : "ae2Dashboard" from the shell still works and draws
--            on an attached monitor with the same look.
--            "ae2Dashboard methods" lists the bridge's methods.
--
--  Back to the menu: touch (<) back, or press Backspace / Q.
-- ============================================================

local args = { ... }

local cfg = {
  pollSeconds = 2,      -- how often the ME network is polled
  textScale   = 0.5,    -- only used when launched directly
  settingsName = "ae2dash.cfg",
}

-- ------------------------------------------------------------
-- OS palette (identical to the OS so nothing shifts)
-- ------------------------------------------------------------
local pale, lav, mid, deep = colors.white, colors.lightGray, colors.purple, colors.blue
local pink, ice, grey, ink, snow = colors.pink, colors.lightBlue, colors.gray, colors.black, colors.cyan
local soft = colors.green
local GRAD = { deep, colors.brown, colors.red, colors.magenta, mid }
-- status colours the OS itself does not use
local mint, peach, butter = colors.lime, colors.orange, colors.yellow

local PAL_BASE = {
  [pale] = 0xF1EDFC, [lav] = 0xD9CFF6, [mid] = 0x8466D9, [deep] = 0x3A2E9E,
  [pink] = 0xE8708F, [ice] = 0x9ED3F0, [grey] = 0xA399C9, [ink] = 0x2B2466,
  [snow] = 0xFFFFFF, [soft] = 0xC3B6EE,
  [colors.brown] = 0x4538AA, [colors.red] = 0x5744BC, [colors.magenta] = 0x6B54CC,
}
local PAL_EXTRA = { [mint] = 0x3FB58A, [peach] = 0xE59A4F, [butter] = 0xD9B23C }

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end
local HB = "\149"   -- left half block (smooth diagonal edge)

local app = { name = "AE2 Dashboard" }

function app.run(ctx)
  local standalone = (ctx == nil)
  local native = term.current()
  local mon, monName

  local function setPal(t)
    for c, v in pairs(t) do pcall(term.setPaletteColour, c, v) end
  end
  local function resetPal(t)
    for c in pairs(t) do
      pcall(function() term.setPaletteColour(c, term.nativePaletteColour(c)) end)
    end
  end

  -- --------------------------------------------------------
  -- Display: OS-owned window, or our own when launched directly
  -- --------------------------------------------------------
  local function openOwnWindow()
    local target = mon or native
    if mon then pcall(mon.setTextScale, cfg.textScale) end
    local w, h = target.getSize()
    term.redirect(window.create(target, 1, 1, w, h, true))
    setPal(PAL_BASE); setPal(PAL_EXTRA)
  end

  local function rebuild()
    if standalone then openOwnWindow()
    else ctx.rebuild(); setPal(PAL_EXTRA) end
  end

  local function tap(ev)
    if ctx then return ctx.tap(ev) end
    if ev[1] == "monitor_touch" and mon and ev[2] == monName then return ev[3], ev[4] end
    if ev[1] == "mouse_click" and not mon then return ev[3], ev[4] end
  end

  local function frame(fn)
    local w = term.current()
    if w.setVisible then w.setVisible(false) end
    local ok, err = pcall(fn)
    if w.setVisible then w.setVisible(true) end
    if not ok then error(err, 0) end
  end

  -- --------------------------------------------------------
  -- Settings (saved beside the app, so a floppy keeps its own)
  -- --------------------------------------------------------
  local show = { power = true, items = true, fluids = true, cpus = true }

  local function settingsPath()
    local dir = ""
    if ctx and ctx.dir then dir = ctx.dir
    elseif shell then dir = fs.getDir(shell.getRunningProgram()) end
    if dir ~= "" and fs.isReadOnly(dir) then dir = "" end
    return fs.combine(dir, cfg.settingsName)
  end

  local function loadSettings()
    local p = settingsPath()
    if not fs.exists(p) then return end
    local f = fs.open(p, "r")
    if not f then return end
    local data = textutils.unserialize(f.readAll())
    f.close()
    if type(data) == "table" and type(data.show) == "table" then
      for k in pairs(show) do
        if data.show[k] ~= nil then show[k] = data.show[k] and true or false end
      end
    end
  end

  local function saveSettings()
    pcall(function()
      local f = fs.open(settingsPath(), "w")
      if f then f.write(textutils.serialize({ show = show })) f.close() end
    end)
  end

  -- --------------------------------------------------------
  -- ME bridge (re-detected on every poll, so it can be plugged in later)
  -- --------------------------------------------------------
  local bridge, bridgeName, methodSet = nil, nil, {}
  local failed, failedList = {}, {}

  local function findBridge()
    bridge = peripheral.find("me_bridge") or peripheral.find("meBridge")
    methodSet = {}
    bridgeName = nil
    if bridge then
      bridgeName = peripheral.getName(bridge)
      for _, m in ipairs(peripheral.getMethods(bridgeName) or {}) do methodSet[m] = true end
    end
  end

  local function call(names, ...)
    if not bridge then return nil end
    for _, name in ipairs(names) do
      if methodSet[name] then
        local ok, res = pcall(bridge[name], ...)
        if ok and res ~= nil then return res end
        if not ok and not failed[name] then
          failed[name] = true
          failedList[#failedList + 1] = name
        end
      end
    end
    return nil
  end

  -- --------------------------------------------------------
  -- Formatting
  -- --------------------------------------------------------
  local function fmt(n)
    if type(n) ~= "number" then return "?" end
    local units = { "", "K", "M", "G", "T", "P" }
    local i, sign = 1, n < 0 and "-" or ""
    n = math.abs(n)
    while n >= 1000 and i < #units do n = n / 1000 i = i + 1 end
    if i == 1 then return string.format("%s%d", sign, math.floor(n)) end
    local num = string.format("%.1f", n):gsub("%.0$", "")
    return sign .. num .. units[i]
  end

  local function sfmt(n)
    if type(n) ~= "number" then return "?" end
    return (n >= 0 and "+" or "") .. fmt(n)
  end

  local function label(stack)
    if type(stack) ~= "table" then return "?" end
    return stack.displayName or stack.name or "?"
  end

  local function ratio(used, max)
    if type(used) ~= "number" or type(max) ~= "number" or max <= 0 then return nil end
    return math.max(0, math.min(100, used / max * 100))
  end

  -- --------------------------------------------------------
  -- Polling
  -- --------------------------------------------------------
  local state = {
    online = nil, stored = nil, cap = nil, usage = nil, inject = nil,
    itemUsed = nil, itemMax = nil, fluidUsed = nil, fluidMax = nil,
    cpus = {}, tasks = {},
  }

  local function poll()
    if not bridge then findBridge() end
    state.online = call({ "isOnline", "isConnected" })
    state.stored = call({ "getStoredEnergy", "getEnergyStorage" })
    state.cap = call({ "getEnergyCapacity", "getMaxEnergyStorage" })
    state.usage = call({ "getEnergyUsage" })
    state.inject = call({ "getAvgPowerInjection" })
    state.itemUsed = call({ "getUsedItemStorage" })
    state.itemMax = call({ "getMaxItemStorage", "getTotalItemStorage" })
    state.fluidUsed = call({ "getUsedFluidStorage" })
    state.fluidMax = call({ "getMaxFluidStorage", "getTotalFluidStorage" })

    local cpus = call({ "getCraftingCPUs" })
    state.cpus = type(cpus) == "table" and cpus or {}

    local tasks = call({ "getCraftingTasks" })
    local list = {}
    if type(tasks) == "table" then
      for _, t in pairs(tasks) do list[#list + 1] = t end
    end
    state.tasks = list
  end

  local function cpuCounts()
    local busy, total, coproc = 0, 0, 0
    for _, cpu in pairs(state.cpus) do
      total = total + 1
      if cpu.isBusy == true then busy = busy + 1 end
      coproc = coproc + (tonumber(cpu.coProcessors) or 0)
    end
    return busy, total, coproc
  end

  local function taskFor(cpu)
    local name = cpu.name
    if type(name) ~= "string" or name == "" then return nil end
    for _, t in ipairs(state.tasks) do
      if type(t.cpu) == "table" and t.cpu.name == name then return t end
    end
    return nil
  end

  -- --------------------------------------------------------
  -- Drawing primitives
  -- --------------------------------------------------------
  local buttons = {}
  local tick = 0
  local scroll = 0

  local function put(x, y, text, fg, bg)
    local w, h = term.getSize()
    if y < 1 or y > h or x > w or #text == 0 then return end
    if x < 1 then text = text:sub(2 - x) x = 1 end
    term.setCursorPos(x, y)
    term.setTextColour(fg or deep)
    term.setBackgroundColour(bg or pale)
    term.write(text:sub(1, w - x + 1))
  end

  local function fill(x1, y1, x2, y2, bg)
    local w, h = term.getSize()
    x1, x2 = math.max(1, x1), math.min(w, x2)
    if x2 < x1 then return end
    local row = string.rep(" ", x2 - x1 + 1)
    for y = math.max(1, y1), math.min(h, y2) do put(x1, y, row, bg, bg) end
  end

  local function center(x1, x2, y, text, fg, bg)
    local width = x2 - x1 + 1
    text = text:sub(1, width)
    put(x1 + math.floor((width - #text) / 2), y, text, fg, bg)
  end

  local function addButton(x1, x2, y, action)
    buttons[#buttons + 1] = { x1 = x1, x2 = x2, y = y, action = action }
  end

  -- Panel in the OS style: soft border, pale inside, coloured title bar.
  local function panel(x1, y1, x2, y2, title, barColor)
    barColor = barColor or mid
    fill(x1, y1, x2, y2, soft)
    fill(x1 + 1, y1 + 1, x2 - 1, y2 - 1, pale)
    fill(x1, y1, x2, y1, barColor)
    put(x1 + 2, y1, " " .. title .. " ", snow, barColor)
  end

  -- --------------------------------------------------------
  -- Header (same gradient / pill / ticker as the OS)
  -- --------------------------------------------------------
  local SPARK = { ice, snow, lav, snow }

  local function hbg(x, y, w)
    local xs = x - (y - 1) * 2
    return GRAD[clamp(math.floor((xs - 1) / (w / 5)) + 1, 1, 5)]
  end

  local function putH(x, y, s, fg)
    local w = term.getSize()
    for i = 1, #s do put(x + i - 1, y, s:sub(i, i), fg, hbg(x + i - 1, y, w)) end
  end

  local function statusText()
    if not bridge then return "NO BRIDGE", pink end
    if state.online == true then return "ONLINE", mint end
    if state.online == false then return "OFFLINE", pink end
    return "WAITING", lav
  end

  local function tickerText()
    local st = statusText()
    local busy, total = cpuCounts()
    local p, i = ratio(state.stored, state.cap), ratio(state.itemUsed, state.itemMax)
    local parts = {
      "ME " .. st,
      "POWER " .. (p and string.format("%d%%", math.floor(p)) or "?"),
      "ITEMS " .. (i and string.format("%d%%", math.floor(i)) or "?"),
      "CPUS " .. busy .. "/" .. total,
      "JOBS " .. #state.tasks,
    }
    return "  " .. table.concat(parts, "  \4  ") .. "  \4  "
  end

  local function drawHeader(w, hh, ty)
    for y = 1, hh do
      local x = 1
      while x <= w do
        local c = hbg(x, y, w)
        local x2 = x
        while x2 < w and hbg(x2 + 1, y, w) == c do x2 = x2 + 1 end
        fill(x, y, x2, y, c)
        x = x2 + 1
      end
    end
    -- scrolling ticker
    local tk = tickerText()
    local off = tick % #tk
    putH(4, 1, tk:rep(math.ceil(w / #tk) + 2):sub(off + 1, off + w - 14), ice)
    -- pill + title
    put(3, ty, " AE2 ", deep, snow)
    putH(10, ty, "Dashboard", snow)
    putH(20, ty, "\4", SPARK[tick % 4 + 1])
    putH(10, ty + 1, "m e n u  \187  a e 2", lav)
    -- right side: back chip + status
    putH(w - 11, ty, "(<) back", snow)
    local st, sc = statusText()
    putH(w - 11, ty + 1, st, sc)
  end

  -- --------------------------------------------------------
  -- Graphs
  -- --------------------------------------------------------
  local function levelColor(pct, base)
    if pct >= 90 then return pink end
    if pct >= 75 then return butter end
    return base
  end

  local GRAPHS = {
    {
      id = "power", title = "Power", label = "Network Power",
      data = function()
        local pct = ratio(state.stored, state.cap)
        local color = mint
        if pct and pct < 20 then color = pink elseif pct and pct < 50 then color = peach end
        local net
        if type(state.inject) == "number" and type(state.usage) == "number" then
          net = state.inject - state.usage
        end
        return pct, color, fmt(state.stored) .. "/" .. fmt(state.cap) .. " AE",
          (net and sfmt(net) or "?") .. " AE/t"
      end,
    },
    {
      id = "items", title = "Items", label = "Item Storage",
      data = function()
        local pct = ratio(state.itemUsed, state.itemMax)
        return pct, levelColor(pct or 0, ice),
          fmt(state.itemUsed) .. "/" .. fmt(state.itemMax), "bytes"
      end,
    },
    {
      id = "fluids", title = "Fluids", label = "Fluid Storage",
      data = function()
        local pct = ratio(state.fluidUsed, state.fluidMax)
        return pct, levelColor(pct or 0, mid),
          fmt(state.fluidUsed) .. "/" .. fmt(state.fluidMax), "bytes"
      end,
    },
    {
      id = "cpus", title = "CPUs", label = "CPU Load",
      data = function()
        local busy, total, coproc = cpuCounts()
        local pct = total > 0 and (busy / total * 100) or nil
        return pct, peach, busy .. "/" .. total .. " busy", coproc .. " cp"
      end,
    },
  }

  local function drawBar(bx1, bw, barTop, barBottom, pct, fillColor)
    local innerW, innerRows = bw - 2, barBottom - barTop - 1
    for y = barTop, barBottom do
      if y == barTop or y == barBottom then
        put(bx1, y, string.rep(" ", bw), deep, soft)
      else
        put(bx1, y, " ", deep, soft)
        put(bx1 + bw - 1, y, " ", deep, soft)
      end
    end
    local fillRows = pct and math.floor(pct / 100 * innerRows + 0.5) or 0
    for r = 1, innerRows do
      local y = barBottom - r
      put(bx1 + 1, y, string.rep(" ", innerW), deep, r <= fillRows and fillColor or lav)
    end
    local text = pct and string.format("%.1f%%", pct) or "n/a"
    if innerW >= #text then
      local r = math.max(1, fillRows)
      local filled = fillRows >= 1
      center(bx1 + 1, bx1 + bw - 2, barBottom - r, text,
        filled and ink or deep, filled and fillColor or lav)
    end
  end

  local function drawGraphs(x1, y1, x2, y2)
    local ix1, ix2 = x1 + 2, x2 - 2
    local titleY, barTop, barBottom = y1 + 2, y1 + 3, y2 - 3
    local list = {}
    for _, g in ipairs(GRAPHS) do
      if show[g.id] then list[#list + 1] = g end
    end
    if #list == 0 then
      center(ix1, ix2, math.floor((y1 + y2) / 2), "No graphs selected", grey)
      center(ix1, ix2, math.floor((y1 + y2) / 2) + 1, "Use Graph Controls", grey)
      return
    end
    local gw = math.floor((ix2 - ix1 + 1) / #list)
    for i, g in ipairs(list) do
      local gx1 = ix1 + (i - 1) * gw
      local gx2 = gx1 + gw - 1
      local pct, color, cap1, cap2 = g.data()
      center(gx1, gx2, titleY, g.title, mid)
      local bw = math.max(4, math.min(gw - 2, 22))
      local bx1 = gx1 + math.floor((gw - bw) / 2)
      drawBar(bx1, bw, barTop, barBottom, pct, color)
      center(gx1, gx2, barBottom + 1, cap1, deep)
      center(gx1, gx2, barBottom + 2, cap2, grey)
    end
  end

  -- --------------------------------------------------------
  -- Right column
  -- --------------------------------------------------------
  local function drawControls(x1, y1, x2, y2)
    local ix1, ix2 = x1 + 2, x2 - 2
    for i, g in ipairs(GRAPHS) do
      local y = y1 + i
      if y < y2 then
        local on = show[g.id]
        local bg = on and deep or lav
        fill(ix1, y, ix2, y, bg)
        if on then put(ix1, y, " ", snow, pink) end
        center(ix1, ix2, y, g.label, on and snow or mid, bg)
        local id = g.id
        addButton(ix1, ix2, y, function() show[id] = not show[id] saveSettings() end)
      end
    end
  end

  local function drawCpus(x1, y1, x2, y2)
    local ix1, ix2 = x1 + 2, x2 - 2
    local iw = ix2 - ix1 + 1
    local rows = y2 - y1 - 1

    if #state.cpus == 0 then
      put(ix1, y1 + 1, "No crafting CPUs", grey)
      return
    end

    local lines = {}
    for i, cpu in ipairs(state.cpus) do
      lines[#lines + 1] = { cpu = cpu, idx = i }
      if cpu.isBusy == true then
        local t = taskFor(cpu)
        if t then lines[#lines + 1] = { job = t } end
      end
    end

    local maxOffset = math.max(0, #lines - rows)
    if scroll > maxOffset then scroll = maxOffset end
    if scroll < 0 then scroll = 0 end

    if #lines > rows then
      put(x2 - 9, y1, "[^]", deep, lav)
      addButton(x2 - 9, x2 - 7, y1, function() scroll = math.max(0, scroll - 3) end)
      put(x2 - 5, y1, "[v]", deep, lav)
      addButton(x2 - 5, x2 - 3, y1, function() scroll = scroll + 3 end)
    end

    local nameW = math.max(4, iw - 2 - 14)
    for r = 1, rows do
      local ln = lines[scroll + r]
      if not ln then break end
      local y = y1 + r
      if ln.cpu then
        local cpu = ln.cpu
        local busy = cpu.isBusy == true
        put(ix1, y, " ", deep, busy and peach or mint)
        local name = type(cpu.name) == "string" and cpu.name ~= "" and cpu.name or ("CPU #" .. ln.idx)
        put(ix1 + 2, y, name:sub(1, nameW), deep)
        local right = string.format("%5s %3s %4s", fmt(cpu.storage), (tonumber(cpu.coProcessors) or 0) .. "cp",
          busy and "BUSY" or "idle")
        put(ix2 - #right + 1, y, right, busy and peach or grey)
      else
        local t = ln.job
        local pct = math.floor((t.completion or 0) * 100)
        local text = string.format("-> %s x%s %d%%", label(t.resource), fmt(t.quantity or 0), pct)
        put(ix1 + 2, y, text:sub(1, iw - 2), mid)
      end
    end
  end

  local function buildStats()
    local busy, total, coproc = cpuCounts()
    local list = {}
    local function add(name, value, color)
      list[#list + 1] = { name = name, value = value, color = color or deep }
    end

    local st, sc = "UNKNOWN", grey
    if not bridge then st, sc = "NO BRIDGE", pink
    elseif state.online == true then st, sc = "ONLINE", mint
    elseif state.online == false then st, sc = "OFFLINE", pink end
    add("Status", st, sc)

    local ppct = ratio(state.stored, state.cap)
    local pColor = deep
    if ppct and ppct < 20 then pColor = pink elseif ppct and ppct < 50 then pColor = peach end
    add("Stored", fmt(state.stored) .. " AE", pColor)
    add("Usage", fmt(state.usage) .. " AE/t")
    local ipct = ratio(state.itemUsed, state.itemMax)
    add("Items", fmt(state.itemUsed) .. "/" .. fmt(state.itemMax) .. (ipct and string.format(" %d%%", math.floor(ipct)) or ""),
      levelColor(ipct or 0, deep))
    local fpct = ratio(state.fluidUsed, state.fluidMax)
    add("Fluids", fmt(state.fluidUsed) .. "/" .. fmt(state.fluidMax) .. (fpct and string.format(" %d%%", math.floor(fpct)) or ""),
      levelColor(fpct or 0, deep))
    add("CPUs", busy .. " busy / " .. total, busy > 0 and peach or deep)
    add("Jobs", #state.tasks .. " crafting", #state.tasks > 0 and butter or deep)
    add("Inject", fmt(state.inject) .. " AE/t")
    if type(state.inject) == "number" and type(state.usage) == "number" then
      local net = state.inject - state.usage
      add("Net", sfmt(net) .. " AE/t", net >= 0 and mint or pink)
    end
    add("Capacity", fmt(state.cap) .. " AE")
    add("Co-proc", tostring(coproc))
    if #failedList > 0 then add("API err", failedList[1], pink) end
    return list
  end

  local function drawStats(x1, y1, x2, y2, stats)
    local ix1, ix2 = x1 + 2, x2 - 2
    local valueX = ix1 + 10
    for i, s in ipairs(stats) do
      local y = y1 + i
      if y >= y2 then break end
      put(ix1, y, s.name, grey)
      put(ix1 + 8, y, ": ", soft)
      put(valueX, y, s.value:sub(1, ix2 - valueX + 1), s.color)
    end
  end

  -- --------------------------------------------------------
  -- Screen
  -- --------------------------------------------------------
  local function diagonal(y0, h, dTop, shift)
    local w = term.getSize()
    local slope = shift / math.max(1, h - y0)
    for y = y0, h do
      local sh = math.floor((dTop + (y - y0) * slope) * 2)
      local lc = math.floor(sh / 2)
      if sh % 2 == 1 then
        put(lc, y, HB, pale, deep)
        fill(lc + 1, y, lc + 1, y, deep)
        put(lc + 2, y, HB, deep, lav)
        fill(lc + 3, y, w, y, lav)
      else
        fill(lc, y, lc + 1, y, deep)
        fill(lc + 2, y, w, y, lav)
      end
    end
  end

  local function drawAll()
    local w, h = term.getSize()
    buttons = {}
    local hh = clamp(math.floor(h * 0.15), 3, 8)
    local ty = math.max(2, math.floor(hh / 2))
    local y0 = hh + 1

    term.setBackgroundColour(pale); term.clear()

    if w < 60 or h < 24 then
      drawHeader(w, hh, ty)
      center(1, w, math.floor(h / 2), "Screen too small", pink)
      center(1, w, math.floor(h / 2) + 1, "need about 60x24 chars", grey)
      center(1, w, math.floor(h / 2) + 2, "(4x3 blocks at scale 0.5)", grey)
      return
    end

    local rw = clamp(math.floor(w * 0.40), 32, 46)
    local x1 = w - rw + 1
    local gap = clamp(math.floor(w * 0.07), 4, 8)
    local dTop = x1 - gap

    -- body: pale left, lavender right, smooth diagonal between
    diagonal(y0, h, dTop, gap - 3)
    fill(1, y0, 2, h, deep)
    for y = y0 + 1, h - 3, 6 do put(1, y, "//", ice, deep) put(1, y + 1, "//", mid, deep) end

    -- panels
    local top, bottom = y0 + 1, h - 1
    local ctrlH = #GRAPHS + 2
    local stats = buildStats()
    local statsH = math.min(#stats + 2, math.max(6, (bottom - top + 1) - ctrlH - 7 - 2))
    local statsTop = bottom - statsH + 1
    local cpuTop = top + ctrlH + 1
    local cpuBottom = statsTop - 2

    panel(4, top, dTop - 2, bottom, "NETWORK GRAPHS", deep)
    drawGraphs(4, top, dTop - 2, bottom)

    panel(x1, top, w - 1, top + ctrlH - 1, "GRAPH CONTROLS", mid)
    drawControls(x1, top, w - 1, top + ctrlH - 1)

    panel(x1, cpuTop, w - 1, cpuBottom, "CPU STATUS", mid)
    drawCpus(x1, cpuTop, w - 1, cpuBottom)

    panel(x1, statsTop, w - 1, bottom, "NETWORK STATISTICS", deep)
    drawStats(x1, statsTop, w - 1, bottom, stats)

    -- footer tag, like the OS
    put(5, h, "ME BRIDGE " .. (bridgeName or "none") .. "  ////  poll " .. cfg.pollSeconds .. "s",
      grey, pale)

    drawHeader(w, hh, ty)
  end

  local function drawHeaderOnly()
    local w, h = term.getSize()
    local hh = clamp(math.floor(h * 0.15), 3, 8)
    drawHeader(w, hh, math.max(2, math.floor(hh / 2)))
  end

  local function handleTap(x, y)
    local w, h = term.getSize()
    local hh = clamp(math.floor(h * 0.15), 3, 8)
    if y <= hh and x >= w - 12 then return "exit" end
    for _, b in ipairs(buttons) do
      if y == b.y and x >= b.x1 and x <= b.x2 then
        b.action()
        return "redraw"
      end
    end
  end

  -- --------------------------------------------------------
  -- Main loop
  -- --------------------------------------------------------
  local function loop()
    poll()
    frame(drawAll)
    local pollTicks = math.max(1, math.floor(cfg.pollSeconds / 0.5 + 0.5))
    local timer = os.startTimer(0.5)

    while true do
      local ev = { os.pullEvent() }
      local e = ev[1]
      if e == "timer" and ev[2] == timer then
        tick = tick + 1
        if tick % pollTicks == 0 then
          poll()
          frame(drawAll)
        else
          frame(drawHeaderOnly)
        end
        timer = os.startTimer(0.5)
      elseif e == "key" then
        if ev[2] == keys.backspace or ev[2] == keys.q then return end
      elseif e == "monitor_touch" or e == "mouse_click" then
        local x, y = tap(ev)
        if x then
          local r = handleTap(x, y)
          if r == "exit" then return end
          if r == "redraw" then frame(drawAll) end
        end
      elseif e == "monitor_resize" or e == "term_resize" then
        rebuild()
        frame(drawAll)
      elseif e == "peripheral" or e == "peripheral_detach" then
        if standalone then
          mon, monName = nil, nil
          for _, n in ipairs(peripheral.getNames()) do
            if peripheral.getType(n) == "monitor" then monName, mon = n, peripheral.wrap(n) break end
          end
          openOwnWindow()
        end
        findBridge()
        frame(drawAll)
      end
    end
  end

  -- --------------------------------------------------------
  -- Start
  -- --------------------------------------------------------
  if standalone then
    for _, n in ipairs(peripheral.getNames()) do
      if peripheral.getType(n) == "monitor" then monName, mon = n, peripheral.wrap(n) break end
    end
    if args[1] == "methods" then
      findBridge()
      if not bridge then print("No ME Bridge found") return end
      local names = {}
      for m in pairs(methodSet) do names[#names + 1] = m end
      table.sort(names)
      print("Bridge: " .. bridgeName)
      textutils.pagedPrint(table.concat(names, "\n"))
      return
    end
    openOwnWindow()
  else
    setPal(PAL_EXTRA)
  end

  loadSettings()
  findBridge()

  local ok, err = pcall(loop)

  resetPal(PAL_EXTRA)
  if standalone then
    resetPal(PAL_BASE)
    term.redirect(native)
    term.setBackgroundColour(colors.black)
    term.setTextColour(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    if mon then pcall(function() mon.setBackgroundColour(colors.black) mon.clear() end) end
  end
  if not ok then error(err, 0) end
end

-- Launched directly from the shell instead of from the OS menu
if shell then app.run(nil) end

return app
