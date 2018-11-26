@LAZYGLOBAL OFF.

run once stdlib.
run once os.
run once engine_info.
run once craft_info.


// Helper file for debugging things that are broken.
// Since kOS does not allow calling functions directly from the terminal,
// one can write said functions into this file and call them by running this file instead.
function main {
	local craft_info is make_craft_info().
	print craft_info.

	local first_stage_engines is craft_info[CRAFT_INFO_STAGE_ENGINES][2].

	print first_stage_engines[0]:name.
	print get_engine_consumption(first_stage_engines[0]).
	print get_engines_max_mass_flow_rate(first_stage_engines).
}


main.
