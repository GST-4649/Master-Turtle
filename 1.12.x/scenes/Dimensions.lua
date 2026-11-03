local version = 20261102.0200
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

    local function draw()
        local w, h = term.getSize()
        mtui.clear()
        mtui.header(program.name .. ": dimensions")
        term.setCursorPos(2, 2)
        mtui.setText(colors.lightGray, colors.lightGray)
        term.write("Leave blank if the program asks.")
        fieldRows = {}
        local y = 3
        -- Field column fits the screen: on a 39 wide turtle the old
        -- fixed column at 29 plus a 16 wide field ran to 44 and was
        -- cropped. Label width and field width scale with w.
        local fx = 29
        if w < 45 then fx = 20 end
        for i, dim in ipairs(program.dims) do
            term.setCursorPos(2, y)
            term.setTextColor(colors.white)
            term.write(mtui.truncate(dim.label, fx - 3))
            term.setCursorPos(fx, y)
            if i == focus then
                term.setBackgroundColor(colors.blue)
                term.setTextColor(colors.white)
            else
                term.setBackgroundColor(colors.black)
                term.setTextColor(colors.white)
            end
            local shown = values[i]
            if shown == "" then shown = " " end
            term.write(mtui.truncate("[" .. shown .. "]", w - fx))
            term.setBackgroundColor(colors.black)
            fieldRows[i] = y
            y = y + 1
        end
        if err ~= "" then
            term.setCursorPos(2, h - 3)
            term.setTextColor(colors.red)
            term.write(mtui.truncate(err, w - 2))
        end
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
                if focus > 1 then focus = focus - 1 else return nil end
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
            elseif key == keys.b then
                return nil
            end
        elseif ev == "char" then
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
