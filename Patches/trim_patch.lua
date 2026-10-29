-- trim_patch.lua : removes the TERMINAL button and the NOTEPAD app
--
--  * The TERMINAL and NOTEPAD buttons are gone from the menu.
--  * The terminal now lives only on the computer itself: quit the OS with Q
--    (or press Ctrl+T on the boot screen) to get the computer's own shell.
--    Nothing on a monitor or touch screen can open a shell any more.
--  * Patch output (UPDATES tab) still appears on the computer's own screen.
--  * The INSTALLED tab and the cleanup program are told about the change.
--
-- Works on the merged OS file, with or without the app store and updates
-- patches applied.
--
-- Usage:  trim_patch            (patches "crabtech")
--         trim_patch myfile     (patches another file name)
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

if src:find("-- trimmed: no terminal", 1, true) then
  print("Already patched - nothing to do.")
  return
end
if not (src:find("local function actNotepad", 1, true) and src:find("local function actTerminal", 1, true)) then
  printError("This patch needs the merged OS file with the terminal and notepad tabs (crabtech.lua).")
  return
end

local ok = true
local function plain(label, old, new, optional)
  local s, t = src:find(old, 1, true)
  if not s then
    print("skipped : " .. label .. " (not found)" .. (optional and ", optional" or ""))
    if not optional then ok = false end
    return false
  end
  src = src:sub(1, s - 1) .. new .. src:sub(t + 1)
  print("patched : " .. label)
  return true
end

-- remove a whole top-level function (ends at the first "end" in column 0)
local function removeBlock(label, startMarker)
  local s = src:find(startMarker, 1, true)
  if not s then print("skipped : " .. label .. " (not found)") ok = false return end
  local _, e = src:find("\nend\n", s, true)
  if not e then print("skipped : " .. label .. " (end not found)") ok = false return end
  if src:sub(e + 1, e + 1) == "\n" then e = e + 1 end      -- swallow one blank line
  src = src:sub(1, s - 1) .. src:sub(e + 1)
  print("patched : " .. label)
end

-- remove one single-line entry from the INSTALLED tab's patch list
local function removeLine(label, needle)
  local s = src:find(needle, 1, true)
  if not s then return end
  local lineStart = s
  while lineStart > 1 and src:sub(lineStart - 1, lineStart - 1) ~= "\n" do lineStart = lineStart - 1 end
  local lineEnd = src:find("\n", s, true) or #src
  src = src:sub(1, lineStart - 1) .. src:sub(lineEnd + 1)
  print("patched : " .. label)
end

-- 1. menu buttons and their actions (both or neither)
plain("Menu buttons", '{ label = "NOTEPAD" }, { label = "TERMINAL" }, ', "")
plain("Button actions", "actNotepad, actTerminal, ", "")

-- 2. the INSTALLED tab no longer tracks the removed patches
removeLine("Installed list: terminal_patch", '{ "terminal_patch",')
removeLine("Installed list: terminal_style_patch", '{ "terminal_style_patch",')
plain("Installed list: app store text", '"app store, notepad"', '"app store"', true)

-- 3. the two screens themselves
removeBlock("Notepad", "local function actNotepad()")
removeBlock("Terminal", "-- styled terminal\nlocal function actTerminal()")

-- 4. the shared frame: keep it if something else still uses it (UPDATES), else drop it
local uses = 0
for _ in src:gmatch("runStyled") do uses = uses + 1 end
local frameStart = "-- styled frame: header, side stripe and footer around a program (terminal, notepad)\nlocal function runStyled(o)"
if src:find("local function runStyled", 1, true) then
  if uses <= 1 then
    removeBlock("Shared frame (no longer used)", frameStart)
  else
    plain("Shared frame comment", "around a program (terminal, notepad)", "around a program (patch output)", true)
  end
end

-- 5. list this patch on the INSTALLED tab, and leave a marker
do
  local s, t = src:find('{ "installed_patch",%s+"this tab",%s+function%(h%) return h%("local function " %.%. "actInstalled"%) end },')
  if s then
    src = src:sub(1, t) .. '\n    { "trim_patch",           "no terminal/notepad", function(h) return h("-- trimmed: " .. "no terminal") end },' .. src:sub(t + 1)
    print("patched : Installed list: trim_patch")
  end
end
plain("Marker", "local actions = {",
  "-- trimmed: no terminal or notepad tab (the terminal lives on the computer itself)\nlocal actions = {")

-- 6. header comment (optional)
plain("Header comment", "MEM. CARD, NOTEPAD, TERMINAL,", "MEM. CARD,", true)

-- nothing may still refer to the removed screens
if src:find("actNotepad", 1, true) or src:find("actTerminal", 1, true) then
  print("problem : something still refers to the removed screens")
  ok = false
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
print("The terminal is now only on the computer: quit the OS with Q to reach it.")
