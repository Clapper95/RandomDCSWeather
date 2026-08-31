--[[
    randWeatherAlternate.lua

    **What this script does**
        Every time the current mission stops (shutdown, mission restart, or mission end), this script will rewrite the weather and time of day into your configured mission file with randomized values. So each time the mission starts, new weather is set up.

        For instance, your current server has one set of Dynamic weather or is set to Static. This script will move weather into a randomized weather set each time the server resets.

    **INSTALL**
        1. Requires 7Zip to be installed on the server. (https://7-zip.org/)
            Update the sevenZip variable below to where 7z.exe is install if not default path
        2. Make a copy of your mission and rename it (example mission_b.miz) and then add it to the missionB variable. Mission A is the other miz file that you copied from. 
        3. Set serverSettingPath to where your serverSettings.lua is located
        3. Copy this file into user\Saved Games\DCS\Scripts\Hooks
        4. Restart your server once to load the hook. From then on, every mission stop generates a new weather set and start time for the NEXT restart.

    **Notes**
            This only changes individual fields. wind, groundTurbulance, qnh, clouds, season/temperature, and start_time. It does not touch anything fog related as fog should be set to AUTO in the mission editor if you wish to have fog.
            Test manually first. If you have your 7z path messed up, there will be no error on DCS.

    **Configurable Lines**
    -Ln 41-44
            7-Zip, missionA, missionB, your serversettings.lua path
    -Ln 59
            Chance of bad weather (0 for never bad weather, 1 for always bad weather, in between is chance)
    -Ln 85-87
            This is randomness of wind. Ln 84 is at ground for runways and carriers. change the rnd(0,359) for direction and rnd(0,8) for speed
    Ln 99
            Chance of night time (same as bad weather)
    
--]]

local sevenZip    = [[C:\Program Files\7-Zip\7z.exe]]
local missionA    = [[C:\Users\YourUser\Saved Games\DCS\Missions\yourmiz.miz]]
local missionB    = [[C:\Users\YourUser\Saved Games\DCS\Missions\yourmiz_b.miz]]
local serverSettingPath = [[C:\Users\YourUser\Saved Games\DCS.dcs_serverrelease\Config\serverSettings.lua]]
local workDir     = (lfs and lfs.writedir() or os.getenv("TEMP") .. "\\") .. "randomizeWeatherTMP\\"

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

local badWeatherChance = 0.25
local goodRegimes = {"clear", "scattered"}
local badRegimes  = {"overcast", "rain", "storm"}

local function buildWeather()
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

local nightChance = 0.12

local function pickStartTime()
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
local function randomizeInPlace(mizPath)
    os.execute('mkdir "' .. workDir .. '" 2>nul')
    local missionPath = workDir .. "mission"
    os.remove(missionPath)

    local extractCmd = string.format('""%s" e -y -o"%s" "%s" mission"', sevenZip, workDir, mizPath)
    local extractResult = os.execute(extractCmd)
    log("Extract from " .. mizPath .. " result: " .. tostring(extractResult))
    if extractResult ~= 0 and extractResult ~= true then
        log("ERROR: extraction failed for " .. mizPath)
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

    -- Repack the modified mission into the inactive .miz file.
    local batPath = workDir .. "repack.bat"
    local batFile = io.open(batPath, "w")
    if not batFile then
        log("ERROR: could not write repack batch file")
        return false
    end
    batFile:write('@echo off\r\n')
    batFile:write('cd /d "' .. workDir .. '"\r\n')
    batFile:write('"' .. sevenZip .. '" u "' .. mizPath .. '" mission > "' .. workDir .. '7zRepackOutput.log" 2>&1\r\n')
    batFile:write('echo EXITCODE=%ERRORLEVEL% >> "' .. workDir .. '7zRepackOutput.log"\r\n')
    batFile:write('exit /b %ERRORLEVEL%\r\n')
    batFile:close()

    local repackResult = os.execute('"' .. batPath .. '"')
    log("Repack into " .. mizPath .. " result: " .. tostring(repackResult))
    if repackResult ~= 0 and repackResult ~= true then
        log("ERROR: repack failed for " .. mizPath .. " - check " .. workDir .. "7zRepackOutput.log")
        return false
    end

    log("SUCCESS: " .. mizPath .. " randomized and ready to load")
    return true
end


-- Selects the mission file that is not currently active.
local function getInactiveMission()
    local ok, current = pcall(function() return DCS.getMissionFilename() end)
    if ok and current then
        local lower = string.lower(current)
        if string.find(lower, "_b%.miz") then
            return missionA
        end
    end
    return missionB
end


-- Hook reg

local function setNextMission(missionPath)
    local f = io.open(serverSettingPath, "rb")
    if not f then
        log("ERROR: could not find serverSettings.lua")
        return false
    end

    local text = f:read("*a")
    f:close()

    local escapedPath = missionPath:gsub("\\", "\\\\")
    local pattern = '(%["missionList"%]%s*=%s*)({.-})(%s*,)'

    local prefix, missionList, comma = text:match(pattern)

    if not prefix then
        log("ERROR: could not locate the missionList in serverSettings.lua")
        return false
    end

    local newMissionList = '{\n' .. '\t\t[1] = "' .. escapedPath .. '",\n' .. '\t}'  
    local replacement = prefix .. newMissionList .. comma

    local updatedText, count = text:gsub(pattern, replacement, 1)
    if count ~= 1 then
        log("ERROR: could not updated missionList in serverSettings.lua")
        return false
    end

    local outF = io.open(serverSettingPath, "wb")
    if not outF then
        log("ERROR: could not write serverSettings.lua")
        return false
    end

    outF:write(updatedText)
    outF:close()

    log("SUCCESS: serverSettings.lua updated to " .. missionPath)

    return true
end
local handler = {}

function handler.onSimulationStart()
    local inactive = getInactiveMission()
    log("Current Session Active")
    log("Staging alternate mission: ".. inactive)

    local backupPath = inactive .. ".bak"
    local bakOk, bakErr = copyFile(inactive, backupPath)

    if not bakOk then
        log("WARNING: could not back up " .. inactive .. " before patching " .. tostring(bakErr))
    end

    if not randomizeInPlace(inactive) then
        log("ERROR: staging failed for " .. inactive)
        log("WARNING: serverSettings.lua will not be changed")
        return
    end

    if not setNextMission(inactive) then
        log("ERROR: mission staged successfully but serverSettings.lua has failed to updated")
        log("WARNING: Next startup may still load the previous mission")
        return
    end

    log("SUCCESS: Next startup READY: " .. inactive)
end

DCS.setUserCallbacks(handler)
