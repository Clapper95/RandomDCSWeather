--[[
    randWeatherAlternate.lua

    **What this script does**
        Every time the current mission stops (shutdown, mission restart, or mission end), this script will rewrite the weather and time of day into your configured mission file with randomized values. So each time the mission starts, new weather is set up.

        For instance, your current server has one set of Dynamic weather or is set to Static. This script will move weather into a randomized weather set each time the server resets.

    **Prerequisite**
        SpecialK DCSServerBot or Similar needs to be installed on your server to auto-rotate missions.

    **INSTALL**
        1. Requires 7Zip to be installed on the server. (https://7-zip.org/)
            Update the sevenZip variable below to where 7z.exe is install if not default path
        2. Make a copy of your mission and rename it (example mission_b.miz)
        3. Add the copy of your mission to your missionList in serverSettings.lua
        4. Set serverSettingPath to where your serverSettings.lua is located
        5. Copy this file into user\Saved Games\DCS\Scripts\Hooks
        6. Restart your server once to load the hook. From then on, every mission stop generates a new weather set and start time for the NEXT restart.

    **Notes**
            This only changes individual fields. wind, groundTurbulance, qnh, clouds, season/temperature, and start_time. It does not touch anything fog related as fog should be set to AUTO in the mission editor if you wish to have fog.
            Test manually first. If you have your 7z path messed up, there will be no error on DCS.
            This script automatically backs up your .miz so if anything were to happen you would have a fall back.
                Each time this script runs, it first checks that the SOURCE .miz is not already corrupted. Then it builds and patches a disposable staging copy, and integrity-checks THAT copy with 7z before committing anything. 
                    The live .miz file is never opened for writing unless a verified-good staging copy is ready to replace it. If the source is already bad, or every attempt fails to produce a verified-good copy,
                        the live .miz and serverSettings.lua are both left completely unchanged - nothing is auto-reverted, the previous configuration just stays in effect for the next restart. 
--]]

local sevenZip    = [[C:\Program Files\7-Zip\7z.exe]]
local serverSettingPath = [[C:\Users\Your User\Saved Games\DCS.dcs_serverrelease\Config\serverSettings.lua]]
local workDir     = (lfs and lfs.writedir() or os.getenv("TEMP") .. "\\") .. "randomizeWeatherTMP\\"
local maxAttempts = 2

-- Chance Configuration
local nightChance = 0.12
local badWeatherChance = 0.25

local function log(msg)
    local f = io.open((lfs and lfs.writedir() or "") .. "Logs\\randomizeWeather.log", "a")
    if f then
        f:write(os.date("%Y-%m-%d %H:%M:%S") .. " " .. msg .. "\n")
        f:close()
    end
end

local function rnd(min, max) return math.random(min, max) end
local function rndf(min, max) return min + math.random() * (max - min) end
local function pick(t) return t[math.random(#t)] end

local goodRegimes = {"clear", "scattered"}
local badRegimes  = {"overcast", "rain", "storm"}

local function buildWeather()
    log("LOG: Picking Weather")
    local isBad = math.random() < badWeatherChance
    local regime = isBad and pick(badRegimes) or pick(goodRegimes)

    local base, thickness, density, iprecptns
    if regime == "clear" then
        base, thickness, density, iprecptns = 300, 0, 0, 0
    elseif regime == "scattered" then
        base, thickness, density, iprecptns = rnd(600, 2500), rnd(200, 1200), rnd(1, 4), 0
    elseif regime == "overcast" then
        base, thickness, density, iprecptns = rnd(300, 1500), rnd(800, 2500), rnd(7, 9), 0
    elseif regime == "rain" then
        base, thickness, density, iprecptns = rnd(300, 1200), rnd(1000, 3000), rnd(7, 9), 1
    else -- storm
        base, thickness, density, iprecptns = rnd(200, 800), rnd(1500, 4000), 9, 2
    end

    local temp = rndf(-5, 32)

    return {
        wind = string.format(
            '["wind"] =\n    {\n        ["at8000"] = { ["speed"] = %d, ["dir"] = %d, },\n        ["at2000"] = { ["speed"] = %d, ["dir"] = %d, },\n        ["atGround"] = { ["speed"] = %d, ["dir"] = %d, },\n    },',
            rnd(0, 25), rnd(0, 359),
            rnd(0, 15), rnd(0, 359),
            rnd(0, 8),  rnd(0, 359)
        ),
        turbulence = string.format('["groundTurbulence"] = %d,', rnd(0, 10)),
        qnh        = string.format('["qnh"] = %d,', rnd(720, 790)),
        clouds     = string.format(
            '["clouds"] = { ["thickness"] = %d, ["density"] = %d, ["base"] = %d, ["iprecptns"] = %d, },',
            thickness, density, base, iprecptns
        ),
        season = string.format('["season"] = { ["temperature"] = %.1f, },', temp),
    }
end



local function pickStartTime()
    log("LOG: Picking Start Time")
    if math.random() < nightChance then
        local t = rnd(20 * 3600, 28 * 3600)
        return t % 86400
    else
        return rnd(6 * 3600, 19 * 3600)
    end
end

local function buildDateAndTime()
    local dateBlock = string.format([[
["date"] =
{
    ["Day"] = %d,
    ["Month"] = %d,
    ["Year"] = 2014, 
},]], rnd(1, 28), rnd(1, 12))

    local startTimeLine = string.format('["start_time"] = %d,', pickStartTime())

    return dateBlock, startTimeLine
end

local function patchMissionText(text)
    math.randomseed(os.time())

    local w = buildWeather()
    local dateBlock, startTimeLine = buildDateAndTime()

    local patches = {
        {"wind",        '%["wind"%]%s*=%s*%b{},',           w.wind},
        {"turbulence",  '%["groundTurbulence"%]%s*=%s*%d+,', w.turbulence},
        {"qnh",         '%["qnh"%]%s*=%s*%d+,',              w.qnh},
        {"clouds",      '%["clouds"%]%s*=%s*%b{},',          w.clouds},
        {"season",      '%["season"%]%s*=%s*%b{},',          w.season},
        {"date",        '%["date"%]%s*=%s*%b{},',            dateBlock},
        {"start_time",  '%["start_time"%]%s*=%s*%d+,',       startTimeLine},
    }

    local counts = {}
    for _, p in ipairs(patches) do
        local name, pattern, replacement = p[1], p[2], p[3]
        local n
        text, n = text:gsub(pattern, replacement, 1)
        counts[name] = n
        if n ~= 1 then
            log(string.format("WARNING: pattern for '%s' matched %d times (expected 1)", name, n))
        end
    end

    return text, counts
end

-- File helpers

local function copyFile(src, dst)
    local inF = io.open(src, "rb")
    if not inF then return false, "cannot open source: " .. src end
    local data = inF:read("*a")
    inF:close()
    local outF = io.open(dst, "wb")
    if not outF then return false, "cannot open destination: " .. dst end
    outF:write(data)
    outF:close()
    return true
end

-- Patch weather 
local function verifyMiz(mizPath)
    local testCmd = string.format('""%s" t "%s" > "%s7zTestOutput.log" 2>&1"', sevenZip, mizPath, workDir)
    local testResult = os.execute(testCmd)
    log("Integrity test on: " .. mizPath .. " result: " .. tostring(testResult))
    return testResult == 0 or testResult == true
end

local function buildAndVerify(mizPath)
    local stagingMiz = workDir .. "staging.miz"
    os.remove(stagingMiz)
    local copyOk, copyErr = copyFile(mizPath, stagingMiz)
    if not copyOk then
        log("ERROR: could not create a staging copy")
        return false
    end

    local missionPath = workDir .. "mission"
    os.remove(missionPath)
        local extractCmd = string.format('""%s" e -y -o"%s" "%s" mission"', sevenZip, workDir, stagingMiz)
    local extractResult = os.execute(extractCmd)
    log("Extract from staging copy result: " .. tostring(extractResult))
    if extractResult ~= 0 and extractResult ~= true then
        log("ERROR: extraction failed from staging copy of " .. mizPath)
        return false
    end

        local f = io.open(missionPath, "rb")
    if not f then
        log("ERROR: could not open extracted mission at " .. missionPath)
        return false
    end
    local text = f:read("*a")
    f:close()

    local patched, counts = patchMissionText(text)
    local summary = {}
    for _, name in ipairs({"wind", "turbulence", "qnh", "clouds", "season", "date", "start_time"}) do
        table.insert(summary, name .. "=" .. counts[name])
    end
    log("Patch match counts for " .. mizPath .. " (expect 1 each): " .. table.concat(summary, ", "))

    local outF = io.open(missionPath, "wb")
    if not outF then
        log("ERROR: could not write patched mission")
        return false
    end
    outF:write(patched)
    outF:close()

    local batPath = workDir .. "repack.bat"
    local batFile = io.open(batPath, "w")
    if not batFile then
        log("ERROR: could not write repack batch file")
        return false
    end
    batFile:write('@echo off\r\n')
    batFile:write('cd /d "' .. workDir .. '"\r\n')
    batFile:write('"' .. sevenZip .. '" u "' .. stagingMiz .. '" mission > "' .. workDir .. '7zRepackOutput.log" 2>&1\r\n')
    batFile:write('echo EXITCODE=%ERRORLEVEL% >> "' .. workDir .. '7zRepackOutput.log"\r\n')
    batFile:write('exit /b %ERRORLEVEL%\r\n')
    batFile:close()

    local repackResult = os.execute('"' .. batPath .. '"')
    log("Repack into staging copy result: " .. tostring(repackResult))
    if repackResult ~= 0 and repackResult ~= true then
        log("ERROR: repack failed on staging copy for " .. mizPath .. " - check " .. workDir .. "7zRepackOutput.log")
        return false
    end

    if not verifyMiz(stagingMiz) then
        log("ERROR: integrity check FAILED on staging copy for " .. mizPath .. " - check " .. workDir .. "7zTestOutput.log")
        return false
    end

    local commitOk, commitErr = copyFile(stagingMiz, mizPath)
    if not commitOk then
        log("ERROR: verified staging copy could not be committed to " .. mizPath .. " - " .. tostring(commitErr))
        return false
    end

    log("SUCCESS: " .. mizPath .. " randomized, verified, and committed")
    return true
end

local function randomizeInPlace(mizPath)
    os.execute('mkdir "' .. workDir .. '" 2>nul')
    if not verifyMiz(mizPath) then
        log("ERROR: source mission file " .. mizPath .. " already fails integrity check BEFORE any patching - skipping randomization, live file left untouched")
        return false
    end

    for attempt = 1, maxAttempts do
        log("Attempt " .. attempt .. " of " .. maxAttempts .. " for " .. mizPath)
        if buildAndVerify(mizPath) then
            return true
        end
        log("WARNING: attempt " .. attempt .. " failed for " .. mizPath)
    end

    log("ERROR: all " .. maxAttempts .. " attempts failed for " .. mizPath .. " - live file left untouched")
    return false
end

-- Read missionList from serverSettings.lua
local function baseName(path)
    return path:match("([^\\/]+)$") or path
end

local function readMissionList()
    local f = io.open(serverSettingPath, "rb")
    if not f then
        log("ERROR: Could not open serverSettings.lua for reading missionList")
        log("CHECK: Is serverSettingPath set correctly?")
        return nil
    end
    local text = f:read("*a")
    f:close()

    local block = text:match('%[?"?missionList"?%]?%s*=%s*(%b{})')
    if not block then
        log("ERROR: Could not locate mission list in serverSettings.lua")
        return nil
    end 

    local missions = {}
    for path in block:gmatch('"(.-)"') do
        table.insert(missions, (path:gsub('\\\\', '\\')))
    end

    if #missions < 2 then
        log("ERROR: missionList MUST contain at least 2 entries")
        return nil
    end

    return missions
end


-- Selects the mission file that is not currently active.
local function getInactiveMission()
    local missions = readMissionList()
    if not missions then
        return nil
    end

    local ok, current = pcall(function() return DCS.getMissionFilename() end)
    local currentBase = (ok and current) and baseName(current):lower() or nil

    if not currentBase then
        log("WARNING: could not determine the active mission filename. Skipping randomization.")
        return nil
    end

    for _, path in ipairs(missions) do
        if baseName(path):lower() ~= currentBase then
            return path
        end
    end

    log("WARNING: Active mission not found in missionList. Skipping randomization.")

    return nil 
end


-- Hook reg

local handler = {}

function handler.onSimulationStart()
    log("------------------------------------------------------------")
    log("Current Session Active")
    
    local ok, current = pcall(function() return DCS.getMissionFilename() end)
    log("Active Session: " .. ((ok and current) and current or "unknown"))
    local inactive = getInactiveMission()
    if not inactive then
        log("ERROR: Could not determine inactive mission // skipping randomization")
        return
    end

    log("Staging alternate mission: " .. inactive)

    local backupPath = inactive .. ".bak"
    local bakOk, bakErr = copyFile(inactive, backupPath)

    if not bakOk then
        log("WARNING: could not back up " .. inactive .. " before patching " .. tostring(bakErr))
    end

    if not randomizeInPlace(inactive) then
        log("ERROR: staging failed for " .. inactive)
        return
    end


    log("SUCCESS: Next startup READY: " .. inactive)
end

DCS.setUserCallbacks(handler)
