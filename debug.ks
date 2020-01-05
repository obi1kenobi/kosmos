@LAZYGLOBAL OFF.

run once stdlib.
run once os.
run once engine_info.
run once craft_info.
run once logging.
run once maneuver_planning.
run once orbits.


// Helper file for debugging things that are broken.
// Since kOS does not allow calling functions directly from the terminal,
// one can write said functions into this file and call them by running this file instead.
function main {
    clearscreen.
    if hasnode {
        remove nextnode.
    }

    // local craft_info is make_craft_info().
    // print craft_info.

    local relative_inclination is get_ship_relative_inclination_trig(target).
    print relative_inclination.

    local orbit_nodes is get_ship_relative_orbit_nodes(target).
    print orbit_nodes.

    //until false {
    //    set relative_inclination to get_ship_relative_inclination_trig(target).
    //    print relative_inclination.
    //}

    //set kuniverse:timewarp:mode to "rails".
    //set kuniverse:timewarp:warp to 5.

    //set kuniverse:timewarp:mode to "physics".
    //set kuniverse:timewarp:warp to 0.
}


main.
