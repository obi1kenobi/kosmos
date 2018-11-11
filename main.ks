@LAZYGLOBAL OFF.


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


function control_func {
    parameter craft_state.
    parameter desired_steering.
    parameter desired_throttle.

    set THROTTLE_SETTING to desired_throttle.

    if craft_state[CRAFT_STATE_ANGLE_FROM_SRF_PROGRADE] >= 7.0 or
       craft_state[CRAFT_STATE_LATERAL_AIR_PRESSURE] >= 0.05 {
        set STEERING_SETTING to ship:facing.  // doesn't quite work
    } else {
        set STEERING_SETTING to desired_steering.
    }

    if stage:resourceslex["liquidfuel"]:amount < 0.1 {
        stage.
    }
}


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

    if ship:orbit:apoapsis >= 90000 {
        set REQUESTED_MODE to DIRECTOR_MODE_COAST_TO_AP.
    } else if ship:altitude >= 10000 and ship:altitude <= 40000 {
        local coeff is (ship:altitude - 10000) / 30000.
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
        set desired_steering to ship:prograde.
    }

    if ship:orbit:apoapsis <= 80000 {
        set REQUESTED_MODE to DIRECTOR_MODE_GRAVITY_TURN.
    } else if ship:orbit:periapsis <= 20000 and eta:apoapsis <= 30 {
        set REQUESTED_MODE to DIRECTOR_MODE_CIRCULARIZE.
    } else if eta:apoapsis <= 5 {
        set REQUESTED_MODE to DIRECTOR_MODE_CIRCULARIZE.
    }

    return list(desired_steering, desired_throttle).
}


function guidance_circularize {
    local desired_steering is ship:prograde.
    local desired_throttle is 1.0.

    if ship:orbit:periapsis >= 90000 {
        set REQUESTED_MODE to DIRECTOR_MODE_DONE.
    } else if eta:periapsis < eta:apoapsis {
        // falling back, continue burning
    } else if eta:apoapsis >= 20 and ship:orbit:periapsis >= 20000 {
        set REQUESTED_MODE to DIRECTOR_MODE_COAST_TO_AP.
    } else if eta:apoapsis >= 50 {
        set REQUESTED_MODE to DIRECTOR_MODE_COAST_TO_AP.
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
        if REQUESTED_MODE = DIRECTOR_MODE_PITCH_PROGRAM {
            set craft_control[CRAFT_CONTROL_GUIDANCE_FUNC_NAME] to guidance_pitch_program@.
        } else if REQUESTED_MODE = DIRECTOR_MODE_GRAVITY_TURN {
            set craft_control[CRAFT_CONTROL_GUIDANCE_FUNC_NAME] to guidance_gravity_turn@.
        } else if REQUESTED_MODE = DIRECTOR_MODE_COAST_TO_AP {
            set craft_control[CRAFT_CONTROL_GUIDANCE_FUNC_NAME] to guidance_coast_to_ap@.
        } else if REQUESTED_MODE = DIRECTOR_MODE_CIRCULARIZE {
            set craft_control[CRAFT_CONTROL_GUIDANCE_FUNC_NAME] to guidance_circularize@.
        } else if REQUESTED_MODE = DIRECTOR_MODE_DONE {
            set craft_control[CRAFT_CONTROL_GUIDANCE_FUNC_NAME] to guidance_done@.
        }

        set CURRENT_MODE to REQUESTED_MODE.
        set STATUS_LINE to CURRENT_MODE + "        ".
    }
}


function main {
    run os.
    set terminal:width to 50.
    set terminal:height to 30.
    set terminal:charheight to 22.
    clearscreen.

    local craft_control is make_craft_control_struct(
        flight_director@,
        guidance_off_the_pad@,
        control_func@,
        list()
    ).

    local desired_steering is ship:up.
    local desired_throttle is 1.0.
    set STEERING_SETTING to desired_steering.
    set THROTTLE_SETTING to desired_throttle.

    sas off.
    lock steering to STEERING_SETTING.
    lock throttle to THROTTLE_SETTING.
    stage.
    set CURRENT_MODE to DIRECTOR_MODE_CLEAR_TOWER.

    until false {
        local tick_start_seconds is time:seconds.

        local craft_state is make_craft_state_struct().
        craft_control[CRAFT_CONTROL_DIRECTOR_FUNC_NAME](
            craft_control, craft_state, desired_steering, desired_throttle).

        local guidance_info is craft_control[CRAFT_CONTROL_GUIDANCE_FUNC_NAME]().
        set desired_steering to guidance_info[0].
        set desired_throttle to guidance_info[1].
        craft_control[CRAFT_CONTROL_CONTROL_FUNC_NAME](
            craft_state, desired_steering, desired_throttle).

        if time:seconds <> tick_start_seconds {
            // set STATUS_LINE to "tick time exceeded".
            //hudtext("tick time exceeded", 1, 2, 22, red, false).
        }
        print_craft_state(status_line, craft_state, desired_steering, desired_throttle).

        wait 0.
    }
}


main().
