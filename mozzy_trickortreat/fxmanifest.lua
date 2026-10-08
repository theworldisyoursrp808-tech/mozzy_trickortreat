fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_experimental_fxv2_oal 'yes'

name 'mozzy_trickortreat'
author 'Mozzy Dev'
description 'Mozzy Trick or Treat - Halloween trick-or-treating, candy, laced candy & robbery setups (Qbox)'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/bridge.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    'server/main.lua',
}

dependencies {
    '/onesync',
    'qbx_core',
    'ox_lib',
    'ox_target',
    'ox_inventory',
}
