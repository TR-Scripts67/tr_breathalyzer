-- tr_breathalyzer's items for qb-inventory (QBCore).
-- Paste these entries into qb-core/shared/items.lua, inside QBShared.Items.
-- Images: copy install/images/breathalyzer.png, breathalyzer_mouthpiece.png and breathalyzer_slip.png to
-- qb-inventory/html/images/.

    breathalyzer = { name = 'breathalyzer', label = 'Breathalyzer', weight = 350, type = 'item', image = 'breathalyzer.png', unique = true, useable = true, shouldClose = true, description = 'A police breath alcohol tester. Use it to take it out or put it away.' },
    breathalyzer_mouthpiece = { name = 'breathalyzer_mouthpiece', label = 'Mouthpiece', weight = 5, type = 'item', image = 'breathalyzer_mouthpiece.png', unique = false, useable = false, shouldClose = false, description = 'A sealed single-use mouthpiece for the breathalyzer.' },
    breathalyzer_slip = { name = 'breathalyzer_slip', label = 'Breath test slip', weight = 1, type = 'item', image = 'breathalyzer_slip.png', unique = true, useable = true, shouldClose = true, description = 'The printed record of a breath test. Use it to read it.' },
