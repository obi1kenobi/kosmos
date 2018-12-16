@LAZYGLOBAL OFF.

run once stdlib.
run once engine_info.
run once logging.


local _craft_info_logger is get_logger("craft_info").


global CRAFT_INFO_MAX_STAGE_NUM is "max_stage_num".
global CRAFT_INFO_DRY_MASS_BY_STAGE is "dry_mass".
global CRAFT_INFO_WET_MASS_BY_STAGE is "wet_mass".
global CRAFT_INFO_CUM_MASS_BY_STAGE is "cum_mass".
global CRAFT_INFO_STAGE_PARTS is "parts".
global CRAFT_INFO_STAGE_ENGINES is "engines".
global CRAFT_INFO_RESOURCE_AMOUNTS is "res_amount".
global CRAFT_INFO_RESOURCE_CAPACITIES is "res_caps".

// Decoupler modules.
global PART_MODULE_DECOUPLER is "ModuleDecouple".
global PART_MODULE_ANCHORED_DECOUPLER is "ModuleAnchoredDecoupler".


function make_craft_info {
    local current_stage is stage:number.

    local dry_masses_per_stage is lexicon().
    local wet_masses_per_stage is lexicon().
    local cum_masses_per_stage is lexicon().
    local parts_per_stage is lexicon().
    local resources_per_stage is lexicon().
    local capacities_per_stage is lexicon().

    local stage_engines is list().

    for i in range(-1, current_stage + 1) {
        parts_per_stage:add(i, list()).
    }
    for i in range(current_stage + 1) {
        stage_engines:add(list()).
    }

    local part_uid_to_stage is lexicon().
    local root_part_stage_number is -1.
    assert(
        ship:rootpart:stage = root_part_stage_number,
        "Root part was not in stage -1, but was in " + ship:rootpart:stage).
    _recursively_calculate_detachment_stages(
        part_uid_to_stage, parts_per_stage, ship:rootpart, root_part_stage_number).

    assert(
        ship:parts:length = part_uid_to_stage:length,
        "Ship part count did not match visited part count: " +
        ship:parts:length + " <> " + part_uid_to_stage:length).

    for stage_number in range(-1, current_stage + 1) {
        local parts_in_this_stage is parts_per_stage[stage_number].

        local masses is _calculate_dry_and_wet_masses(parts_in_this_stage).
        dry_masses_per_stage:add(stage_number, masses[0]).
        wet_masses_per_stage:add(stage_number, masses[1]).

        resources_per_stage:add(stage_number, _calculate_resource_amounts(parts_in_this_stage)).
        capacities_per_stage:add(stage_number, _calculate_resource_capacities(parts_in_this_stage)).
    }

    set cum_masses_per_stage[-1] to wet_masses_per_stage[-1].
    for i in range(current_stage + 1) {
        set cum_masses_per_stage[i] to cum_masses_per_stage[i - 1] + wet_masses_per_stage[i].
    }

    local engine_list is list().
    list engines in engine_list.
    for engine_part in engine_list {
        local activation_stage_num is engine_part:stage.
        local detachment_stage_num is part_uid_to_stage[engine_part:uid].

        for stage_num in range(detachment_stage_num, activation_stage_num + 1) {
            stage_engines[stage_num]:add(engine_part).
        }
    }

    local result is lexicon(
        CRAFT_INFO_MAX_STAGE_NUM, current_stage,
        CRAFT_INFO_DRY_MASS_BY_STAGE, dry_masses_per_stage,
        CRAFT_INFO_WET_MASS_BY_STAGE, wet_masses_per_stage,
        CRAFT_INFO_CUM_MASS_BY_STAGE, cum_masses_per_stage,
        CRAFT_INFO_STAGE_PARTS, parts_per_stage,
        CRAFT_INFO_STAGE_ENGINES, stage_engines,
        CRAFT_INFO_RESOURCE_AMOUNTS, resources_per_stage,
        CRAFT_INFO_RESOURCE_CAPACITIES, capacities_per_stage).

    _craft_info_logger(result).
    return result.
}


function update_stage_resource_amounts {
    parameter craft_info, stage_number.

    local parts_in_this_stage is craft_info[CRAFT_INFO_STAGE_PARTS][stage_number].
    local stage_resource_amounts is _calculate_resource_amounts(parts_in_this_stage).

    _craft_info_logger(
        "Updating stage " + stage_number +
        " resource amounts: " + stage_resource_amounts).
    set craft_info[CRAFT_INFO_RESOURCE_AMOUNTS][stage_number] to stage_resource_amounts.
}


local function _recursively_calculate_detachment_stages {
    // For each part, calculate which stage it gets detached and discarded in.
    parameter part_uid_to_stage, parts_per_stage, current_part, current_stage.

    set part_uid_to_stage[current_part:uid] to current_stage.
    parts_per_stage[current_stage]:add(current_part).

    for part_info in current_part:children {
        if not part_uid_to_stage:haskey(part_info:uid) {
            local part_stage is current_stage.
            local is_decoupler is (
                part_info:hasmodule(PART_MODULE_DECOUPLER) or
                part_info:hasmodule(PART_MODULE_ANCHORED_DECOUPLER)
            ).
            if is_decoupler {
                // Decouplers activated in stage X are detached when stage X is active.
                // Therefore, they only contribute their mass to stage X+1, and not stage X.
                set part_stage to part_info:stage + 1.
            }

            _recursively_calculate_detachment_stages(
                part_uid_to_stage, parts_per_stage, part_info, part_stage).
        }
    }
}


local function _calculate_dry_and_wet_masses {
    parameter parts_list.

    local dry_mass_in_tons is 0.0.
    local wet_mass_in_tons is 0.0.
    for current_part in parts_list {
        if current_part:hasphysics {
            set dry_mass_in_tons to dry_mass_in_tons + current_part:drymass.
            set wet_mass_in_tons to wet_mass_in_tons + current_part:wetmass.
        }
    }

    // Convert masses to kg before returning.
    return list(
        dry_mass_in_tons * 1000,
        wet_mass_in_tons * 1000
    ).
}


local function _calculate_resource_amounts {
    parameter parts_list.

    local total_resources is lexicon().
    for current_part in parts_list {
        for resource_info in current_part:resources {
            local resource_name is resource_info:name.
            local existing_amount is 0.0.
            if total_resources:haskey(resource_name) {
                set existing_amount to total_resources[resource_name].
            }
            set total_resources[resource_name] to existing_amount + resource_info:amount.
        }
    }
    return total_resources.
}


local function _calculate_resource_capacities {
    parameter parts_list.

    local total_resources is lexicon().
    for current_part in parts_list {
        for resource_info in current_part:resources {
            local resource_name is resource_info:name.
            local existing_capacity is 0.0.
            if total_resources:haskey(resource_name) {
                set existing_capacity to total_resources[resource_name].
            }
            set total_resources[resource_name] to existing_capacity + resource_info:capacity.
        }
    }
    return total_resources.
}
