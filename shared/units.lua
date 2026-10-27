-- A blood alcohol level (% BAC) as the device shows it, in the unit the config asks for.
Breathalyzer = Breathalyzer or {}

local UNITS = {
    percent = { factor = 1, places = 3, label = '% BAC' },
    permille = { factor = 10, places = 2, label = '‰' },
    -- Breath, at the 2000 : 1 blood to breath ratio the EU limits use (0.5 ‰ = 0.25 mg/L).
    mgl = { factor = 5, places = 2, label = 'mg/L' },
}

---@param bac number % BAC
---@param unit? string Config.unit
---@param limits? table<string, number> Config.limits
---@return string value, string label, boolean over the limit
function Breathalyzer.format(bac, unit, limits)
    local name = UNITS[unit] and unit or 'percent'
    local u = UNITS[name]
    local value = ('%.' .. u.places .. 'f'):format(math.max(0.0, bac) * u.factor)
    local limit = limits and limits[name]
    return value, u.label, limit ~= nil and tonumber(value) >= limit - 1e-9
end

---The legal limit as the device prints it, in the unit the config asks for.
---@param unit? string Config.unit
---@param limits? table<string, number> Config.limits
---@return string
function Breathalyzer.formatLimit(unit, limits)
    local name = UNITS[unit] and unit or 'percent'
    return ('%.' .. UNITS[name].places .. 'f'):format(limits and limits[name] or 0.0)
end
