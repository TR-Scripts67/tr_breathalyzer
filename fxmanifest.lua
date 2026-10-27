fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_experimental_fxv2_oal 'yes'

name 'tr_breathalyzer'
author 'TR Scripts'
description 'Police breathalyzer with its own blood alcohol, its own props and animations'
version '1.0.0'

-- Layout: shared/rig.lua and shared/anim.lua are written by props/breathalyzer/build.py and anim.py (the props
-- and the clips, from Blender); stream/ has what they export. web/dist/ is the resource's own page: it draws the
-- device's screen for the props and TR's hint bar and menus (source in [tr]/dev/breathalyzer-web), and plays sounds/
-- (the device's recordings, built by [tr]/dev/sounds).

shared_scripts {
    '@tr_core/init.lua',
    'shared/config.lua',
    'shared/rig.lua',
    'shared/anim.lua',
    'shared/units.lua',
}

server_scripts {
    'server/bac.lua',
    'server/drinks.lua',
    'server/slip.lua',
    'server/test.lua',
}

client_scripts {
    'client/device.lua',
    'client/sound.lua',
    'client/body.lua',
    'client/drinks.lua',
    'client/dummy.lua',
    'client/view.lua',
    'client/slip.lua',
    'client/officer.lua',
    'client/suspect.lua',
}

ui_page 'web/dist/index.html'

files {
    'locales/*.json',
    'web/dist/index.html',
    'web/dist/assets/*',
    'sounds/*.wav',
    'stream/**/*.ytyp',
}

data_file 'DLC_ITYP_REQUEST' 'stream/breathalyzer/tr_breathalyzer.ytyp'

-- Menus with closeLabel, the hint bar on the resource's own page, and TR's own target (no target script needed).
tr_core_version '1.6.0'

dependencies {
    'tr_core',
    '/onesync',
}
