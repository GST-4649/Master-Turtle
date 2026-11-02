version = 20261102.0200
local mtui = require("lib.mtui")
-- FILLER v1.0
-- Date: 2025-12-17
-- Adapted from Platformer v5.0
-- Objective: Fill columns with falling blocks (sand, gravel, etc.)

local VERSION = "1.0"
local RESTORE_FILE = ".filler_restore"
local LOG_FILE = "filler_log.txt"
local filler_backup = "startup_old_filler"

-- Embedded table of falling blocks
local fallingBlocks = {
    ["minecraft:sand"] = true,
    ["minecraft:red_sand"] = true,
    ["minecraft:gravel"] = true,
    ["minecraft:suspicious_sand"] = true,
    ["minecraft:suspicious_gravel"] = true,
    ["minecraft:concrete_powder"] = true -- All colors of powder fall
}

local function isFallingBlock(name)
    if not name then return false end
    local id = name:lower()
    if fallingBlocks[id] then return true end
    -- Catch all concrete powder
    if id:find("concrete_powder") then return true end
    return false
end

--------------------------------------
-- CONFIGURATION & DEFAULTS
--------------------------------------
local tArgs = { ... }
local Resume = require("lib.Resume")
local LoopSetup = require("lib/LoopSetup")
local LoopFuel = require("lib/LoopFuel")

-- Fuel state: assigned once at startup (or safe defaults on resume).
local cfg = nil   -- LoopSetup answers (fuel chest side, lava, tags)
local tripEst = 0 -- one-way fuel estimate: block count + travel margin
local checkFuel   -- proactive fuel evac; defined below with the refill code
local params = {
    length = 0,
    width = 0,
    debug = false
}

-- Current State (Persisted)
local state = {
    x = 0,
    z = 0,
    facing = 0,     -- 0=Forward (+Z), 1=Right (+X), 2=Back (-Z), 3=Left (-X)
    built = 0,
    isReturning = false,
    params = params
}

--------------------------------------
-- LOGGING & HELPER FUNCTIONS
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

local function loadProgress()
    local data = Resume.load(RESTORE_FILE)
    if data then
        state = data
        return true
    end
    return false
end

--------------------------------------
-- STARTUP & CLEANUP
--------------------------------------
local function createStartup()
    Resume.installBootResume("-- Filler Auto-Resume", filler_backup)
end

local function cleanupStartup()
    Resume.removeBootResume("-- Filler Auto-Resume", filler_backup)
end

local function fullCleanup()
    Resume.clear(RESTORE_FILE)
    cleanupStartup()
    if fs.exists(LOG_FILE) then fs.delete(LOG_FILE) end
end

--------------------------------------
-- MOVEMENT (Coordinate System)
--------------------------------------
local function turnRight()
    turtle.turnRight()
    state.facing = (state.facing + 1) % 4
    saveProgress()
end

local function turnLeft()
    turtle.turnLeft()
    state.facing = (state.facing + 3) % 4
    saveProgress()
end

local function turnTo(targetFace)
    local diff = (targetFace - state.facing) % 4
    if diff == 1 then turnRight()
    elseif diff == 2 then turnRight(); turnRight()
    elseif diff == 3 then turnLeft()
    end
end

local function forward()
    checkFuel() -- proactive fuel evac; replaces the old OutOfFuel error
    while not turtle.forward() do
        turtle.dig()
        turtle.attack()
        sleep(0.5)
    end
    
    if state.facing == 0 then state.z = state.z + 1
    elseif state.facing == 1 then state.x = state.x + 1
    elseif state.facing == 2 then state.z = state.z - 1
    elseif state.facing == 3 then state.x = state.x - 1
    end
    saveProgress()
end

local function goTo(tx, tz)
    if state.x < tx then
        turnTo(1)
        while state.x < tx do forward() end
    elseif state.x > tx then
        turnTo(3)
        while state.x > tx do forward() end
    end
    
    if state.z < tz then
        turnTo(0)
        while state.z < tz do forward() end
    elseif state.z > tz then
        turnTo(2)
        while state.z > tz do forward() end
    end
end

--------------------------------------
-- FILLER LOGIC
--------------------------------------
local function drawUI()
    term.clear()
    term.setCursorPos(1,1)
    mtui.header("FILLER v" .. VERSION)
    print(string.rep("=",30))
    
    local total = state.params.length * state.params.width
    local percent = 0
    if total > 0 then percent = math.floor((state.built / total) * 100) end
    
    colorPrint("Filled Columns: "..state.built.." / "..total, colors.orange)
    print("Pos: "..state.x..","..state.z.." Facing: "..state.facing)
    
    local fuel = turtle.getFuelLevel()
    local fuelMax = turtle.getFuelLimit()
    io.write("Fuel: ")
    if fuel < 500 then
        colorPrint(fuel.." (LOW)", colors.red)
    else
        colorPrint(fuel.." / "..fuelMax, colors.green)
    end
    
    colorPrint("Press Q to Terminate", colors.red)
    
    print(mtui.progress(percent))
    print(string.rep("=",30))
    
    if state.isReturning then
        colorPrint(">> RETURNING TO ".. (state.x == 0 and state.z == 0 and "REFILL" or "WORK").. " <<", colors.magenta)
    end
end

local function checkInventory()
    local have = 0
    for i=1,16 do 
        local detail = turtle.getItemDetail(i)
        if detail and isFallingBlock(detail.name) then
            have = have + detail.count
        end
    end
    return have
end

local function selectFallingBlock()
    for slot = 1, 16 do
        local detail = turtle.getItemDetail(slot)
        if detail and isFallingBlock(detail.name) then
            turtle.select(slot)
            return true
        end
    end
    return false
end

--------------------------------------
-- FUEL (LoopFuel integration)
--------------------------------------
local inEvac = false -- true during a fuel evac (no nested evacs)

local function topUpFuel()
    -- Fixed-point refuel at the start. If the point is dry, wait for fuel
    -- items here (reachable); Q aborts and the program stops quietly.
    if not LoopFuel.refuelAtStart(cfg, 2 * tripEst) then
        if not LoopFuel.waitForFuel(cfg, 2 * tripEst) then
            error("", 0)
        end
    end
end

checkFuel = function()
    -- Proactive fuel evac: head home while the trip is still affordable.
    if inEvac or not cfg then return end
    local dist = math.abs(state.x) + math.abs(state.z)
    if LoopFuel.needEvac(dist) then
        inEvac = true
        local rx, rz, rf = state.x, state.z, state.facing
        log("Fuel evac at " .. rx .. "," .. rz)
        state.isReturning = true
        goTo(0, 0)
        topUpFuel()
        goTo(rx, rz)
        turnTo(rf)
        state.isReturning = false
        inEvac = false
    end
end

local function warnRestock()
    -- Estimate: length * width blocks, one per column. This file has no
    -- height param; columns fill until the falling blocks stop, so real
    -- use is higher when the holes are deep. Over 960 blocks (15 stacks)
    -- a mid-run restock will be needed via the return-to-start refill.
    local need = state.params.length * state.params.width
    if need > 960 then
        colorPrint("WARNING: This job needs at least " .. need .. " blocks, over 960 (15 stacks).", colors.red)
        colorPrint("A mid-run restock will be needed; the turtle returns to 0,0 for it.", colors.orange)
    end
end

local function performRefillSequence()
    local returnX, returnZ = state.x, state.z
    local returnFacing = state.facing
    
    log("Refill required at "..state.x..","..state.z)
    state.isReturning = true
    goTo(0,0)
    topUpFuel() -- fixed-point fuel refill while we are at the start

    while not selectFallingBlock() do
        turtle.suck()
        turtle.suckUp()
        turtle.suckDown()
        
        term.clear()
        term.setCursorPos(1,1)
        mtui.header("WAITING FOR BLOCKS")
        print("Turtle returned to 0,0 for refill.")
        print("Required: FALLING blocks (Sand, Gravel, etc.)")
        print("Add blocks to inventory or place chest.")
        print("")
        print("Next check in 30 seconds...")
        sleep(30)
    end
    
    log("Refill successful. Returning to work.")
    state.isReturning = true
    goTo(returnX, returnZ)
    turnTo(returnFacing)
    state.isReturning = false
end

local function fillColumn()
    if state.params.debug then
        print("Debug: Simulating fill at "..state.x..","..state.z)
        sleep(0.5)
        return
    end

    while true do
        local exists, data = turtle.inspectDown()
        if exists and isFallingBlock(data.name) then
            -- Column is already filled up to this level with a falling block
            break
        end

        -- Ensure we have falling blocks
        while not selectFallingBlock() do
            performRefillSequence()
        end
        
        local detail = turtle.getItemDetail()
        local placedName = detail.name

        -- Try to place
        if turtle.placeDown() then
            -- Wait one second as requested to let it fall
            sleep(1)
            -- Verify if the block we just placed is still there
            local stillExists, stillData = turtle.inspectDown()
            if stillExists and stillData.name == placedName then
                -- It stayed! column is full at this coordinate
                break
            end
            -- If it's not there (air/water/something else), it fell, so loop and place again.
        else
            -- Could not place (blocked by something non-replaceable that isn't a falling block)
            -- We break to avoid infinite loop when blocked by stone or other obstacles.
            break
        end
    end
end

local function buildLogic()
    log("Starting fill cycle")
    state.isReturning = false
    
    for x = 0, state.params.width - 1 do
        if x >= state.x then 
             goTo(x, state.z)
             
             local targetZ = (x % 2 == 0) and (state.params.length - 1) or 0
             
             while state.z ~= targetZ do
                 fillColumn()
                 state.built = state.built + 1 
                 drawUI()
                 
                 local moveDir = (state.z < targetZ) and 0 or 2
                 turnTo(moveDir)
                 forward()
             end
             -- Place at end of row
             fillColumn()
             state.built = state.built + 1
             drawUI()
        end
    end
    
    drawUI()
    log("Fill complete.")
    state.isReturning = true
    goTo(0,0)
    turnTo(0)
    
    colorPrint("Area Filled Successfully!", colors.green)
    fullCleanup()
    state.built = state.params.length * state.params.width
end

local function listenForExit()
    while true do
        local ev, p1 = os.pullEvent()
        if ev == "key" and p1 == keys.q then
            error("Terminated", 0)
        end
    end
end

local function runBuild()
    parallel.waitForAny(buildLogic, listenForExit)
end

--------------------------------------
-- ENTRY POINTS
--------------------------------------
local function parseArgs()
    -- CLI dimensions: filler -length 20 -width 12
    for i = 1, #tArgs, 2 do
        local k = tArgs[i]
        local v = tArgs[i + 1]
        if k == "-length" then params.length = tonumber(v) or 0
        elseif k == "-width" then params.width = tonumber(v) or 0
        end
    end
    -- Interactive fallback for anything not given on the command line
    if params.length == 0 then
        colorPrint("Enter Area Length (Z):", colors.orange)
        params.length = tonumber(read()) or 0
    end
    if params.width == 0 then
        colorPrint("Enter Area Width  (X):", colors.orange)
        params.width = tonumber(read()) or 0
    end
    
    if #tArgs > 0 then
         for _,v in ipairs(tArgs) do
             if v == "-debug" then params.debug = true end
         end
    end
end

local function promptStart(resume)
    local timer = resume and os.startTimer(5) or nil -- Auto-start after 5s if resume
    
    while true do
        term.clear()
        term.setCursorPos(1,1)
        mtui.header("FILLER v" .. VERSION)
        colorPrint("Mode: Falling Block Column Fill", colors.yellow)
        colorPrint("Start Position: 0, 0", colors.yellow)
        print("Required: Falling Blocks (Sand/Gravel)")
        
        if params.debug then colorPrint("DEBUG MODE: DRY RUN", colors.magenta) end
        
        local have = checkInventory()
        
        if not resume and have == 0 and not params.debug then
             colorPrint("ERROR: No falling blocks detected!", colors.red)
             colorPrint("Place blocks in inventory and press ENTER.", colors.orange)
             colorPrint("Press Q to Abort and Cleanup.", colors.red)
        elseif not resume and have < 64 and not params.debug then
             colorPrint("WARNING: Low block count ("..have..")", colors.red)
             colorPrint("Press ENTER to Start Anyway", colors.orange)
             colorPrint("Press Q to Abort and Cleanup.", colors.red)
        else
             colorPrint(resume and "Resuming in 5s... (ENTER to start now)" or "Press ENTER to Start", colors.green)
             colorPrint("Press Q to Abort and Cleanup.", colors.red)
        end

        local ev, p1 = os.pullEventRaw()
        if ev == "terminate" or (ev == "key" and p1 == keys.q) then
            fullCleanup()
            colorPrint("\nTerminated/Aborted by user.", colors.red)
            error("Terminated", 0)
        elseif ev == "key" and p1 == keys.enter then
             -- If we were at 0 blocks and pressed ENTER, check again
             if have == 0 and not params.debug then
                  have = checkInventory()
                  if have == 0 then
                       colorPrint("Still no blocks. Searching for chests...", colors.yellow)
                       sleep(2)
                       performRefillSequence()
                       break
                  end
             end
             break
        elseif ev == "timer" and p1 == timer then
             break
        end
    end
    
    colorPrint(resume and "Resuming..." or "Starting...", colors.green)
    sleep(1)
end

-- MAIN EXECUTION
if loadProgress() then
    cfg = LoopSetup.defaults() -- resume: no questions; safe no-op fuel config
    tripEst = state.params.length * state.params.width + 64
    createStartup()
    promptStart(true)
else
    parseArgs()
    if params.length > 0 and params.width > 0 then
        warnRestock()
        -- Fuel setup: every question answered once, here.
        cfg = LoopSetup.run({
            blurb = "Filler: fills columns with falling blocks (sand, gravel, etc.). "
                .. "Returns to 0,0 for material and fuel refills.",
            fuel = true, fuelTags = true, lava = true, fuelChest = true, bucketSlot = 16,
        })
        if not cfg then return end -- user aborted; stop quietly
        -- One-way fuel estimate: block count plus a small travel margin.
        tripEst = state.params.length * state.params.width + 64
        if not LoopFuel.ensure(cfg, tripEst) then return end -- aborted; quiet
        createStartup()
        promptStart(false)
        saveProgress()
    else
        colorPrint("Invalid Dimensions.", colors.red)
        return
    end
end

while true do
    local ok, err = pcall(runBuild)
    if not ok then
        if err == "Terminated" then
            fullCleanup()
            colorPrint("\nTerminated by user.", colors.red)
            return
        elseif err == "" then
            return -- quiet stop: user aborted a fuel or material wait
        else
            error(err)
        end
    else
        break
    end
end
