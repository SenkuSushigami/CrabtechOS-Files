-- ============================================================
--  Crabtech OS  --  menu UI for CC:Tweaked
--  Built for advanced monitors; falls back to the computer's
--  own terminal when no monitor is attached.
--
--  Controls : Up/Down + Enter, or click / touch a button
--  Quit     : Q on the computer keyboard
--  Menu     : APPS, SETTINGS, MEM. CARD, NOTEPAD, TERMINAL,
--             INSTALLED, CREDITS
--  Apps     : Lua apps in /apps or /disk/apps (see ae2Dashboard);
--             with two or more monitors you choose where one opens
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
  { label = "APPS" }, { label = "SETTINGS" }, { label = "MEM. CARD" },
  { label = "NOTEPAD" }, { label = "TERMINAL" }, { label = "INSTALLED" }, { label = "CREDITS" },
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

local function actNotepad()
  onComputer(function() shell.run("edit", "notes.txt") end)
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

-- styled terminal
local function actTerminal()
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
  tp(3, 2, " TERM ", deep, snow)
  th(10, 2, "Terminal", snow)
  th(10, 3, "m e n u  \187  t e r m i n a l", lav)
  th(nw - 11, 2, "type  exit", snow)
  th(nw - 11, 3, "to go back", lav)

  -- side stripe + footer tag
  for y = hh + 1, nh do tp(1, y, "  ", ice, deep) end
  for y = hh + 2, nh - 2, 6 do tp(1, y, "//", ice, deep) end
  tp(3, nh, string.rep(" ", math.max(0, nw - 2)), grey, pale)
  tp(5, nh, "TERMINAL  ////  type exit to return to the menu", grey, pale)

  -- the shell lives in a window under the header
  local sw = window.create(native, 3, hh + 1, math.max(10, nw - 2), math.max(3, nh - hh - 1), true)
  term.redirect(sw)
  sw.setBackgroundColour(colors.black)
  sw.setTextColour(colors.white)
  sw.clear()
  sw.setCursorPos(1, 1)
  sw.setTextColour(ice)
  print("Type 'exit' to return to the menu.")
  sw.setTextColour(colors.white)
  pcall(shell.run, "shell")

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

-- installed patches tab
local function actInstalled()
  -- what each patch leaves in the OS file (written so this code never matches itself)
  local PATCHES = {
    { "unbrand", "branding removed",
      function(h) return not h(" SNC" .. "TRY\\174 ") and not h("--  Sanct" .. "uary OS  --  menu UI")
        and not h('local TICKER = "  SANCT' .. 'UARY OS') end },
    { "apps_patch",           "apps support",       function(h) return h("local function " .. "runApp") end },
    { "terminal_patch",       "terminal button",    function(h) return h("local function " .. "actTerminal") end },
    { "terminal_style_patch", "styled terminal",    function(h) return h("-- styled " .. "terminal") end },
    { "monitor_patch",        "monitor chooser",    function(h) return h("local function " .. "chooseMonitor") end },
    { "rename_patch",         "renamed, new tags",  function(h) return not h("STD. " .. "AROUND") and not h("INTERNAL" .. "-559") end },
    { "fade_patch",           "centre fade-in",     function(h) return h("local function " .. "fadeIn") end },
    { "fade_white_patch",     "white fade",         function(h) return h("local function " .. "bootFadeOut") end },
    { "loading_fade_patch",   "loading fade",       function(h) return h("local function " .. "paletteFromWhite") end },
    { "installed_patch",      "this tab",           function(h) return h("local function " .. "actInstalled") end },
  }

  local text, readOk = "", false
  pcall(function()
    local h = fs.open(shell.getRunningProgram(), "r")
    text = h.readAll()
    h.close()
    readOk = true
  end)
  local function has(s) return text:find(s, 1, true) ~= nil end

  -- folders that may still hold patch files
  local dirs, seen = {}, {}
  local function addDir(d)
    d = fs.combine(d, "")
    if not seen[d] and fs.isDir(d) then seen[d] = true dirs[#dirs + 1] = d end
  end
  addDir(shell.dir()); addDir("")
  for _, n in ipairs(fs.list("/")) do if n:match("^disk") then addDir(n) end end

  local function fileFor(name)
    for _, d in ipairs(dirs) do
      for _, s in ipairs({ ".lua", "" }) do
        local p = fs.combine(d, name .. s)
        if fs.exists(p) and not fs.isDir(p) then return true end
      end
    end
    return false
  end

  local rows, known, count = {}, {}, 0
  for _, p in ipairs(PATCHES) do
    known[p[1]] = true
    local inst = readOk and p[3](has) or false
    if inst then count = count + 1 end
    rows[#rows + 1] = { name = p[1], desc = p[2], installed = inst, file = fileFor(p[1]) }
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

  local top = 1
  local function draw(x1, y1, x2, y2)
    local w = x2 - x1 + 1
    if readOk then
      put(x1, y1, count .. " of " .. #PATCHES .. " patches installed", deep, pale)
    else
      put(x1, y1, "Could not read the OS file", pink, pale)
    end
    put(x1 + 2, y1 + 1, "PATCH", grey, pale)
    put(x1 + 24, y1 + 1, "STATUS", grey, pale)
    if w >= 58 then put(x1 + 38, y1 + 1, "WHAT", grey, pale) end

    local vis = math.max(1, y2 - (y1 + 2))          -- last row is the hint line
    top = math.max(1, math.min(top, math.max(1, #rows - vis + 1)))
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
    local hint = "[file] = patch file still present   run  cleanup  to remove used files"
    put(x1, y2, hint:sub(1, w), grey, pale)
    if #rows > vis then put(x2 - 6, y1, (top + vis - 1 < #rows) and "\31 more" or "", mid, pale) end
  end

  page("INSTALLED", draw, function(kind, a)
    if kind == "key" then
      if a == keys.up and top > 1 then top = top - 1 return "render" end
      if a == keys.down then top = top + 1 return "render" end
    end
  end)
end

local actions = { actGames, actSettings, actMemCard, actNotepad, actTerminal, actInstalled, actCredits }

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
