@LAZYGLOBAL OFF.


function unreachable {
    parameter message.

    assert(false, "Unreachable condition reached: " + message).
}


function assert {
    parameter truthy, message.

    if not truthy {
        print(message) at (0, 0).
        local illegal is 1.0 / 0.0.
    }
}


function clamp {
    parameter value, clamp_lo, clamp_hi.

    if value < clamp_lo {
        return clamp_lo.
    } else if value > clamp_hi {
        return clamp_hi.
    } else {
        return value.
    }
}


function positive_remainder {
    parameter value, modulus.

    return mod(mod(value, modulus) + modulus, modulus).
}


function rescale_to_fraction_of_unity {
    parameter value, bound_lo, bound_hi.

    local clamped_value is clamp(value, bound_lo, bound_hi).

    local numerator is value - bound_lo.
    local denominator is bound_hi - bound_lo.

    return numerator / denominator.
}


function calculate_single_stage_burn_time {
    parameter thrust, pre_burn_mass, mass_flow_rate, delta_v.

    assert(thrust > 0.0, "Thrust must be positive, but was: " + thrust).

    // First, apply the rocket equation to calculate the necessary mass fraction for the burn.
    local ln_mass_fraction is (delta_v * mass_flow_rate) / thrust.
    local mass_fraction is constant:e ^ ln_mass_fraction.

    local post_burn_mass is pre_burn_mass / mass_fraction.
    assert(
        post_burn_mass <= pre_burn_mass,
        "post_burn_mass " + post_burn_mass + "\n" +
        "pre_burn_mass" + pre_burn_mass + "\n" +
        "mass_fraction" + mass_fraction).

    // Then, calculate how long until the necessary amount of mass is expelled by the engines.
    return (pre_burn_mass - post_burn_mass) / mass_flow_rate.
}


function calculate_delta_v {
    parameter thrust, pre_burn_mass, post_burn_mass, mass_flow_rate.

    assert(mass_flow_rate > 0.0, "Mass flow rate must be positive, but was: " + mass_flow_rate).
    assert(post_burn_mass > 0.0, "Post-burn mass must be positive, but was: " + post_burn_mass).

    // Direct application of the rocket equation.
    local ln_mass_fraction is ln(pre_burn_mass / post_burn_mass).
    return thrust * ln_mass_fraction / mass_flow_rate.
}


function get_or_default {
    // Get the value of the given key in the lexicon, or return a default if the key is not present.
    parameter lex, key, default_value.

    if lex:haskey(key) {
        return lex[key].
    } else {
        return default_value.
    }
}
