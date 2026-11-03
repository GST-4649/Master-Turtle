version = 20261102.0400
-- lib/mtui.lua
-- Shared native term UI for the Master Turtle launcher and Daniel's
-- own programs, in quarry-ui style. No SceneMgr, no lib/ui.
-- Color falls back to white and light gray on a normal turtle.

local M = {}

local function isColor()
    return term.isColor and term.isColor()
end

function M.setText(color, fallback)
    if isColor() then
        term.setTextColor(color)
    else
        term.setTextColor(fallback or colors.white)
    end
end

function M.setBg(color)
    term.setBackgroundColor(color)
end

function M.clear()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
end

function M.center(y, text, color)
    local w = term.getSize()
    local x = math.floor((w - #text) / 2) + 1
    if x < 1 then x = 1 end
    term.setCursorPos(x, y)
    if color then M.setText(color, colors.white) end
    term.write(text)
end

function M.header(title)
    M.center(1, title, colors.yellow)
    term.setTextColor(colors.white)
end

function M.wrap(text, width)
    local lines = {}
    local line = ""
    for word in text:gmatch("%S+") do
        if #line == 0 then
            line = word
        elseif #line + #word + 1 > width then
            lines[#lines + 1] = line
            line = word
        else
            line = line .. " " .. word
        end
    end
    if line ~= "" then lines[#lines + 1] = line end
    if #lines == 0 then lines[1] = "" end
    return lines
end

function M.truncate(text, width)
    if #text <= width then return text end
    if width < 4 then return text:sub(1, width) end
    return text:sub(1, width - 3) .. "..."
end

-- Scrollable info screen. Any key or mouse click returns.
-- Wait for a fresh key or mouse click, not any event. Pressing I
-- queues a key event and then a char event, and a mouse click
-- queues mouse_click and then mouse_up. The old unfiltered
-- os.pullEvent() ate that second event and closed the screen at
-- once, so I looked dead and a mouse click only worked while held.
function M.showInfo(title, text)
    local w, h = term.getSize()
    M.clear()
    M.header(title)
    local lines = M.wrap(text, w - 2)
    local y = 3
    for _, line in ipairs(lines) do
        if y > h - 2 then break end
        term.setCursorPos(2, y)
        term.setTextColor(colors.white)
        term.write(line)
        y = y + 1
    end
    term.setCursorPos(2, h - 1)
    M.setText(colors.lightGray, colors.lightGray)
    term.write("Press any key to return.")
    while true do
        local ev = os.pullEvent()
        if ev == "key" or ev == "mouse_click" then break end
    end
end

-- Loop insights: session count live, lifetime total in a file on the turtle.
-- File name is <name>-insights.txt, first line is the lifetime total.
-- These files live on the turtle only and are never pushed to GitHub.
function M.insightsFile(name)
    return name .. "-insights.txt"
end

function M.readLifetime(name)
    local file = M.insightsFile(name)
    if not fs.exists(file) then return 0 end
    local h = fs.open(file, "r")
    if not h then return 0 end
    local line = h.readLine()
    h.close()
    return tonumber(line) or 0
end

function M.writeLifetime(name, total)
    local h = fs.open(M.insightsFile(name), "w")
    if not h then return end
    h.writeLine(tostring(total))
    h.close()
end

function M.showInsights(name, session, lifetime, extra)
    local w, h = term.getSize()
    M.clear()
    M.header("Insights: " .. name)
    term.setCursorPos(2, 3)
    term.setTextColor(colors.white)
    term.write("Session: " .. tostring(session))
    term.setCursorPos(2, 4)
    term.write("Lifetime: " .. tostring(lifetime))
    local y = 6
    if extra then
        for _, line in ipairs(extra) do
            if y > h - 2 then break end
            term.setCursorPos(2, y)
            term.write(M.truncate(line, w - 2))
            y = y + 1
        end
    end
    term.setCursorPos(2, h - 1)
    M.setText(colors.lightGray, colors.lightGray)
    term.write("Press any key to return.")
    while true do
        local ev = os.pullEvent()
        if ev == "key" or ev == "mouse_click" then break end
    end
end

-- Draw one button shaped tab at x, y: a space, the label, a space,
-- with a solid background. Active tabs get a yellow background with
-- black text, inactive tabs get a gray background with white text.
-- On a non color turtle, active tabs invert to white background
-- with black text so they still stand out. Returns the button width.
-- This is the mtui version of a button: lib/ui Button needs a
-- SceneMgr scene and is usually 3 rows tall, which would waste
-- two rows per tab row here, so it is not used for the launcher.
function M.tabButton(x, y, label, active)
    local width = #label + 2
    term.setCursorPos(x, y)
    if isColor() then
        if active then
            term.setBackgroundColor(colors.yellow)
            term.setTextColor(colors.black)
        else
            term.setBackgroundColor(colors.gray)
            term.setTextColor(colors.white)
        end
    else
        if active then
            term.setBackgroundColor(colors.white)
            term.setTextColor(colors.black)
        else
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.white)
        end
    end
    term.write(" " .. label .. " ")
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    return width
end

function M.progress(percent)
    if percent < 0 then percent = 0 end
    if percent > 100 then percent = 100 end
    local bars = math.floor(percent / 5)
    return "Progress: [" .. string.rep("=", bars) .. string.rep(" ", 20 - bars) .. "] " .. percent .. "%"
end

-- Draw a centered button row at y. Each button is {id, text, fg, bg}.
-- Returns rects for mouse hit testing: {id, x1, x2, y}.
-- Gap shrinks to fit a narrow screen: a turtle is 39 wide, not 51.
-- With gap 2 the launcher buttons total 46, which cropped Back on a
-- turtle. With gap 0 they total 38, and 39 with the pinned star, so
-- they fit a turtle and still centre on a 51 wide computer.
function M.buttonRow(buttons, y)
    local w = term.getSize()
    local function totalWith(gap)
        local total = 0
        for _, b in ipairs(buttons) do total = total + #b.text + 2 end
        return total + (#buttons - 1) * gap
    end
    local gap = 2
    if totalWith(gap) > w then gap = 1 end
    if totalWith(gap) > w then gap = 0 end
    local total = totalWith(gap)
    local x = math.floor((w - total) / 2) + 1
    if x < 1 then x = 1 end
    local rects = {}
    for _, b in ipairs(buttons) do
        local wBtn = #b.text + 2
        term.setCursorPos(x, y)
        if isColor() then
            term.setTextColor(b.fg)
            term.setBackgroundColor(b.bg)
        else
            term.setTextColor(colors.white)
            term.setBackgroundColor(colors.black)
        end
        term.write(" " .. b.text .. " ")
        rects[#rects + 1] = { id = b.id, x1 = x, x2 = x + wBtn - 1, y = y }
        x = x + wBtn + gap
    end
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    return rects
end

function M.buttonAt(rects, x, y)
    for _, r in ipairs(rects) do
        if y == r.y and x >= r.x1 and x <= r.x2 then return r.id end
    end
    return nil
end

return M
