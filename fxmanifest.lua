fx_version 'cerulean'
game 'gta5'

author 'Dein Name oder Team'
description 'NPC-Management Dashboard für ESX (GreenZone420)'
version '1.0.0'

dependency 'es_extended'
dependency 'oxmysql'

client_scripts {
    'config/config.lua',       -- ZUERST die config laden!
    'client/client.lua'        -- Dann das eigentliche Client-Skript
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/server.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/img/logo.png'
}

shared_scripts {
    '@es_extended/imports.lua'
}