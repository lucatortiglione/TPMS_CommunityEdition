require "Vehicles/ISUI/ISVehicleDashboard"
local Indicator = require "TPMS/Indicator"

local LAWLYTPMS = {}
if rawget(_G, "LAWLYTPMS") and _G.LAWLYTPMS.Loaded then return end
LAWLYTPMS.Loaded = true
_G.LAWLYTPMS = LAWLYTPMS

-- Install after client scripts: dashboard mods can replace vanilla methods.
local hooks = {}

local function install()
    -- Another dashboard mod may replace the methods after us; only re-wrap when
    -- the current functions are not ours, instead of a one-shot boolean flag.
    if rawget(ISVehicleDashboard, "createChildren") == hooks.createChildren then return end

    local createChildren = ISVehicleDashboard.createChildren
    function ISVehicleDashboard:createChildren(...)
        local result = createChildren(self, ...)
        Indicator.ensure(self)
        return result
    end
    hooks.createChildren = ISVehicleDashboard.createChildren

    local setVehicle = ISVehicleDashboard.setVehicle
    function ISVehicleDashboard:setVehicle(vehicle, ...)
        local result = setVehicle(self, vehicle, ...)
        Indicator.setVehicle(self, self.vehicle)
        return result
    end
    hooks.setVehicle = ISVehicleDashboard.setVehicle

    local prerender = ISVehicleDashboard.prerender
    function ISVehicleDashboard:prerender(...)
        local result = prerender(self, ...)
        -- RD selects family, textures and scale in prerender; follow its update.
        Indicator.update(self)
        return result
    end
    hooks.prerender = ISVehicleDashboard.prerender

    local onResolutionChange = ISVehicleDashboard.onResolutionChange
    function ISVehicleDashboard:onResolutionChange(...)
        local result = onResolutionChange(self, ...)
        Indicator.invalidateLayout(self)
        return result
    end
    hooks.onResolutionChange = ISVehicleDashboard.onResolutionChange
end

-- Dashboard mods load after client scripts, so keep retrying for a while.
local RETRY_TICKS = 600
local ticks = 0

local function reinstall()
    if rawget(ISVehicleDashboard, "createChildren") ~= hooks.createChildren then
        ticks = ticks + 1
        if ticks <= RETRY_TICKS then install() end
    end
    if rawget(ISVehicleDashboard, "createChildren") == hooks.createChildren
        or ticks > RETRY_TICKS then
        -- Hooks are stable (or we gave up): keep no lasting per-frame handler.
        if Events and Events.OnPlayerUpdate then Events.OnPlayerUpdate.Remove(reinstall) end
    end
end

LAWLYTPMS.install = install
Events.OnGameBoot.Add(install)
Events.OnGameStart.Add(install)
if Events and Events.OnPlayerUpdate then
    Events.OnPlayerUpdate.Add(reinstall)
end
