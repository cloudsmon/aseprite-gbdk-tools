local sprite = app.sprite

if not sprite then
    app.alert("No active sprite!")
    return
end

if sprite.colorMode ~= ColorMode.INDEXED then
    return app.alert("This works only with indexed palettes.")
end

-- CONFIG
-- w->b
local dmg_pal_hex = {"#e0f8cf","#86c06c","#306850","#071821"}
local pal_map = {
    --{221, 220, 219, 218}, -- normal
    {0, 0, 0, 0}, --gets filled automatically with default DMG PAL 
    {0, 221, 220, 218}, -- PINK as transparent / sprite pal
    {218, 220, 221, 219}, -- battlesys inverted pal
}


local TILE_SIZE = 8
local NUM_PALETTES = #pal_map

-- plugin vars

local dmg_pal_idx = {}
local active_pal = 1
local active_size = 1
local dialog_visible = false
local dialog = nil

local array_prefix = app.fs.fileTitle(sprite.filename) -- name without ext and path

local filename = array_prefix..".c"

--utility

function hex_to_color(hex)
    -- Remove the '#' if it exists
    hex = hex:sub(2)

    -- Extract the red, green, and blue components from the hex string
    local red = tonumber(hex:sub(1, 2), 16)
    local green = tonumber(hex:sub(3, 4), 16)
    local blue = tonumber(hex:sub(5, 6), 16)
    --print("r"..red.."g"..green.."b"..blue)
    return Color{r=red, g=green, b=blue}
end


function find_dmg_pal_idx()
    print(sprite.palettes[1])
    local color = nil
    local targetColor = nil
    for i = 1, #sprite.palettes[1] do
        color = sprite.palettes[1]:getColor(i-1)

        for p = 1, #dmg_pal_hex do
            targetColor = hex_to_color(dmg_pal_hex[p])
            if color.red == targetColor.red and color.green == targetColor.green and color.blue == targetColor.blue then
                --print("Found color at index: " .. (i))
                dmg_pal_idx[p] = i - 1
                break
            end
        end
    end
    --print(tostring(dmg_pal_idx))
end


-- EXPORT STUFF

--Processes a 8x8 sector of an image and generate the GBDK C code representing its content as a GB sprite
--row & col are expressed as blocks of 8 pixels
local function exportTile2table(img, row, col)
    local output = {arr = {}, hexstr = ""}
    local i = 1
    --x,y are the PIXEL we look at in the Sprite coordinate (0,0) = top-left most point
    for y = row * 8, (row + 1) * 8 -1, 1
    do
        local b1 = 0
        local b2 = 0

        for x = col * 8, (col +1) * 8 -1, 1
        do
            --indexed palette: get the color index of that pixel
            local pal_idx = img:getPixel(x, y)
            local idx = nil
            if pal_idx == pal_map[active_pal][1] then idx = 0
			elseif pal_idx == pal_map[active_pal][2] then idx = 1
			elseif pal_idx == pal_map[active_pal][3] then idx = 2
			elseif pal_idx == pal_map[active_pal][4] then idx = 3
			end

            if idx == nil then
                print(string.format("idx not not found in palette: %d at (%d,%d)\n", pal_idx, x, y))
            end

            b1 = b1 << 1
            b2 = b2 << 1

            b1 = b1 | (0x01 & idx)
            b2 = b2 | ((0x02 & idx) >> 1)

        end --x
		output.hexstr = output.hexstr .. string.format("%02x%02x ", b1, b2)
		output.arr[i] = b1
		output.arr[i+1] = b2
		i = i + 2
--         if output ~= "" then
--             output = output .. ","
--         end
--         output = output .. string.format("0x%02x,0x%02x", b1, b2)
    end --y

    return output
end

function find_dupl_tiles(tiles, hexstr)
    for i, v in ipairs(tiles) do
        if v.hexstr == hexstr then
            return i - 1
        end
    end
    return nil
end

function exportSpr2table(img, row, col, w, h, use8x16, map_offset, keep_duplicates)
    if use8x16 and h % 16 ~= 0 then
        return nil
    end
    
    local output = {tiles = {}, map = {}}
    local step_y = 1
    if use8x16 then
        step_y = 2
    end
    local cnt = 0
    local n_rows = (h//TILE_SIZE)
    local n_cols = (w//TILE_SIZE)
    for y = row, row + n_rows - 1, step_y do 
        for x = col, col + n_cols - 1, 1 do 
            local tiles = exportTile2table(img, y, x) 
            local idx = nil
            if not keep_duplicates then
                idx = find_dupl_tiles(output.tiles, tiles.hexstr)
            end 
            if idx == nil then 
                output.tiles[#output.tiles + 1] = tiles
                output.map[(y-row)*(n_cols) + (x-col+1)] = cnt+map_offset
                cnt = cnt + 1
            elseif idx ~= nil then
                output.map[(y-row)*(n_cols) + (x-col+1)] = idx+map_offset
            end
            
            if use8x16 then 
                tiles = exportTile2table(img, y+1, x) 
                if not keep_duplicates then
                    idx = find_dupl_tiles(output, tiles.hexstr)
                end 
                if idx == nil then 
                    output.tiles[#output.tiles + 1] = tiles
                    output.map[(y+1-row)*(n_cols) + (x-col+1)] = cnt+map_offset
                    cnt = cnt + 1
                elseif idx ~= nil then
                    output.map[(y+1-row)*(n_cols) + (x-col+1)] = idx+map_offset
                end
            end
        end
    end

    return output
end

local function arr_to_bytes_str(arr)
	output = ""
	for i,b in ipairs(arr) do
		output = output .. string.format("0x%02x,", b)
	end
	return output
end

local function gen_tiles_cstr(content_o, bankref_name, metadata_str)
	local o = ""
    o = o .. "// AUTOGENERATED by gb_export_indexed.lua\n"
    o = o .. metadata_str
	o = o .. "#pragma bank 255\n#include <stdint.h>\n#include <gbdk/platform.h>\n\n"
	o = o .. string.format("BANKREF(%s)\n", bankref_name)
	o = o .. content_o
	return o
end

local function gen_tiles_hstr(arr_prefix, bankref_name, nr_tiles, size_map)
	local o = ""
    o = o .. "// AUTOGENERATED by gb_export_indexed.lua\n"
    o = o .. string.format("#ifndef GFX_%s_H\n", arr_prefix)
    o = o .. string.format("#define GFX_%s_H\n", arr_prefix)

	o = o .. "#include <stdint.h>\n#include <gbdk/platform.h>\n\n"
	o = o .. string.format("BANKREF_EXTERN(%s)\n", bankref_name)
	o = o .. string.format("extern const uint8_t %s_tiles[%d];\n", arr_prefix, nr_tiles * 16)
    if size_map > 0 then 
        o = o .. string.format("extern const uint8_t %s_map[%d];\n", arr_prefix, size_map)
    end
    o = o .."#endif\n"
	return o
end

local function dialog_get_sprsize()
    if active_size == 1 then -- 8x8 
        return {8,8}
    elseif active_size == 2 then
        return {16,16}
    elseif active_size == 3 then
        return {32, 32}
    else
        return {dialog.data["sizex"], dialog.data["sizey"]}
    end
end 



function export_gameboy_tiles()
    -- hacky
    local copyImg = Image(sprite.width, sprite.height, sprite.colorMode)
    copyImg:drawSprite(sprite, app.activeFrame)

    local row = 0
    local col = 0
    local tiles_o = ""
    --local maps_lut_o = string.format("const far_ptr_t bs_unit_map_lut_%ux%u[] = {\n", spr_size.w, spr_size.h)
    local spritecount = 0
    local tilecnt = 0
    local bankref_name = array_prefix
    -- readin values from gui
    local size = dialog_get_sprsize()
    local use8x16 = dialog.data["opt_sprite8x16"]
    local export_map = dialog.data["opt_map"]
    local map_offset = dialog.data["tileoffset"]
    local keep_duplicates = not dialog.data["opt_deduplicate"]
    local spr_cutoff_cnt = dialog.data["opt_tilecutoff"] -- or 0 for all

    if use8x16 == nil then 
        use8x16 = false
    end

    if export_map == nil then 
        export_map = false
    end

    if not map_offset then 
        map_offset = 0
    else
        map_offset = math.floor(map_offset)
    end

    if keep_duplicates == nil then 
        keep_duplicates = false
    end

    if not spr_cutoff_cnt then 
        spr_cutoff_cnt = 0
    else 
        spr_cutoff_cnt = math.floor(spr_cutoff_cnt)
    end

    if spr_cutoff_cnt > 0 and export_map then 
        app.alert("Tile cutoff and Tilemap export at the same time is not supported!")
        return
    end

    -- if 8x8 just take the whole canvas as one sprite
    if size[1] == TILE_SIZE and size[2] == TILE_SIZE and spr_cutoff_cnt == 0 then
        size[1] = sprite.width
        size[2] = sprite.height
    end


    local spr_table = nil
    while (row * TILE_SIZE < sprite.height)
    do
    col = 0
        while (col * TILE_SIZE < sprite.width)
        do

            spr_table = exportSpr2table(copyImg, row, col, size[1], size[2], use8x16, map_offset, keep_duplicates)
            if spr_table == nil then
                if use8x16 and size[2] % 16 ~= 0 then
                    app.alert("ERROR! 8x16 checked but height not divisible by 16!")
                else
                    app.alert("Conversion ERROR! Likely a bug in the code..")
                end
                return 
            end
            tiles_o = tiles_o .. string.format("// spr: %u tx: %u, ty: %u\n", spritecount, col, row)
            for i, t in ipairs(spr_table.tiles) do 
                tiles_o = tiles_o .. string.format("%s\n", arr_to_bytes_str(t.arr))
                tilecnt = tilecnt + 1
            end

            spritecount = spritecount + 1
            if spr_cutoff_cnt > 0 and spritecount == spr_cutoff_cnt then
                break
            end

            col = col + (size[1] // TILE_SIZE)
        end 
        if spr_cutoff_cnt > 0 and spritecount == spr_cutoff_cnt then
            break
        end
    row = row + (size[2] // TILE_SIZE)
    end

    local metadata_str = string.format("// size: %d x %d, use8x16=%s, map_offset=%d, keep_duplicates=%s, pal=%d\n", size[1], size[2], tostring(use8x16), map_offset, tostring(keep_duplicates), active_pal)

    local tile_str = string.format("%s_tiles", array_prefix)
    local map_str = string.format("%s_map", array_prefix)
    tiles_o = string.format("const uint8_t %s[] = {\n%s\n};\n", tile_str, tiles_o)
    local map_size = 0
    if export_map then 
        tiles_o = tiles_o .. string.format("const uint8_t %s[] = {\n%s\n};\n", map_str, arr_to_bytes_str(spr_table.map))
        map_size = #spr_table.map
    end
    local tile_data_c = gen_tiles_cstr(tiles_o, bankref_name, metadata_str)
    local tile_data_h = gen_tiles_hstr(array_prefix, bankref_name, tilecnt, map_size)

    local file = io.open(filename, "w")
    file:write(tile_data_c)
    file:close()

    local headername = filename:gsub("%.c$", ".h")
    file = io.open(headername, "w")
    file:write(tile_data_h)
    file:close()
    app.alert(string.format("Done exporting! Sprite count: %d, Tile count: %d", spritecount, tilecnt))
    dialog:close()
end



-- MAIN

find_dmg_pal_idx()
if #dmg_pal_idx ~= 4 then
    print("error")
    return
end

local label_palettes = {"DMG (w->b)"}
for i = 1, NUM_PALETTES do
    label_palettes[i+1] = "Palette #"..(i-1)
end

function plugin_cleanup()
    dialog_visible = false
end

dialog = Dialog{title= "GBDK C Exporter", onclose = plugin_cleanup}
--dialog:color(id = "dmg",label = "DMG: ",color = Color(0xffff7f00))
-- dlg:color{ id=string,
--            label=string,
--            color=app.Color,
--            onchange=function }


dialog:separator{"Reference Palette"}
dialog:newrow()

dialog:label{text=label_palettes[1]}

for i = 1, #dmg_pal_idx do
    dialog:color{color=Color{index=dmg_pal_idx[i]}}
end

dialog:newrow()
dialog:separator{text="Choose palette"}

pal_map[1][1] = dmg_pal_idx[1]
pal_map[1][2] = dmg_pal_idx[2]
pal_map[1][3] = dmg_pal_idx[3]
pal_map[1][4] = dmg_pal_idx[4]

for i = 1,NUM_PALETTES do
    function set_palette_active()
        --print("button active"..i)
        active_pal = i
    end
    dialog:button{text=label_palettes[i+1], onclick=set_palette_active}
    dialog:color{color=Color{index=pal_map[i][1]}}
    dialog:color{color=Color{index=pal_map[i][2]}}
    dialog:color{color=Color{index=pal_map[i][3]}}
    dialog:color{color=Color{index=pal_map[i][4]}}
    dialog:newrow()
end

dialog:newrow()

dialog:separator{text="Size"}
radio_labels = {"8x8", "16x16", "32x32", "Custom"}
for i = 1,#radio_labels do
    function set_radio_active()
        active_size = i
        --print("radio active"..i.." "..radio_labels[active_size])
    end
    local checked = false
    if i == 1 then 
        checked = true 
    end
    dialog:radio{ text=radio_labels[i], onclick=set_radio_active, selected=checked}
end

dialog:number{id="sizex", label="w", decimals=8}
dialog:number{id="sizey", label="h", decimals=8}

dialog:newrow()
dialog:separator{text="Export Options"}
dialog:check{id="opt_map", label="Export Tilemap"}
dialog:number{id="tileoffset", label="Tilemapoffset", decimals=0}
dialog:check{id="opt_sprite8x16", label="Export in 8x16 chunks", selected=true}
dialog:check{id="opt_tilecutoff", label="Only export n tiles"}
dialog:number{id="tilecutoff", label="n", decimals=0}
dialog:check{id="opt_deduplicate", label="Deduplicate"}

dialog:separator{}

function prefix_change()
    if dialog.data["name_prefix"] and dialog.data["name_prefix"] ~= "" then 
        array_prefix = dialog.data["name_prefix"]
        local path = app.fs.filePath(dialog.data["file_save_as"])
        local fn_new = path..array_prefix..".c"
        print("prefix change filename "..fn_new)

        dialog:modify{
            id="file_save_as",
            filename = fn_new
        }
        --dialog.file_save_as = array_prefix..".c"
    end
end

dialog:entry{id="name_prefix", label="Array name:", text=array_prefix,onchange=prefix_change}

function filename_change()
    filename = dialog.data["file_save_as"]
    print("changed fn: "..filename)
end

dialog:file{id="file_save_as", label="Save as...", save=true, filename=filename, onchange=filename_change}

function export_stuff()
    -- TODO ask user for confirmation (on filename then export)
    local dlg = Dialog{title="Confirm", parent=dialog}
    dlg:label{ id="userfilepath", text="save to "..filename.." ?" }
    dlg:button{ id="confirm", text="Confirm" }
    dlg:button{ id="cancel", text="Cancel" }
    dlg:show{wait=true}
    dlg:close()

    if dlg.data.confirm then
        print("doing export stuff")
        export_gameboy_tiles()
    end

end
dialog:button{text="Do Export", onclick=export_stuff}


dialog_visible = true
dialog:show{wait=false}
