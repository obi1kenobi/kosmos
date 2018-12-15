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

    assert(allnodes:length = 0, "Expected no maneuver nodes, but found: " + allnodes).

    // The upper bound is guaranteed to produce an orbit that is at least as high as desired.
    // This is why we use the upper bound exclusively when setting the maneuver node.
    local next_node is node(time:seconds + eta:apoapsis, 0, 0, dv_bounds[1]).
    add next_node.
    return next_node.
}


function plan_maneuver_time_init {
    // Calculate how long before the maneuver node a maneuver with given delta-V should start,
    // such that half of the delta-V happens before the maneuver node, and half happens after.
    // This helps with stages with very low thrust at maneuver start, and high thrust near burnout.
    //
    // Assumptions:
    // - Engines that burn out after being activated by staging are discarded right away at burnout.
    // - Engines do not burn for more than one stage, and only draw propellants from tanks that are
    //   discarded in the same staging command as the engine itself.
    parameter craft_info, maneuver_dv.

    local initial_stage is stage:number.
    local current_stage is initial_stage.
    local pre_burn_mass is ship:mass * 1000.  // convert to kg.
    local remaining_dv is maneuver_dv.

    local maneuver_dv_components is list().
    local maneuver_time_components is list().

    until remaining_dv = 0.0 or current_stage < 0 {
        print remaining_dv + " " + current_stage.

        local stage_engines is craft_info[CRAFT_INFO_STAGE_ENGINES][current_stage].

        if stage_engines:length > 0 {
            local stage_resources is craft_info[CRAFT_INFO_RESOURCE_AMOUNTS][current_stage].

            local stage_max_flow_rate is get_engines_max_mass_flow_rate(stage_engines).
            local stage_max_burn_time is get_engines_max_burn_time(stage_engines, stage_resources).
            local stage_thrust is get_engines_max_vacuum_thrust(stage_engines).

            local post_stage_burn_mass is (
                pre_burn_mass - (stage_max_flow_rate * stage_max_burn_time)).
            local applied_dv is calculate_delta_v(
                stage_thrust, pre_burn_mass, post_stage_burn_mass, stage_max_flow_rate).

            if applied_dv >= remaining_dv {
                local needed_stage_burn_time is calculate_single_stage_burn_time(
                    stage_thrust, pre_burn_mass, stage_max_flow_rate, maneuver_dv).
                maneuver_dv_components:add(remaining_dv).
                maneuver_time_components:add(needed_stage_burn_time).
                set remaining_dv to 0.0.
            } else {
                maneuver_dv_components:add(applied_dv).
                maneuver_time_components:add(stage_max_burn_time).
                set remaining_dv to remaining_dv - applied_dv.
            }
        }
        set current_stage to current_stage - 1.
        set pre_burn_mass to craft_info[CRAFT_INFO_CUM_MASS_BY_STAGE][current_stage].
    }

    assert(
        current_stage >= 0,
        "Ran out of stages before achieving delta-V requirement: " + remaining_dv + " " +
        maneuver_dv_components + " " + maneuver_time_components).
    assert(
        maneuver_time_components:length = maneuver_dv_components:length,
        "Component mismatch: " + maneuver_dv_components + " " + maneuver_time_components).

    local remaining_half_dv is maneuver_dv / 2.
    local accumulated_time is 0.0.
    local stage_being_consumed is initial_stage.
    local time_bound is 0.0.
    for i in range(maneuver_time_components:length) {
        local component_dv is maneuver_dv_components[i].
        local component_time is maneuver_time_components[i].

        if component_dv >= remaining_half_dv {
            set time_bound to component_time.
            break.
        } else {
            set remaining_half_dv to remaining_half_dv - component_dv.
            set accumulated_time to component_time.
            set stage_being_consumed to stage_being_consumed - 1.
        }
    }

    // Return all the data necessary to refine the maneuver.
    return list(
        stage_being_consumed,
        remaining_half_dv,
        accumulated_time,
        list(0, time_bound)
    ).
}


function plan_maneuver_time_refine {
    parameter craft_info, maneuver_args.

    local stage_being_consumed is maneuver_args[0].
    local remaining_half_dv is maneuver_args[1].
    local accumulated_time is maneuver_args[2].
    local time_bounds is maneuver_args[3].

    local mid_burn_time is (time_bounds[0] + time_bounds[1]) / 2.0.

    local stage_engines is craft_info[CRAFT_INFO_STAGE_ENGINES][stage_being_consumed].
    local stage_resources is craft_info[CRAFT_INFO_RESOURCE_AMOUNTS][stage_being_consumed].

    local initial_mass is craft_info[CRAFT_INFO_CUM_MASS_BY_STAGE][stage_being_consumed].
    local stage_max_flow_rate is get_engines_max_mass_flow_rate(stage_engines).
    local stage_max_burn_time is get_engines_max_burn_time(stage_engines, stage_resources).
    local stage_thrust is get_engines_max_vacuum_thrust(stage_engines).

    local post_burn_mass is (
        initial_mass - (stage_max_flow_rate * mid_burn_time)).
    local applied_dv is calculate_delta_v(
        stage_thrust, initial_mass, post_burn_mass, stage_max_flow_rate).

    local new_time_bounds is list(time_bounds[0], time_bounds[1]).
    if applied_dv >= remaining_half_dv {
        set new_time_bounds[1] to mid_burn_time.
    } else {
        set new_time_bounds[0] to mid_burn_time.
    }

    return list(
        stage_being_consumed,
        remaining_half_dv,
        accumulated_time,
        new_time_bounds
    ).
}


function plan_maneuver_time_has_converged {
    parameter maneuver_args, allowed_difference.

    local time_bounds is maneuver_args[3].

    local time_difference is time_bounds[1] - time_bounds[0].
    assert(
        time_difference >= 0.0,
        "Expected non-negative time_difference, but got: " + time_difference).

    return time_difference <= allowed_difference.
}


function plan_maneuver_time_finalize {
    parameter maneuver_args.

    local accumulated_time is maneuver_args[2].
    local time_bounds is maneuver_args[3].

    return accumulated_time + time_bounds[1].
}
