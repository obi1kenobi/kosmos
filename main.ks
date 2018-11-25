@LAZYGLOBAL OFF.

run once stdlib.
run once os.
run once engine_info.


global DIRECTOR_MODE_PRE_LAUNCH is "prelaunch".
global DIRECTOR_MODE_CLEAR_TOWER is "tower".
global DIRECTOR_MODE_PITCH_PROGRAM is "pitch".
global DIRECTOR_MODE_GRAVITY_TURN is "gravity".
global DIRECTOR_MODE_COAST_TO_AP is "coast".
global DIRECTOR_MODE_CIRCULARIZE is "circular".
global DIRECTOR_MODE_DONE is "done".


global THROTTLE_SETTING is 0.0.
global STEERING_SETTING is ship:facing.
global STATUS_LINE is "nominal".
global CURRENT_MODE is DIRECTOR_MODE_PRE_LAUNCH.
global REQUESTED_MODE is DIRECTOR_MODE_PRE_LAUNCH.


global CRAFT_INFO is readjson("current_craft_info.json").
global CRAFT_INFO_STAGES is CRAFT_INFO["stages"].


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

    if staging_enabled and stage:resourceslex["liquidfuel"]:amount < 0.1 {
        stage.
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
    } else if ship:altitude >= orbit_prograde_start and ship:altitude <= orbit_prograde_end {
        local coeff is rescale_to_fraction_of_unity(
            ship:altitude, orbit_prograde_start, orbit_prograde_end).
        local mixed_prograde is (
            (coeff * ship:prograde:forevector) + ((1 - coeff) * ship:srfprograde:forevector)).
        set desired_steering to mixed_prograde:normalized.
    }

    return list(desired_steering, desired_throttle).
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
        // Plan the circularization manuever, since there either currently isn't one
        // or the existing one isn't satisfactory.
        local prograde_manuever_dv is 0.0.
        local maneuver_periapsis is ship:orbit:periapsis.
        if hasnode {
            set maneuver_periapsis to nextnode:orbit:periapsis.
            set prograde_manuever_dv to nextnode:prograde.

            remove nextnode.
        }

        if maneuver_periapsis <= -50000 {
            set prograde_manuever_dv to prograde_manuever_dv + 100.0.
        } else if maneuver_periapsis <= 30000 {
            set prograde_manuever_dv to prograde_manuever_dv + 10.0.
        } else if maneuver_periapsis <= 80000 {
            set prograde_manuever_dv to prograde_manuever_dv + 1.0.
        } else {
            set prograde_manuever_dv to prograde_manuever_dv + 0.1.
        }

        local new_node is node(time:seconds + eta:apoapsis, 0, 0, prograde_manuever_dv).
        add new_node.
    } else {
        // Estimate the burn time for the manuever, and switch to
        // circularization mode at the right time.
        local manuever_dv is nextnode:deltav:mag.
        local total_burn_time is 0.0.

        local stage_number is stage:number.
        local stage_engines is CRAFT_INFO_STAGES[stage_number].

        local pre_burn_mass is ship:mass * 1000.  // convert to kg
        local stage_max_flow_rate is get_engines_max_mass_flow_rate(stage_engines).
        local stage_max_burn_time is get_engines_max_burn_time(stage_engines, stage:resourceslex).
        local stage_thrust is get_engines_max_vacuum_thrust(stage_engines).

        local needed_stage_burn_time is calculate_single_stage_burn_time(
            stage_thrust, pre_burn_mass, stage_max_flow_rate, manuever_dv).

        local new_status_line is "".

        if needed_stage_burn_time <= stage_max_burn_time {
            set total_burn_time to needed_stage_burn_time.
            set new_status_line to "single stage burn of " + round(needed_stage_burn_time, 3).
        } else {
            assert(
                stage_number > 0,
                "need another stage to circularize orbit: " +
                round(needed_stage_burn_time, 3) + " > " + round(stage_max_burn_time, 3)).
            local next_stage_engines is CRAFT_INFO_STAGES[stage_number - 1].
            assert(
                next_stage_engines:length > 0,
                "no engines on next stage: " + next_stage_engines).

            local post_stage_burn_mass is (
                pre_burn_mass - (stage_max_flow_rate * stage_max_burn_time)).
            local applied_dv is calculate_delta_v(
                stage_thrust, pre_burn_mass, post_stage_burn_mass, stage_max_flow_rate).
            local remaining_dv is manuever_dv - applied_dv.
            assert(
                remaining_dv > 0.0,
                "remaining delta v was not positive: " + remaining_dv).

            local next_max_flow_rate is get_engines_max_mass_flow_rate(next_stage_engines).
            local next_thrust is get_engines_max_vacuum_thrust(next_stage_engines).

            // FIXME: account for discarded parts when staging, since this includes the mass
            //        of the hardware that would be discarded by staging.
            local next_pre_burn_mass is post_stage_burn_mass.

            local next_burn_time is calculate_single_stage_burn_time(
                next_thrust, post_stage_burn_mass, next_max_flow_rate, remaining_dv).
            set total_burn_time to stage_max_burn_time + next_burn_time.

            set new_status_line to "two stage burn of " + round(total_burn_time, 3).
        }

        local node_eta is nextnode:eta.
        local eta_to_burn is node_eta - (total_burn_time / 2).

        set STATUS_LINE to new_status_line + "; eta to burn: " + round(eta_to_burn, 3).

        // Make sure to kill any timewarp a bit before the burn.
        if eta_to_burn < 30 and kuniverse:timewarp:mode <> "physics" {
            set kuniverse:timewarp:warp to 0.
            set kuniverse:timewarp:mode to "physics".

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
    local slow_maneuver_start_seconds is 1.5.

    local allowed_prograde_dv_error is 0.1.
    local prograde_component is vdot(nextnode:deltav, ship:prograde:forevector).

    if prograde_component <= allowed_prograde_dv_error {
        set desired_throttle to 0.0.
        set REQUESTED_MODE to DIRECTOR_MODE_DONE.
    } else if remaining_dv < ship:availablethrust * slow_maneuver_start_seconds {
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
        craft_control[CRAFT_CONTROL_DIRECTOR_FUNC_NAME](
            craft_control, craft_state, desired_steering, desired_throttle).

        local guidance_info is craft_control[CRAFT_CONTROL_GUIDANCE_FUNC_NAME]().
        set desired_steering to guidance_info[0].
        set desired_throttle to guidance_info[1].
        craft_control[CRAFT_CONTROL_CONTROL_FUNC_NAME](
            craft_state, desired_steering, desired_throttle).

        if time:seconds <> craft_history_entry[CRAFT_HISTORY_TIMESTAMP] {
            // set STATUS_LINE to "tick time exceeded".
            //hudtext("tick time exceeded", 1, 2, 22, red, false).
        }
        print_craft_state(status_line, craft_state, desired_steering, desired_throttle).

        wait 0.
    }
}


main().
