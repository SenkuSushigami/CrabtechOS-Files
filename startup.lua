-- ============================================================
--  startup.lua  --  boot screen (autorun)
--
--  Save as /startup.lua (or /startup/boot.lua). The computer shows
--  one large BOOT button in the OS style. Press Enter / Space, or
--  click / touch the button, to start the OS. When the OS quits you
--  land back here. Ctrl+T drops to the normal shell.
--
--  The OS file is found automatically as /crabtech or /sanctuary
--  (set CONFIG.os to force a name).
-- ============================================================

local CONFIG = {
  scale = 0.5,    -- monitor text scale (same as the OS)
  os    = nil,    -- program to start; nil = auto-detect
}
local OS_NAMES = { "crabtech", "sanctuary", "os" }

-- ------------------------------------------------------------
-- Palette (same as the OS)
-- ------------------------------------------------------------
local pale, lav, mid, deep = colors.white, colors.lightGray, colors.purple, colors.blue
local pink, ice, grey, ink, snow = colors.pink, colors.lightBlue, colors.gray, colors.black, colors.cyan
local soft = colors.green
local GRAD = { deep, colors.brown, colors.red, colors.magenta, mid }
local SPARK = { mid, ice, deep, ice }

local PAL = {
  [pale] = 0xF1EDFC, [lav] = 0xD9CFF6, [mid] = 0x8466D9, [deep] = 0x3A2E9E,
  [pink] = 0xE8708F, [ice] = 0x9ED3F0, [grey] = 0xA399C9, [ink] = 0x2B2466,
  [snow] = 0xFFFFFF, [soft] = 0xC3B6EE,
  [colors.brown] = 0x4538AA, [colors.red] = 0x5744BC, [colors.magenta] = 0x6B54CC,
}

local HB = "\149"
local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

-- ------------------------------------------------------------
-- Display (monitor if attached, otherwise the computer screen)
-- ------------------------------------------------------------
local native = term.current()
local target, mon, monName, win
local W, H = 51, 19
local tick, errMsg = 0, nil

local function setup()
  monName, mon = nil, nil
  for _, n in ipairs(peripheral.getNames()) do
    if peripheral.getType(n) == "monitor" then monName, mon = n, peripheral.wrap(n) break end
  end
  target = mon or native
  if mon then pcall(mon.setTextScale, CONFIG.scale) end
  W, H = target.getSize()
  win = window.create(target, 1, 1, W, H, true)
  term.redirect(win)
  for c, v in pairs(PAL) do pcall(term.setPaletteColour, c, v) end
  term.setCursorBlink(false)
end

local function frame(fn)
  win.setVisible(false)
  local ok, err = pcall(fn)
  win.setVisible(true)
  if not ok then error(err, 0) end
end

local function put(x, y, s, fg, bg)
  if y < 1 or y > H or x > W then return end
  if x < 1 then s = s:sub(2 - x); x = 1 end
  s = s:sub(1, W - x + 1)
  if #s == 0 then return end
  term.setCursorPos(x, y)
  term.setTextColour(fg or deep)
  term.setBackgroundColour(bg or pale)
  term.write(s)
end

local function fill(x1, y1, x2, y2, bg)
  x1, x2 = math.max(1, x1), math.min(W, x2)
  if x2 < x1 then return end
  local row = string.rep(" ", x2 - x1 + 1)
  for y = math.max(1, y1), math.min(H, y2) do put(x1, y, row, bg, bg) end
end

-- ------------------------------------------------------------
-- Big block lettering for "BOOT"
-- ------------------------------------------------------------
local FONT = {
  B = { "110", "101", "110", "101", "110" },
  O = { "111", "101", "101", "101", "111" },
  T = { "111", "010", "010", "010", "010" },
  S = { "111", "100", "111", "001", "111" },
}
local LABEL = "BOOT"

local function pixelRows()
  local rows = { "", "", "", "", "" }
  for i = 1, #LABEL do
    local ch = LABEL:sub(i, i)
    for r = 1, 5 do
      rows[r] = rows[r] .. ((ch == " ") and "000" or (FONT[ch][r] .. "0"))
    end
  end
  for r = 1, 5 do rows[r] = rows[r]:sub(1, -2) end
  return rows
end

local ROWS = pixelRows()
local PW = #ROWS[1]

-- button geometry: scales with the screen so it is always large
local function geometry()
  local g = { text = false }
  local bw = clamp(math.floor(W * 0.7), PW + 6, 150)
  bw = math.min(bw, W - 2)
  local cw, ch = 1, 1
  local k = math.floor((bw - 6) / (PW * 2))
  if k >= 1 then cw, ch = 2 * k, k end
  local pad = 3
  if 5 * ch + 2 * pad > H - 2 then pad = 1 end
  local bh = 5 * ch + 2 * pad
  if bw < PW * cw + 2 or bh > H - 2 then
    -- tiny screen: plain text button
    g.text = true
    bw, bh = math.min(W - 2, 24), 3
  end
  g.bw, g.bh, g.cw, g.ch = bw, bh, cw, ch
  g.x1 = math.floor((W - bw) / 2) + 1
  g.y1 = math.floor((H - bh) / 2) + 1
  g.x2, g.y2 = g.x1 + bw - 1, g.y1 + bh - 1
  return g
end

-- ------------------------------------------------------------
-- Drawing
-- ------------------------------------------------------------
local function hbg(x, y)
  local xs = x - (y - 1) * 2
  return GRAD[clamp(math.floor((xs - 1) / (W / 5)) + 1, 1, 5)]
end

local function draw(pressed)
  local hh = clamp(math.floor(H * 0.15), 3, 8)
  term.setBackgroundColour(pale); term.clear()

  -- gradient band
  for y = 1, hh do
    local x = 1
    while x <= W do
      local c = hbg(x, y)
      local x2 = x
      while x2 < W and hbg(x2 + 1, y) == c do x2 = x2 + 1 end
      fill(x, y, x2, y, c)
      x = x2 + 1
    end
  end

  -- diagonal split with a smooth edge
  local y0 = hh + 1
  local d0, d1 = math.floor(W * 0.40), math.floor(W * 0.66)
  local slope = (d1 - d0) / math.max(1, H - y0)
  for y = y0, H do
    local sh = math.floor((d0 + (y - y0) * slope) * 2)
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

  -- side stripe
  fill(1, y0, 2, H, deep)
  for y = y0 + 1, H - 3, 6 do put(1, y, "//", ice, deep) put(1, y + 1, "//", mid, deep) end

  -- the button
  local g = geometry()
  fill(g.x1, g.y1, g.x2, g.y2, (tick % 2 == 0) and soft or ice)       -- breathing border
  fill(g.x1 + 1, g.y1 + 1, g.x2 - 1, g.y2 - 1, pressed and mid or deep)
  if g.text then
    local label = LABEL
    put(g.x1 + math.floor((g.bw - #label) / 2), g.y1 + math.floor(g.bh / 2), label,
      snow, pressed and mid or deep)
  else
    local ox = g.x1 + math.floor((g.bw - PW * g.cw) / 2)
    local oy = g.y1 + math.floor((g.bh - 5 * g.ch) / 2)
    for r = 1, 5 do
      for c = 1, PW do
        if ROWS[r]:sub(c, c) == "1" then
          fill(ox + (c - 1) * g.cw, oy + (r - 1) * g.ch,
               ox + c * g.cw - 1, oy + r * g.ch - 1, snow)
        end
      end
    end
  end

  -- twinkling corner sparkles
  local corners = { { g.x1 - 2, g.y1 - 1 }, { g.x2 + 2, g.y1 - 1 }, { g.x1 - 2, g.y2 + 1 }, { g.x2 + 2, g.y2 + 1 } }
  for i, p in ipairs(corners) do
    local bg = (p[1] > d0 + (p[2] - y0) * slope + 2) and lav or pale
    put(p[1], p[2], "\4", SPARK[(tick + i) % 4 + 1], bg)
  end

  if errMsg then put(5, H, errMsg, pink, pale) end
end

-- fade everything to white (matches the OS loading screen)
local function fadeWhite()
  local steps = 14
  for s = 1, steps do
    local k = s / steps
    for c, v in pairs(PAL) do
      local r, gg, b = math.floor(v / 65536) % 256, math.floor(v / 256) % 256, v % 256
      pcall(term.setPaletteColour, c, (r + (255 - r) * k) / 255, (gg + (255 - gg) * k) / 255, (b + (255 - b) * k) / 255)
    end
    sleep(0.03)
  end
end

-- ------------------------------------------------------------
-- Boot
-- ------------------------------------------------------------
local function findOS()
  if CONFIG.os then return CONFIG.os end
  for _, n in ipairs(OS_NAMES) do
    if fs.exists(n) or fs.exists(n .. ".lua") then return n end
  end
end

local function launch()
  local name = findOS()
  if not name then
    errMsg = "OS file not found (expected /crabtech)"
    return
  end
  errMsg = nil
  frame(function() draw(true) end)
  sleep(0.15)
  fadeWhite()
  term.redirect(native)
  shell.run(name)
end

local function screen()
  setup()
  frame(function() draw(false) end)
  local timer = os.startTimer(0.5)
  while true do
    local ev = { os.pullEvent() }
    local e = ev[1]
    if e == "timer" and ev[2] == timer then
      tick = tick + 1
      frame(function() draw(false) end)
      timer = os.startTimer(0.5)
    elseif e == "key" then
      if ev[2] == keys.enter or ev[2] == keys.space or ev[2] == keys.numPadEnter then return "boot" end
    elseif (e == "mouse_click" and target == native) or (e == "monitor_touch" and ev[2] == monName) then
      local g = geometry()
      local x, y = ev[3], ev[4]
      if x >= g.x1 and x <= g.x2 and y >= g.y1 and y <= g.y2 then return "boot" end
    elseif e == "monitor_resize" or e == "term_resize" then
      setup()
      frame(function() draw(false) end)
    end
  end
end

local function cleanup()
  if target then
    for c in pairs(PAL) do
      pcall(function() target.setPaletteColour(c, term.nativePaletteColour(c)) end)
    end
  end
  term.redirect(native)
  native.setBackgroundColour(colors.black)
  native.setTextColour(colors.white)
  native.clear()
  native.setCursorPos(1, 1)
  if mon then pcall(function() mon.setBackgroundColour(colors.black) mon.clear() end) end
end

while true do
  local ok, res = pcall(screen)
  if not ok then
    cleanup()
    error(res, 0)        -- Ctrl+T: back to the normal shell
  end
  if res == "boot" then launch() end
end
