version = 20261102.0200
local mtui = require("lib.mtui")
-- CROPPER v0.4 BETA (Quarry Edition)
-- Date: 2026-10-13
-- Inspired by Civilwargeeky's Quarry & AE2 Cluster Scanner
-- v0.4 Changes:
--   - Starter prompt (lib/LoopSetup): fuel questions answered once.
--   - Refuel: burns tagged fuel found while working, or a lava bucket
--     in slot 16 (lava side at start, or lava below while traveling),
--     instead of spinning forever at 0 fuel.
--   - Dump excludes the fuel/bucket slot; found fuel is staged there.
--   - Stop now SAVES progress (like the cluster scanner) instead of
--     wiping the session; single Q press or Ctrl+T.
--   - Cropper rework (20261013.1200): 15-point field workflow; the storage
--     dump takes everything including seeds; inventory-full returns to
--     start at the same Y, deposits, and resumes the saved field position;
--     night wait with epoch day-wrap; fixed-point refuel through LoopFuel
--     (2x SmartFuel, fuel-chest prompt added).
-- v0.3 Changes:
--   - Full Quarry Logic: CLI Args (-length, -width, -wait).
--   - Persistence: Resumes exactly where left off.
--   - Robust Movement: Coordinate-based tracking (x,z).
--   - Auto-Startup: Creates persistent startup file.
--   - Strict Cleanup: Q to Abort deletes all temp files (logs, startup, restore).
--   - Farming: Harvests mature crops (age >= 7) and replants.

local VERSION = "0.4 Beta"
local RESTORE_FILE = ".cropper_restore"
local LOG_FILE = "cropper_log.txt"
local LOG_DIR = "Cropper_Logs"
local cluster_startup = "startup"
local cluster_backup = "startup_old_cropper"

--------------------------------------
-- CONFIGURATION & DEFAULTS
--------------------------------------
local tArgs = { ... }
local Resume = require("lib.Resume")
local LoopSetup = require("lib.LoopSetup")
local LoopFuel = require("lib.LoopFuel")
local cfg = LoopSetup.defaults()
local tripEst = 0
local params = {
    length = 0,
    width = 0,
    waitTime = 0,
    startDelay = 3,
    debug = false
}

-- Current State (Persisted)
local state = {
    x = 0,
    z = 0,
    facing = 0,     -- 0=Forward, 1=Right, 2=Back, 3=Left
    inventoryFull = false,
    cycleCount = 0,
    totalScanned = 0,
    isReturning = false,
    params = params
}

--------------------------------------
-- LOGGING & UI
--------------------------------------
local function log(message)
    local f = fs.open(LOG_FILE, "a")
    if f then
        f.writeLine("["..os.day().."-"..textutils.formatTime(os.time(), true).."] "..message)
        f.close()
    end
end

local function colorPrint(message, color)
    if term.isColor() then term.setTextColor(color) end
    print(message)
    if term.isColor() then term.setTextColor(colors.white) end
end

local function drawUI()
    term.clear()
    term.setCursorPos(1,1)

    mtui.header("CROPPER v" .. VERSION)
    print(string.rep("=",30))

    colorPrint("Cycle: "..state.cycleCount, colors.orange)
    colorPrint("Scanned: "..state.totalScanned, colors.orange)
    print("Pos: "..state.x..","..state.z.." Facing: "..state.facing)

    local fuel = turtle.getFuelLevel()
    local fuelMax = turtle.getFuelLimit()
    io.write("Fuel: ")
    if fuel < 500 then
        colorPrint(fuel.." (LOW)", colors.red)
    else
        colorPrint(fuel.." / "..fuelMax, colors.green)
    end
    
    colorPrint("Press Q (or Ctrl+T) to stop; progress is saved", colors.red)

    if state.isReturning then
        colorPrint(">> RETURNING TO START <<", colors.orange)
    else
        local total = state.params.length * state.params.width
        local percent = 0
        if total > 0 then
            percent = math.floor((state.totalScanned / total) * 100)
        end

        print(mtui.progress(percent))
    end

    print(string.rep("=",30))
end

--------------------------------------
-- PERSISTENCE & CLEANUP
--------------------------------------
local function saveProgress()
    Resume.save(RESTORE_FILE, state)
end

local function loadProgress()
    local data = Resume.load(RESTORE_FILE)
    if data then
        state = data
        state.params = state.params or { length = 0, width = 0, waitTime = 0 }
        if not state.params.waitTime then state.params.waitTime = 0 end
        return true
    end
    return false
end

local function createStartup()
    Resume.installBootResume("-- Cropper Auto-Resume", cluster_backup)
end

local function cleanupStartup()
    Resume.removeBootResume("-- Cropper Auto-Resume", cluster_backup)
end

local function fullCleanup()
    -- 1. Delete Restore File
    Resume.clear(RESTORE_FILE)
    
    -- 2. Cleanup Startup
    cleanupStartup()
    
    -- 3. Delete Log File
    if fs.exists(LOG_FILE) then fs.delete(LOG_FILE) end
    
    -- 4. Delete Log Directory Contents (Keep Folder)
    if fs.exists(LOG_DIR) and fs.isDir(LOG_DIR) then
        local files = fs.list(LOG_DIR)
        for _, file in ipairs(files) do
            fs.delete(fs.combine(LOG_DIR, file))
        end
    end
end

--------------------------------------
-- MOVEMENT SYSTEM (Coordinate Based)
--------------------------------------
local function turnRight()
    turtle.turnRight()
    state.facing = (state.facing + 1) % 4
    saveProgress()
    drawUI()
end

local function turnLeft()
    turtle.turnLeft()
    state.facing = (state.facing + 3) % 4
    saveProgress()
    drawUI()
end

local function turnTo(targetFace)
    local diff = (targetFace - state.facing) % 4
    if diff == 1 then turnRight()
    elseif diff == 2 then turnRight(); turnRight()
    elseif diff == 3 then turnLeft()
    end
end

local function forward()
    while not turtle.forward() do
        if turtle.getFuelLevel() == 0 then
            -- Out of fuel: burn tagged fuel or use the bucket. If that
            -- fails too, stop (progress is saved by the error handler).
            if not LoopFuel.ensure(cfg, tripEst) then
                log("Out of fuel at "..state.x..","..state.z)
                colorPrint("OUT OF FUEL", colors.red)
                error("Terminated", 0)
            end
        else
            turtle.dig(); turtle.attack()
        end
    end
    
    if state.facing == 0 then state.z = state.z + 1
    elseif state.facing == 1 then state.x = state.x + 1
    elseif state.facing == 2 then state.z = state.z - 1
    elseif state.facing == 3 then state.x = state.x - 1
    end
    saveProgress()
    drawUI()
end

local function goTo(tx, tz)
    if state.x < tx then turnTo(1); while state.x < tx do forward() end
    elseif state.x > tx then turnTo(3); while state.x > tx do forward() end end
    
    if state.z < tz then turnTo(0); while state.z < tz do forward() end
    elseif state.z > tz then turnTo(2); while state.z > tz do forward() end end
end

--------------------------------------
-- FARMING LOGIC
--------------------------------------
local crops = {
    vanilla = {
        ["minecraft:wheat"] = true,
        ["minecraft:carrots"] = true,
        ["minecraft:potatoes"] = true,
        ["minecraft:beetroots"] = true
    },
    modded = {
        ["thermal:rice"] = true,
    }
}

-- Mature age per crop: beetroots finish at 3, the rest at 7.
local maxAge = {
    ["minecraft:wheat"] = 7,
    ["minecraft:carrots"] = 7,
    ["minecraft:potatoes"] = 7,
    ["minecraft:beetroots"] = 3,
    ["thermal:rice"] = 7,
}

local seeds = {
    vanilla = {
        ["minecraft:wheat"] = "minecraft:wheat_seeds",
        ["minecraft:carrots"] = "minecraft:carrot",
        ["minecraft:potatoes"] = "minecraft:potato",
        ["minecraft:beetroots"] = "minecraft:beetroot_seeds"
    },
    modded = {
        ["thermal:rice"] = "thermal:rice_seeds",
    }
}

local function seedForCrop(name)
    return seeds.vanilla[name] or seeds.modded[name]
end

local function findSeedSlot(seedItem)
    if not seedItem then return nil end
    for s=1,16 do
        local d = turtle.getItemDetail(s)
        if d and d.name == seedItem then return s end
    end
    return nil
end

-- All known seed items, vanilla + modded; used to plant empty farmland.
local function allSeedItems()
    local items = {}
    for _, seed in pairs(seeds.vanilla) do items[#items + 1] = seed end
    for _, seed in pairs(seeds.modded) do items[#items + 1] = seed end
    return items
end

local function findAnySeedSlot()
    local items = allSeedItems()
    for s=1,16 do
        local d = turtle.getItemDetail(s)
        if d and d.name then
            for _, seed in ipairs(items) do
                if d.name == seed then return s end
            end
        end
    end
    return nil
end

local function inventoryCount()
    local n = 0
    for i=1,16 do if turtle.getItemCount(i) > 0 then n = n + 1 end end
    return n
end

-- Set when the deposit at start fails, so a full inventory does not bounce
-- the turtle home once per cell for the rest of the pass.
local suppressFull = false

-- One cell of the field workflow: check below; dump into an inventory below
-- (everything, seeds included; replanting runs off the fresh harvest at each
-- cell, so protecting seed slots only clogs slots); identify a crop below
-- and check maturity; harvest the mature crop; suck up the drops; replant
-- the corresponding seed or tuber.
local function workCell()
    local has, data = turtle.inspectDown()
    local belowName = (has and data and data.name) or nil
    if has and LoopSetup.isInventory("bottom") then
        for i=1,16 do
            if i ~= cfg.bucketSlot then
                turtle.select(i)
                turtle.dropDown()
            end
        end
        turtle.select(1)
        state.inventoryFull = false
        LoopFuel.stage(cfg)
        log("Dumped items into storage at "..state.x..","..state.z..
            ", epoch "..os.epoch("ingame"))
    elseif has and cfg.lavaUnder and belowName and belowName:find("lava") then
        -- Lava below while traveling: fill the bucket when possible.
        LoopFuel.fillFrom(turtle.inspectDown, turtle.placeDown, cfg)
    elseif belowName and (crops.vanilla[belowName] or crops.modded[belowName])
        and data.state and data.state.age
        and data.state.age >= (maxAge[belowName] or 7) then
        log("Harvesting "..belowName.." at "..state.x..","..state.z)
        turtle.digDown()
        turtle.suckDown()
        local slot = findSeedSlot(seedForCrop(belowName))
        if slot then
            turtle.select(slot)
            turtle.placeDown()
            turtle.select(1)
        end
    elseif belowName == "minecraft:farmland" then
        -- Empty farmland: plant any known seed from inventory.
        local slot = findAnySeedSlot()
        if slot then
            turtle.select(slot)
            turtle.placeDown()
            turtle.select(1)
        end
    end
    if not suppressFull and inventoryCount() >= 16 then
        state.inventoryFull = true
        log("Inventory full at "..state.x..","..state.z)
    end
end

-- Deposit everything (bucket slot excluded) into an inventory adjacent to
-- the start block. Returns true when a deposit inventory was found.
local function depositAtStart()
    local side = LoopSetup.findInventory("bottom")
    if not side then
        log("No deposit inventory at start")
        return false
    end
    LoopSetup.dropToward(side, function(i) return i ~= cfg.bucketSlot end)
    LoopFuel.stage(cfg)
    log("Deposited at start via "..side..", epoch "..os.epoch("ingame"))
    return true
end

-- Inventory full with no dump chest nearby: save the field position, return
-- to start at the same Y (this program never changes Y), deposit, and resume
-- the saved field position.
local function returnDepositResume()
    local sx, sz, sf = state.x, state.z, state.facing
    log("Inventory full, returning to start for deposit, epoch "..os.epoch("ingame"))
    state.isReturning = true
    saveProgress()
    goTo(0, 0)
    local deposited = depositAtStart()
    state.isReturning = false
    if inventoryCount() >= 16 then
        if not suppressFull then
            suppressFull = true
            if deposited then
                log("Deposit inventory full; continuing with a full inventory")
            else
                log("No deposit inventory at start; continuing with a full inventory")
            end
            colorPrint("WARNING: deposit at start failed", colors.red)
        end
    end
    state.inventoryFull = false
    goTo(sx, sz)
    turnTo(sf)
    saveProgress()
end

-- Called when the inventory is full: dump into a nearby inventory when one
-- is found quickly, else return to start at the same Y and resume.
local function handleFull()
    if not state.inventoryFull then return end
    local side = LoopSetup.findInventory("bottom")
    if side then
        local moved = LoopSetup.dropToward(side, function(i) return i ~= cfg.bucketSlot end)
        LoopFuel.stage(cfg)
        if moved then
            state.inventoryFull = inventoryCount() >= 16
            log("Dumped into nearby inventory ("..side..") at "..
                state.x..","..state.z..", epoch "..os.epoch("ingame"))
            return
        end
        -- Nothing moved: the nearby chest is full. Fall through to start.
    end
    returnDepositResume()
end

-- Once-per-cell fuel check: head home while the trip is still affordable,
-- refuel at the fixed point, resume the saved field position. Y never
-- changes. A user-aborted fuel wait saves and quits quietly.
local function fuelCheck()
    if not LoopFuel.needEvac(math.abs(state.x) + math.abs(state.z)) then return end
    local sx, sz, sf = state.x, state.z, state.facing
    state.isReturning = true
    saveProgress()
    log("Fuel low at "..sx..","..sz.."; evacuating to start, epoch "..os.epoch("ingame"))
    goTo(0, 0)
    local ok = LoopFuel.refuelAtStart(cfg, 2 * tripEst)
    if not ok then
        -- Fixed point dry: wait at the start (reachable) for fuel items.
        ok = LoopFuel.waitForFuel(cfg, 2 * tripEst)
    end
    state.isReturning = false
    if not ok then
        saveProgress()
        error("", 0)
    end
    goTo(sx, sz)
    turnTo(sf)
    saveProgress()
end

-- One Minecraft day is 24000 ticks; os.epoch("ingame") is game time in ms.
local DAY_MS = 1200000

local function isNightTick()
    return (math.floor(os.epoch("ingame") / 50) % 24000) >= 12000
end

-- Wait for nightfall so crops regrow before the next pass. If the day
-- already wrapped while this pass ran, continue instead of waiting for
-- another night. Day wrap is epoch math, never clock subtraction.
local function waitForNight(passStart)
    if math.floor(os.epoch("ingame") / DAY_MS) > math.floor(passStart / DAY_MS) then
        log("Day wrapped during the pass; skipping the night wait")
        return
    end
    if isNightTick() then
        log("Already night; starting the next pass")
        return
    end
    log("Waiting for nightfall")
    while not isNightTick() do
        sleep(5)
    end
    log("Nightfall reached; starting the next pass")
end

--------------------------------------
-- LOGGING RUNS
--------------------------------------
local function logRunSummary()
    if not fs.exists(LOG_DIR) then fs.makeDir(LOG_DIR) end
    local n = 1
    while fs.exists(LOG_DIR.."/Run_"..n..".txt") do n = n + 1 end
    
    local f = fs.open(LOG_DIR.."/Run_"..n..".txt", "w")
    f.writeLine("Run Summary")
    f.writeLine("============")
    f.writeLine("Dimensions: "..state.params.length.."x"..state.params.width)
    f.writeLine("Time: "..textutils.formatTime(os.time(), true))
    f.writeLine("Total Scanned: "..state.totalScanned)
    f.close()
end

--------------------------------------
-- MAIN LOGIC
--------------------------------------
local function parseArgs()
    for i=1, #tArgs, 2 do
        local k = tArgs[i]
        local v = tArgs[i+1]
        if k == "-length" then params.length = tonumber(v)
        elseif k == "-width" then params.width = tonumber(v)
        end
    end
end

local function getArgsInteractive()
    colorPrint("Enter Field Length:", colors.orange)
    params.length = tonumber(read())
    colorPrint("Enter Field Width:", colors.orange)
    params.width = tonumber(read())
end

local function scanLogic()
    state.totalScanned = 0
    state.isReturning = false
    suppressFull = false
    -- The turtle hovers one block above the field for the whole pass.
    -- Return and resume move in x/z only; Y never changes (breaks crops).
    local passStart = os.epoch("ingame")
    log("Pass start, epoch "..passStart)

    for x = 0, state.params.width - 1 do
        goTo(x, state.z)
        local targetZ = (x % 2 == 0) and (state.params.length - 1) or 0

        while state.z ~= targetZ do
            workCell()
            handleFull()
            fuelCheck()
            if state.z < targetZ then turnTo(0); forward()
            else turnTo(2); forward() end
            state.totalScanned = state.totalScanned + 1
        end
        workCell()
        handleFull()
        fuelCheck()
    end

    -- Field done: return to start at the same Y, refuel at the fixed point,
    -- then wait for nightfall before the next pass.
    log("Pass finish, epoch "..os.epoch("ingame"))
    state.isReturning = true
    goTo(0,0)
    turnTo(0)
    if not LoopFuel.refuelAtStart(cfg, 2 * tripEst) then
        -- Fixed point dry: wait at the start (reachable) for fuel items.
        if not LoopFuel.waitForFuel(cfg, 2 * tripEst) then
            saveProgress()
            error("", 0) -- quiet quit; the fuel wait was aborted by the user
        end
    end

    state.cycleCount = state.cycleCount + 1
    logRunSummary()
    saveProgress()

    waitForNight(passStart)
end

local function listenForExit()
    while true do
        local ev, p1 = os.pullEvent()
        if ev == "terminate" or (ev == "key" and p1 == keys.q) then
            error("Terminated", 0)
        end
    end
end

local function runScan()
    parallel.waitForAny(scanLogic, listenForExit)
end

-- Returns false when the user aborts with Q; the caller then exits cleanly
-- so the MT launcher menu resumes (no error to the shell).
local function promptStart(resume)
    local msg = resume and "Resuming" or "Starting"
    local count = 5

    while count > 0 do
        term.clear()
        term.setCursorPos(1,1)
        mtui.header("CROPPER v" .. VERSION)
        if resume then colorPrint("Previous session restored.", colors.green) end

        colorPrint(msg.." in "..count.." seconds...", colors.yellow)
        colorPrint("Press ENTER to start immediately.", colors.green)
        colorPrint("Press Q to CANCEL and ABORT.", colors.red)

        local timer = os.startTimer(1)
        local ev, p1 = os.pullEventRaw() -- Catch terminate during prompt
        if ev == "terminate" then
            fullCleanup()
            colorPrint("\nTerminated by user (Cleanup Complete).", colors.red)
            error("Terminated", 0)
        elseif ev == "timer" and p1 == timer then
            count = count - 1
        elseif ev == "key" then
            if p1 == keys.enter then break
            elseif p1 == keys.q then
                fullCleanup()
                colorPrint("\nAborted by user (Safe Cleanup Complete).", colors.red)
                return false
            end
        end
    end
    return true
end

if loadProgress() then
    if state.setup then cfg = state.setup end
    if not promptStart(true) then return end
end

if state.x == 0 and state.z == 0 and state.cycleCount == 0 then
    if #tArgs > 0 then parseArgs() else getArgsInteractive() end
    if not params.length or not params.width then
        colorPrint("Invalid arguments.", colors.red)
        return
    end
    -- Starter prompt, answered once; saved so resumes never re-ask.
    local scfg = LoopSetup.run({
        blurb = "Farms the field below: harvests mature crops, replants, dumps into chests found below.",
        fuel = true,
        fuelTags = true,
        fuelChest = true,
        lava = true,
        bucketSlot = 16,
    })
    if not scfg then
        colorPrint("Setup aborted.", colors.red)
        return
    end
    cfg = scfg
    state.setup = scfg
    state.params = params
    saveProgress()
    createStartup()
    if not promptStart(false) then return end
end

-- One-way trip estimate; ensure() doubles it internally (2x SmartFuel).
tripEst = state.params.length * state.params.width + 10

if not LoopFuel.ensure(cfg, tripEst) then
    print("Not enough fuel to start.")
    return
end

while true do
    local ok, err = pcall(runScan)

    if not ok then
        if err == "Terminated" or err == "" then
            saveProgress()
            colorPrint("\nStopped. Progress saved; reboot or re-run to resume.", colors.green)
            return
        else
            error(err) -- Propagate other errors
        end
    end
end
