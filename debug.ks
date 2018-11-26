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

    print ship:drymass * 1000.
    print ship:mass * 1000.
    print ship:wetmass * 1000.
    print get_engines_max_vacuum_thrust(craft_info[CRAFT_INFO_STAGE_ENGINES][1]).
}


main.
