-- Tire monitoring and sandbox settings; deliberately independent of dashboard UI.
local Core = {}

Core.VehListLuxury = {
    "Base.CarLuxury",
    "Base.ModernCar",
    "Base.ModernCar02",
    "Base.ModernCar_Martin",
    "Base.ModernCar_ez",
    "Base.SportsCar",
    "Base.SportsCar_ez",
    "Base.CarLightsPolice",
}

local luxuryVehicles = {}
for i = 1, #Core.VehListLuxury do
    luxuryVehicles[Core.VehListLuxury[i]] = true
end

local cachedSettings
local lastAlert, lastWarning, lastUbiquity, lastWhitelist
local parsedWhitelist, customVehicles

local function isFinite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function threshold(value, default)
    value = tonumber(value)
    if not isFinite(value) then return default end
    return math.max(0, math.min(1, value))
end

local function sameValue(a, b)
    -- NaN is unequal to itself, but an unchanged invalid option must still cache.
    return a == b or (type(a) == "number" and type(b) == "number"
        and a ~= a and b ~= b)
end

function Core.getSettings()
    local options = SandboxVars and SandboxVars.LTPMS
    local rawAlert = options and options.ThresholdOne
    local rawWarning = options and options.ThresholdTwo
    local rawUbiquity = options and options.Ubiquity
    local rawWhitelist = options and options.Whitelist

    if cachedSettings and sameValue(rawAlert, lastAlert)
        and sameValue(rawWarning, lastWarning)
        and sameValue(rawUbiquity, lastUbiquity)
        and sameValue(rawWhitelist, lastWhitelist) then
        return cachedSettings
    end

    -- Ratios use PZ's nominal tire capacity as the reference: steady amber at
    -- 75% remaining pressure, flashing amber at 50%, with faults taking priority.
    local alert = threshold(rawAlert, 0.75)
    local warning = math.min(alert, threshold(rawWarning, 0.5))
    local ubiquity = tonumber(rawUbiquity)
    if ubiquity ~= 1 and ubiquity ~= 2 and ubiquity ~= 3 then
        ubiquity = 1
    end
    local whitelist = type(rawWhitelist) == "string" and rawWhitelist or ""
    if whitelist ~= parsedWhitelist then
        customVehicles = {}
        for name in whitelist:gmatch("[^;]+") do
            name = name:match("^%s*(.-)%s*$")
            if name ~= "" then customVehicles[name] = true end
        end
        parsedWhitelist = whitelist
    end

    local allowedVehicles
    if ubiquity == 2 then
        allowedVehicles = luxuryVehicles
    elseif ubiquity == 3 then
        allowedVehicles = customVehicles
    end

    cachedSettings = {
        alertThreshold = alert,
        warningThreshold = warning,
        ubiquity = ubiquity,
        whitelist = whitelist,
        allowedVehicles = allowedVehicles,
    }
    lastAlert, lastWarning = rawAlert, rawWarning
    lastUbiquity, lastWhitelist = rawUbiquity, rawWhitelist
    return cachedSettings
end

function Core.isEligible(vehicle, settings)
    if not vehicle then return false end
    settings = settings or Core.getSettings()
    if settings.ubiquity == 1 then return true end
    if not settings.allowedVehicles then return false end
    return settings.allowedVehicles[vehicle:getScriptName()] == true
end

function Core.collectTires(vehicle)
    local tires = {}
    if not vehicle then return tires end
    for i = 0, vehicle:getPartCount() - 1 do
        local part = vehicle:getPartByIndex(i)
        if part and part:getCategory() == "tire" then
            -- Wheel-less parts (for example stored spare tires) are not monitored.
            -- The category fallback also supports mods without getWheelIndex.
            local wheelIndex = part.getWheelIndex and part:getWheelIndex()
            if wheelIndex == nil or wheelIndex >= 0 then
                tires[#tires + 1] = part
            end
        end
    end
    return tires
end

function Core.sample(tires, settings)
    if not tires or #tires == 0 then return "off", nil end
    settings = settings or Core.getSettings()
    local minimum = math.huge
    for i = 1, #tires do
        local part = tires[i]
        if not part:getInventoryItem() then return "error", nil end
        local condition = part:getCondition()
        local capacity = part:getContainerCapacity()
        local pressure = part:getContainerContentAmount()
        if not isFinite(condition) or condition <= 0
            or not isFinite(capacity) or capacity <= 0
            or not isFinite(pressure) or pressure < 0 then
            return "error", nil
        end
        local ratio = pressure / capacity
        if not isFinite(ratio) then return "error", nil end
        if ratio < minimum then minimum = ratio end
    end
    -- Check the critical threshold first so exactly 50% flashes by default.
    if minimum <= settings.warningThreshold then return "warn", minimum end
    if minimum <= settings.alertThreshold then return "on", minimum end
    return "off", minimum
end

return Core
