version = 20261102.0200
local mtui = require("lib.mtui")
-- AE2 QUARTZ CLUSTER SCANNER v4.3 (Quarry Edition)
-- Date: 2026-10-13
-- Inspired by Civilwargeeky's Quarry
-- v4.3 Changes:
--   - Starter prompt (lib/LoopSetup): fuel questions answered once.
--   - Refuel: SmartFuel startup plus a fixed refuel point (fuel chest
--     side at start); evacuates home while the trip is affordable,
--     refuels, and resumes the saved position.
--   - Dump excludes the fuel/bucket slot; found fuel is staged there.
-- v4.2 Changes:
--   - Graceful stop: single Q press or Ctrl+T stops the scan and SAVES
--     progress (replaces the 3-second hold-Q abort that wiped the save).
--     Reboot or re-run to resume where it left off.
-- v4.1 Changes:
--   - Added "Q to Abort" with cleanup (removes session/startup files).
--   - Added 5s Auto-Start Timer for Resume and New Runs.
-- v4.0 Changes:
--   - Full Quarry Logic: CLI Args (-length, -width, -wait).
--   - Persistence: Resumes exactly where left off after reboot/term.
--   - Robust Movement: Coordinate-based tracking (x,z) vs relative pathing.
--   - Auto-Startup: Creates persistent startup file.
--   - Logging: Tracks runs in 'Cluster_Logs' and events in 'cluster_log.txt'.
--   - Enhanced UI: Fuel warnings, cycle count, position tracking.

local VERSION = "4.3.0"
local RESTORE_FILE = ".cluster_restore"
local LOG_FILE = "cluster_log.txt"
local LOG_DIR = "Cluster_Logs"
local cluster_startup = "startup"
local cluster_backup = "startup_old_cluster"

--------------------------------------
-- CONFIGURATION & DEFAULTS
--------------------------------------
local tArgs = { ... }
local Resume = require("lib.Resume")
local LoopSetup = require("lib.LoopSetup")
local LoopFuel = require("lib.LoopFuel")
local cfg = LoopSetup.defaults()
local tripEst = 0
-- Suppresses the per-step needEvac check during the evac movement
-- itself (the turtle is already on its way home by then).
local evacuating = false
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
    facing = 0,     -- 0=Forward, 1=Right, 2=Back, 3=Left (Relative to start)
    inventoryFull = false,
    cycleCount = 0,
    totalScanned = 0,
    isReturning = false, -- Flag if we are on the way back to start
    params = params      -- Persist params too
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

local function saveProgress()
    Resume.save(RESTORE_FILE, state)
end

--------------------------------------
-- STARTUP MANAGEMENT
--------------------------------------
local function createStartup()
    Resume.installBootResume("-- Cluster Auto-Resume", cluster_backup)
end

local function cleanupStartup()
    Resume.removeBootResume("-- Cluster Auto-Resume", cluster_backup)
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


local function drawUI()
    term.clear()
    term.setCursorPos(1,1)

    mtui.header("AE2 CLUSTER SCANNER v" .. VERSION)
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
-- PERSISTENCE
--------------------------------------
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

--------------------------------------
-- MOVEMENT SYSTEM (Coordinate Based)
--------------------------------------
-- 0: +Z (Forward relative to start)
-- 1: +X (Right)
-- 2: -Z (Back)
-- 3: -X (Left)
-- NOTE: Quarry uses different coords maybe, but we stick to:
-- Start is 0,0. Facing 0.
-- Forward increases Z. Right increases X.

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
    -- Once per step: if the trip home is barely affordable, go now.
    if not evacuating and LoopFuel.needEvac(math.abs(state.x) + math.abs(state.z)) then
        evacuating = true
        local rx, rz = state.x, state.z
        goTo(0, 0)
        turnTo(0) -- face the start direction for the stated chest/lava sides
        if not LoopFuel.refuelAtStart(cfg, 2 * tripEst) then
            -- Fixed point dry: wait at the start (reachable) for fuel items.
            if not LoopFuel.waitForFuel(cfg, 2 * tripEst) then
                saveProgress()
                error("", 0) -- user aborted with Q; progress is saved
            end
        end
        goTo(rx, rz) -- resume where we left off
        evacuating = false
    end
    while not turtle.forward() do
        -- Blocked? Dig it or kill it.
        turtle.dig()
        turtle.attack()
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
    -- Align X
    if state.x < tx then
        turnTo(1)
        while state.x < tx do forward() end
    elseif state.x > tx then
        turnTo(3)
        while state.x > tx do forward() end
    end
    
    -- Align Z
    if state.z < tz then
        turnTo(0)
        while state.z < tz do forward() end
    elseif state.z > tz then
        turnTo(2)
        while state.z > tz do forward() end
    end
end

--------------------------------------
-- INVENTORY & QUARTZ
--------------------------------------
local validQuartz = {
    ["ae2:quartz_cluster"] = true,
    ["ae2:small_quartz_bud"] = true,
    ["ae2:medium_quartz_bud"] = true,
    ["ae2:large_quartz_bud"] = true,
}

local function scanCluster()
    local has, data = turtle.inspectDown()
    if has and validQuartz[data.name] then
        log("Found "..data.name.." at "..state.x..","..state.z)
        turtle.digDown()
    end
end

local function checkInventory()
    -- Check if full
    local count = 0
    for i=1,16 do 
        if turtle.getItemCount(i) > 0 then count = count + 1 end
    end
    
    if count >= 16 then
        state.inventoryFull = true
        log("Inventory full at "..state.x..","..state.z)
        -- Return to start to dump?
        -- For now, we will handle this in the main loop or opportunistic dumping
    end
    
    -- Opportunistic dump (fuel/bucket slot excluded)
    local has, data = turtle.inspectDown()
    if has and LoopSetup.isInventory("bottom") then
        for i=1,16 do
            if i ~= cfg.bucketSlot then turtle.select(i); turtle.dropDown() end
        end
        turtle.select(1)
        state.inventoryFull = false
        LoopFuel.stage(cfg)
        log("Dumped items into storage at "..state.x..","..state.z)
    elseif has and cfg.lavaUnder and data.name:find("lava") then
        -- Lava below while traveling: fill the bucket when possible.
        LoopFuel.fillFrom(turtle.inspectDown, turtle.placeDown, cfg)
    end
end

--------------------------------------
-- LOGGING RUNS
--------------------------------------
local function logRunSummary()
    if not fs.exists(LOG_DIR) then fs.makeDir(LOG_DIR) end
    local n = 1
    while fs.exists(LOG_DIR.."/Scan_"..n..".txt") do n = n + 1 end
    
    local f = fs.open(LOG_DIR.."/Scan_"..n..".txt", "w")
    f.writeLine("Scan Summary")
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
        elseif k == "-wait" then params.waitTime = tonumber(v)
        end
    end
end

local function getArgsInteractive()
    colorPrint("Enter Scan Length:", colors.orange)
    params.length = tonumber(read())
    colorPrint("Enter Scan Width:", colors.orange)
    params.width = tonumber(read())
    colorPrint("Wait Time (seconds):", colors.orange)
    params.waitTime = tonumber(read()) or 0
end

local function scanLogic()
    state.totalScanned = 0
    state.isReturning = false
    log("Starting scan cycle "..state.cycleCount)
    
    -- Snake Pattern
    -- Rows are Width (X), Cols are Length (Z)
    -- We scan stepping Z, then turn X.
    for x = 0, state.params.width - 1 do
        -- Go to start of this col
        goTo(x, state.z)
        local targetZ = (x % 2 == 0) and (state.params.length - 1) or 0
        
        while state.z ~= targetZ do
            scanCluster()
            checkInventory()
            if state.z < targetZ then turnTo(0); forward()
            else turnTo(2); forward() end
            state.totalScanned = state.totalScanned + 1
        end
        scanCluster()
        checkInventory()
    end
    
    log("Cycle complete, returning to start")
    state.isReturning = true
    goTo(0,0)
    turnTo(0)
    -- Back at start facing the start direction: refill the bucket from
    -- the stated lava side when possible.
    LoopFuel.fillAtStart(cfg)
    
    state.cycleCount = state.cycleCount + 1
    logRunSummary()
    saveProgress()
    
    if state.params.waitTime > 0 then
        log("Waiting "..state.params.waitTime.."s")
        for i=state.params.waitTime, 1, -1 do
            term.clear()
            term.setCursorPos(1,1)
            colorPrint("Waiting: "..i.."s", colors.yellow)
            sleep(1)
        end
    end
end

local function listenForExit()
    while true do
        local ev, p1 = os.pullEvent()
        if ev == "terminate" or (ev == "key" and (p1 == keys.q or p1 == keys.enter)) then
            error("Terminated", 0)
        end
    end
end

local function runScan()
    parallel.waitForAny(scanLogic, listenForExit)
end

-- ENTRY POINT
-- ENTRY POINT
local function promptStart(resume)
    local timer = os.startTimer(5)
    local msg = resume and "Resuming" or "Starting"
    
    while true do
        term.clear()
        term.setCursorPos(1,1)
        mtui.header("AE2 CLUSTER SCANNER v" .. VERSION)
        if resume then colorPrint("Previous session restored.", colors.green) end
        
        colorPrint(msg.." in 5 seconds...", colors.yellow)
        colorPrint("Press ENTER to start immediately.", colors.green)
        colorPrint("Press Q to CANCEL and ABORT.", colors.red)
        
        local ev, p1 = os.pullEventRaw() -- Catch terminate during prompt
        if ev == "terminate" then
            fullCleanup()
            colorPrint("\nTerminated by user (Cleanup Complete).", colors.red)
            error("Terminated", 0)
        elseif ev == "timer" and p1 == timer then
            break -- Auto start
        elseif ev == "key" then
            if p1 == keys.enter then
                break -- Manual start
            elseif p1 == keys.q then
                fullCleanup()
                colorPrint("\nAborted by user (Safe Cleanup Complete).", colors.red)
                error("", 0)
            end
        end
    end
end

if loadProgress() then
    if state.setup then cfg = state.setup end
    promptStart(true)
end

if state.x == 0 and state.z == 0 and state.cycleCount == 0 then
    -- New run or reset
    if #tArgs > 0 then
        parseArgs()
    else
        getArgsInteractive()
    end
    -- Validate
    if not params.length or not params.width then
        colorPrint("Invalid arguments.", colors.red)
        return
    end
    -- Starter prompt, answered once; saved so resumes never re-ask.
    local scfg = LoopSetup.run({
        blurb = "Scans the field below for AE2 quartz clusters, digs them, dumps into chests found below.",
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
    state.params = params -- Save to state
    saveProgress()
    createStartup() -- Enable auto-resume
    promptStart(false)
end

-- One-way move estimate for a full cycle plus the trip home; ensure()
-- doubles it internally and caps at the fuel limit.
tripEst = state.params.length * state.params.width + 10

if not LoopFuel.ensure(cfg, tripEst) then
    print("Fuel wait aborted.")
    return
end

-- Main Loop
while true do
    local ok, err = pcall(runScan)
    
    if not ok then
        if err == "Terminated" then
            saveProgress()
            colorPrint("\nStopped. Progress saved; reboot or re-run to resume.", colors.green)
            return
        else
            error(err) -- Propagate other errors
        end
    end
end
