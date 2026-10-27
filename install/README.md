# Installing tr_breathalyzer

## 1. Resources

Start it after your framework, inventory and tr_core in `server.cfg`:

```cfg
ensure tr_core
ensure tr_breathalyzer
```

It needs tr_core 1.6.0 or newer and OneSync. Its props and animations stream from its own `stream/` folder.

## 2. The items

| Item | What it's for |
|---|---|
| `breathalyzer` | The device. Using it takes it out (the officer holds it) or puts it away |
| `breathalyzer_mouthpiece` | One is used by each test. Set `mouthpiece = false` in `shared/config.lua` for tests without |
| `breathalyzer_slip` | The printed record of a test: the device prints it after the reading and the officer tears it off. Using it reads it. The record is kept in the item's metadata |

The names are in `shared/config.lua` (`item`, `mouthpiece`, `slip`). Images are in [`images/`](images).

- **ox_inventory** (ESX, Qbox, or QBCore with ox_inventory): paste [`ox_inventory/items.lua`](ox_inventory/items.lua)
  into `ox_inventory/data/items.lua`, copy the three images to `ox_inventory/web/images/`, restart the server.
- **qb-inventory** (QBCore): paste [`qb-inventory/items.lua`](qb-inventory/items.lua) into `qb-core/shared/items.lua`,
  copy the three images to `qb-inventory/html/images/`.
- **ESX without ox_inventory**: run [`esx/items.sql`](esx/items.sql) on your database.

## 3. Who may use it

`jobs` in `shared/config.lua` (police by default; `false` lets anyone with the item use it). Admins (the `tr.admin`
ace, or your framework's admins) have `/bac [id]`, `/setbac <id> <value>` and `/br_dummy [bac] [car]`, a stand-in to
test on alone.

## 4. Drinks

Blood alcohol comes from the drinks your server's own scripts give, listed in `drinks` in `shared/config.lua`
(standard drinks per use). ox_inventory items, qb-smallresources' alcohol and ESX's drunk status
(esx_optionalneeds) are seen without changing those scripts. Anything else can call
`exports.tr_breathalyzer:addAlcohol(source, drinks)` on the server.
