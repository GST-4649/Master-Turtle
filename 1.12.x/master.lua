local version = 20261108.2320
-- Master Turtle launcher v1.0
-- Unified native term menu for every program in the Master Turtle pack.
-- No SceneMgr, no lib/ui in the launcher path. Toolkit v3 still boots
-- its own scene system when run as a program, unchanged.
-- Select a program, answer any dimension prompts, and it runs;
-- when it exits you return here. Run at boot via startup.lua.

local unpack = table.unpack or unpack

local Launcher = require("scenes.Launcher")

local w, h = term.getSize()
_G.WIDTH = w
_G.HEIGHT = h

-- Program registry.
--   prog: file to shell.run (extensionless names work)
--   name: short display name
--   desc: one-line description
--   cat: launcher category, Build, Gather, Action, Refuel, Tools, Pinned
--   loop: true = intentional run-until-stopped program
--   dims: dimension prompts; each is {flag, label} and becomes
--         command-line args. A dim with triple=true takes three
--         numbers from one box (the quarry's -dim L W H).
--   gate: entry is listed only when fs.exists(gate) is true
_G.MasterTurtle = {
    version = version,
    programs = {
        { prog = "quarry-ui", name = "Quarry", cat = "Pinned",
          desc = "Massive quarry (civilwargeeky), crash-proof resume, via quarry-ui preset builder" },
        { prog = "builder", name = "Builder", cat = "Build",
          desc = "Builder: floor/walls/solid/hollow/roof/wall/frame/shell/fill/torch",
          dims = {
            { flag = "-length", label = "Length (Z)" },
            { flag = "-width", label = "Width (X)" },
            { flag = "-mode", label = "Mode" },
            { flag = "-height", label = "Height" },
            { flag = "-inverted", label = "Inverted" },
            { flag = "-depth", label = "Depth (X)" },
            { flag = "-size", label = "Size (N)" },
            { flag = "-spacing", label = "Spacing" },
          },
          -- Mode-first dialog: pick the mode, then only its fields
          -- are asked. Torch keeps torcher's own axis wording,
          -- length X and width Z, unlike the rest.
          modeDims = {
            floor = { "-length", "-width", "-inverted" },
            walls = { "-length", "-width", "-height", "-inverted" },
            solid = { "-length", "-width", "-height", "-inverted" },
            hollow = { "-length", "-width", "-height", "-inverted" },
            roof = { "-length", "-width", "-height", "-inverted" },
            wall = { "-length", "-height", "-depth" },
            frame = { "-size" },
            shell = { "-size" },
            fill = { "-length", "-width" },
            torch = { "-length", "-width", "-spacing" },
          },
          modeLabels = {
            torch = { ["-length"] = "Length (X)", ["-width"] = "Width (Z)" },
          } },
        { prog = "cropper", name = "Cropper", cat = "Gather",
          desc = "Auto crop farmer, replants as it goes",
          dims = {
            { flag = "-length", label = "Field length" },
            { flag = "-width", label = "Field width" },
          } },
        { prog = "cluster", name = "Cluster Scanner", cat = "Gather",
          desc = "AE2 quartz cluster scanner", loop = true,
          dims = {
            { flag = "-length", label = "Scan length" },
            { flag = "-width", label = "Scan width" },
          } },
        { prog = "vacuum", name = "Vacuum", cat = "Gather",
          desc = "Floor sweeper, sucks up loose items",
          dims = {
            { flag = "-length", label = "Area length" },
            { flag = "-width", label = "Area width" },
          } },
        { prog = "blockman", name = "Block Manager", cat = "Tools",
          desc = "View/edit allowed building blocks" },
        { prog = "chopchop", name = "ChopChop", cat = "Gather",
          desc = "Tree chopper", loop = true },
        { prog = "cranker", name = "Cranker", cat = "Action",
          desc = "Create hand crank driver: simulates player right-click via turtle.place, one click every 8 ticks (32 RPM max)", loop = true },
        { prog = "attack", name = "Attacker", cat = "Action",
          desc = "Auto attacker, weapon select", loop = true },
        { prog = "cobble", name = "Cobble Miner", cat = "Gather",
          desc = "Infinite miner, dumps to chests", loop = true },
        { prog = "flint", name = "Flint Maker", cat = "Action",
          desc = "Turns gravel into flint" },
        { prog = "buckRef", name = "Bucket Refuel", cat = "Refuel",
          desc = "Refuels from any filled bucket" },
        { prog = "lavaRefuel", name = "Lava Refuel", cat = "Refuel",
          desc = "Refuels on a lava lake" },
        { prog = "go", name = "Go Driver", cat = "Tools",
          desc = "Interactive WASD turtle driver" },
        { prog = "data", name = "Data", cat = "Tools",
          desc = "Block and item inspector" },
        { prog = "movehelp", name = "Move cmds", cat = "Tools",
          desc = "b/d/f/u/l/r/p/x: shell movement commands",
          info = "Shell commands (type at the shell, not here):\n"
              .. "  b/d/f/u <n> [d]  move back/down/forward/up n blocks\n"
              .. "                   add any 2nd arg to dig through\n"
              .. "  f <n> +-         forward, also dig above/below\n"
              .. "  l/r <n>          turn left/right n times\n"
              .. "  p [u|d]          place block forward/up/down\n"
              .. "  x [u|d]          dig forward/up/down" },
        { prog = "tk3", name = "Toolkit v3", cat = "Pinned",
          desc = "Inksaver GUI toolkit (classic)",
          gate = "tk3.lua" },
        { prog = "cc-ai", name = "AI Chat", cat = "Pinned",
          desc = "Chat with an AI (needs the cc-ai server)",
          gate = "cc-ai", scene = "CCAI" },
        { prog = "updater", name = "Updater", cat = "Pinned",
          desc = "Reinstall / update this pack from GitHub" },
    },
}

-- Run a program outside the launcher, then come back.
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
    local ok, err = shell.run(launch.prog, unpack(launch.args or {}))
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

while true do
    local action = Launcher.run(_G.MasterTurtle.programs)
    if not action or action.action == "quit" then
        break
    elseif action.action == "launch" and action.launch then
        runProgram(action.launch)
    end
end

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
print("Master Turtle closed.")
