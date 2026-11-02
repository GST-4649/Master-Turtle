version = 20261102.0200
local mtui = require("lib.mtui")
-------------------------------------
-- YES/NO DICTIONARIES
-------------------------------------
local yesList = {
    yes = true, y = true, yey = true,
    sure = true, ["of course"] = true,
    indeed = true, yeah = true, yep = true,
    affirmative = true, aye = true,
    ok = true, okay = true, da = true,
    si = true, correct = true,
}

local noList = {
    no = true, n = true, nay = true,
    nope = true, ["of course not"] = true,
    ["not really"] = true, nah = true,
    negative = true, never = true,
    non = true, niet = true,
}

local stopFlag = false
local insightsFlag = false
local chopped = 0
local lifetimeChopped = mtui.readLifetime("chopchop")

-------------------------------------
-- UI HELPERS
-------------------------------------
local function header(title)
    term.clear()
    term.setCursorPos(1,1)
    term.setTextColor(colors.blue)
    print("================================")
    print(" "..title)
    print("================================")
    term.setTextColor(colors.white)
end

local function info(msg)
    term.setTextColor(colors.orange)
    print(msg)
    term.setTextColor(colors.white)
end

local function errorMsg(msg)
    term.setTextColor(colors.red)
    print(msg)
    term.setTextColor(colors.white)
end

local function formatTime(seconds)
    local m = math.floor(seconds / 60)
    local s = math.floor(seconds % 60)
    return string.format("%02d:%02d", m, s)
end

-------------------------------------
-- INPUT VALIDATION
-------------------------------------
header("CHOPCHOP?")
info("yay or nay")

local ans = (read() or ""):lower()

while not yesList[ans] and not noList[ans] do
    sleep(2)
    errorMsg("what u mean? is a yay or nay")
    ans = (read() or ""):lower()
end

-- NO path -> instant exit
if noList[ans] then
    header("ABORT")
    sleep(2)
    errorMsg("why u calling then??")
    return
end

-------------------------------------
-- BLOCK CHECK
-------------------------------------
header("BLOCK SCAN")
sleep(2)
if not turtle.detect() then
    errorMsg("Nothing to chop immediately ahead.")
    sleep(2)
    -- We allow it to proceed anyway? Original just stopped if detect failed loop. 
    -- But maybe user wants to start it and THEN place blocks?
    -- Cranker checks "if ok and data.name...". 
    -- Let's stick to strict check like Cranker for now to prevent useless running.
    -- Actually original logic was: "while turtle.detect() do ... end". So if nothing there, it ends immediately.
    -- Let's warn but maybe allow?
    -- Nah, let's just warn and exit to be safe/consistent with "Target acquired".
    errorMsg("Call me when there's wood.")
    return
end

info("Target acquired.")
sleep(2)

-------------------------------------
-- CHOP LOOP
-------------------------------------
local function chopLoop()
    header("CHOPCHOPCHOP")
    info("CHOPPING AWAY")

    term.setTextColor(colors.blue)
    print("Press Q (or Ctrl+T) to stop.")
    print("Chopped for: 00:00")
    print("--------------------------------")

    local startTime = os.clock()

    -- capture Y position of the timer line
    local _, timerY = term.getCursorPos()
    timerY = timerY - 2

    -- Run while there is something to detect OR until user stops
    -- Note: Original loop only ran "while turtle.detect()". If block breaks, it stops.
    -- If we want it to act like a machine that waits for blocks, we'd use "while not stopFlag".
    -- But the request said "Using cranker as ... template, improve chopchop".
    -- ChopChop original intent: dig UNTIL empty.
    -- Cranker logic: Keep cranking UNTIL stop.
    -- I will implement: Keep chopping AS LONG AS THERE ARE BLOCKS, but allow manual stop.
    -- So if it runs out of blocks, it auto-stops.
    
    while turtle.detect() and not stopFlag do
        if insightsFlag then
            insightsFlag = false
            mtui.showInsights("chopchop", chopped, lifetimeChopped, {"Chopped for: " .. formatTime(os.clock() - startTime)})
            header("CHOPCHOPCHOP")
            info("CHOPPING AWAY")
            term.setTextColor(colors.blue)
            print("Press Q (or Ctrl+T) to stop.")
            print("Chopped for: 00:00")
            print("--------------------------------")
            local _, ty = term.getCursorPos()
            timerY = ty - 2
        end
        turtle.dig()
        chopped = chopped + 1
        sleep(0) -- mild delay to not choke/spam too hard, allows yield

        local elapsed = os.clock() - startTime
        term.setCursorPos(1, timerY)
        term.clearLine()
        term.write("Chopped for: " .. formatTime(elapsed))
        term.setCursorPos(1, timerY + 2)
        term.clearLine()
        term.write("Chopped: " .. chopped .. "  Lifetime: " .. lifetimeChopped .. "  Press V for insights.")
    end
    
    if not stopFlag then
        -- Ended because ran out of blocks
        term.setCursorPos(1, timerY + 3) -- Jump below
        info("Done chopping!")
    end
end

-------------------------------------
-- KEY LISTENER
-------------------------------------
local function stopListener()
    while true do
        local ev, key = os.pullEvent()
        if ev == "key" and key == keys.v then
            insightsFlag = true
        elseif ev == "terminate" or (ev == "key" and (key == keys.q or key == keys.enter)) then
            stopFlag = true
            term.setTextColor(colors.green)
            return
        end
        -- If chopLoop finishes naturally (no blocks), this listener is still running.
        -- parallel.waitForAny will return when chopLoop returns, so this kills automatically.
    end
end

-------------------------------------
-- START BOTH
-------------------------------------
parallel.waitForAny(chopLoop, stopListener)

term.setTextColor(colors.green)
mtui.writeLifetime("chopchop", lifetimeChopped + chopped)
print("\nChop ended hehe")
print("Chopped this session: " .. chopped .. "  Lifetime: " .. (lifetimeChopped + chopped))
print("Stopped.")
term.setTextColor(colors.white)