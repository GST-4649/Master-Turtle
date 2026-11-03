local version = 20261102.0300
-- scenes/Dimensions.lua
-- Dimension prompt dialog, native term style, no SceneMgr, no lib/ui.
-- Plain module. Dimensions.prompt(program) returns a launch table
-- {prog, args} on OK, or nil on Cancel or Back.
-- Simple prompt flow, only restyled. Flags sent to each program do not change.
-- Up/Down changes field, type in place, +/- adjusts a number field,
-- Enter moves to the next field and confirms on the last, empty Enter
-- on a field leaves it blank, B goes back, no Esc.

local mtui = require("lib.mtui")

local D = {}
D.version = version

function D.prompt(program)
    local values = {}
    for i = 1, #program.dims do values[i] = "" end
    local focus = 1
    local err = ""
    local btnRects = {}
    local fieldRows = {}

    local function clean(i)
        return (values[i] or ""):gsub("%s+", "")
    end

    local function tryLaunch()
        local args = {}
        for i, dim in ipairs(program.dims) do
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
                        if v ~= "floor" and v ~= "walls" and v ~= "solid" and v ~= "hollow" and v ~= "roof" then
                            err = "Mode: floor/walls/solid/hollow/roof"
                            return nil
                        end
                        args[#args + 1] = "-mode"
                        args[#args + 1] = v
                    else
                        local n = math.floor(tonumber(text) or 0)
                        if n < 1 then
                            err = "Enter a positive number: " .. dim.label
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

    local function hintFor(dim)
        if dim.flag == "-mode" then
            return "floor, walls, solid, hollow, roof"
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
        -- and every field box is a fixed width shape.
        term.setCursorPos(2, 2)
        if err ~= "" then
            term.setTextColor(colors.red)
            term.write(mtui.truncate(err, w - 2))
        else
            mtui.setText(colors.lightGray, colors.lightGray)
            term.write(mtui.truncate(hintFor(program.dims[focus]), w - 2))
        end
        fieldRows = {}
        local y = 3
        -- Label at col 2, width 16. Field box at col 19, fixed
        -- width: "[" + 17 chars + "]" = 19, ending at col 37
        -- on a 39 wide turtle, with room to spare on both sides.
        local fx = 19
        local boxInner = 17
        if w >= 45 then
            fx = 22
            boxInner = 24
        end
        for i, dim in ipairs(program.dims) do
            term.setCursorPos(2, y)
            term.setTextColor(colors.white)
            term.write(mtui.truncate(dim.label, fx - 3))
            term.setCursorPos(fx, y)
            if i == focus then
                term.setBackgroundColor(colors.blue)
                term.setTextColor(colors.white)
            else
                -- Dark gray, not black, so unfocused boxes are
                -- still visible as boxes, not plain text.
                term.setBackgroundColor(colors.gray)
                term.setTextColor(colors.white)
            end
            local shown = values[i] or ""
            if i == focus then shown = shown .. "_" end
            shown = mtui.truncate(shown, boxInner)
            while #shown < boxInner do shown = shown .. " " end
            term.write("[" .. shown .. "]")
            term.setBackgroundColor(colors.black)
            fieldRows[i] = y
            y = y + 1
        end
        -- Controls hint, just above the buttons, so the dialog
        -- does not leave a blank gap with no guidance.
        term.setCursorPos(2, h - 2)
        mtui.setText(colors.lightGray, colors.lightGray)
        term.write(mtui.truncate("Up/Down move  Enter next/OK  B back", w - 2))
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
                if focus < #program.dims then focus = focus + 1 end
            elseif key == keys.enter then
                if focus < #program.dims then
                    focus = focus + 1
                else
                    local launch = tryLaunch()
                    if launch then return launch end
                end
            elseif key == keys.backspace then
                values[focus] = values[focus]:sub(1, -2)
                err = ""
            elseif key == keys.b then
                return nil
            end
        elseif ev == "char" then
            err = ""
            local ch = p1
            local dim = program.dims[focus]
            if ch == "+" and dim.flag ~= "-mode" and dim.flag ~= "-inverted" and not dim.triple then
                local n = tonumber(clean(focus)) or 0
                values[focus] = tostring(n + 1)
            elseif ch == "-" and dim.flag ~= "-mode" and dim.flag ~= "-inverted" and not dim.triple then
                local n = tonumber(clean(focus)) or 0
                if n > 1 then values[focus] = tostring(n - 1) end
            else
                values[focus] = values[focus] .. ch
            end
        elseif ev == "mouse_click" then
            local btn = mtui.buttonAt(btnRects, p2, p3)
            if btn == "ok" then
                local launch = tryLaunch()
                if launch then return launch end
            elseif btn == "cancel" then
                return nil
            else
                for i, row in ipairs(fieldRows) do
                    if p3 == row then focus = i break end
                end
            end
        end
    end
end

return D
