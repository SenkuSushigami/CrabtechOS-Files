-- cleanup_button_patch.lua : adds a CLEAN UP button to the INSTALLED tab
--
-- The button sits in the bottom-right corner of the INSTALLED tab and shows
-- how many used patch files can be deleted. A "used" patch file is one whose
-- patch is already installed in the OS and whose file is still lying around
-- (marked [file]), on the computer or on any floppy.
--
--   Tap the button, or press C       arms it ("CONFIRM: DELETE n")
--   Tap / press C again              deletes those files
--   Up / Down (or any other key)     cancels
--
-- Patch files that are not installed yet, and unknown patch-like files, are
-- never touched. The OS file and apps are never touched either.
--
-- Usage:  cleanup_button_patch            (patches "crabtech")
--         cleanup_button_patch myfile     (patches another file name)
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

if src:find("local function cleanUp", 1, true) then
  print("Already patched - nothing to do.")
  return
end
local pageStart = src:find("-- installed patches tab", 1, true)
if not pageStart then
  printError("This patch needs the INSTALLED tab (installed_patch / crabtech.lua).")
  return
end

local ok = true
-- plain replace, searching only from the INSTALLED page onwards
local function edit(label, old, new, optional)
  local s, t = src:find(old, pageStart, true)
  if not s then
    print("skipped : " .. label .. " (not found)" .. (optional and ", optional" or ""))
    if not optional then ok = false end
    return
  end
  src = src:sub(1, s - 1) .. new .. src:sub(t + 1)
  print("patched : " .. label)
end

edit("Find patch files", [==[  local function fileFor(name)
    for _, d in ipairs(dirs) do
      for _, s in ipairs({ ".lua", "" }) do
        local p = fs.combine(d, name .. s)
        if fs.exists(p) and not fs.isDir(p) then return true end
      end
    end
    return false
  end]==], [==[  local function pathsFor(name)
    local out = {}
    for _, d in ipairs(dirs) do
      for _, s in ipairs({ ".lua", "" }) do
        local p = fs.combine(d, name .. s)
        if fs.exists(p) and not fs.isDir(p) then out[#out + 1] = p break end
      end
    end
    return out
  end
  local function fileFor(name) return #pathsFor(name) > 0 end]==])

edit("Remember file paths", "file = fileFor(p[1]) }", "file = fileFor(p[1]), paths = pathsFor(p[1]) }")

edit("Cleanup logic", "  local top = 1\n", [==[  -- CLEAN UP: delete patch files whose patch is already installed
  local armed, message, messageColor = false, "", mid
  local btn = nil

  local function doomed()
    local list = {}
    for _, r in ipairs(rows) do
      if r.installed and r.paths then
        for _, p in ipairs(r.paths) do
          if not fs.isReadOnly(p) then list[#list + 1] = p end
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
    armed = false
    message, messageColor = "deleted " .. n .. " patch file(s)", mid
  end

  local top = 1
]==])

edit("Button", [==[    local hint = "[file] = patch file still present   run  cleanup  to remove used files"
    put(x1, y2, hint:sub(1, w), grey, pale)]==], [==[    local n = #doomed()
    local label = armed and (" CONFIRM: DELETE " .. n .. " ") or (" CLEAN UP (" .. n .. ") ")
    local bx = x2 - #label + 1
    btn = { x1 = bx, x2 = x2, y = y2 }
    put(bx, y2, label, (armed or n > 0) and snow or grey, armed and pink or (n > 0 and deep or lav))
    put(x1, y2, ("[file] = patch file still present"):sub(1, math.max(0, bx - x1 - 1)), grey, pale)
    if message ~= "" then put(x1 + 30, y1, message:sub(1, math.max(0, w - 38)), messageColor, pale) end]==])

edit("Keys and touch", [==[  page("INSTALLED", draw, function(kind, a)
    if kind == "key" then
      if a == keys.up and top > 1 then top = top - 1 return "render" end
      if a == keys.down then top = top + 1 return "render" end
    end
  end)]==], [==[  page("INSTALLED", draw, function(kind, a, b)
    if kind == "key" then
      if a == keys.up then armed = false if top > 1 then top = top - 1 end return "render" end
      if a == keys.down then armed = false top = top + 1 return "render" end
      if a == keys.c then cleanUp() return "render" end
    elseif kind == "click" and btn and b == btn.y and a >= btn.x1 and a <= btn.x2 then
      cleanUp()
      return "render"
    end
  end)]==])

-- list this patch on the INSTALLED tab (optional)
do
  local s, t = src:find('{ "installed_patch",%s+"this tab",%s+function%(h%) return h%("local function " %.%. "actInstalled"%) end },')
  if s then
    src = src:sub(1, t) .. '\n    { "cleanup_button_patch", "cleanup button",     function(h) return h("local function " .. "cleanUp") end },' .. src:sub(t + 1)
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
