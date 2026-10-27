-- tr_breathalyzer's items for ESX without ox_inventory (the default ESX inventory reads the items table).
-- Run once on your database. Images: your inventory's own folder, from install/images.
INSERT IGNORE INTO `items` (`name`, `label`, `weight`, `rare`, `can_remove`) VALUES
    ('breathalyzer', 'Breathalyzer', 1, 0, 1),
    ('breathalyzer_mouthpiece', 'Mouthpiece', 0, 0, 1),
    ('breathalyzer_slip', 'Breath test slip', 0, 0, 1);
