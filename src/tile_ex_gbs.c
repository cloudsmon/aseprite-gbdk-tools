#include "bankdata.h"
#include <stdint.h>
#pragma bank 255

#include "tile_ex.h"

#include "data_manager.h"

// same as set_bkg_based_tiles (but I can never remember the name)
inline void SetBankedBkgTilesFromOffset(UINT8 x, UINT8 y, UINT8 w, UINT8 h, UINT8 off, const unsigned char *tiles, UBYTE bank) {
	_map_tile_offset = off;
	SetBankedBkgTiles(x, y, w, h, tiles, bank);
	_map_tile_offset = 0;
}

size_t tile_ex_load_tilesubset(uint8_t base_tile, const tilesubset_t *ts, uint8_t bank) BANKED {
	uint16_t n_tiles = ReadBankedUWORD(&(ts->n), bank);
	const uint8_t* tiles_ptr = (const uint8_t*) ReadBankedUWORD(&(ts->tiles), bank);
	SetBankedBkgData(base_tile, n_tiles, tiles_ptr, bank);
	return (size_t) n_tiles;
}

void tile_ex_draw_bkg_submap(uint8_t otx, uint8_t oty, uint8_t base_tile, const tilesubmap_t *tm, uint8_t tmidx, uint8_t bank) BANKED {
	uint16_t wh = ReadBankedUWORD(&(tm->tw), bank); // assumes packed struct
	uint8_t *ptr = (uint8_t*) &wh;
	uint8_t w = ptr[0];
	uint8_t h = ptr[1];

	const uint8_t *map = (const uint8_t*) ReadBankedUWORD(tm->map + tmidx, bank);

	SetBankedBkgTilesFromOffset(otx, oty, w, h, base_tile, map, bank);

}
