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
