@LAZYGLOBAL OFF.

run once engine_info.
run once logging.
run once os.
run once stdlib.

local _planning_logger is get_logger("planning").


function plan_orbital_insertion_init {
    parameter desired_periapsis.

    local starting_maneuver_dv is 0.0.
    local starting_periapsis is ship:orbit:periapsis.
    local starting_apoapsis is ship:orbit:apoapsis.

    assert(allnodes:length = 0, "Expected no maneuver nodes, but found: " + allnodes).
    assert(
        desired_periapsis <= starting_apoapsis,
        "Cannot raise periapsis above the current orbit apoapsis. Requested PE: " +
        desired_periapsis + " but current AP: " + starting_apoapsis).

    // Calculate a coarse upper bound for the maneuver delta-V requirement by making
    // large steps in delta-V until we can show we've achieved (and probably exceeded)
    // the desired final orbit.
    local step_size is 1000.0.
    local maneuver_dv is starting_maneuver_dv + step_size.
    local next_node is node(time:seconds + eta:apoapsis, 0, 0, maneuver_dv).
    add next_node.
    until next_node:orbit:periapsis >= desired_periapsis {
        remove next_node.
        set maneuver_dv to maneuver_dv + step_size.
        set next_node to node(time:seconds + eta:apoapsis, 0, 0, maneuver_dv).
        add next_node.
    }
    remove next_node.

    // Return a list containing the delta-V bounds of the requested maneuver.
    return list(maneuver_dv - step_size, maneuver_dv).
}


function plan_orbital_insertion_refine {
    parameter dv_bounds, desired_periapsis.

    local starting_apoapsis is ship:orbit:apoapsis.

    assert(allnodes:length = 0, "Expected no maneuver nodes, but found: " + allnodes).
    assert(
        desired_periapsis <= starting_apoapsis,
        "Cannot raise periapsis above the current orbit apoapsis. Requested PE: " +
        desired_periapsis + " but current AP: " + starting_apoapsis).
    assert(dv_bounds:length = 2, "Expected delta-V bounds list of length 2 but got: " + dv_bounds).

    local dv_lower is dv_bounds[0].
    local dv_upper is dv_bounds[1].

    local dv_mid is (dv_lower + dv_upper) / 2.
    local next_node is node(time:seconds + eta:apoapsis, 0, 0, dv_mid).
    add next_node.

    if next_node:orbit:periapsis >= desired_periapsis {
        set dv_bounds to list(dv_lower, dv_mid).
    } else {
        set dv_bounds to list(dv_mid, dv_upper).
    }
    remove next_node.

    return dv_bounds.
}


function plan_orbital_insertion_has_converged {
    parameter dv_bounds, allowed_difference.

    local dv_difference is dv_bounds[1] - dv_bounds[0].
    assert(dv_difference >= 0.0, "Expected non-negative dv_difference, but got: " + dv_difference).

    return dv_difference <= allowed_difference.
}


function plan_orbital_insertion_add_node {
    parameter dv_bounds.

    // The upper bound is guaranteed to produce an orbit that is at least as high as desired.
    // This is why we use the upper bound exclusively when setting the maneuver node.
    local dv_mid is dv_bounds[1].
    local next_node is node(time:seconds + eta:apoapsis, 0, 0, dv_mid).
    add next_node.
}
