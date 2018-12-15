@LAZYGLOBAL OFF.

run once stdlib.
run once craft_info.


global CRAFT_INFO is make_craft_info().

global THROTTLE_SETTING is 0.0.
global STEERING_SETTING is ship:facing.


function refresh_craft_info {
    set CRAFT_INFO to make_craft_info().
}


function stage_and_refresh_info {
    stage.

    until stage:ready {
        wait 0.
    }

    refresh_craft_info().
}


global CRAFT_CONTROL_DIRECTOR_FUNC_NAME is "director".
global CRAFT_CONTROL_GUIDANCE_FUNC_NAME is "guidance".
global CRAFT_CONTROL_CONTROL_FUNC_NAME is "control".
global CRAFT_CONTROL_MISC_FUNCS_NAME is "misc".


function make_craft_control_struct {
    parameter
        flight_director_func,
        guidance_func,
        control_func,
        misc_funcs.

    local craft_control is lexicon().
    craft_control:add(CRAFT_CONTROL_DIRECTOR_FUNC_NAME, flight_director_func@).
    craft_control:add(CRAFT_CONTROL_GUIDANCE_FUNC_NAME, guidance_func@).
    craft_control:add(CRAFT_CONTROL_CONTROL_FUNC_NAME, control_func@).
    craft_control:add(CRAFT_CONTROL_MISC_FUNCS_NAME, misc_funcs).

    return craft_control.
}


global CRAFT_HISTORY_TIMESTAMP is "timestamp".
global CRAFT_HISTORY_MASS_KG is "mass".
global CRAFT_HISTORY_STAGE_NUMBER is "stage".
global CRAFT_HISTORY_STAGE_LIQUID_FUEL is "stage_liquid_fuel".
global CRAFT_HISTORY_STAGE_OXIDIZER is "stage_oxidizer".
global CRAFT_HISTORY_THROTTLE is "throttle".


function make_craft_history_entry {
    parameter current_throttle.

    local history is lexicon().

    local captured_valid_data is false.

    local timestamp is 0.
    local mass_at_ts is 0.
    local stage_number is 0.
    local stage_liquid_fuel is 0.
    local stage_oxidizer is 0.

    until captured_valid_data {
        set timestamp to time:seconds.
        set mass_at_ts to ship:mass * 1000.
        set stage_number to stage:number.
        set stage_liquid_fuel to stage:resourceslex["liquidfuel"]:amount.
        set stage_oxidizer to stage:resourceslex["oxidizer"]:amount.
        set captured_valid_data to (timestamp = time:seconds).
    }

    history:add(CRAFT_HISTORY_TIMESTAMP, timestamp).
    history:add(CRAFT_HISTORY_MASS_KG, mass_at_ts).
    history:add(CRAFT_HISTORY_STAGE_NUMBER, stage_number).
    history:add(CRAFT_HISTORY_STAGE_LIQUID_FUEL, stage_liquid_fuel).
    history:add(CRAFT_HISTORY_STAGE_OXIDIZER, stage_oxidizer).
    history:add(CRAFT_HISTORY_THROTTLE, current_throttle).

    return history.
}.


global CRAFT_STATE_ANGLE_FROM_ORB_PROGRADE is "angle_from_orb".
global CRAFT_STATE_ANGLE_FROM_SRF_PROGRADE is "angle_from_srf".
global CRAFT_STATE_HEADING is "heading".
global CRAFT_STATE_PITCH is "pitch".
global CRAFT_STATE_LATERAL_AIR_PRESSURE is "lateral_pressure".
global CRAFT_STATE_MASS_FLOW_RATE is "mass_flow_rate".
global CRAFT_STATE_STEERING_ERROR is "steering_error".


function make_craft_state_struct {
    parameter craft_history.

    local craft_state is lexicon().

    local ship_vector is ship:facing:forevector.
    local steering_vector is STEERING_SETTING.
    if steering_vector:istype("Direction") {
        set steering_vector to steering_vector:forevector.
    }
    local steering_error is vectorangle(ship_vector, steering_vector).
    craft_state:add(CRAFT_STATE_STEERING_ERROR, steering_error).

    local srf_prograde_vector is ship:srfprograde:forevector.
    local orb_prograde_vector is ship:prograde:forevector.

    local min_magnitude is 1.  // do not calculate angles when velocity is <1m/s.

    local angle_from_srf is 0.
    local angle_from_orb is 0.

    if ship:velocity:surface:mag >= min_magnitude {
        set angle_from_srf to vectorangle(ship_vector, srf_prograde_vector).
    }
    if ship:velocity:orbit:mag >= min_magnitude {
        set angle_from_orb to vectorangle(ship_vector, orb_prograde_vector).
    }
    craft_state:add(CRAFT_STATE_ANGLE_FROM_SRF_PROGRADE, angle_from_srf).
    craft_state:add(CRAFT_STATE_ANGLE_FROM_ORB_PROGRADE, angle_from_orb).

    local ship_heading is vectorangle(ship_vector, ship:north:forevector).
    local ship_pitch is vectorangle(ship_vector, ship:up:forevector).
    craft_state:add(CRAFT_STATE_HEADING, ship_heading).
    craft_state:add(CRAFT_STATE_PITCH, ship_pitch).

    local total_pressure is ship:dynamicpressure + ship:body:atm:altitudepressure(ship:altitude).
    local lateral_pressure is sin(angle_from_srf) * total_pressure.
    craft_state:add(CRAFT_STATE_LATERAL_AIR_PRESSURE, lateral_pressure).

    local current_history is craft_history[craft_history:length - 1].
    local last_history is craft_history[craft_history:length - 2].
    local mass_flow_rate is 0.0.
    if current_history[CRAFT_HISTORY_STAGE_NUMBER] = last_history[CRAFT_HISTORY_STAGE_NUMBER] {
        set mass_flow_rate to calculate_ts_rate(
            last_history, current_history, CRAFT_HISTORY_TIMESTAMP, CRAFT_HISTORY_MASS_KG).
    }
    craft_state:add(CRAFT_STATE_MASS_FLOW_RATE, mass_flow_rate).

    return craft_state.
}


function print_craft_state {
    parameter
        status_line,
        craft_state,
        desired_steering,
        desired_throttle.

    local ship_vector is ship:facing:forevector.

    local srf_angle is craft_state[CRAFT_STATE_ANGLE_FROM_SRF_PROGRADE].
    local orb_angle is craft_state[CRAFT_STATE_ANGLE_FROM_ORB_PROGRADE].
    local ship_heading is craft_state[CRAFT_STATE_HEADING].
    local ship_pitch is craft_state[CRAFT_STATE_PITCH].
    local lateral_pressure is craft_state[CRAFT_STATE_LATERAL_AIR_PRESSURE].
    local mass_flow_rate is craft_state[CRAFT_STATE_MASS_FLOW_RATE].
    local steering_error is craft_state[CRAFT_STATE_STEERING_ERROR].

    print("STATUS:             " + status_line) at (0, 0).
    print("Ship facing:        " + round(ship_heading, 2) + " " + round(ship_pitch, 2)) at (0, 3).
    print("Angle srf prograde: " + round(srf_angle, 2)) at (0, 4).
    print("Angle orb prograde: " + round(orb_angle, 2)) at (0, 5).
    print("Lateral pressure:   " + round(lateral_pressure, 8)) at (0, 6).
    print("Desired steering:   " + desired_steering) at (0, 7).
    print("Desired throttle:   " + round(desired_throttle, 2)) at (0, 8).
    print("Mass flow rate:     " + round(mass_flow_rate, 6)) at (0, 9).
    print("Steering error:     " + round(steering_error, 2)) at (0, 10).
}
