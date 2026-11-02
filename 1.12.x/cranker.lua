version = 20261102.0200
local mtui = require("lib.mtui")
-------------------------------------
-- YES/NO DICTIONARIES
-------------------------------------
local yesList = {
    yes = true, y = true, yey = true,
    sure = true, ["of course"] = true,
    indeed = true,
}

local noList = {
    no = true, n = true, nay = true,
    nope = true, ["of course not"] = true,
    ["not really"] = true,
}

local stopFlag = false
local insightsFlag = false
local cranked = 0
local lifetimeCranked = mtui.readLifetime("cranker")

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
header("SHOULD I CRANK IT???")
info("TELL ME")

local ans = (read() or ""):lower()

while not yesList[ans] and not noList[ans] do
    errorMsg("wym. it's a yey or nay question.")
    ans = (read() or ""):lower()
end

-- NO path -> instant exit
if noList[ans] then
    header("ABORT")
    errorMsg("then why tf u callin??")
    return
end

-------------------------------------
-- BLOCK CHECK
-------------------------------------
header("BLOCK SCAN")
sleep(1)
local ok, data = turtle.inspect()
local blockName = ""

if ok and data.name then
    blockName = data.name:lower()
end

if not ok or not blockName:find("crank") then
    errorMsg("Nothin to crank mate. Call me later.")
    return
end
sleep(1)
info("Target acquired.")
sleep(1)
-------------------------------------
-- CRANK LOOP
-------------------------------------
local function crankLoop()
    header("CCCCRANKINGG")
    info("IM CRANKING IT")

    term.setTextColor(colors.blue)
    print("Press Q (or Ctrl+T) to stop.")
    print("Cranked it for: 00:00")
    print("--------------------------------")

    local startTime = os.clock()

    -- capture Y position of the timer line (the second line we just printed)
    local _, timerY = term.getCursorPos()
    timerY = timerY - 2

    while not stopFlag do
        if insightsFlag then
            insightsFlag = false
            mtui.showInsights("cranker", cranked, lifetimeCranked, {"Cranked it " .. cranked .. " times!"})
            header("CCCCRANKINGG")
            info("IM CRANKING IT")
            term.setTextColor(colors.blue)
            print("Press Q (or Ctrl+T) to stop.")
            print("Cranked it for: 00:00")
            print("--------------------------------")
            local _, ty = term.getCursorPos()
            timerY = ty - 2
        end
        turtle.place()
        cranked = cranked + 1
        sleep(0.4)

        local elapsed = os.clock() - startTime
        term.setCursorPos(1, timerY)
        term.clearLine()
        term.write("Cranked it for: " .. formatTime(elapsed))
        term.setCursorPos(1, timerY + 2)
        term.clearLine()
        term.write("Cranked it " .. cranked .. " times!  Lifetime: " .. lifetimeCranked .. "  Press V for insights.")
    end
end



-------------------------------------
-- KEY LISTENER
-------------------------------------
local function stopListener()
    while true do
        local ev, key = os.pullEvent()
        if ev == "terminate" or (ev == "key" and (key == keys.q or key == keys.enter)) then
            stopFlag = true
            term.setTextColor(colors.green)
            return
        elseif ev == "key" and key == keys.v then
            insightsFlag = true
        end
    end
end

-------------------------------------
-- START BOTH
-------------------------------------
parallel.waitForAny(crankLoop, stopListener)

term.setTextColor(colors.green)
mtui.writeLifetime("cranker", lifetimeCranked + cranked)
print("\nAlright fine. Stopping the crank...")
print("Cranked it " .. cranked .. " times!  Lifetime: " .. (lifetimeCranked + cranked))
print("Stopped.")
sleep(3)
print("\nBUT BECAUSE I WAS DONE XD")
term.setTextColor(colors.white)