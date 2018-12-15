@LAZYGLOBAL OFF.

run once craft_info.
run once engine_info.
run once logging.
run once maneuver_planning.
run once os.
run once stdlib.


global DIRECTOR_MODE_PRE_LAUNCH is "prelaunch".
global DIRECTOR_MODE_CLEAR_TOWER is "tower".
global DIRECTOR_MODE_PITCH_PROGRAM is "pitch".
global DIRECTOR_MODE_GRAVITY_TURN is "gravity".
global DIRECTOR_MODE_COAST_TO_AP is "coast".
global DIRECTOR_MODE_CIRCULARIZE is "circular".
global DIRECTOR_MODE_DONE is "done".

global STATUS_LINE is "nominal".
global CURRENT_MODE is DIRECTOR_MODE_PRE_LAUNCH.
global REQUESTED_MODE is DIRECTOR_MODE_PRE_LAUNCH.


function control_func_base {
    parameter staging_enabled.
    parameter craft_state.
    parameter desired_steering.
    parameter desired_throttle.

    set THROTTLE_SETTING to desired_throttle.

    if ship:altitude >= ship:body:atm:height {
        // We're above the atmosphere, point orbit prograde instead of surface prograde
        // since there is no more air drag to worry about.
        set STEERING_SETTING to desired_steering.
    } else if (
            craft_state[CRAFT_STATE_ANGLE_FROM_SRF_PROGRADE] >= 7.0 or
            craft_state[CRAFT_STATE_LATERAL_AIR_PRESSURE] >= 0.05) {
        set STEERING_SETTING to ship:facing.  // FIXME: this doesn't quite do the right thing
    } else {
        set STEERING_SETTING to desired_steering.
    }

    if staging_enabled {
        local resourceslex is stage:resourceslex.

        local liquid_fuel is resourceslex["liquidfuel"].
        local should_stage_for_liquid_fuel is (
            liquid_fuel:amount < 0.1 and liquid_fuel:capacity > 0.0).

        local solid_fuel is resourceslex["solidfuel"].
        local should_stage_for_solid_fuel is (
            solid_fuel:amount < 0.1 and solid_fuel:capacity > 0.0).

        if should_stage_for_liquid_fuel or should_stage_for_solid_fuel {
            stage_and_refresh_info().
        }
    }
}


local staging_enabled_control_func is control_func_base@:bind(true).
local staging_disabled_control_func is control_func_base@:bind(false).


function guidance_off_the_pad {
    local desired_throttle is 1.0.
    local desired_steering is ship:up.

    if ship:velocity:surface:mag >= 65 {
        set REQUESTED_MODE to DIRECTOR_MODE_PITCH_PROGRAM.
    }
    return list(desired_steering, desired_throttle).
}


function guidance_pitch_program {
    local pitch_degree is 5.0.
    local desired_throttle is 1.0.
    local desired_steering is angleaxis(-pitch_degree, ship:north:forevector) * ship:up.

    // If the ship is sufficiently close to the 4-degree pitch, switch to gravity turn.
    local eastward is vcrs(ship:up:forevector, ship:north:forevector).
    local facing_easterly is vdot(ship:facing:forevector, eastward).
    local desired_easterly is vdot(desired_steering:forevector, eastward).
    if facing_easterly >= 0.95 * desired_easterly {
        set REQUESTED_MODE to DIRECTOR_MODE_GRAVITY_TURN.
    }

    return list(desired_steering, desired_throttle).
}


function guidance_gravity_turn {
    local desired_throttle is 1.0.
    local desired_steering is ship:srfprograde.

    local coast_ap_altitude is 90000.
    local orbit_prograde_start is 10000.
    local orbit_prograde_end is 40000.

    if ship:orbit:apoapsis >= coast_ap_altitude {
        set REQUESTED_MODE to DIRECTOR_MODE_COAST_TO_AP.
        set desired_throttle to 0.0.
    } else if ship:altitude >= orbit_prograde_start and ship:altitude <= orbit_prograde_end {
        local coeff is rescale_to_fraction_of_unity(
            ship:altitude, orbit_prograde_start, orbit_prograde_end).
        local mixed_prograde is (
            (coeff * ship:prograde:forevector) + ((1 - coeff) * ship:srfprograde:forevector)).
        set desired_steering to mixed_prograde:normalized.
    } else if ship:altitude > orbit_prograde_end {
        set desired_steering to ship:prograde.
    }

    return list(desired_steering, desired_throttle).
}


local function _calculate_circularization_maneuver {
    // Plan the circularization maneuver, since there either currently isn't one
    // or the existing one isn't satisfactory.
    parameter desired_periapsis.

    if hasnode {
        remove nextnode.
    }

    local dv_bounds is plan_orbital_insertion_init(desired_periapsis).
    local allowed_dv_error is 0.02.
    until plan_orbital_insertion_has_converged(dv_bounds, allowed_dv_error) {
        set dv_bounds to plan_orbital_insertion_refine(dv_bounds, desired_periapsis).
    }

    plan_orbital_insertion_add_node(dv_bounds).
}


local function _calculate_burn_start_time {
    // Estimate the burn time for the maneuver, and switch to
    // circularization mode at the right time.
    parameter maneuver_dv, maneuver_eta.

    local maneuver_args is plan_maneuver_time_init(craft_info, maneuver_dv).
    local allowed_time_error is 0.1.

    until plan_maneuver_time_has_converged(maneuver_args, allowed_time_error) {
        set maneuver_args to plan_maneuver_time_refine(craft_info, maneuver_args).
    }
    local maneuver_early_start_time is plan_maneuver_time_finalize(maneuver_args).

    local eta_to_burn is maneuver_eta - maneuver_early_start_time.

    set STATUS_LINE to "eta to burn: " + round(eta_to_burn, 3).

    return eta_to_burn.
}


function guidance_coast_to_ap {
    local desired_steering is ship:srfprograde.
    local desired_throttle is 0.0.

    if ship:altitude >= ship:body:atm:height {
        // We're above the atmosphere, point orbit prograde instead of surface prograde
        // since there is no more air drag to worry about.
        set desired_steering to ship:prograde.
    }

    if ship:orbit:apoapsis <= 80000 {
        // Our apoapsis has drifted too low, presumably because of air drag.
        // Reset guidance back to gravity turn mode so we restart the engines and boost once more.
        set REQUESTED_MODE to DIRECTOR_MODE_GRAVITY_TURN.
        return list(desired_steering, desired_throttle).
    }

    local min_desired_periapsis is min(90000, ship:orbit:apoapsis).
    if not hasnode or nextnode:orbit:periapsis < min_desired_periapsis {
        refresh_craft_info().
        _calculate_circularization_maneuver(min_desired_periapsis).
    } else {
        local maneuver_dv is nextnode:deltav:mag.
        local maneuver_eta is nextnode:eta.
        local eta_to_burn is _calculate_burn_start_time(maneuver_dv, maneuver_eta).

        // Make sure to kill any timewarp a bit before the burn.
        if eta_to_burn < 30 and kuniverse:timewarp:mode <> "physics" {
            set kuniverse:timewarp:warp to 0.
            set kuniverse:timewarp:mode to "physics".
        }

        if eta_to_burn < 30 {
            set desired_steering to nextnode:deltav:normalized.
        }

        if eta_to_burn < 0.1 {
            set REQUESTED_MODE to DIRECTOR_MODE_CIRCULARIZE.
        }
    }

    return list(desired_steering, desired_throttle).
}


function guidance_prograde_node_burn {
    assert(hasnode, "no maneuver node was found").

    local desired_steering is nextnode:deltav:normalized.
    local desired_throttle is 1.0.

    local remaining_dv is nextnode:deltav:mag.
    local slow_maneuver_start_seconds is 1.0.

    local allowed_prograde_dv_error is 0.1.
    local prograde_component is vdot(nextnode:deltav, ship:prograde:forevector).

    if prograde_component <= allowed_prograde_dv_error {
        set desired_throttle to 0.0.
        set REQUESTED_MODE to DIRECTOR_MODE_DONE.
    } else if remaining_dv < (ship:availablethrust * slow_maneuver_start_seconds) {
        set desired_throttle to 0.3.
    }

    return list(desired_steering, desired_throttle).
}


function guidance_done {
    local desired_steering is ship:prograde.
    local desired_throttle is 0.0.

    return list(desired_steering, desired_throttle).
}


function flight_director {
    parameter craft_control.
    parameter craft_state.
    parameter desired_steering.
    parameter desired_throttle.

    if REQUESTED_MODE <> CURRENT_MODE {
        if REQUESTED_MODE = DIRECTOR_MODE_CLEAR_TOWER {
            sas off.
            lock steering to STEERING_SETTING.
            lock throttle to THROTTLE_SETTING.
            stage.

            set craft_control[CRAFT_CONTROL_CONTROL_FUNC_NAME] to staging_disabled_control_func@.
            set craft_control[CRAFT_CONTROL_GUIDANCE_FUNC_NAME] to guidance_off_the_pad@.
        } else if REQUESTED_MODE = DIRECTOR_MODE_PITCH_PROGRAM {
            set craft_control[CRAFT_CONTROL_CONTROL_FUNC_NAME] to staging_disabled_control_func@.
            set craft_control[CRAFT_CONTROL_GUIDANCE_FUNC_NAME] to guidance_pitch_program@.
        } else if REQUESTED_MODE = DIRECTOR_MODE_GRAVITY_TURN {
            set craft_control[CRAFT_CONTROL_CONTROL_FUNC_NAME] to staging_enabled_control_func@.
            set craft_control[CRAFT_CONTROL_GUIDANCE_FUNC_NAME] to guidance_gravity_turn@.
        } else if REQUESTED_MODE = DIRECTOR_MODE_COAST_TO_AP {
            set craft_control[CRAFT_CONTROL_CONTROL_FUNC_NAME] to staging_disabled_control_func@.
            set craft_control[CRAFT_CONTROL_GUIDANCE_FUNC_NAME] to guidance_coast_to_ap@.
        } else if REQUESTED_MODE = DIRECTOR_MODE_CIRCULARIZE {
            set craft_control[CRAFT_CONTROL_CONTROL_FUNC_NAME] to staging_enabled_control_func@.
            set craft_control[CRAFT_CONTROL_GUIDANCE_FUNC_NAME] to guidance_prograde_node_burn@.
        } else if REQUESTED_MODE = DIRECTOR_MODE_DONE {
            set craft_control[CRAFT_CONTROL_CONTROL_FUNC_NAME] to staging_disabled_control_func@.
            set craft_control[CRAFT_CONTROL_GUIDANCE_FUNC_NAME] to guidance_done@.
        } else {
            unreachable("unknown mode: " + REQUESTED_MODE).
        }

        set CURRENT_MODE to REQUESTED_MODE.
        set STATUS_LINE to CURRENT_MODE + "                                                  ".
    }
}


function main {
    local main_loop_logger is get_logger("main_loop").
    main_loop_logger("Initializing...").

    local craft_state_logger is get_logger("craft_state").
    local craft_guidance_logger is get_logger("guidance").

    set terminal:width to 50.
    set terminal:height to 30.
    set terminal:charheight to 22.
    clearscreen.

    local craft_control is make_craft_control_struct(
        flight_director@,
        guidance_off_the_pad@,
        staging_disabled_control_func@,
        list()
    ).
    local craft_history is list(make_craft_history_entry(THROTTLE_SETTING)).

    local desired_steering is ship:up.
    local desired_throttle is 1.0.
    set STEERING_SETTING to desired_steering.
    set THROTTLE_SETTING to desired_throttle.

    set REQUESTED_MODE to DIRECTOR_MODE_CLEAR_TOWER.

    until false {
        local craft_history_entry is make_craft_history_entry(THROTTLE_SETTING).
        craft_history:add(craft_history_entry).

        local craft_state is make_craft_state_struct(craft_history).
        craft_state_logger(craft_state).

        craft_control[CRAFT_CONTROL_DIRECTOR_FUNC_NAME](
            craft_control, craft_state, desired_steering, desired_throttle).

        local guidance_info is craft_control[CRAFT_CONTROL_GUIDANCE_FUNC_NAME]().
        craft_guidance_logger(guidance_info).
        set desired_steering to guidance_info[0].
        set desired_throttle to guidance_info[1].
        craft_control[CRAFT_CONTROL_CONTROL_FUNC_NAME](
            craft_state, desired_steering, desired_throttle).

        print_craft_state(status_line, craft_state, desired_steering, desired_throttle).

        local loop_time is time:seconds - craft_history_entry[CRAFT_HISTORY_TIMESTAMP].
        main_loop_logger("Loop time: " + round(loop_time, 3)).

        wait 0.
    }
}


main().
