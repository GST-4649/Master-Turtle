local version = 20261102.0800
-- scenes/Launcher.lua
-- Master Turtle launcher, native term style, no SceneMgr, no lib/ui.
-- Main screen: title, three view buttons, categories, program list,
-- bottom buttons (R)un, (I)nfo, (P)in, (Q)uit, (B)ack.
-- View buttons, row 2: (Tab)Search, (F)requent, (L)ast.
-- Pressing or tapping a view button opens that view. Pressing or
-- tapping the same button again leaves it and returns to main.
-- Search view: type to filter across all programs, regardless of
-- category. Tab leaves search and clears the search text.
-- Frequent view: programs sorted by launch count, most used first,
-- with the count shown, regardless of category. Use arrows only.
-- Last view: programs in most recent launch order, regardless of
-- category. Use arrows only. Launch history is kept in
-- mtui-usage.txt as hist= lines, most recent first, up to 10.
-- No Esc anywhere. Q quits, B goes back to main.

local mtui = require("lib.mtui")
local Dimensions = require("scenes.Dimensions")

local L = {}
L.version = version

local CATEGORIES = { "All", "Build", "Gather", "Action", "Refuel", "Tools", "Pinned" }
local USAGE_FILE = "mtui-usage.txt"

local function loadUsage()
    local u = { counts = {}, last = nil, pins = {}, pinOrder = {}, unpins = {}, history = {} }
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
                elseif k == "unpin" then
                    u.unpins[v] = true
                elseif k == "hist" then
                    u.history[#u.history + 1] = v
                elseif k then
                    u.counts[k] = tonumber(v) or 0
                end
                line = h.readLine()
            end
            h.close()
        end
    end
    -- Old usage files have only last=, no history. Seed history
    -- with that one program so Last is not empty after updating.
    if #u.history == 0 and u.last then
        u.history[1] = u.last
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
    for name in pairs(u.unpins) do
        h.writeLine("unpin=" .. name)
    end
    for name, count in pairs(u.counts) do
        h.writeLine(name .. "=" .. tostring(count))
    end
    for _, name in ipairs(u.history) do
        h.writeLine("hist=" .. name)
    end
    h.close()
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
    local view = "main"
    local sel = 1
    local offset = 1
    local btnRects = {}
    local catRects = {}
    local viewRects = {}
    local drawListTop = 3
    local drawListBottom = 12

    local function currentCat()
        return CATEGORIES[catIdx]
    end

    -- A program is effectively pinned if the user pinned it, or if
    -- it is a default pinned program (cat Pinned in master.lua:
    -- Quarry, Toolkit v3, AI Chat, Updater) and the user has not
    -- unpinned it. Default pinned programs are not forced: pressing
    -- P on one unpins it, pressing P again re-pins it.
    local function isPinned(p)
        if usage.pins[p.prog] then return true end
        if usage.unpins[p.prog] then return false end
        return (p.cat or "") == "Pinned"
    end

    local function recordUsage(prog)
        usage.last = prog
        usage.counts[prog] = (usage.counts[prog] or 0) + 1
        for i, name in ipairs(usage.history) do
            if name == prog then table.remove(usage.history, i) break end
        end
        table.insert(usage.history, 1, prog)
        while #usage.history > 10 do table.remove(usage.history) end
        saveUsage(usage)
    end

    local function filtered()
        local out = {}
        if view == "frequent" then
            local names = {}
            for name, count in pairs(usage.counts) do
                if count > 0 and byName[name] then names[#names + 1] = name end
            end
            table.sort(names, function(a, b)
                if usage.counts[a] ~= usage.counts[b] then
                    return usage.counts[a] > usage.counts[b]
                end
                return a < b
            end)
            for _, name in ipairs(names) do out[#out + 1] = byName[name] end
            return out
        end
        if view == "last" then
            for _, name in ipairs(usage.history) do
                if byName[name] then out[#out + 1] = byName[name] end
            end
            return out
        end
        local q = search:lower()
        for _, p in ipairs(entries) do
            local catOk = true
            if view == "main" then
                if currentCat() == "All" then
                    catOk = true
                elseif currentCat() == "Pinned" then
                    catOk = isPinned(p)
                else
                    catOk = (p.cat or "Tools") == currentCat()
                end
            end
            local qOk = true
            if view == "search" then
                qOk = q == "" or p.name:lower():find(q, 1, true) or p.desc:lower():find(q, 1, true)
            end
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

    local function setView(newView)
        if view == newView then
            view = "main"
        else
            view = newView
        end
        if view ~= "search" then search = "" end
        sel = 1
        offset = 1
    end

    local function exitView()
        view = "main"
        search = ""
        sel = 1
        offset = 1
    end

    local function draw()
        local w, h = term.getSize()
        mtui.clear()
        mtui.header("MASTER TURTLE")
        -- Row 2: view buttons, real button shapes with a solid
        -- background, no square brackets. Active view is yellow.
        viewRects = {}
        local viewButtons = {
            { view = "search", label = "(Tab)Search" },
            { view = "frequent", label = "(F)requent" },
            { view = "last", label = "(L)ast" },
        }
        local x = 1
        for _, b in ipairs(viewButtons) do
            local btnWidth = #b.label + 2
            if x + btnWidth - 1 <= w then
                mtui.tabButton(x, 2, b.label, view == b.view)
                viewRects[#viewRects + 1] = { view = b.view, x1 = x, x2 = x + btnWidth - 1, y = 2 }
                x = x + btnWidth + 1
            end
        end
        -- Search bar row, only in search view.
        local listTop = 3
        if view == "search" then
            term.setCursorPos(1, 3)
            term.setTextColor(colors.white)
            term.write(mtui.truncate("(Tab)Search: " .. search .. "_", w))
            listTop = 4
        end
        -- Categories, only in main view, wrapped to fit the screen.
        -- A turtle is 39 wide, so all seven tabs do not fit on one row.
        catRects = {}
        if view == "main" then
            local catY = 3
            x = 1
            for i, cat in ipairs(CATEGORIES) do
                local label = cat
                local btnWidth = #label + 2
                if x > 1 and x + btnWidth - 1 > w then
                    catY = catY + 1
                    x = 1
                end
                mtui.tabButton(x, catY, label, i == catIdx)
                catRects[#catRects + 1] = { idx = i, x1 = x, x2 = x + btnWidth - 1, y = catY }
                x = x + btnWidth + 1
            end
            listTop = catY + 1
        end
        -- List rows, from listTop to h-1. No info row above the
        -- buttons: that is what the Info button is for.
        local list = filtered()
        if sel < 1 then sel = 1 end
        if sel > #list then sel = math.max(1, #list) end
        local listBottom = h - 1
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
                local mark = isPinned(p) and " [pinned]" or ""
                local line = (idx == sel and "> " or "  ") .. p.name .. mark
                if view == "frequent" then
                    line = line .. " x" .. tostring(usage.counts[p.prog] or 0)
                end
                term.write(mtui.truncate(line, w))
                term.setBackgroundColor(colors.black)
            end
        end
        if #list == 0 then
            term.setCursorPos(2, listTop)
            term.setTextColor(colors.lightGray)
            if view == "frequent" then
                term.write("No frequent programs yet. Run one first.")
            elseif view == "last" then
                term.write("No recent programs yet. Run one first.")
            else
                term.write("No match. Clear the search to see all programs.")
            end
        end
        -- Buttons row h.
        local p = selectedEntry()
        local pinLabel = "(P)in"
        if p and isPinned(p) then
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
        -- Remember list bounds for mouse clicks.
        drawListTop = listTop
        drawListBottom = listBottom
    end

    local function doPin()
        local p = selectedEntry()
        if not p then return end
        if isPinned(p) then
            -- Unpin it fully in one press, even if an old usage file
            -- has both a user pin and a default pin for this program.
            if usage.pins[p.prog] then
                usage.pins[p.prog] = nil
                for i, name in ipairs(usage.pinOrder) do
                    if name == p.prog then table.remove(usage.pinOrder, i) break end
                end
            end
            if (p.cat or "") == "Pinned" then
                -- Default pinned, now unpin it. It stays in All.
                usage.unpins[p.prog] = true
            end
        else
            -- Re-pin it: removing an unpin is enough for a default
            -- program, other programs get a user pin.
            if usage.unpins[p.prog] then
                usage.unpins[p.prog] = nil
            elseif (p.cat or "") ~= "Pinned" then
                usage.pins[p.prog] = true
                usage.pinOrder[#usage.pinOrder + 1] = p.prog
            end
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
            recordUsage(p.prog)
            return { action = "launch", launch = { prog = "cc-ai", args = {} } }
        end
        local launch = nil
        if p.dims then
            launch = Dimensions.prompt(p)
            if not launch then return nil end
        else
            launch = { prog = p.prog, args = {} }
        end
        recordUsage(p.prog)
        return { action = "launch", launch = launch }
    end

    while true do
        draw()
        local ev, p1, p2, p3 = os.pullEvent()
        if ev == "key" then
            local key = p1
            if view == "search" then
                if key == keys.tab then
                    exitView()
                elseif key == keys.f then
                    setView("frequent")
                elseif key == keys.l then
                    setView("last")
                elseif key == keys.backspace then
                    search = search:sub(1, -2)
                    sel = 1
                    offset = 1
                elseif key == keys.up then
                    sel = sel - 1
                elseif key == keys.down then
                    sel = sel + 1
                elseif key == keys.enter then
                    local act = doRun()
                    if act then return act end
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
                    exitView()
                end
            else
                if key == keys.up then
                    sel = sel - 1
                elseif key == keys.down then
                    sel = sel + 1
                elseif view == "main" and key == keys.left then
                    catIdx = catIdx - 1
                    if catIdx < 1 then catIdx = #CATEGORIES end
                    sel = 1
                    offset = 1
                elseif view == "main" and key == keys.right then
                    catIdx = catIdx + 1
                    if catIdx > #CATEGORIES then catIdx = 1 end
                    sel = 1
                    offset = 1
                elseif key == keys.enter then
                    local act = doRun()
                    if act then return act end
                elseif key == keys.tab then
                    setView("search")
                elseif key == keys.f then
                    setView("frequent")
                elseif key == keys.l then
                    setView("last")
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
                    if view == "main" then
                        search = ""
                        catIdx = 1
                        sel = 1
                        offset = 1
                    else
                        exitView()
                    end
                end
            end
        elseif ev == "char" then
            if view == "search" then
                search = search .. p1
                sel = 1
                offset = 1
            end
        elseif ev == "mouse_click" then
            local mx, my = p2, p3
            local viewHit = nil
            for _, r in ipairs(viewRects) do
                if my == r.y and mx >= r.x1 and mx <= r.x2 then viewHit = r.view break end
            end
            if viewHit then
                setView(viewHit)
            else
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
                    if view == "main" then
                        search = ""
                        catIdx = 1
                        sel = 1
                        offset = 1
                    else
                        exitView()
                    end
                else
                    local handled = false
                    if view == "main" then
                        for _, r in ipairs(catRects) do
                            if my == r.y and mx >= r.x1 and mx <= r.x2 then
                                catIdx = r.idx
                                sel = 1
                                offset = 1
                                handled = true
                                break
                            end
                        end
                    end
                    if not handled and my >= drawListTop and my <= drawListBottom then
                        local list = filtered()
                        local idx = offset + (my - drawListTop)
                        if list[idx] then sel = idx end
                    end
                end
            end
        end
    end
end

return L
