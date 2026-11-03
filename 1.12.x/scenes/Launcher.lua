local version = 20261102.0400
-- scenes/Launcher.lua
-- Master Turtle launcher, native term style, no SceneMgr, no lib/ui.
-- Categories AND search, Frequently used, Last used, pinned shortcuts,
-- and bottom buttons (R)un, (I)nfo, (P)in, (Q)uit, (B)ack.
-- This is a plain module. master.lua calls Launcher.run(programs).
-- It returns {action="quit"} or {action="launch", launch={prog,args,info}}.
-- No Esc anywhere. Q quits, B goes back to All with search cleared.

local mtui = require("lib.mtui")
local Dimensions = require("scenes.Dimensions")

local L = {}
L.version = version

local CATEGORIES = { "All", "Build", "Gather", "Action", "Refuel", "Tools", "Pinned" }
local USAGE_FILE = "mtui-usage.txt"

local function loadUsage()
    local u = { counts = {}, last = nil, pins = {}, pinOrder = {} }
    if fs.exists(USAGE_FILE) then
        local h = fs.open(USAGE_FILE, "r")
        if h then
            local line = h.readLine()
            while line do
                local k, v = line:match("^([^=]+)=(.+)$")
                if k == "last" then
                    u.last = v
                elseif k == "pin" then
                    if not u.pins[v] then
                        u.pins[v] = true
                        u.pinOrder[#u.pinOrder + 1] = v
                    end
                elseif k then
                    u.counts[k] = tonumber(v) or 0
                end
                line = h.readLine()
            end
            h.close()
        end
    end
    return u
end

local function saveUsage(u)
    local h = fs.open(USAGE_FILE, "w")
    if not h then return end
    if u.last then h.writeLine("last=" .. u.last) end
    for _, name in ipairs(u.pinOrder) do
        if u.pins[name] then h.writeLine("pin=" .. name) end
    end
    for name, count in pairs(u.counts) do
        h.writeLine(name .. "=" .. tostring(count))
    end
    h.close()
end

local function sortedCounts(u)
    local names = {}
    for name in pairs(u.counts) do names[#names + 1] = name end
    table.sort(names, function(a, b) return u.counts[a] > u.counts[b] end)
    return names
end

function L.run(programs)
    local entries = {}
    for _, p in ipairs(programs) do
        if not p.gate or fs.exists(p.gate) then entries[#entries + 1] = p end
    end
    local byName = {}
    for _, p in ipairs(entries) do byName[p.prog] = p end

    local usage = loadUsage()
    local catIdx = 1
    local search = ""
    local focus = "list"
    local sel = 1
    local offset = 1
    local btnRects = {}
    local catRects = {}
    local chipRects = {}
    local listTop = 6
    local listBottom = 12

    local function currentCat()
        return CATEGORIES[catIdx]
    end

    local function filtered()
        local out = {}
        local q = search:lower()
        for _, p in ipairs(entries) do
            local catOk = currentCat() == "All" or (p.cat or "Tools") == currentCat()
            local qOk = q == "" or p.name:lower():find(q, 1, true) or p.desc:lower():find(q, 1, true)
            if catOk and qOk then out[#out + 1] = p end
        end
        return out
    end

    local function selectedEntry()
        local list = filtered()
        if #list == 0 then return nil end
        if sel < 1 then sel = 1 end
        if sel > #list then sel = #list end
        return list[sel]
    end

    local function freqNames()
        local out = {}
        local seen = {}
        local function add(name)
            if name and byName[name] and not seen[name] then
                seen[name] = true
                out[#out + 1] = name
            end
        end
        -- Pinned shortcuts always first: Toolkit v3 and Updater, if present.
        add("tk3")
        add("updater")
        for _, name in ipairs(usage.pinOrder) do add(name) end
        for _, name in ipairs(sortedCounts(usage)) do add(name) end
        return out
    end

    local function draw()
        local w, h = term.getSize()
        mtui.clear()
        mtui.header("MASTER TURTLE")
        -- Row 2: search. Tab or click to focus it, Tab or click
        -- again to leave it. The hint is on the row itself, because
        -- before this fix there was no way to know Tab did that.
        term.setCursorPos(1, 2)
        term.setTextColor(colors.white)
        local searchLine
        if focus == "search" then
            searchLine = "Search: " .. search .. "_ (Tab to exit)"
        elseif search == "" then
            searchLine = "Search: (Tab to type)"
        else
            searchLine = "Search: " .. search .. " (Tab to type)"
        end
        term.write(mtui.truncate(searchLine, w))
        -- Row 3: frequently used chips.
        chipRects = {}
        term.setCursorPos(1, 3)
        term.setTextColor(colors.lightGray)
        term.write("Often: ")
        local x = 8
        local freq = freqNames()
        for i = 1, math.min(4, #freq) do
            local p = byName[freq[i]]
            local label = p and p.name or freq[i]
            if x + #label <= w then
                term.setCursorPos(x, 3)
                mtui.setText(colors.white, colors.white)
                term.write(label)
                chipRects[#chipRects + 1] = { prog = freq[i], x1 = x, x2 = x + #label - 1, y = 3 }
                x = x + #label + 2
            end
        end
        -- Row 4: last used.
        term.setCursorPos(1, 4)
        term.setTextColor(colors.lightGray)
        local lastLabel = "Last: " .. (usage.last and (byName[usage.last] and byName[usage.last].name or usage.last) or "-")
        term.write(mtui.truncate(lastLabel, w))
        if usage.last and byName[usage.last] then
            chipRects[#chipRects + 1] = { prog = usage.last, x1 = 7, x2 = 6 + #lastLabel, y = 4 }
        end
        -- Categories, wrapped to fit the screen width. A turtle is
        -- 39 wide, so all seven tabs do not fit on one row. They wrap
        -- to a second row instead of being dropped, and the list
        -- starts below the last category row.
        catRects = {}
        local catY = 5
        x = 1
        for i, cat in ipairs(CATEGORIES) do
            local label = "[" .. cat .. "]"
            if x > 1 and x + #label - 1 > w then
                catY = catY + 1
                x = 1
            end
            term.setCursorPos(x, catY)
            if i == catIdx then mtui.setText(colors.yellow, colors.white) else term.setTextColor(colors.white) end
            term.write(label)
            catRects[#catRects + 1] = { idx = i, x1 = x, x2 = x + #label - 1, y = catY }
            x = x + #label + 1
        end
        -- List rows, from below the categories to h-1. There is no
        -- info row above the buttons: that is what the Info button
        -- is for, so the list gets that row instead.
        local list = filtered()
        if sel < 1 then sel = 1 end
        if sel > #list then sel = math.max(1, #list) end
        listTop = catY + 1
        listBottom = h - 1
        local listRows = listBottom - listTop + 1
        if listRows < 1 then listRows = 1 end
        if sel < offset then offset = sel end
        if sel > offset + listRows - 1 then offset = sel - listRows + 1 end
        for row = 1, listRows do
            local idx = offset + row - 1
            local p = list[idx]
            if p then
                local y = listTop + row - 1
                term.setCursorPos(1, y)
                if idx == sel then
                    term.setBackgroundColor(colors.gray)
                    term.setTextColor(colors.white)
                else
                    term.setBackgroundColor(colors.black)
                    term.setTextColor(colors.white)
                end
                local mark = usage.pins[p.prog] and " [pinned]" or ""
                local line = (idx == sel and "> " or "  ") .. p.name .. mark
                term.write(mtui.truncate(line, w))
                term.setBackgroundColor(colors.black)
            end
        end
        if #list == 0 then
            term.setCursorPos(2, listTop)
            term.setTextColor(colors.lightGray)
            term.write("No match. Clear the search to see all programs.")
        end
        -- Buttons row h. No info row above it.
        local p = selectedEntry()
        local pinLabel = "(P)in"
        if p and usage.pins[p.prog] then
            -- "(P)inned" plus the other four buttons totals 41 with
            -- no gap, which crops Back on a 39 wide turtle. Use a
            -- star on a narrow screen; the list still shows [pinned].
            if w >= 45 then pinLabel = "(P)inned" else pinLabel = "(P)in*" end
        end
        btnRects = mtui.buttonRow({
            { id = "run", text = "(R)un", fg = colors.black, bg = colors.lime },
            { id = "info", text = "(I)nfo", fg = colors.white, bg = colors.blue },
            { id = "pin", text = pinLabel, fg = colors.black, bg = colors.orange },
            { id = "quit", text = "(Q)uit", fg = colors.black, bg = colors.red },
            { id = "back", text = "(B)ack", fg = colors.black, bg = colors.gray },
        }, h)
    end

    local function doPin()
        local p = selectedEntry()
        if not p then return end
        if usage.pins[p.prog] then
            usage.pins[p.prog] = nil
            for i, name in ipairs(usage.pinOrder) do
                if name == p.prog then table.remove(usage.pinOrder, i) break end
            end
        else
            usage.pins[p.prog] = true
            usage.pinOrder[#usage.pinOrder + 1] = p.prog
        end
        saveUsage(usage)
    end

    local function doInfo()
        local p = selectedEntry()
        if not p then return end
        local text = p.desc .. (p.loop and " [runs until stopped]" or "")
        if p.info then text = p.info end
        mtui.showInfo(p.name, text)
    end

    local function doRun()
        local p = selectedEntry()
        if not p then return nil end
        if p.info then
            mtui.showInfo(p.name, p.info)
            return nil
        end
        if p.scene then
            -- CC-AI scene is SceneMgr based and is not loaded by the
            -- native launcher. Function is preserved: show its info,
            -- then launch the chat client directly on Enter.
            mtui.clear()
            mtui.header("AI CHAT (cc-ai)")
            term.setCursorPos(2, 3)
            term.setTextColor(colors.white)
            term.write("Chat with an AI from this turtle.")
            term.setCursorPos(2, 4)
            term.setTextColor(colors.lightGray)
            term.write("Needs the cc-ai server running.")
            term.setCursorPos(2, 6)
            term.write("Press Enter to launch chat, any other key to return.")
            local ev, key = os.pullEvent("key")
            if key ~= keys.enter then return nil end
            usage.last = p.prog
            usage.counts[p.prog] = (usage.counts[p.prog] or 0) + 1
            saveUsage(usage)
            return { action = "launch", launch = { prog = "cc-ai", args = {} } }
        end
        local launch = nil
        if p.dims then
            launch = Dimensions.prompt(p)
            if not launch then return nil end
        else
            launch = { prog = p.prog, args = {} }
        end
        usage.last = p.prog
        usage.counts[p.prog] = (usage.counts[p.prog] or 0) + 1
        saveUsage(usage)
        return { action = "launch", launch = launch }
    end

    while true do
        draw()
        local ev, p1, p2, p3 = os.pullEvent()
        if ev == "key" then
            local key = p1
            if focus == "search" then
                if key == keys.enter or key == keys.tab then
                    focus = "list"
                elseif key == keys.backspace then
                    search = search:sub(1, -2)
                    sel = 1
                    offset = 1
                elseif key == keys.up then
                    focus = "list"
                    sel = sel - 1
                elseif key == keys.down then
                    focus = "list"
                    sel = sel + 1
                elseif key == keys.left then
                    focus = "list"
                    catIdx = catIdx - 1
                    if catIdx < 1 then catIdx = #CATEGORIES end
                    sel = 1
                    offset = 1
                elseif key == keys.right then
                    focus = "list"
                    catIdx = catIdx + 1
                    if catIdx > #CATEGORIES then catIdx = 1 end
                    sel = 1
                    offset = 1
                end
            else
                if key == keys.up then
                    sel = sel - 1
                elseif key == keys.down then
                    sel = sel + 1
                elseif key == keys.left then
                    catIdx = catIdx - 1
                    if catIdx < 1 then catIdx = #CATEGORIES end
                    sel = 1
                    offset = 1
                elseif key == keys.right then
                    catIdx = catIdx + 1
                    if catIdx > #CATEGORIES then catIdx = 1 end
                    sel = 1
                    offset = 1
                elseif key == keys.enter then
                    local act = doRun()
                    if act then return act end
                elseif key == keys.tab then
                    focus = "search"
                elseif key == keys.r then
                    local act = doRun()
                    if act then return act end
                elseif key == keys.i then
                    doInfo()
                elseif key == keys.p then
                    doPin()
                elseif key == keys.q then
                    return { action = "quit" }
                elseif key == keys.b then
                    search = ""
                    catIdx = 1
                    sel = 1
                    offset = 1
                end
            end
        elseif ev == "char" then
            if focus == "search" then
                search = search .. p1
                sel = 1
                offset = 1
            end
        elseif ev == "mouse_click" then
            local mx, my = p2, p3
            -- Clicking the search row toggles search focus. Clicking
            -- anything else leaves search focus, so the keyboard
            -- shortcuts work again instead of typing into search.
            -- Before this fix, clicking search a second time did
            -- nothing, and clicking a program left focus in search,
            -- so every letter key kept typing into the search box.
            if my == 2 then
                if focus == "search" then focus = "list" else focus = "search" end
            else
                focus = "list"
                local btn = mtui.buttonAt(btnRects, mx, my)
                if btn == "run" then
                    local act = doRun()
                    if act then return act end
                elseif btn == "info" then
                    doInfo()
                elseif btn == "pin" then
                    doPin()
                elseif btn == "quit" then
                    return { action = "quit" }
                elseif btn == "back" then
                    search = ""
                    catIdx = 1
                    sel = 1
                    offset = 1
                else
                local handled = false
                for _, r in ipairs(catRects) do
                    if my == r.y and mx >= r.x1 and mx <= r.x2 then
                        catIdx = r.idx
                        sel = 1
                        offset = 1
                        handled = true
                        break
                    end
                end
                if not handled then
                    for _, r in ipairs(chipRects) do
                        if my == r.y and mx >= r.x1 and mx <= r.x2 then
                            local target = byName[r.prog]
                            if target then
                                search = ""
                                for i, cat in ipairs(CATEGORIES) do
                                    if cat == (target.cat or "Tools") then catIdx = i break end
                                end
                                local list = filtered()
                                for i, item in ipairs(list) do
                                    if item == target then sel = i break end
                                end
                            end
                            handled = true
                            break
                        end
                    end
                end
                if not handled and my >= listTop and my <= listBottom then
                    local list = filtered()
                    local idx = offset + (my - listTop)
                    if list[idx] then sel = idx end
                end
            end
            end
        end
    end
end

return L
