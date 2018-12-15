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
    if hasnode {
        remove nextnode.
    }

    local craft_info is make_craft_info().
    //print craft_info.

    local desired_periapsis is 90000.0.

    local dv_bounds is plan_orbital_insertion_init(desired_periapsis).
    //print dv_bounds.

    local allowed_difference is 0.02.
    until plan_orbital_insertion_has_converged(dv_bounds, allowed_difference) {
        set dv_bounds to plan_orbital_insertion_refine(dv_bounds, desired_periapsis).
        //print dv_bounds.
    }

    local next_node is plan_orbital_insertion_add_node(dv_bounds).
    local burn_dv is next_node:deltav:mag.

    local maneuver_args is plan_maneuver_time_init(craft_info, burn_dv).
    print maneuver_args.

    until plan_maneuver_time_has_converged(maneuver_args, 0.1) {
        set maneuver_args to plan_maneuver_time_refine(craft_info, maneuver_args).
        print maneuver_args.
    }

    local maneuver_early_start_time is plan_maneuver_time_finalize(maneuver_args).
    print maneuver_early_start_time.
}


main.
