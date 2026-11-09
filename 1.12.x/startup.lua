local version = 20261108.2320
-- Master Turtle startup.
-- Boots the Master Turtle launcher menu.
--
-- Quarry resume safety net: the quarry installs its own extensionless
-- "startup" resume stub while it runs (that file takes boot precedence).
-- If a quarry save exists but the stub is missing, offer the resume here
-- instead of dropping straight to the menu.
-- The other long runners (platformer, filler, cropper, cluster) manage
-- their own "startup" stubs the same way.
--
-- A save at 100% is a finished run whose end screen never ran (the
-- turtle was rebooted, or the program died on the way home). There is
-- nothing left to resume, so delete it and go to the menu instead of
-- nagging about it on every boot. A save below 100% is a live run and
-- still gets the resume offer. A save that cannot be read is offered
-- as before, never deleted blind.

local saveFile = "Civil_Quarry_Restore"

local function quarryIsDone()
    if not fs.exists(saveFile) then return false end
    local f = fs.open(saveFile, "r")
    if not f then return false end
    local data = f.readAll() or ""
    f.close()
    local pct = data:match("percent%s*=%s*([%d%.]+)")
    pct = pct and tonumber(pct) or nil
    return pct ~= nil and pct >= 100
end

if fs.exists(saveFile) and quarryIsDone() then
    fs.delete(saveFile)
end

if fs.exists(saveFile) then
    print("Quarry save found.")
    print("Wait 5 seconds to resume it,")
    print("or press any key for the menu.")
    local timer = os.startTimer(5)
    local resume = true
    while true do
        local e = os.pullEvent()
        if e == "key" then
            resume = false
            break
        elseif e == "timer" then
            break
        end
    end
    if resume then
        print("Resuming quarry...")
        shell.run("quarry", "-resume")
    end
end

shell.run("master")
