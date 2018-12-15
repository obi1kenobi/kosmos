@LAZYGLOBAL OFF.

run once stdlib.


global DENSITY_LIQUID_FUEL is 5.0.
global DENSITY_OXIDIZER is 5.0.
global DENSITY_MONOPROP is 4.0.
global DENSITY_SOLID_FUEL is 7.5.

// Data from: https://wiki.kerbalspaceprogram.com/wiki/Reaction_engine#Liquid_fuel_rocket_engines
global ENGINE_INFO_TYPE is "type".
global ENGINE_INFO_MAX_PROPELLANT_FLOW is "max_propellant_flow".
global ENGINE_INFO_FUEL_RATIO is "fuel_to_oxidizer_ratio".
global ENGINE_INFO_VACUUM_ISP is "vacuum_isp".

global ENGINE_INFO_TYPE_LF_LOX is "lf+lox".
global ENGINE_INFO_TYPE_LF_ONLY is "lf".
global ENGINE_INFO_TYPE_MONOPROP is "monoprop".
global ENGINE_INFO_TYPE_SOLID is "solid".

global ENGINE_INFO_FUEL_FRACTION_IN_FUEL_LOX is 9.0 / 20.0.
global ENGINE_INFO_OXIDIZER_FRACTION_IN_FUEL_LOX is 1.0 - ENGINE_INFO_FUEL_FRACTION_IN_FUEL_LOX.


global ENGINE_INFO is readjson("engines.json").


function get_engine_consumption {
    parameter engine_part.

    local engine_name is engine_part:name.
    local engine_data is ENGINE_INFO[engine_name].
    local engine_type is engine_data[ENGINE_INFO_TYPE].
    local engine_propellant_flow is engine_data[ENGINE_INFO_MAX_PROPELLANT_FLOW].

    local fuel_flow is 0.0.
    local oxidizer_flow is 0.0.
    local monoprop_flow is 0.0.
    local solid_fuel_flow is 0.0.

    if engine_type = ENGINE_INFO_TYPE_LF_LOX {
        set fuel_flow to engine_propellant_flow * ENGINE_INFO_FUEL_FRACTION_IN_FUEL_LOX.
        set oxidizer_flow to engine_propellant_flow - fuel_flow.
    } else if engine_type = ENGINE_INFO_TYPE_LF_ONLY {
        set fuel_flow to engine_propellant_flow.
    } else if engine_type = ENGINE_INFO_TYPE_MONOPROP {
        set monoprop_flow to engine_propellant_flow.
    } else if engine_type = ENGINE_INFO_TYPE_SOLID {
        set solid_fuel_flow to engine_propellant_flow.
    } else {
        unreachable("Unknown engine type: " + engine_data[ENGINE_INFO_TYPE] + " " + engine_data).
    }

    return list(fuel_flow, oxidizer_flow, monoprop_flow, solid_fuel_flow).
}


function get_engines_max_mass_flow_rate {
    parameter engine_list.

    local total_mass_flow_rate is 0.0.

    for engine_part in engine_list {
        local consumption is get_engine_consumption(engine_part).

        set total_mass_flow_rate to total_mass_flow_rate + (
            (consumption[0] * DENSITY_LIQUID_FUEL) +
            (consumption[1] * DENSITY_OXIDIZER) +
            (consumption[2] * DENSITY_MONOPROP) +
            (consumption[3] * DENSITY_SOLID_FUEL)
        ).
    }
    return total_mass_flow_rate.
}


function get_engines_max_burn_time {
    parameter engine_list, resourceslex.

    local total_liquid_fuel is 0.0.
    local total_oxidizer is 0.0.
    local total_monopropellant is 0.0.
    local total_solid_fuel is 0.0.
    if resourceslex:haskey("liquidfuel") {
        set total_liquid_fuel to resourceslex["liquidfuel"].
    }
    if resourceslex:haskey("oxidizer") {
        set total_oxidizer to resourceslex["oxidizer"].
    }
    if resourceslex:haskey("monopropellant") {
        set total_monopropellant to resourceslex["monopropellant"].
    }
    if resourceslex:haskey("solidfuel") {
        set total_solid_fuel to resourceslex["solidfuel"].
    }

    local total_consumption is list(0.0, 0.0, 0.0, 0.0).
    local total_resources is list(
        total_liquid_fuel,
        total_oxidizer,
        total_monopropellant,
        total_solid_fuel
    ).
    assert(
        total_consumption:length = total_resources:length,
        "list length mismatch: " + total_consumption + " vs " + total_resources).

    for engine_part in engine_list {
        local consumption is get_engine_consumption(engine_part).

        for i in range(total_consumption:length) {
            set total_consumption[i] to total_consumption[i] + consumption[i].
        }
    }

    local max_burn_time is -1.0.
    for i in range(total_consumption:length) {
        if total_consumption[i] > 0.0 {
            local burn_time is total_resources[i] / total_consumption[i].
            if max_burn_time < 0 or burn_time < max_burn_time {
                set max_burn_time to burn_time.
            }
        }
    }
    return max_burn_time.
}


function get_engines_max_vacuum_thrust {
    parameter engine_list.

    local total_thrust is 0.0.
    for engine_part in engine_list {
        local engine_name is engine_part:name.
        local engine_data is ENGINE_INFO[engine_name].
        local exhaust_speed is engine_data[ENGINE_INFO_VACUUM_ISP] * 9.81.
        local flow_rate is get_engines_max_mass_flow_rate(list(engine_part)).

        set total_thrust to total_thrust + (exhaust_speed * flow_rate).
    }

    return total_thrust.
}
