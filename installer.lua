version = 20261013.1200
-- this script fetches "updater.lua" from the github repository
-- pastebin get piTvMqye installer
local filename = "updater.lua"
-- url masked so this account is not banned by Pastebin
-- From FAQ do not post spam links (this includes promoting your own site)
local base = "https:".."//".."raw.".."githubusercontent.".."com".."/GST-4649".."/Master-Turtle".."/main/"

-- Detect version tree: "ComputerCraft 1.80pr1" -> 1.12.x, else 1.20.x
-- Prefer _MC_VERSION (e.g. "1.12.2"), since an unescaped dot in the
-- _HOST check never matched "ComputerCraft 1.89.2" (dan200 CC on 1.12.2).
local tree = "1.20.x"
local mc = _MC_VERSION or ""
if mc:find("^1%.12") or (_HOST or ""):find("1%.80") then tree = "1.12.x" end
term.setTextColor(colors.orange)
print("Master Turtle installer")
term.setTextColor(colors.white)
print("Detected: " .. (_HOST or "?") .. " -> " .. tree .. " tree.")
io.write("Correct? [Y/n]: ")
local ans = (read() or ""):lower()
if ans ~= "" and ans ~= "y" and ans ~= "yes" then
	io.write("Which tree? [1] 1.12.x  [2] 1.20.x+: ")
	local c = read() or ""
	if c:sub(1, 1) == "1" then tree = "1.12.x" else tree = "1.20.x" end
end

-- Disk space gate: the tree plus updater staging in tmp/ must fit.
-- Measured trees: 1.12.x ~1.1 MB, 1.20.x ~1.5 MB. Require 2.5 MB / 3.5 MB
-- (tree + tmp staging + margin).
local need = tree == "1.12.x" and 2621440 or 3670016
local free = fs.getFreeSpace("/") or 0
if free < need then
	term.setTextColor(colors.red)
	print("Not enough disk space. Master Turtle is massive and this turtle's disk limit is too low.")
	print("")
	print("To raise the limit, edit .minecraft/config/computercraft-server.toml")
	print("(on a dedicated server: <server folder>/config/computercraft-server.toml),")
	print("find the computer_space_limit line and add zeroes to the end of the number:")
	if tree == "1.12.x" then
		print("on 1.12.x add TWO zeroes (1000000 becomes 100000000).")
	else
		print("on 1.20.x add ONE zero (10000000 becomes 100000000).")
	end
	print("")
	print("Then restart the game and rerun the installer.")
	term.setTextColor(colors.white)
	error("Aborted: not enough disk space.", 0)
end

term.setTextColor(colors.lime)
print("Disk space check passed. Plenty of room for Master Turtle.")
term.setTextColor(colors.white)

local url = base .. tree .. "/" .. filename

-- Request download script from GitHub
local response, message = http.get(url)
if response == nil then
	error("Repository content request failed: " .. message)
end

local data = response.readAll()
response.close()

if data == nil then
	error("Download script not found!")
end

-- Write to updater.new first and validate it before touching the old
-- updater, so a truncated download never leaves no working updater.
if fs.exists("updater.new") then
	fs.delete("updater.new")
end

-- Try creating new file
local f = fs.open("updater.new", "w")
if f == nil then
	error("Could not open file!")
end

-- Save new file
f.write(data)
f.close()

assert(loadfile("updater.new"), "bad updater download")

-- Replace the old updater only after the download validated
if fs.exists(filename) then
	fs.delete(filename)
end
fs.move("updater.new", filename)

print("Running updater...")
-- Run download script
shell.run(filename:sub(0, -5))
