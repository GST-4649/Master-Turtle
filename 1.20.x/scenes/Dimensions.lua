local version = 20261108.2320
-- scenes/Dimensions.lua
-- Dimension prompt dialog, native term style, no SceneMgr, no lib/ui.
-- Plain module. Dimensions.prompt(program) returns a launch table
-- {prog, args} on OK, or nil on Cancel or Back.
-- Simple prompt flow, only restyled. Flags sent to each program do not change.
-- Up/Down changes field, type in place, +/- adjusts a number field,
-- Enter moves to the next field and confirms on the last, empty Enter
-- on a field leaves it blank, B goes back, no Esc.
-- Pages: at most 4 fields per page, so a long dialog shows pages
-- instead of one cramped screen. Up/Down and Enter cross page
-- boundaries; B goes back a page, and B on the first page cancels.
-- Long hints wrap to 2 lines so nothing cuts off mid word.
-- Mode first: a program with program.modeDims (Builder) asks Mode
-- on its own page, then shows only the fields that mode uses, in
-- program.dims order. B from the fields page goes back to the Mode
-- page (clearing the mode so a fresh one can be typed). The other
-- fields keep their values, so switching modes keeps the dims that
-- still apply. modeLabels gives per-mode label overrides, used for
-- torch, whose length is X and width is Z, unlike the rest.

local mtui = require("lib.mtui")

local D = {}
D.version = version

function D.prompt(program)
    local values = {}
    for i = 1, #program.dims do values[i] = "" end
    local perPage = 4
    local modeDims = program.modeDims
    local modeIdx = nil
    if modeDims then
        for i, dim in ipairs(program.dims) do
            if dim.flag == "-mode" then modeIdx = i break end
        end
    end
    -- shown: positions map to global dim indices on screen.
    -- Mode-first programs start with only the Mode field.
    local shown = {}
    if modeIdx then
        shown = { modeIdx }
    else
        for i = 1, #program.dims do shown[i] = i end
    end
    local focus = 1
    local err = ""
    local btnRects = {}
    local fieldRows = {}

    local function pageOf(pos)
        return math.floor((pos - 1) / perPage) + 1
    end

    -- Total pages and current page, counting the Mode page as page 1
    -- for mode-first programs.
    local function pageInfo()
        if modeIdx then
            local picked = not (#shown == 1 and shown[1] == modeIdx)
            return picked and 2 or 1, 2
        end
        return pageOf(focus), math.ceil(#shown / perPage)
    end

    -- Wrap text to lines of at most width chars, breaking at spaces.
    -- At most 2 lines; a longer tail is cut, never mid word.
    local function wrapHint(text, width)
        local lines = {}
        local line = ""
        for word in text:gmatch("%S+") do
            if line == "" then
                line = word
            elseif #line + 1 + #word <= width then
                line = line .. " " .. word
            else
                lines[#lines + 1] = line
                line = word
            end
        end
        if line ~= "" then lines[#lines + 1] = line end
        while #lines > 2 do table.remove(lines) end
        if #lines == 2 then lines[2] = mtui.truncate(lines[2], width) end
        return lines
    end

    local function clean(i)
        return (values[i] or ""):gsub("%s+", "")
    end

    local modes = { floor = true, walls = true, solid = true, hollow = true,
        roof = true, wall = true, frame = true, shell = true, fill = true,
        torch = true }
    local function validMode(v)
        return modes[v] == true
    end

    local function modeValue()
        if not modeIdx then return "" end
        return (values[modeIdx] or ""):lower()
    end

    local function labelFor(dim)
        if modeIdx then
            local m = modeValue()
            if m ~= "" and program.modeLabels then
                local per = program.modeLabels[m]
                if per and per[dim.flag] then return per[dim.flag] end
            end
        end
        return dim.label
    end

    -- Global dim indices for a mode, in program.dims order.
    local function fieldsForMode(m)
        local list = {}
        local want = modeDims and modeDims[m]
        if not want then return list end
        local set = {}
        for _, f in ipairs(want) do set[f] = true end
        for i, dim in ipairs(program.dims) do
            if set[dim.flag] then list[#list + 1] = i end
        end
        return list
    end

    -- Dims to validate and send: the Mode plus the shown fields,
    -- in program.dims order.
    local function launchIdx()
        local idx = {}
        local set = {}
        if modeIdx then idx[#idx + 1] = modeIdx set[modeIdx] = true end
        for _, g in ipairs(shown) do
            if not set[g] then idx[#idx + 1] = g set[g] = true end
        end
        table.sort(idx)
        return idx
    end

    local function tryLaunch()
        local args = {}
        for _, i in ipairs(launchIdx()) do
            local dim = program.dims[i]
            if dim.triple then
                local nums = {}
                for n in (values[i] or ""):gmatch("%d+") do
                    nums[#nums + 1] = math.floor(tonumber(n))
                end
                if #nums ~= 3 or nums[1] < 1 or nums[2] < 1 or nums[3] < 1 then
                    err = "Enter 3 positive numbers: length width height"
                    return nil
                end
                args[#args + 1] = dim.flag
                args[#args + 1] = tostring(nums[1])
                args[#args + 1] = tostring(nums[2])
                args[#args + 1] = tostring(nums[3])
            else
                local text = clean(i)
                if text ~= "" then
                    if dim.flag == "-inverted" then
                        local v = text:lower()
                        if v == "true" or v == "y" or v == "yes" or v == "1" then
                            args[#args + 1] = "-inverted"
                        elseif v ~= "false" and v ~= "n" and v ~= "no" and v ~= "0" then
                            err = "Inverted: true or false"
                            return nil
                        end
                    elseif dim.flag == "-mode" then
                        local v = text:lower()
                        if not validMode(v) then
                            err = "Mode: floor/walls/solid/hollow/roof/wall/frame/shell/fill/torch"
                            return nil
                        end
                        args[#args + 1] = "-mode"
                        args[#args + 1] = v
                    else
                        local n = math.floor(tonumber(text) or 0)
                        if n < 1 then
                            err = "Enter a positive number: " .. labelFor(dim)
                            return nil
                        end
                        args[#args + 1] = dim.flag
                        args[#args + 1] = tostring(n)
                    end
                end
            end
        end
        return { prog = program.prog, args = args }
    end

    -- Enter or OK. Returns true when the dialog should launch.
    local function advance()
        if modeIdx and #shown == 1 and shown[1] == modeIdx then
            local v = modeValue()
            if not validMode(v) then
                err = "Mode: floor/walls/solid/hollow/roof/wall/frame/shell/fill/torch"
                return false
            end
            local fields = fieldsForMode(v)
            if #fields == 0 then
                err = "No fields for mode: " .. v
                return false
            end
            shown = fields
            focus = 1
            err = ""
            return false
        end
        if focus < #shown then
            focus = focus + 1
            return false
        end
        return true
    end

    -- B. Returns true when the dialog should cancel.
    local function goBack()
        if modeIdx and not (#shown == 1 and shown[1] == modeIdx) then
            -- Back to the Mode page. Clear the mode so the user
            -- types a fresh one instead of appending to the old
            -- value; the other fields keep what was typed.
            values[modeIdx] = ""
            shown = { modeIdx }
            focus = 1
            err = ""
            return false
        end
        if pageOf(focus) > 1 then
            focus = (pageOf(focus) - 2) * perPage + 1
            return false
        end
        return true
    end

    local function hintFor(dim)
        if dim.flag == "-mode" then
            return "floor, walls, solid, hollow, roof, wall, frame, shell, fill, torch"
        elseif dim.flag == "-inverted" then
            return "true or false, blank = skip"
        elseif dim.triple then
            return "3 numbers: length width height"
        else
            return "Number, + / - adjust, blank = skip"
        end
    end

    local function draw()
        local w, h = term.getSize()
        mtui.setDarkGray()
        mtui.clear()
        mtui.header(program.name)
        -- Row 2: per field hint, or the error in red. The old
        -- dialog truncated long labels mid word, for example
        -- "Mode (floor/walls/solid/hollow/roof)" became
        -- "Mode (floor/walls", and the field box was only as
        -- wide as its text, so empty fields looked like "[ ]"
        -- and the layout shifted as you typed. Labels are now
        -- short (see master.lua), hints carry the full options,
        -- and every field box is a fixed width shape. Long hints
        -- wrap to 2 lines; fields start below them.
        local hintCount
        if err ~= "" then
            term.setCursorPos(2, 2)
            term.setTextColor(colors.red)
            term.write(mtui.truncate(err, w - 2))
            hintCount = 1
        else
            local lines = wrapHint(hintFor(program.dims[shown[focus]]), w - 2)
            mtui.setText(colors.lightGray, colors.lightGray)
            for i, line in ipairs(lines) do
                term.setCursorPos(2, 1 + i)
                term.write(line)
            end
            hintCount = #lines
        end
        fieldRows = {}
        local y = 2 + hintCount
        -- Label at col 2, width 16. Field box at col 19, fixed
        -- width: "[" + 17 chars + "]" = 19, ending at col 37
        -- on a 39 wide turtle, with room to spare on both sides.
        local fx = 19
        local boxInner = 17
        if w >= 45 then
            fx = 22
            boxInner = 24
        end
        local page, pages = pageInfo()
        local first = (pageOf(focus) - 1) * perPage + 1
        local last = math.min(pageOf(focus) * perPage, #shown)
        for pos = first, last do
            local g = shown[pos]
            local dim = program.dims[g]
            term.setCursorPos(2, y)
            term.setTextColor(colors.white)
            term.write(mtui.truncate(labelFor(dim), fx - 3))
            term.setCursorPos(fx, y)
            if pos == focus then
                term.setBackgroundColor(colors.blue)
                term.setTextColor(colors.white)
            else
                -- Dark gray, not black, so unfocused boxes are
                -- still visible as boxes, not plain text.
                term.setBackgroundColor(colors.gray)
                term.setTextColor(colors.white)
            end
            local text = values[g] or ""
            if pos == focus then text = text .. "_" end
            text = mtui.truncate(text, boxInner)
            while #text < boxInner do text = text .. " " end
            term.write("[" .. text .. "]")
            term.setBackgroundColor(colors.black)
            fieldRows[pos] = y
            y = y + 1
        end
        -- Controls hint, just above the buttons, so the dialog
        -- does not leave a blank gap with no guidance.
        term.setCursorPos(2, h - 2)
        mtui.setText(colors.lightGray, colors.lightGray)
        local controls = "Up/Down move  Enter next/OK  B back"
        if pages > 1 then
            controls = controls .. "  Page " .. page .. "/" .. pages
        end
        term.write(mtui.truncate(controls, w - 2))
        btnRects = mtui.buttonRow({
            { id = "ok", text = "OK", fg = colors.black, bg = colors.lime },
            { id = "cancel", text = "(B)ack", fg = colors.black, bg = colors.gray },
        }, h)
    end

    while true do
        draw()
        local ev, p1, p2, p3 = os.pullEvent()
        if ev == "key" then
            local key = p1
            if key == keys.up then
                -- Up on the first field used to cancel the whole
                -- dialog, losing everything typed. Now it stays.
                if focus > 1 then focus = focus - 1 end
            elseif key == keys.down then
                if focus < #shown then focus = focus + 1 end
            elseif key == keys.enter then
                if advance() then
                    local launch = tryLaunch()
                    if launch then return launch end
                end
            elseif key == keys.backspace then
                values[shown[focus]] = values[shown[focus]]:sub(1, -2)
                err = ""
            elseif key == keys.b then
                if goBack() then return nil end
            end
        elseif ev == "char" then
            err = ""
            local ch = p1
            local g = shown[focus]
            local dim = program.dims[g]
            if ch == "+" and dim.flag ~= "-mode" and dim.flag ~= "-inverted" and not dim.triple then
                local n = tonumber(clean(g)) or 0
                values[g] = tostring(n + 1)
            elseif ch == "-" and dim.flag ~= "-mode" and dim.flag ~= "-inverted" and not dim.triple then
                local n = tonumber(clean(g)) or 0
                if n > 1 then values[g] = tostring(n - 1) end
            else
                values[g] = values[g] .. ch
            end
        elseif ev == "mouse_click" then
            local btn = mtui.buttonAt(btnRects, p2, p3)
            if btn == "ok" then
                if advance() then
                    local launch = tryLaunch()
                    if launch then return launch end
                end
            elseif btn == "cancel" then
                return nil
            else
                for pos, row in ipairs(fieldRows) do
                    if p3 == row then focus = pos break end
                end
            end
        end
    end
end

return D
