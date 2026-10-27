-- ESX's drunk status (esx_optionalneeds and the like) is only told to the drinker's game: esx_status:add 'drunk'.
-- The points go to the server, which counts them as drinks (server/drinks.lua). esx_status keeps its own handler;
-- this one only listens.
if GetResourceState('es_extended') == 'missing' then return end

RegisterNetEvent('esx_status:add', function(name, value)
    if name ~= 'drunk' or type(value) ~= 'number' or value <= 0 then return end
    TriggerServerEvent('tr_breathalyzer:drunk', value)
end)
