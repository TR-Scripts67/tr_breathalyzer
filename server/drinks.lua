-- Watches the drinks the server's own scripts give (Config.drinks) and adds them to the drinker's blood alcohol.
-- Nothing here takes an item over: the drink script still does all it did. Each way in was checked against the
-- real resource's code (ox_inventory 2.47.9, qb-smallresources, esx_optionalneeds; see dev/tools/trbreath/ref).
local drinks = Config.drinks

-- ox_inventory ------------------------------------------------------------------------------------------
-- Its usingItem hook runs as an item starts being used (items with consume set; a framework's usable items
-- don't go through it). Once the use is over, ox_inventory fires an event named as the hook with
-- (success, payload): a cancelled drink is false and isn't counted.
local oxStarted = {} ---@type table<integer, integer> src -> GetGameTimer() when ox last started an alcohol use
local oxHandler

local function hookOx()
    if GetResourceState('ox_inventory') ~= 'started' then return end
    local filter = {}
    for name in pairs(drinks) do filter[name] = true end

    local id = exports.ox_inventory:registerHook('usingItem', function(payload)
        oxStarted[payload.source] = GetGameTimer()
    end, { itemFilter = filter })

    if oxHandler then RemoveEventHandler(oxHandler) end
    oxHandler = AddEventHandler(id, function(success, payload)
        local item = type(payload) == 'table' and payload.item
        if success and type(item) == 'table' and drinks[item.name] then
            Breathalyzer.addAlcohol(payload.source, drinks[item.name])
        end
    end)
end

hookOx()
AddEventHandler('onResourceStart', function(name)
    if name == 'ox_inventory' then hookOx() end -- its hooks went with it
end)

-- qb-smallresources -------------------------------------------------------------------------------------
-- Its client sends this once the drinking progress bar finished; its own handler takes the item.
RegisterNetEvent('consumables:server:drinkAlcohol', function(item)
    local src = source
    if type(item) ~= 'string' or not drinks[item] then return end
    if not TR.guard.ratelimit(src, 'tr_breathalyzer:qbdrink', { max = 3, window = 10000 }) then return end
    Breathalyzer.addAlcohol(src, drinks[item])
end)

-- ESX's drunk status (esx_optionalneeds and the like) ---------------------------------------------------
-- They only tell the drinker's game (esx_status:add 'drunk'), so client/drinks.lua passes the points on. With
-- ox_inventory its own items set that status too; those were counted by the hook above already.
TR.net.on('tr_breathalyzer:drunk', function(src, points)
    local started = oxStarted[src]
    if started and GetGameTimer() - started < 15000 then return end
    local amount = math.min(points / Config.esxDrunkPerDrink, Config.esxMostPerUse)
    if amount > 0 then Breathalyzer.addAlcohol(src, amount) end
end, {
    schema = { { type = 'number', min = 0, max = 100000000 } },
    rateLimit = { max = 3, window = 10000 },
})

AddEventHandler('playerDropped', function()
    oxStarted[source] = nil
end)
