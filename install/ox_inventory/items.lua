-- tr_breathalyzer's items for ox_inventory (ESX, Qbox, or QBCore running ox_inventory).
-- Paste these entries into ox_inventory/data/items.lua, inside the returned table.
-- Images: copy install/images/breathalyzer.png, breathalyzer_mouthpiece.png and breathalyzer_slip.png to
-- ox_inventory/web/images/.
-- Keep the breathalyzer and the slip without `consume`, `client` or `server` fields: using them must reach the
-- framework, which hands them to tr_breathalyzer. The script takes one mouthpiece per test itself.

	['breathalyzer'] = {
		label = 'Breathalyzer',
		weight = 350,
		stack = false,
		close = true,
		description = 'A police breath alcohol tester. Use it to take it out or put it away.',
	},

	['breathalyzer_mouthpiece'] = {
		label = 'Mouthpiece',
		weight = 5,
		stack = true,
		close = false,
		description = 'A sealed single-use mouthpiece for the breathalyzer.',
	},

	['breathalyzer_slip'] = {
		label = 'Breath test slip',
		weight = 1,
		stack = false,
		close = true,
		description = 'The printed record of a breath test. Use it to read it.',
	},
