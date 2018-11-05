@LAZYGLOBAL OFF.


function main {
	run os.
	set terminal:width to 50.
	set terminal:height to 30.
	set terminal:charheight to 22.

	//local craft_control is make_craft_control_struct().
	until false {
		local tick_start_seconds is time:seconds.

		local craft_state is make_craft_state_struct().

		local status_line is "nominal".
		if time:seconds <> tick_start_seconds {
			set status_line to "tick time exceeded".
			hudtext("tick time exceeded", 1, 2, 14, red, false).
		}
		print_craft_state(status_line, craft_state).

		wait 0.
	}
}


main().
