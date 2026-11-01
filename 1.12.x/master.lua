local version = 20261101.0200
-- Master Turtle launcher v1.0
-- Unified GUI menu for every program in the Master Turtle pack.
-- Built on the Inksaver lib/ui + scenes framework.
-- Select a program, answer any dimension prompts, and it runs;
-- when it exits you return here. Run at boot via startup.lua.

local unpack = table.unpack or unpack

-- Globals required by the lib/ui + scenes framework
_G.U = require("lib.TurtleUtils")
local Event = require("lib.Events")
local SceneMgr = require("lib.SceneMgr")
_G.events = Event(false)

local w, h = term.getSize()
_G.WIDTH = w
_G.HEIGHT = h

-- Program registry.
--   prog: file to shell.run (extensionless names work)
--   name: short display name
--   desc: one-line description
--   loop: true = intentional run-until-stopped program
--   dims: dimension prompts; each is {flag, label} and becomes
--         command-line args. A dim with triple=true takes three
--         numbers from one box (the quarry's -dim L W H).
--   gate: entry is listed only when fs.exists(gate) is true
_G.MasterTurtle = {
    version = version,
    programs = {
        { prog = "quarry-ui", name = "Quarry",
          desc = "Massive quarry (civilwargeeky), crash-proof resume, via quarry-ui preset builder" },
        { prog = "platformer", name = "Platformer",
          desc = "Builder: floor/walls/solid/hollow/roof",
          dims = {
            { flag = "-length", label = "Length (Z)" },
            { flag = "-width", label = "Width (X)" },
            { flag = "-mode", label = "Mode (floor/walls/solid/hollow/roof)" },
            { flag = "-height", label = "Height: layers (blocks-up for roof)" },
            { flag = "-inverted", label = "Inverted (true/false)" },
          } },
        { prog = "cropper", name = "Cropper",
          desc = "Auto crop farmer, replants as it goes",
          dims = {
            { flag = "-length", label = "Field length" },
            { flag = "-width", label = "Field width" },
          } },
        { prog = "cluster", name = "Cluster Scanner",
          desc = "AE2 quartz cluster scanner", loop = true,
          dims = {
            { flag = "-length", label = "Scan length" },
            { flag = "-width", label = "Scan width" },
          } },
        { prog = "filler", name = "Filler",
          desc = "Fills an area with falling blocks",
          dims = {
            { flag = "-length", label = "Area length (Z)" },
            { flag = "-width", label = "Area width (X)" },
          } },
        { prog = "vacuum", name = "Vacuum",
          desc = "Floor sweeper, sucks up loose items",
          dims = {
            { flag = "-length", label = "Area length" },
            { flag = "-width", label = "Area width" },
          } },
        { prog = "trump", name = "TRMP",
          desc = "Layered wall builder (snake pattern)",
          dims = {
            { flag = "-length", label = "Wall length (X)" },
            { flag = "-height", label = "Wall height" },
            { flag = "-depth", label = "Wall thickness" },
          } },
        { prog = "framer", name = "Framer",
          desc = "Hollow room shell or edge frame",
          dims = { { flag = "-size", label = "Cube size (N)" } } },
        { prog = "blockman", name = "Block Manager",
          desc = "View/edit allowed building blocks" },
        { prog = "chopchop", name = "ChopChop",
          desc = "Tree chopper", loop = true },
        { prog = "cranker", name = "Cranker",
          desc = "Create hand crank driver: simulates player right-click via turtle.place, one click every 8 ticks (32 RPM max)", loop = true },
        { prog = "attack", name = "Attacker",
          desc = "Auto attacker, weapon select", loop = true },
        { prog = "cobble", name = "Cobble Miner",
          desc = "Infinite miner, dumps to chests", loop = true },
        { prog = "flint", name = "Flint Maker",
          desc = "Turns gravel into flint" },
        { prog = "buckRef", name = "Bucket Refuel",
          desc = "Refuels from any filled bucket" },
        { prog = "lavaRefuel", name = "Lava Refuel",
          desc = "Refuels on a lava lake" },
        { prog = "go", name = "Go Driver",
          desc = "Interactive WASD turtle driver" },
        { prog = "data", name = "Data",
          desc = "Block and item inspector" },
        { prog = "movehelp", name = "Move cmds",
          desc = "b/d/f/u/l/r/p/x: shell movement commands",
          info = "Shell commands (type at the shell, not here):\n"
              .. "  b/d/f/u <n> [d]  move back/down/forward/up n blocks\n"
              .. "                   add any 2nd arg to dig through\n"
              .. "  f <n> +-         forward, also dig above/below\n"
              .. "  l/r <n>          turn left/right n times\n"
              .. "  p [u|d]          place block forward/up/down\n"
              .. "  x [u|d]          dig forward/up/down" },
        { prog = "tk3", name = "Toolkit v3",
          desc = "Inksaver GUI toolkit (classic)",
          gate = "tk3.lua" },
        { prog = "cc-ai", name = "AI Chat",
          desc = "Chat with an AI (needs the cc-ai server)",
          gate = "cc-ai", scene = "CCAI" },
        { prog = "updater", name = "Updater",
          desc = "Reinstall / update this pack from GitHub" },
    },
}

-- Run a program outside the GUI event dispatch, then come back.
local function runProgram(launch)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    if launch.info then
        print(launch.info)
        print("")
        print("Press Enter to return.")
        read()
        return
    end
    print("Running: " .. launch.prog)
    if launch.args and #launch.args > 0 then
        print("Args: " .. table.concat(launch.args, " "))
    end
    print("")
    local saveSm, saveEv = _G.sm, _G.events
    local ok, err = shell.run(launch.prog, unpack(launch.args or {}))
    _G.sm, _G.events = saveSm, saveEv
    print("")
    if not ok then
        print("Exited with error: " .. tostring(err))
    else
        print("Done.")
    end
    print("Press Enter to return to the menu.")
    read()
end

_G.MasterTurtle.runProgram = runProgram

-- Boot
_G.sm = SceneMgr("scenes", { "Launcher", "Dimensions", "CCAI" })
_G.sm:switch("Launcher")

while true do
    local e = { os.pullEvent() }
    _G.sm:update(e)
    _G.sm:draw()
    local launch = _G.MasterTurtle.launch
    if launch then
        _G.MasterTurtle.launch = nil
        runProgram(launch)
        _G.sm:switch("Launcher")
    end
    if _G.MasterTurtle.quit then
        break
    end
end

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
print("Master Turtle closed.")
