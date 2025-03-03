# About 

Aseprite utility script to export Images to GBDK C arrays with an export dialog.

Features:
    * supports subdividing the image in e.g 32x32 sprites (e.g for monster sprites for an RPG)
    * tile map generation with optional tile offset
    * optional simple tile deduplication
    * no GBC support yet

It uses indexed palettes and probably won't work out of the box unless your DMG palette contains these shades of green: "#e0f8cf","#86c06c","#306850","#071821" (the same are used by GB Studio)
But the colors can easily be configured in the script itself.

This script was created based on [gbdk-sprite-exporter](https://github.com/AlanFromJapan/gbdk-sprite-exporter)

