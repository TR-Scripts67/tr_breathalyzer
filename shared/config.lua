-- Values every server owner may want to change. Keep logic out of this file.
Config = {
    -- The items (install/ has them for ox_inventory, qb-core and ESX).
    item = 'breathalyzer',
    mouthpiece = 'breathalyzer_mouthpiece',     -- one is used up by each test; false: tests need none
    slip = 'breathalyzer_slip',                 -- the printed record of a test (its values in the metadata)

    -- Who may use the breathalyzer: job names (any grade), { police = 2 } for a lowest grade, or false for
    -- anyone who has the item.
    jobs = { 'police' },
    onDuty = false,                             -- true: only while on duty (frameworks that have duty)

    -- The other player is asked first and may refuse. false: the officer just starts the test.
    consent = true,
    consentSeconds = 20,

    -- What the screen shows: 'percent' (0.084 % BAC, as US devices), 'permille' (0.84 ‰) or 'mgl'
    -- (0.42 mg/L of breath, as EU devices).
    unit = 'percent',
    -- The legal limit in each unit: a reading at or over it shows OVER LIMIT.
    limits = { percent = 0.08, permille = 0.5, mgl = 0.25 },

    -- The test
    distance = 2.0,                             -- m: how near the officer must be to start one
    tries = 3,                                  -- breaths too short before the device says TEST FAILED
    blowSeconds = 4.0,                          -- how long a full breath is (holding the blow key)
    analyzeSeconds = 2.5,

    -- How loud the device and the slip are, 0..1 (1 = the recordings' own level).
    volume = 0.3,

    -- Keys, as the game names them. Players change theirs in Settings > Key Bindings > FiveM.
    keys = { blow = 'E', cancel = 'X', accept = 'Y', refuse = 'N' },

    -- Blood alcohol, in % BAC (grams per 100 ml of blood)
    perDrink = 0.02,                            -- one standard drink, taken up over absorbMinutes
    absorbMinutes = 20,
    burnPerHour = 0.015,                        -- what the body clears in a real hour
    deviceError = 0.003,                        -- a reading is off by up to this, as a real device's is

    -- The drinks the server's own scripts give, in standard drinks per use. Seen through ox_inventory's
    -- usingItem hook, qb-smallresources' alcohol event and ESX's drunk status (server/drinks.lua): the drink
    -- scripts keep doing all they did. Others can call exports.tr_breathalyzer:addAlcohol(source, drinks).
    drinks = {
        beer = 1.0, wine = 1.0, vine = 1.0, whiskey = 1.5, whisky = 1.5, vodka = 1.5, tequila = 1.5, rum = 1.5,
        rhum = 1.5, martini = 1.0, jager = 1.0, bacardi = 1.5, whiskycoca = 1.0, vodkafruit = 1.0,
        vodkaenergy = 1.0, cubalibre = 1.0,
    },
    -- ESX without ox_inventory (esx_optionalneeds and the like): the drunk status points that make one standard
    -- drink, and the most one use can count as.
    esxDrunkPerDrink = 250000,
    esxMostPerUse = 2.0,
}
