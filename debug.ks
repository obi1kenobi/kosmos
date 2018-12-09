@LAZYGLOBAL OFF.

run once stdlib.
run once os.
run once engine_info.
run once craft_info.
run once logging.
run once maneuver_planning.


// Helper file for debugging things that are broken.
// Since kOS does not allow calling functions directly from the terminal,
// one can write said functions into this file and call them by running this file instead.
function main {
    clearscreen.

    local craft_info is make_craft_info().
    print craft_info.

    local fueltank is craft_info[CRAFT_INFO_STAGE_PARTS][1][1].

    print fueltank:allmodules.

    print fueltank:getmodulebyindex(4):allfields.
    print fueltank:getmodulebyindex(5):allfields.

    print fueltank:resources.

    //local desired_periapsis is 90000.0.

    //local dv_bounds is plan_orbital_insertion_init(desired_periapsis).
    //print dv_bounds.

    //local allowed_difference is 0.02.
    //until plan_orbital_insertion_has_converged(dv_bounds, allowed_difference) {
    //    set dv_bounds to plan_orbital_insertion_refine(dv_bounds, desired_periapsis).
    //    print dv_bounds.
    //}

    //plan_orbital_insertion_add_node(dv_bounds).
}


main.
