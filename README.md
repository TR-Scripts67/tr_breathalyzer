# tr_breathalyzer

A police breathalyzer for FiveM with its own 3D device, the VIGILEX AB-560. The officer holds the mouthpiece
to the other player's lips, the player blows into it by holding a key, and the reading shows on the device's
own screen. A printed slip comes out of the bottom, and the officer tears it off as an item that keeps the
test's values.

GTA has no alcohol level to measure, so the resource keeps its own blood alcohol (BAC) per character. It
comes from the drinks your server already has. It never changes how a player walks, sees or drives: it only
measures.

- **Its own props and animations**: the device, the mouthpiece and the slip, and clips that bring the mouthpiece
  to the lips standing, through a car's window, or at a high truck's open door.
- **Consent**: the other player is asked first and may refuse (Y / N). It can be turned off.
- **Real readings**: alcohol is taken up over 20 minutes and burned off over time. A reading is off by up to
  0.003, as a real device's is. The screen shows % BAC, ‰ or mg/L, with your legal limit.
- **The server decides**: the BAC, the reading and the slip are worked out on the server.

## Requirements

- [tr_core](https://github.com/TR-Scripts67/tr_core) 1.6.0 or newer.
- OneSync.
- ESX, QBCore or Qbox, with ox_inventory or qb-inventory (or ESX's own inventory).
- A target script is optional: tr_core has its own, and uses ox_target or qb-target when it is set to.
- tr_core finds what the server runs by itself.

## Installing

1. Put the folder in your resources as `tr_breathalyzer` and start it after tr_core:

   ```cfg
   ensure tr_core
   ensure tr_breathalyzer
   ```

2. Add the three items (`breathalyzer`, `breathalyzer_mouthpiece`, `breathalyzer_slip`) and their icons:
   [install/README.md](install/README.md) has them for ox_inventory, qb-inventory and ESX.
3. Settings are in `shared/config.lua`. Text is in `locales/` (English and Swedish).

After updating the resource, players need a full reconnect to load new props and animations.

## A test

1. **Take it out**: use the `breathalyzer` item. The officer holds the device.
2. **Start**: look at a player on foot, or at a car with someone in it, and pick **Breath test** (within 2 m).
3. **Consent**: the player gets **Y** to agree and **N** to refuse (`Config.consent`).
4. **The mouthpiece**: the officer walks up and holds it to the player's lips. One `breathalyzer_mouthpiece` is
   used per test (`Config.mouthpiece = false` for tests without).
5. **Blow**: the player holds **E** until the bar is full (`Config.blowSeconds`). Let go too early and they
   blow again. After 3 short breaths the device says TEST FAILED.
6. **The reading**: the officer looks at the screen while it analyzes, then reads the result. **X** goes back
   early.
7. **The slip**: the officer prints it and tears it off. It becomes a `breathalyzer_slip` item; using one
   reads it.

**X** stops a test at any time. Players can change the keys in Settings > Key Bindings > FiveM.

## Settings

All in `shared/config.lua`:

| Setting | Default | What it does |
|---|---|---|
| `jobs` | `{ 'police' }` | Who may use it: job names, `{ police = 2 }` for a lowest grade, or `false` for anyone with the item |
| `onDuty` | `false` | Only while on duty (frameworks that have duty) |
| `consent`, `consentSeconds` | `true`, `20` | Ask the player first, and how long they have to answer |
| `unit` | `'percent'` | `'percent'` (0.084 % BAC, US devices), `'permille'` (0.84 ‰) or `'mgl'` (0.42 mg/L, EU devices) |
| `limits` | 0.08 / 0.5 / 0.25 | The legal limit in each unit: at or over it the screen shows OVER LIMIT |
| `tries`, `blowSeconds`, `analyzeSeconds` | `3`, `4.0`, `2.5` | Short breaths allowed, how long a full breath is, how long it analyzes |
| `volume` | `0.3` | How loud the device and the slip are |
| `perDrink`, `absorbMinutes`, `burnPerHour` | `0.02`, `20`, `0.015` | One standard drink's BAC, how long it takes to be taken up, what the body clears per hour |
| `deviceError` | `0.003` | How far a reading can be off |
| `drinks` | beer, wine, whiskey... | Your drinks' item names, in standard drinks per use |

## Drinks

Blood alcohol comes from the drinks your server's own scripts give, listed in `drinks` in the config. They
are seen without changing those scripts:

- **ox_inventory** items, through its `usingItem` hook.
- **qb-smallresources**' alcohol.
- **ESX's drunk status** (esx_optionalneeds and the like): `esxDrunkPerDrink` status points make one drink.

Anything else can add alcohol from the server:

```lua
exports.tr_breathalyzer:addAlcohol(source, 1.5)   -- standard drinks
exports.tr_breathalyzer:getBAC(source)            -- % BAC
exports.tr_breathalyzer:setBAC(source, 0.0)
```

## Admin commands

For the `tr.admin` ace, or your framework's admins:

| Command | What it does |
|---|---|
| `/bac [id]` | Shows a player's BAC (yours without an id) |
| `/setbac <id> <value>` | Sets a player's BAC, in % BAC |
| `/br_dummy [bac] [car]` | Spawns a stand-in to test on alone, on foot or in a car |

## Credits

The sound effects are CC0 recordings from freesound.org, listed in [sounds/CREDITS.txt](sounds/CREDITS.txt).

## License

[GPL-3.0](LICENSE).
