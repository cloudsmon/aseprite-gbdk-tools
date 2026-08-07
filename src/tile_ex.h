#ifndef ASEPRITE_EXPORT_TILE_EX_H
#define ASEPRITE_EXPORT_TILE_EX_H

#include <stddef.h>
#include <stdint.h>
#include <gbdk/platform.h>


typedef struct tilesubmap_t {
	uint8_t tw;
	uint8_t th;
	const uint8_t * const map[];
} tilesubmap_t;

typedef struct tilesubset_t {
	uint16_t n;
	const uint8_t * const tiles;
} tilesubset_t;

size_t tile_ex_load_tilesubset(uint8_t base_tile, const tilesubset_t *ts, uint8_t bank) BANKED;
void tile_ex_draw_bkg_submap(uint8_t otx, uint8_t oty, uint8_t base_tile, const tilesubmap_t *tm, uint8_t tmidx, uint8_t bank) BANKED;

#endif