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


function rescale_to_fraction_of_unity {
	parameter value, bound_lo, bound_hi.

	local clamped_value is clamp(value, bound_lo, bound_hi).

	local numerator is value - bound_lo.
	local denominator is bound_hi - bound_lo.

	return numerator / denominator.
}


function calculate_ts_rate {
	parameter last_craft_history, current_craft_history, time_key, value_key.

	local time_step is current_craft_history[time_key] - last_craft_history[time_key].
	if time_step = 0.0 {
		return 0.0.
	}
	return (current_craft_history[value_key] - last_craft_history[value_key]) / time_step.
}


function calculate_single_stage_burn_time {
	parameter thrust, pre_burn_mass, mass_flow_rate, delta_v.

	assert(thrust > 0.0, "thrust must be positive, but was: " + thrust).

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

	// Direct application of the rocket equation.
	local ln_mass_fraction is ln(pre_burn_mass / post_burn_mass).
	return thrust * ln_mass_fraction / mass_flow_rate.
}
