@LAZYGLOBAL OFF.

run once stdlib.
run once logging.


local _orbits_logger is get_logger("orbits").


function get_ship_relative_inclination_trig {
    parameter target_orbitable.

    local common_parent_body is ship:body.
    assert(
        target_orbitable:hasbody,
        "Target " + target_orbitable:name + " does not have a parent body. " +
        "Cannot calculate relative inclination.").
    assert(
        common_parent_body = target_orbitable:body,
        "Target " + target_orbitable:name + " and the ship do not have a common parent body. " +
        "Ship parent: " + ship:body:name + "; target parent: " + target_orbitable:body:name).

    // Using formula 4.75 from the following website:
    // http://www.braeunig.us/space/orbmech.htm#maneuver
    local ship_lan is ship:orbit:lan.
    local ship_inclination is ship:orbit:inclination.
    local target_lan is target:orbit:lan.
    local target_inclination is target:orbit:inclination.

    local sin_ship_inclination is sin(ship_inclination).
    local ship_parameters is V(
        sin_ship_inclination * cos(ship_lan),
        sin_ship_inclination * sin(ship_lan),
        cos(ship_inclination)
    ).

    local sin_target_inclination is sin(target_inclination).
    local target_parameters is V(
        sin_target_inclination * cos(target_lan),
        sin_target_inclination * sin(target_lan),
        cos(target_inclination)
    ).

    local relative_inclination is arccos(vdot(ship_parameters, target_parameters)).

    return relative_inclination.
}


function get_ship_relative_inclination_orbit_normals {
    parameter target_orbitable.

    local common_parent_body is ship:body.
    assert(
        target_orbitable:hasbody,
        "Target " + target_orbitable:name + " does not have a parent body. " +
        "Cannot calculate relative inclination.").
    assert(
        common_parent_body = target_orbitable:body,
        "Target " + target_orbitable:name + " and the ship do not have a common parent body. " +
        "Ship parent: " + ship:body:name + "; target parent: " + target_orbitable:body:name).

    local ship_position is ship:position - common_parent_body:position.
    local target_position is target:position - common_parent_body:position.

    local ship_velocity is ship:velocity:orbit.
    local target_velocity is target:velocity:orbit.

    local ship_orbit_normal is vcrs(ship_position, ship_velocity):normalized.
    local target_orbit_normal is vcrs(target_position, target_velocity):normalized.

    return vang(ship_orbit_normal, target_orbit_normal).
}
