@LAZYGLOBAL OFF.

run once stdlib.
run once os.
run once engine_info.


global CRAFT_INFO is readjson("current_craft_info.json").
global CRAFT_INFO_STAGES is CRAFT_INFO["stages"].


// Helper file for debugging things that are broken.
// Since kOS does not allow calling functions directly from the terminal,
// one can write said functions into this file and call them by running this file instead.
function main {
	print get_engines_max_vacuum_thrust(CRAFT_INFO_STAGES[stage:number]).
	print get_engines_max_vacuum_thrust(CRAFT_INFO_STAGES[stage:number - 1]).
}


main.
