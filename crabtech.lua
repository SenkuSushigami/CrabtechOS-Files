-- ============================================================
--  Crabtech OS  --  menu UI for CC:Tweaked
--  Built for advanced monitors; falls back to the computer's
--  own terminal when no monitor is attached.
--
--  Controls : Up/Down + Enter, or click / touch a button
--  Quit     : Q on the computer keyboard
--  Menu     : APPS, APP STORE, SETTINGS, MEM. CARD, UPDATES,
--             TASKS, INSTALLED, CREDITS
--  Apps     : Lua apps in /apps or /disk/apps (see ae2Dashboard);
--             with two or more monitors you choose where one opens;
--             APP STORE installs more from the GitHub apps folder
--  Updates  : UPDATES replaces the OS / boot screen from GitHub and applies
--             new patches from the repo's patches folder
--  Tasks    : TASKS offloads work to worker computers (see worker.lua)
--  Settings : press S inside SETTINGS to cycle monitor scale
--  Start-up : CONFIG.boot / CONFIG.fade switch the animations
-- ============================================================

local CONFIG = {
  monitor = nil,   -- peripheral name (e.g. "monitor_0"); nil = auto-detect
  scale   = 0.5,   -- monitor text scale: 0.5 gives the most room
  boot    = true,  -- short boot animation
  fade    = true,  -- fade the menu in from the middle outwards
}
local SCALES = { 0.5, 1, 1.5, 2, 3, 4, 5 }

-- ------------------------------------------------------------
-- Palette
-- ------------------------------------------------------------
local pale, lav, mid, deep = colors.white, colors.lightGray, colors.purple, colors.blue
local pink, ice, grey, ink, snow = colors.pink, colors.lightBlue, colors.gray, colors.black, colors.cyan
local soft = colors.green                     -- soft lavender line colour
local GRAD = { deep, colors.brown, colors.red, colors.magenta, mid }

local PAL = {
  [pale]           = 0xF1EDFC,
  [lav]            = 0xD9CFF6,
  [mid]            = 0x8466D9,
  [deep]           = 0x3A2E9E,
  [pink]           = 0xE8708F,
  [ice]            = 0x9ED3F0,
  [grey]           = 0xA399C9,
  [ink]            = 0x2B2466,
  [snow]           = 0xFFFFFF,
  [soft]           = 0xC3B6EE,
  [colors.brown]   = 0x4538AA,
  [colors.red]     = 0x5744BC,
  [colors.magenta] = 0x6B54CC,
}

-- ------------------------------------------------------------
-- Output target (monitor or terminal) + double-buffered window
-- ------------------------------------------------------------
local native = term.current()
local target, mon, monName = native, nil, nil
local win
local W, H = 51, 19
local scale = CONFIG.scale

local function findMonitor()
  if CONFIG.monitor and peripheral.isPresent(CONFIG.monitor) then
    return CONFIG.monitor, peripheral.wrap(CONFIG.monitor)
  end
  for _, n in ipairs(peripheral.getNames()) do
    if peripheral.getType(n) == "monitor" then return n, peripheral.wrap(n) end
  end
end

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

local function setPalette()
  for c, v in pairs(PAL) do pcall(term.setPaletteColour, c, v) end
end

local function restorePalette()
  local nat = term.nativePaletteColour
  for c in pairs(PAL) do
    pcall(function()
      local f = (target.nativePaletteColour or nat)
      target.setPaletteColour(c, f(c))
    end)
  end
end

local holdFrame = false   -- true while the fade-in builds the first frame
local function frame(fn)
  win.setVisible(false)
  local ok, err = pcall(fn)
  if not holdFrame then win.setVisible(true) end
  if not ok then error(err, 0) end
end

-- ------------------------------------------------------------
-- Primitive helpers
-- ------------------------------------------------------------
local function put(x, y, s, fg, bg)
  if y < 1 or y > H or x > W then return end
  if x < 1 then s = s:sub(2 - x); x = 1 end
  s = s:sub(1, W - x + 1)
  if #s == 0 then return end
  term.setCursorPos(x, y)
  term.setTextColour(fg or ink)
  term.setBackgroundColour(bg or pale)
  term.write(s)
end

local function fill(x1, y1, x2, y2, bg)
  x1, x2 = math.max(1, x1), math.min(W, x2)
  if x2 < x1 then return end
  local row = string.rep(" ", x2 - x1 + 1)
  for y = math.max(1, y1), math.min(H, y2) do put(x1, y, row, bg, bg) end
end

local function box(x1, y1, x2, y2, bg)
  fill(x1, y1, x2, y2, soft)
  fill(x1 + 1, y1 + 1, x2 - 1, y2 - 1, bg or pale)
end

local function bar(x, y, w, frac, fc, ec)
  local n = clamp(math.floor(w * frac + 0.5), 0, w)
  fill(x, y, x + n - 1, y, fc)
  fill(x + n, y, x + w - 1, y, ec)
end

local HB = "\149" -- left half block

-- ------------------------------------------------------------
-- Layout (recomputed for every terminal / monitor size)
-- ------------------------------------------------------------
local L = {}
local items = {
  { label = "APPS" }, { label = "APP STORE" }, { label = "SETTINGS" }, { label = "MEM. CARD" },
  { label = "UPDATES" }, { label = "TASKS" }, { label = "INSTALLED" }, { label = "CREDITS" },
}
local sel, tick = 1, 0

local function diagX(y) return L.d0 + (y - L.y0) * L.slope end

local function storage()
  local free = fs.getFreeSpace("/")
  local cap = 0
  if fs.getCapacity then
    local ok, c = pcall(fs.getCapacity, "/")
    if ok and c then cap = c end
  end
  if cap <= 0 then cap = 1000000 end
  if free > cap then cap = free end
  return (cap - free) / cap, free, cap
end

local function layout()
  L.hh = clamp(math.floor(H * 0.15), 3, 8)
  L.y0 = L.hh + 1
  L.ty = math.max(2, math.floor(L.hh / 2))
  L.card = W >= 72
  L.d0 = math.floor(W * (L.card and 0.56 or 0.50))
  L.d1 = math.floor(W * 0.76)
  L.slope = (L.d1 - L.d0) / math.max(1, H - L.y0)

  -- profile card (left)
  L.cx = 5
  L.cr = L.cx + clamp(math.floor(W * 0.2), 16, 30) - 1
  L.ctop, L.cbot = L.y0 + 2, H - 2

  -- buttons
  L.bx = L.card and (L.cr + 5) or 6
  L.bh = (H >= 40 and 3) or (H >= 28 and 2) or 1
  local ys = L.hh + 5
  local step = L.bh + 1 + ((H >= 34) and 1 or 0)
  L.ys = ys
  local nItems = #items
  local gstep = math.max(L.bh, math.min(step, math.floor((H - L.bh - 1 - ys) / (nItems - 1))))
  for i = 1, nItems - 1 do items[i].y = ys + (i - 1) * gstep end
  items[nItems].y = math.max(items[nItems - 1].y + gstep, H - L.bh - 1)
  L.bw = clamp(math.floor(diagX(ys) - L.bx - 3), 14, math.max(16, math.floor(W * 0.28)))

  -- right-hand widgets, stacked top to bottom
  L.clock, L.sys, L.code = nil, nil, nil
  local ycur = L.y0 + 1
  local function edge(y1, y2) return math.ceil(math.max(diagX(y1), diagX(y2))) + 4 end

  local bigX = edge(ycur, ycur + 10)
  if H >= 30 and (W - 2 - bigX + 1) >= 36 then
    L.clock = { x = bigX, y = ycur + 1, w = W - 2 - bigX + 1, h = 9, big = true }
  else
    local sx = edge(ycur, ycur + 4)
    if (W - 2 - sx + 1) >= 14 then
      L.clock = { x = sx, y = ycur + 1, w = W - 2 - sx + 1, h = 3, big = false }
    end
  end
  if L.clock then ycur = ycur + L.clock.h + 2 end

  local reserve = 3

  local nlines = clamp(H - ycur - reserve - 3, 0, 5)
  if nlines >= 2 then
    local sx = edge(ycur, ycur + nlines + 3)
    if (W - 2 - sx + 1) >= 14 then
      L.sys = { x = sx, y = ycur + 1, w = W - 2 - sx + 1, n = nlines }
    end
  end

  local cw = math.min(22, W - 2 - edge(H - 1, H))
  if cw >= 8 then L.code = { x = W - 1 - cw, w = cw } end
end

local function setupTarget(newScale)
  if mon then
    scale = newScale or scale
    pcall(mon.setTextScale, scale)
  end
  W, H = target.getSize()
  win = window.create(target, 1, 1, W, H, false)
  term.redirect(win)
  setPalette()
  layout()
  win.setBackgroundColour(pale)
  win.clear()
  win.setVisible(true)
end

-- ------------------------------------------------------------
-- Pieces of the screen
-- ------------------------------------------------------------
local function hbg(x, y)
  local xs = x - (y - 1) * 2
  return GRAD[clamp(math.floor((xs - 1) / (W / 5)) + 1, 1, 5)]
end

local function putH(x, y, s, fg)
  for i = 1, #s do put(x + i - 1, y, s:sub(i, i), fg, hbg(x + i - 1, y)) end
end

local TICKER = "  CRABTECH OS  \4  CC:TWEAKED  \4  MENU  \4  CRABTECH OS  \4  "
local SPARK = { ice, snow, lav, snow }

local function drawHeader(sub)
  for y = 1, L.hh do
    local x = 1
    while x <= W do
      local c = hbg(x, y)
      local x2 = x
      while x2 < W and hbg(x2 + 1, y) == c do x2 = x2 + 1 end
      fill(x, y, x2, y, c)
      x = x2 + 1
    end
  end
  local ty = L.ty
  putH(15, ty, "Crabtech", snow)
  putH(24, ty, "OS", ice)
  putH(15, ty + 1, sub, lav)
end

local function drawTicker()
  local off = tick % #TICKER
  local s = TICKER:rep(math.ceil(W / #TICKER) + 2):sub(off + 1, off + W - 14)
  putH(4, 1, s, ice)
end

local function drawSparkles()
  local c = function(i) return SPARK[(tick + i) % 4 + 1] end
  putH(12, L.ty, "\4", c(0))
  putH(28, L.ty, "\4", c(1))
  for i, it in ipairs(items) do
    put(L.bx - 3, it.y + math.floor(L.bh / 2), "\4", (i == sel) and pink or c(i), pale)
  end
end

local function drawBody()
  term.setBackgroundColour(pale); term.clear()
  for y = L.y0, H do
    local sh = math.floor(diagX(y) * 2)
    local lc = math.floor(sh / 2)
    if sh % 2 == 1 then
      put(lc, y, HB, pale, deep)
      fill(lc + 1, y, lc + 1, y, deep)
      put(lc + 2, y, HB, deep, lav)
      fill(lc + 3, y, W, y, lav)
    else
      fill(lc, y, lc + 1, y, deep)
      fill(lc + 2, y, W, y, lav)
    end
  end
  -- slim left stripe with slash marks
  fill(1, L.y0, 2, H, deep)
  for y = L.y0 + 1, H - 3, 6 do
    put(1, y, "//", ice, deep); put(1, y + 1, "//", mid, deep)
  end
  -- tag line
  put(5, L.y0, "CE [ Crabtech OS ]  [10]", grey, pale)
  -- serial chip + prompt
  put(L.bx, L.y0 + 1, " SN " .. string.format("%08d", os.getComputerID()) .. " ", deep, lav)
  put(L.bx, L.y0 + 2, "Select* \187", mid, pale)
  put(L.bx, H, "CRABTECH OS", grey, pale)
  put(L.bx + 13, H, "////", mid, pale)
end

local function drawButton(i)
  local it = items[i]
  local on = (i == sel)
  local bg = on and deep or lav
  local fg = on and snow or mid
  local ty = it.y + math.floor(L.bh / 2)
  fill(L.bx, it.y, L.bx + L.bw - 1, it.y + L.bh - 1, bg)
  if on then fill(L.bx, it.y, L.bx, it.y + L.bh - 1, pink) end
  put(L.bx + 3, ty, it.label, fg, bg)
  put(L.bx + L.bw - 3, ty, on and "\16" or ".", on and ice or grey, bg)
end

local function hm()
  local t = os.time()
  local h = math.floor(t) % 24
  return h, math.floor((t - math.floor(t)) * 60)
end

local function mmss(sec)
  sec = math.floor(sec)
  return string.format("%02d:%02d", math.floor(sec / 60) % 100, sec % 60)
end

local function drawCard()
  if not L.card then return end
  local cx, cr, top, bot = L.cx, L.cr, L.ctop, L.cbot
  fill(cx, top, cr, bot, soft)
  fill(cx + 1, top + 1, cr - 1, bot - 1, lav)
  fill(cx + 1, top + 1, cr - 1, top + 1, mid)
  put(cx + 3, top + 1, "PROFILE", snow, mid)
  put(cr - 3, top + 1, "\4", SPARK[tick % 4 + 1], mid)
  local iw = cr - cx - 5
  local h, m = hm()
  local used = storage()
  local rows = {
    { "USER",    function() return (os.getComputerLabel() or "unnamed"):sub(1, iw) end },
    { "ID",      function() return string.format("#%04d", os.getComputerID()) end },
    { "TIME",    function() return string.format("%02d:%02d  day %d", h, m, os.day()) end },
    { "UPTIME",  function() return mmss(os.clock()) end },
    { "STORAGE", function() return nil, used end },
    { "LINKS",   function() return #peripheral.getNames() .. " connected" end },
  }
  local y = top + 3
  for _, r in ipairs(rows) do
    if y + 1 >= bot then break end
    put(cx + 3, y, r[1], grey, lav)
    local txt, frac = r[2]()
    if txt then
      put(cx + 3, y + 1, txt, deep, lav)
    else
      bar(cx + 3, y + 1, iw, frac, mid, pale)
    end
    y = y + 3
  end
end

-- big 3x5 digits ------------------------------------------------
local DIG = {
  [0] = "111101101101111", "010110010010111", "111001111100111", "111001111001111",
  "101101111001001", "111100111001111", "111100111101111", "111001001001001",
  "111101111101111", "111101111001111",
}
local function bigDigit(x, y, d)
  local p = DIG[d]
  for r = 0, 4 do
    for c = 0, 2 do
      local on = p:sub(r * 3 + c + 1, r * 3 + c + 1) == "1"
      put(x + c * 2, y + r, "  ", ink, on and deep or pale)
    end
  end
end

local function drawClock()
  local c = L.clock
  if not c then return end
  local h, m = hm()
  put(c.x, c.y - 1, "CLOCK \187", mid, lav)
  box(c.x, c.y, c.x + c.w - 1, c.y + c.h - 1)
  local dayTxt = "day " .. os.day()
  if c.big then
    local ox = c.x + math.floor((c.w - 34) / 2)
    local oy = c.y + 2
    bigDigit(ox, oy, math.floor(h / 10)); bigDigit(ox + 8, oy, h % 10)
    local dot = (tick % 2 == 0) and mid or pale
    put(ox + 16, oy + 1, "  ", ink, dot); put(ox + 16, oy + 3, "  ", ink, dot)
    bigDigit(ox + 20, oy, math.floor(m / 10)); bigDigit(ox + 28, oy, m % 10)
    put(c.x + math.floor((c.w - #dayTxt) / 2), c.y + 7, dayTxt, mid, pale)
  else
    local s = string.format("%02d%s%02d  %s", h, (tick % 2 == 0) and ":" or " ", m, dayTxt)
    put(c.x + math.floor((c.w - #s) / 2), c.y + 1, s, deep, pale)
  end
end

local function drawSystem()
  local s = L.sys
  if not s then return end
  put(s.x, s.y - 1, "SYSTEM \187", mid, lav)
  box(s.x, s.y, s.x + s.w - 1, s.y + s.n + 1)
  local ix, iw = s.x + 2, s.w - 4
  local used, free = storage()
  local lines = {
    function(y) put(ix, y, "ID    " .. string.format("%04d", os.getComputerID()), deep, pale) end,
    function(y) put(ix, y, (os.getComputerLabel() or "unnamed"):sub(1, iw), mid, pale) end,
    function(y)
      put(ix, y, "MEM", grey, pale)
      bar(ix + 4, y, math.max(2, iw - 4), used, mid, lav)
    end,
    function(y) put(ix, y, "LINK  " .. #peripheral.getNames(), deep, pale) end,
    function(y) put(ix, y, "UP    " .. mmss(os.clock()), deep, pale) end,
  }
  for i = 1, s.n do lines[i](s.y + i) end
end

local function drawBarcode()
  local c = L.code
  if not c then return end
  for i = 0, c.w - 1 do
    local on = ((i * 5 + math.floor(i / 3)) % 3 == 0) or i % 4 == 1
    put(c.x + i, H, " ", ink, on and deep or lav)
  end
end

local function drawDynamic()
  drawTicker()
  drawCard()
  drawClock()
  drawSystem()
  drawSparkles()
end

local function drawAll()
  frame(function()
    drawBody()
    drawHeader("m e n u")
    put(W - 5, L.ty, "(C1)", snow, hbg(W - 5, L.ty))
    for i = 1, #items do drawButton(i) end
    drawBarcode()
    drawDynamic()
  end)
end

-- ------------------------------------------------------------
-- Running things on the computer's own terminal
-- ------------------------------------------------------------
local function onComputer(fn)
  if target == native then restorePalette() end
  term.redirect(native)
  term.setBackgroundColour(colors.black); term.setTextColour(colors.white)
  term.clear(); term.setCursorPos(1, 1)
  pcall(fn)
  term.redirect(win)
  if target == native then setPalette() end
  win.redraw()
end

-- ------------------------------------------------------------
-- Sub pages
-- ------------------------------------------------------------
local function page(title, draw, onEvent)
  local function render()
    frame(function()
      term.setBackgroundColour(pale); term.clear()
      fill(1, L.y0, 2, H, deep)
      drawHeader("m e n u  \187  " .. title)
      putH(W - 11, L.ty, "(<) back", snow)
      local x1, y1, x2, y2 = 5, L.hh + 3, W - 4, H - 3
      box(x1 - 2, y1 - 1, x2 + 2, y2 + 1)
      fill(x1 - 1, y1 - 1, x2 + 1, y1 - 1, mid)
      put(x1 + 1, y1 - 1, " " .. title .. " ", snow, mid)
      draw(x1 + 1, y1 + 1, x2 - 1, y2)
      put(5, H, "backspace / click back to return", grey, pale)
    end)
  end
  render()
  local timer = os.startTimer(1)
  while true do
    local ev = { os.pullEvent() }
    local e = ev[1]
    local r
    if e == "key" then
      if onEvent then r = onEvent("key", ev[2]) end
      if r == nil and (ev[2] == keys.backspace or ev[2] == keys.q or ev[2] == keys.enter) then return end
    elseif (e == "mouse_click" and target == native) or (e == "monitor_touch" and ev[2] == monName) then
      local x, y = ev[3], ev[4]
      if y <= L.hh and x >= W - 12 then return end
      if onEvent then r = onEvent("click", x, y) end
    elseif e == "char" then
      if onEvent then r = onEvent("char", ev[2]) end
    elseif e == "timer" and ev[2] == timer then
      timer = os.startTimer(1)
      if onEvent then r = onEvent("tick") end
    end
    if r == "close" then return elseif r == "render" then render() end
  end
end

local function kb(b) return string.format("%.1f kB", b / 1024) end

local function gameList()
  local out = {}
  local function scan(dir)
    if fs.isDir(dir) then
      for _, f in ipairs(fs.list(dir)) do
        local p = fs.combine(dir, f)
        if not fs.isDir(p) then out[#out + 1] = { name = (f:gsub("%.lua$", "")), path = "/" .. p } end
      end
    end
  end
  scan("games"); scan("rom/programs/fun")
  local function scanApps(dir, tag)
    if fs.isDir(dir) then
      for _, f in ipairs(fs.list(dir)) do
        local p = fs.combine(dir, f)
        if not fs.isDir(p) and f:match("%.lua$") then
          out[#out + 1] = { name = (f:gsub("%.lua$", "")) .. tag, path = "/" .. p, app = true }
        end
      end
    end
  end
  scanApps("apps", "  [app]")
  for _, d in ipairs(fs.list("/")) do
    if d:match("^disk") and fs.isDir(d) then scanApps(fs.combine(d, "apps"), "  [" .. d .. "]") end
  end
  table.sort(out, function(a, b)
    if (a.app or false) ~= (b.app or false) then return a.app == true end
    return a.name < b.name
  end)
  return out
end

-- Run an app: a Lua file that returns { run = function(ctx) ... end }
local function runAppHere(path)
  local ctx = {
    path = path,
    dir = fs.getDir(path),
    monName = monName,
    getSize = function() return W, H end,
    rebuild = function() setupTarget() return win end,
    tap = function(ev)
      if ev[1] == "mouse_click" and target == native then return ev[3], ev[4] end
      if ev[1] == "monitor_touch" and ev[2] == monName then return ev[3], ev[4] end
    end,
  }
  local fn, err = loadfile(path)
  local ok, res = false, err
  if fn then
    ok, res = pcall(function()
      local mod = fn()
      if type(mod) == "table" and type(mod.run) == "function" then mod.run(ctx)
      elseif type(mod) == "function" then mod(ctx)
      else error("not an app: the file must return { run = function(ctx) ... end }", 0) end
    end)
  end
  setPalette()
  if not ok then
    page("APP ERROR", function(x1, y1)
      put(x1, y1, "Could not run " .. path, pink, pale)
      local msg, n = tostring(res), math.max(10, W - 14)
      for i = 0, 3 do put(x1, y1 + 2 + i, msg:sub(i * n + 1, (i + 1) * n), deep, pale) end
    end)
  end
end

-- ---- monitor chooser for apps ---------------------------------------
local function monitorNames()
  local t = {}
  for _, n in ipairs(peripheral.getNames()) do
    if peripheral.getType(n) == "monitor" then t[#t + 1] = n end
  end
  table.sort(t)
  return t
end

-- flash the highlighted monitor's name on it; blank the other monitors
local function identify(names, pick)
  for i, n in ipairs(names) do
    if n ~= monName then
      local m = peripheral.wrap(n)
      if m then
        pcall(function()
          m.setTextScale(1)
          m.setBackgroundColour(colors.black)
          m.setTextColour(colors.white)
          m.clear()
          if i == pick then
            local w, h = m.getSize()
            m.setCursorPos(math.max(1, math.floor((w - #n) / 2) + 1), math.max(1, math.floor(h / 2)))
            m.write(n)
          end
        end)
      end
    end
  end
end

-- returns nil (no choice needed), false (cancelled) or a monitor name
local function chooseMonitor()
  local names = monitorNames()
  if #names < 2 then return nil end
  local sel = 1
  for i, n in ipairs(names) do if n == monName then sel = i end end

  local widest = 0
  for _, n in ipairs(names) do widest = math.max(widest, #n + 10) end
  local bw = math.max(34, widest + 8)
  local bh = #names + 5
  local x1 = math.max(1, math.floor((W - bw) / 2) + 1)
  local y1 = math.max(1, math.floor((H - bh) / 2) + 1)
  local x2, y2 = x1 + bw - 1, y1 + bh - 1

  local function render()
    frame(function()
      box(x1, y1, x2, y2)
      fill(x1, y1, x2, y1, mid)
      put(x1 + 2, y1, " SEND APP TO MONITOR ", snow, mid)
      for i, n in ipairs(names) do
        local y = y1 + 1 + i
        local on = (i == sel)
        local bg = on and deep or pale
        fill(x1 + 1, y, x2 - 1, y, bg)
        if on then put(x1 + 1, y, " ", snow, pink) end
        put(x1 + 3, y, n .. ((n == monName) and "   (menu)" or ""), on and snow or deep, bg)
      end
      put(x1 + 2, y2 - 1, "enter = run   backspace = cancel", grey, pale)
    end)
  end

  local function finish(result)
    for _, n in ipairs(names) do
      if n ~= monName then
        local m = peripheral.wrap(n)
        if m then pcall(function() m.setBackgroundColour(colors.black) m.clear() end) end
      end
    end
    return result
  end

  render()
  identify(names, sel)
  while true do
    local ev = { os.pullEvent() }
    local e = ev[1]
    if e == "key" then
      if ev[2] == keys.up and sel > 1 then sel = sel - 1 render() identify(names, sel)
      elseif ev[2] == keys.down and sel < #names then sel = sel + 1 render() identify(names, sel)
      elseif ev[2] == keys.enter then return finish(names[sel])
      elseif ev[2] == keys.backspace or ev[2] == keys.q then return finish(false) end
    elseif (e == "mouse_click" and target == native) or (e == "monitor_touch" and ev[2] == monName) then
      local x, y = ev[3], ev[4]
      local idx = y - (y1 + 1)
      if x >= x1 and x <= x2 and names[idx] then
        if idx == sel then return finish(names[sel]) end
        sel = idx; render(); identify(names, sel)
      elseif x < x1 or x > x2 or y < y1 or y > y2 then
        return finish(false)
      end
    end
  end
end

local function runApp(path)
  local choice = chooseMonitor()
  if choice == false then return end
  if choice and choice ~= monName then
    frame(function()
      local msg = "Running on " .. choice
      local w = math.max(#msg, 30) + 6
      local x = math.max(1, math.floor((W - w) / 2) + 1)
      local y = math.max(1, math.floor(H / 2) - 1)
      box(x, y, x + w - 1, y + 3)
      put(x + 3, y + 1, msg, deep, pale)
      put(x + 3, y + 2, "(<) back there returns here", grey, pale)
    end)
    local oldTarget, oldMon, oldName = target, mon, monName
    mon = peripheral.wrap(choice)
    monName, target = choice, mon
    setupTarget()
    runAppHere(path)
    restorePalette()
    pcall(function() target.setBackgroundColour(colors.black) target.clear() end)
    target, mon, monName = oldTarget, oldMon, oldName
    setupTarget()
  else
    runAppHere(path)
  end
end

local function actGames()
  local list = gameList()
  local gsel, top = 1, 1
  local area = {}
  local function draw(x1, y1, x2, y2)
    area = { x1 = x1, y1 = y1 + 1, x2 = x2, y2 = y2 }
    put(x1, y1, "APPS: /apps + floppy    PROGRAMS: /games    (enter = launch)", grey, pale)
    if #list == 0 then put(x1, y1 + 2, "no programs found", mid, pale) return end
    local rows = y2 - (y1 + 1) + 1
    if gsel < top then top = gsel end
    if gsel > top + rows - 1 then top = gsel - rows + 1 end
    for i = 0, rows - 1 do
      local g = list[top + i]
      if not g then break end
      local on = (top + i == gsel)
      fill(x1, y1 + 1 + i, x2, y1 + 1 + i, on and deep or pale)
      put(x1 + 1, y1 + 1 + i, (on and "\16 " or "  ") .. g.name, on and snow or deep, on and deep or pale)
    end
  end
  local function run()
    local g = list[gsel]
    if g and g.app then runApp(g.path)
    elseif g then onComputer(function() shell.run(g.path) end) end
    return "render"
  end
  page("APPS", draw, function(kind, a, b)
    if kind == "key" then
      if a == keys.up and gsel > 1 then gsel = gsel - 1 return "render" end
      if a == keys.down and gsel < #list then gsel = gsel + 1 return "render" end
      if a == keys.enter then return run() end
    elseif kind == "click" and area.x1 and b >= area.y1 and b <= area.y2 and #list > 0 then
      local idx = top + (b - area.y1)
      if list[idx] then
        if gsel == idx then return run() end
        gsel = idx; return "render"
      end
    end
  end)
end

local function actSettings()
  local function draw(x1, y1)
    put(x1, y1,     "Label   " .. (os.getComputerLabel() or "(none)"), deep, pale)
    put(x1, y1 + 1, "ID      " .. os.getComputerID(), deep, pale)
    put(x1, y1 + 2, "Host    " .. _HOST:sub(1, 40), deep, pale)
    put(x1, y1 + 3, "Screen  " .. W .. " x " .. H, deep, pale)
    put(x1, y1 + 4, "Output  " .. (mon and ("monitor  " .. monName .. "  scale " .. scale) or "computer terminal"), deep, pale)
    put(x1, y1 + 6, "[R]  rename this computer", mid, pale)
    put(x1, y1 + 7, mon and "[S]  cycle monitor text scale" or "(attach a monitor to enable scaling)", mid, pale)
  end
  page("SETTINGS", draw, function(kind, a)
    if kind ~= "key" then return end
    if a == keys.r then
      onComputer(function()
        write("New computer label: ")
        local n = read()
        if n and n ~= "" then os.setComputerLabel(n) end
      end)
      return "render"
    elseif a == keys.s and mon then
      local idx = 1
      for i, v in ipairs(SCALES) do if v == scale then idx = i end end
      setupTarget(SCALES[idx % #SCALES + 1])
      return "render"
    end
  end)
end

local function actMemCard()
  local function draw(x1, y1, x2, y2)
    local used, free, cap = storage()
    put(x1, y1, "ROOT STORAGE", grey, pale)
    local bw = math.max(10, math.min(x2 - x1 + 1, 50))
    bar(x1, y1 + 1, bw, used, mid, lav)
    put(x1, y1 + 2, kb(cap - free) .. " used  /  " .. kb(free) .. " free", deep, pale)
    put(x1, y1 + 4, "DISK DRIVES", grey, pale)
    local y, found = y1 + 5, false
    for _, n in ipairs(peripheral.getNames()) do
      if peripheral.getType(n) == "drive" and disk.isPresent(n) and y <= y2 then
        found = true
        put(x1, y, "\4 " .. n .. "  " .. (disk.getLabel(n) or "unlabeled"), deep, pale)
        y = y + 1
      end
    end
    if not found then put(x1, y, "(no disk inserted)", mid, pale) y = y + 1 end
    y = y + 1
    if y <= y2 then put(x1, y, "PERIPHERALS", grey, pale) y = y + 1 end
    for _, n in ipairs(peripheral.getNames()) do
      if y > y2 then break end
      put(x1, y, "\4 " .. n .. "  (" .. peripheral.getType(n) .. ")", deep, pale)
      y = y + 1
    end
  end
  page("MEM. CARD", draw, function(kind) if kind == "tick" then return "render" end end)
end

-- styled frame: header, side stripe and footer around a program (patch output)
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

local function actCredits()
  page("CREDITS", function(x1, y1)
    local t = {
      "Crabtech OS", "a CC:Tweaked menu UI", "",
      "palette   lavender / deep purple / ice",
      "layout    scales to any monitor size",
      "render    double-buffered window",
    }
    for i, l in ipairs(t) do put(x1, y1 + i - 1, l, (i == 1) and deep or mid, pale) end
  end)
end

-- patches that are already built into this OS: they are not listed in INSTALLED or UPDATES
local BUILTIN_PATCHES = {
  unbrand = true, apps_patch = true, terminal_patch = true, terminal_style_patch = true,
  monitor_patch = true, rename_patch = true, fade_patch = true, fade_white_patch = true,
  loading_fade_patch = true, installed_patch = true, appstore_patch = true, updates_patch = true,
  trim_patch = true, cleanup_button_patch = true, tasks_patch = true, assign_patch = true,
}

-- installed patches tab: extra patches applied later through UPDATES
local function actInstalled()
  -- patches applied from the UPDATES tab are remembered in a small file
  local extras = {}
  pcall(function()
    local h = fs.open(".crabtech_updates", "r")
    if not h then return end
    local text = h.readAll()
    h.close()
    local t = textutils.unserialize(text)
    if type(t) == "table" and type(t.patches) == "table" then
      for name in pairs(t.patches) do extras[#extras + 1] = (name:gsub("%.lua$", "")) end
    end
  end)
  table.sort(extras)

  -- folders that may still hold patch files
  local dirs, seen = {}, {}
  local function addDir(d)
    d = fs.combine(d, "")
    if not seen[d] and fs.isDir(d) then seen[d] = true dirs[#dirs + 1] = d end
  end
  addDir(shell.dir()); addDir("")
  for _, n in ipairs(fs.list("/")) do if n:match("^disk") then addDir(n) end end

  local function pathsFor(name)
    local out = {}
    for _, d in ipairs(dirs) do
      for _, s in ipairs({ ".lua", "" }) do
        local p = fs.combine(d, name .. s)
        if fs.exists(p) and not fs.isDir(p) then out[#out + 1] = p break end
      end
    end
    return out
  end

  local rows, known = {}, {}
  for _, name in ipairs(extras) do
    known[name] = true
    local paths = pathsFor(name)
    rows[#rows + 1] = { name = name, desc = "applied from GitHub", installed = true, file = #paths > 0, paths = paths }
  end
  -- leftover files of the built-in patches are not listed, but CLEAN UP can delete them
  local hidden = {}
  for name in pairs(BUILTIN_PATCHES) do
    known[name] = true
    local paths = pathsFor(name)
    if #paths > 0 then hidden[#hidden + 1] = { name = name, paths = paths } end
  end
  for _, d in ipairs(dirs) do
    for _, fname in ipairs(fs.list(d)) do
      local base = (fname:gsub("%.lua$", ""))
      if base:match("patch$") and not known[base] then
        known[base] = true
        rows[#rows + 1] = { name = base, desc = "unknown patch file", installed = false, file = true, unknown = true }
      end
    end
  end

  -- CLEAN UP: delete patch files whose patch is already installed
  local armed, message, messageColor = false, "", mid
  local btn = nil

  local function doomed()
    local list = {}
    for _, group in ipairs({ rows, hidden }) do
      for _, r in ipairs(group) do
        if (r.installed or group == hidden) and r.paths then
          for _, p in ipairs(r.paths) do
            if not fs.isReadOnly(p) then list[#list + 1] = p end
          end
        end
      end
    end
    return list
  end

  local function cleanUp()
    local list = doomed()
    if #list == 0 then
      armed, message, messageColor = false, "no used patch files to delete", grey
      return
    end
    if not armed then
      armed = true
      message, messageColor = "tap again to delete " .. #list .. " file(s)", pink
      return
    end
    local n = 0
    for _, p in ipairs(list) do
      if pcall(fs.delete, p) and not fs.exists(p) then n = n + 1 end
    end
    for _, r in ipairs(rows) do
      if r.paths then r.paths = pathsFor(r.name) r.file = #r.paths > 0 end
    end
    for _, r in ipairs(hidden) do r.paths = pathsFor(r.name) end
    armed = false
    message, messageColor = "deleted " .. n .. " patch file(s)", mid
  end

  local top = 1
  local function draw(x1, y1, x2, y2)
    local w = x2 - x1 + 1
    local nExtra = #extras
    put(x1, y1, (nExtra == 0) and "no extra patches - everything is built into this OS"
      or (nExtra .. " extra patch(es) installed from GitHub"), (nExtra == 0) and grey or deep, pale)
    put(x1 + 2, y1 + 1, "PATCH", grey, pale)
    put(x1 + 24, y1 + 1, "STATUS", grey, pale)
    if w >= 58 then put(x1 + 38, y1 + 1, "WHAT", grey, pale) end

    local vis = math.max(1, y2 - (y1 + 2))          -- last row is the hint line
    top = math.max(1, math.min(top, math.max(1, #rows - vis + 1)))
    if #rows == 0 then put(x1 + 2, y1 + 2, "nothing to list", grey, pale) end
    for i = 0, vis - 1 do
      local r = rows[top + i]
      if not r then break end
      local y = y1 + 2 + i
      put(x1, y, r.installed and "\4" or " ", mid, pale)
      put(x1 + 2, y, r.name, r.installed and deep or grey, pale)
      put(x1 + 24, y, r.unknown and "unknown" or (r.installed and "installed" or "not installed"),
        r.installed and mid or grey, pale)
      if w >= 58 then put(x1 + 38, y, r.desc, grey, pale) end
      if r.file then put(x2 - 5, y, "[file]", deep, pale) end
    end
    local n = #doomed()
    local label = armed and (" CONFIRM: DELETE " .. n .. " ") or (" CLEAN UP (" .. n .. ") ")
    local bx = x2 - #label + 1
    btn = { x1 = bx, x2 = x2, y = y2 }
    put(bx, y2, label, (armed or n > 0) and snow or grey, armed and pink or (n > 0 and deep or lav))
    put(x1, y2, ("[file] = patch file still present"):sub(1, math.max(0, bx - x1 - 1)), grey, pale)
    if message ~= "" then put(x1 + 30, y1, message:sub(1, math.max(0, w - 38)), messageColor, pale) end
    if #rows > vis then put(x2 - 6, y1, (top + vis - 1 < #rows) and "\31 more" or "", mid, pale) end
  end

  page("INSTALLED", draw, function(kind, a, b)
    if kind == "key" then
      if a == keys.up then armed = false if top > 1 then top = top - 1 end return "render" end
      if a == keys.down then armed = false top = top + 1 return "render" end
      if a == keys.c then cleanUp() return "render" end
    elseif kind == "click" and btn and b == btn.y and a >= btn.x1 and a <= btn.x2 then
      cleanUp()
      return "render"
    end
  end)
end

-- app store
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

-- updates tab
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
        if e.type == "file" and type(e.name) == "string" and e.name:match("%.lua$")
          and not BUILTIN_PATCHES[(e.name:gsub("%.lua$", ""))] then names[#names + 1] = e end
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

-- trimmed: no terminal or notepad tab (the terminal lives on the computer itself)
-- tasks tab (offload)
-- tasks v3: signed messages, workers pull from github, autocomplete
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

-- task files come from the GitHub repo's apps folder
local tkRepo = { repo = "SenkuSushigami/CrabtechOS-Files", branch = "main", dir = "apps" }

local function tkGet(url, headers)
  if not http then return nil, "the HTTP API is disabled" end
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

-- the .lua files in the repo's apps folder: { name, file, size, remote = true }
local function tkRemoteList()
  local api = "https://api.github.com/repos/" .. tkRepo.repo .. "/contents/" .. tkRepo.dir
    .. "?ref=" .. tkRepo.branch
  local body, err = tkGet(api, { Accept = "application/vnd.github+json" })
  if not body then return nil, err end
  local data = textutils.unserializeJSON(body)
  if type(data) ~= "table" then return nil, "unexpected reply from GitHub" end
  if data.message then return nil, tostring(data.message) end
  local out = {}
  for _, e in ipairs(data) do
    if e.type == "file" and type(e.name) == "string" and e.name:match("%.lua$") then
      out[#out + 1] = { name = (e.name:gsub("%.lua$", "")), file = e.name, size = e.size or 0, remote = true }
    end
  end
  table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
  return out
end

-- fallback when GitHub cannot be reached: the apps folders on this computer and floppies
local function tkLocalList()
  local out = {}
  local function scan(dir, tag)
    if fs.isDir(dir) then
      for _, f in ipairs(fs.list(dir)) do
        local p = fs.combine(dir, f)
        if not fs.isDir(p) and f:match("%.lua$") then
          out[#out + 1] = { name = (f:gsub("%.lua$", "")), file = f, path = p, tag = tag }
        end
      end
    end
  end
  scan("apps", "")
  for _, d in ipairs(fs.list("/")) do
    if d:match("^disk") and fs.isDir(d) then scan(fs.combine(d, "apps"), "  [" .. d .. "]") end
  end
  table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
  return out
end

-- the list of known computers and submitted tasks is kept in a small file
local function tkLoad()
  local s = tkReadFile(tkDbFile)
  local db = s and textutils.unserialize(s)
  if type(db) ~= "table" then db = {} end
  db.workers = type(db.workers) == "table" and db.workers or {}
  db.tasks = type(db.tasks) == "table" and db.tasks or {}
  db.rr = db.rr or 0
  db.history = type(db.history) == "table" and db.history or {}
  return db
end

local function tkSave(db)
  while #db.tasks > 40 do table.remove(db.tasks, 1) end
  while #db.history > 30 do table.remove(db.history, 1) end
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
      name = spec.name, kind = spec.kind, cmd = spec.cmd, code = spec.code, file = spec.file, args = spec.args or {},
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
  local function ask(title, prompt, secret, history, complete)
    local answer
    local function run()
      print(title)
      print()
      write(prompt .. " ")
      answer = read(secret and "*" or nil, history, complete)
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

  -- Tab completion for the command prompt: earlier commands + programs from this computer's shell
  local function complete(line)
    local out, seen = {}, {}
    local function add(s)
      if type(s) == "string" and s ~= "" and not seen[s] then seen[s] = true out[#out + 1] = s end
    end
    for i = #db.history, 1, -1 do
      local h = db.history[i]
      if #h > #line and h:sub(1, #line) == line then add(h:sub(#line + 1)) end
    end
    if shell and shell.complete then
      local ok, list = pcall(shell.complete, line)
      if ok and type(list) == "table" then for _, s in ipairs(list) do add(s) end end
    end
    return out
  end

  -- tasks files: the repo's apps folder on GitHub, with type-to-filter and Tab completion
  local function commonPrefix(list)
    if #list == 0 then return "" end
    local p = list[1].name
    for i = 2, #list do
      local n, j = list[i].name, 0
      while j < #p and j < #n and p:sub(j + 1, j + 1):lower() == n:sub(j + 1, j + 1):lower() do j = j + 1 end
      p = p:sub(1, j)
    end
    return p
  end

  local function pickTaskFile()
    flash("asking GitHub for the apps folder ...")
    local files, err = tkRemoteList()
    local source = "GitHub  " .. tkRepo.repo .. "/" .. tkRepo.dir
    if not files then
      files = tkLocalList()
      source = "this computer's apps folders  (GitHub: " .. tostring(err) .. ")"
    end
    local query, psel, ptop = "", 1, 1
    local chosen, parea = nil, {}

    local function matches()
      local q, out = query:lower(), {}
      for _, f in ipairs(files) do
        if q == "" or f.name:lower():find(q, 1, true) then out[#out + 1] = f end
      end
      return out
    end

    page("TASK FILES", function(x1, y1, x2, y2)
      local w = x2 - x1 + 1
      put(x1, y1, ("from " .. source):sub(1, w), grey, pale)
      fill(x1, y1 + 1, x2, y1 + 1, lav)
      put(x1 + 1, y1 + 1, ("find: " .. query .. "_"):sub(1, math.max(1, w - 2)), deep, lav)
      local list = matches()
      if #files == 0 then
        put(x1, y1 + 3, "No .lua files found in the apps folder.", mid, pale)
      elseif #list == 0 then
        put(x1, y1 + 3, ("Nothing matches '" .. query .. "'"):sub(1, w), pink, pale)
      end
      psel = clamp(psel, 1, math.max(1, #list))
      local rows = math.max(1, y2 - 1 - (y1 + 3))
      parea = { y0 = y1 + 3, rows = rows }
      if psel < ptop then ptop = psel end
      if psel > ptop + rows - 1 then ptop = psel - rows + 1 end
      for i = 0, rows - 1 do
        local f = list[ptop + i]
        if not f then break end
        local on = (ptop + i == psel)
        local bg = on and deep or pale
        local y = y1 + 3 + i
        fill(x1, y, x2, y, bg)
        put(x1 + 1, y, ((on and "\16 " or "  ") .. f.name .. (f.tag or "")):sub(1, math.max(1, w - 12)), on and snow or deep, bg)
        if f.size then put(x2 - 8, y, string.format("%.1f kB", f.size / 1024), on and ice or grey, bg) end
      end
      put(x1, y2, ("type to filter   tab complete   enter send   backspace erase"):sub(1, w), grey, pale)
    end, function(kind, a, b)
      local list = matches()
      if kind == "char" then
        query, psel, ptop = query .. a, 1, 1
        return "render"
      elseif kind == "key" then
        if a == keys.up then psel = math.max(1, psel - 1) return "render"
        elseif a == keys.down then psel = math.min(math.max(1, #list), psel + 1) return "render"
        elseif a == keys.tab then
          if #list == 1 then query = list[1].name
          elseif #list > 1 then
            local p = commonPrefix(list)
            if #p > #query then query = p end
          end
          psel, ptop = 1, 1
          return "render"
        elseif a == keys.enter then
          chosen = list[psel]
          if chosen then return "close" end
          return "render"
        elseif a == keys.backspace then
          if #query > 0 then query, psel, ptop = query:sub(1, -2), 1, 1 return "render" end
          return nil                       -- empty search: Backspace goes back
        elseif a == keys.delete then
          query, psel, ptop = "", 1, 1
          return "render"
        elseif a == keys.q then
          return "render"                  -- Q is a letter here, not "back"
        end
      elseif kind == "click" and parea.y0 and b >= parea.y0 and b < parea.y0 + parea.rows then
        local idx = ptop + (b - parea.y0)
        if list[idx] then
          if idx == psel then chosen = list[idx] return "close" end
          psel = idx
          return "render"
        end
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

  -- ASSIGN: tap a task from the list, then tap the computer that should run it
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
    if needKey() then return end
    local ids, label = selectedTargets()
    if not ids then say(label, pink) return end
    local cmd = ask("Run a command on " .. label, "Command:", false, db.history, complete)
    tkSave(db)                                     -- keeps the command history
    if cmd then send(ids, { name = cmd:sub(1, 40), kind = "cmd", cmd = cmd }, label) end
  end

  local function runFile()
    if needKey() then return end
    local ids, label = selectedTargets()
    if not ids then say(label, pink) return end
    local file = pickTaskFile()
    if not file then return end
    local spec
    local argText
    if file.remote then
      argText = ask("Run " .. file.name .. " on " .. label .. "  (the computer downloads it from GitHub)", "Arguments (optional):")
      spec = { name = file.name, kind = "github", file = file.file }
    else
      local code = tkReadFile(file.path)
      if not code then say("could not read " .. file.path, pink) return end
      if #code > 100000 then say(file.name .. " is too big to send (100 kB max)", pink) return end
      local fn, perr = load(code, "=" .. file.name)
      if not fn then say(file.name .. " is not valid Lua: " .. tostring(perr), pink) return end
      argText = ask("Send " .. file.name .. " to " .. label, "Arguments (optional):")
      spec = { name = file.name, kind = "lua", code = code }
    end
    local list = {}
    for word in (argText or ""):gmatch("%S+") do list[#list + 1] = word end
    spec.args = list
    send(ids, spec, label)
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
      and "enter run   f file   a assign   s scan   k key   tab tasks"
      or "enter output   x cancel   c clear   r refresh   tab computers"
    local btn = " ASSIGN "
    area.abtn = { x1 = x2 - #btn + 1, x2 = x2, y = y2 }
    put(x2 - #btn + 1, y2, btn, snow, deep)
    put(x1, y2, hint:sub(1, math.max(0, w - #btn - 1)), grey, pale)
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
      elseif a == keys.a then assignTask() return "render"
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
      if area.abtn and b == area.abtn.y and a >= area.abtn.x1 and a <= area.abtn.x2 then
        assignTask()
        return "render"
      elseif area.cy and b >= area.cy and b < area.cy + area.cn then
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

local actions = { actGames, actStore, actSettings, actMemCard, actUpdates, actTasks, actInstalled, actCredits }

-- ------------------------------------------------------------
-- Boot animation
-- ------------------------------------------------------------
-- end of loading: the bar fades out, then the screen fades to white
-- k = 0 : every colour white ... k = 1 : the normal palette
local function paletteFromWhite(k)
  for c, v in pairs(PAL) do
    local r, g, b = math.floor(v / 65536) % 256, math.floor(v / 256) % 256, v % 256
    pcall(term.setPaletteColour, c, (r * k + 255 * (1 - k)) / 255,
      (g * k + 255 * (1 - k)) / 255, (b * k + 255 * (1 - k)) / 255)
  end
end

local function bootFadeOut()
  if CONFIG.fade == false or not win.getLine then return end
  local function rgb(v) return math.floor(v / 65536) % 256, math.floor(v / 256) % 256, v % 256 end
  local dr, dg, db = rgb(PAL[deep])

  -- 1) the bar melts into its box
  for s = 1, 10 do
    local k = s / 10
    for _, c in ipairs({ ice, mid }) do
      local r, g, b = rgb(PAL[c])
      term.setPaletteColour(c, (r + (dr - r) * k) / 255, (g + (dg - g) * k) / 255, (b + (db - b) * k) / 255)
    end
    sleep(0.03)
  end

  -- 2) everything fades to white (the bar stays hidden in the box colour)
  for s = 1, 12 do
    local k = s / 12
    for c, v in pairs(PAL) do
      local r, g, b
      if c == ice or c == mid then r, g, b = dr, dg, db else r, g, b = rgb(v) end
      term.setPaletteColour(c, (r + (255 - r) * k) / 255, (g + (255 - g) * k) / 255, (b + (255 - b) * k) / 255)
    end
    sleep(0.03)
  end
end

local function boot()
  local steps = 24
  local fadeUp = CONFIG.fade ~= false
  if fadeUp then paletteFromWhite(0) end
  for i = 0, steps do
    frame(function()
      term.setBackgroundColour(pale); term.clear()
      local cx, cy = math.floor(W / 2), math.floor(H / 2)
      local bwid = clamp(math.floor(W * 0.4), 16, 60)
      fill(cx - math.floor(bwid / 2) - 2, cy - 3, cx + math.floor(bwid / 2) + 2, cy + 3, deep)
      put(cx - 5, cy - 1, "Crabtech OS", snow, deep)
      put(cx - 1, cy - 2, "\4", SPARK[i % 4 + 1], deep)
      bar(cx - math.floor(bwid / 2), cy + 1, bwid, i / steps, ice, mid)
    end)
    if i == 0 and fadeUp then
      for s = 1, 12 do paletteFromWhite(s / 12) sleep(0.03) end
    end
    sleep(0.04)
  end
  sleep(0.15)
  bootFadeOut()
end

-- ------------------------------------------------------------
-- Main loop
-- ------------------------------------------------------------
local function selectItem(i)
  if i < 1 or i > #items or i == sel then return end
  local old = sel
  sel = i
  frame(function() drawButton(old); drawButton(sel); drawSparkles() end)
end

-- fade-in: the menu grows from the middle column out to both sides
local function fadeIn()
  if CONFIG.fade == false or not win.getLine then drawAll() return end

  -- build the finished frame off-screen
  win.setVisible(false)
  holdFrame = true
  local ok, err = pcall(drawAll)
  holdFrame = false
  if not ok then win.setVisible(true) error(err, 0) end
  setPalette()   -- window palette back to normal (the loading fade changed it)

  local rows = {}
  for y = 1, H do
    local t, fg, bg = win.getLine(y)
    rows[y] = { t, fg, bg }
  end

  local steps, cx = 28, math.floor(W / 2)
  local spaces, void = string.rep(" ", W), string.rep("0", W)
  for s = 1, steps do
    local p = s / steps
    local hw = math.max(1, math.ceil(p * W / 2))
    local l, r = math.max(1, cx - hw + 1), math.min(W, cx + hw)
    local k = p ^ 0.8
    for c, v in pairs(PAL) do   -- colours fade up from black
      local rr, gg, bb = math.floor(v / 65536) % 256, math.floor(v / 256) % 256, v % 256
      pcall(target.setPaletteColour, c, (rr * k + 255 * (1 - k)) / 255, (gg * k + 255 * (1 - k)) / 255, (bb * k + 255 * (1 - k)) / 255)
    end
    for y = 1, H do
      local row = rows[y]
      target.setCursorPos(1, y)
      target.blit(
        spaces:sub(1, l - 1) .. row[1]:sub(l, r) .. spaces:sub(1, W - r),
        void:sub(1, l - 1) .. row[2]:sub(l, r) .. void:sub(1, W - r),
        void:sub(1, l - 1) .. row[3]:sub(l, r) .. void:sub(1, W - r))
    end
    sleep(0.025)
  end

  win.setVisible(true)
  setPalette()
end

local function main()
  monName, mon = findMonitor()
  if mon then target = mon end
  setupTarget(scale)
  if CONFIG.boot then boot() end
  fadeIn()
  local timer = os.startTimer(0.5)

  local function activate(i)
    selectItem(i)
    actions[i]()
    drawAll()
    timer = os.startTimer(0.5)
  end

  while true do
    local ev = { os.pullEvent() }
    local e = ev[1]
    if e == "timer" and ev[2] == timer then
      tick = tick + 1
      frame(drawDynamic)
      timer = os.startTimer(0.5)
    elseif e == "key" then
      if ev[2] == keys.up then selectItem(sel - 1)
      elseif ev[2] == keys.down then selectItem(sel + 1)
      elseif ev[2] == keys.enter then activate(sel)
      elseif ev[2] == keys.q then break end
    elseif (e == "mouse_click" and target == native) or (e == "monitor_touch" and ev[2] == monName) then
      local x, y = ev[3], ev[4]
      for i, it in ipairs(items) do
        if y >= it.y and y <= it.y + L.bh - 1 and x >= L.bx and x < L.bx + L.bw then
          activate(i)
          break
        end
      end
    elseif e == "monitor_resize" or e == "term_resize" then
      setupTarget(scale)
      drawAll()
    end
  end
end

local ok, err = pcall(main)
restorePalette()
term.redirect(native)
term.setBackgroundColour(colors.black)
term.setTextColour(colors.white)
term.clear()
term.setCursorPos(1, 1)
if not ok then printError(err) end
