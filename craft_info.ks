@LAZYGLOBAL OFF.

run once stdlib.
run once engine_info.


global CRAFT_INFO_MAX_STAGE_NUM is "max_stage_num".
global CRAFT_INFO_DRY_MASS_BY_STAGE is "dry_mass".
global CRAFT_INFO_WET_MASS_BY_STAGE is "wet_mass".
global CRAFT_INFO_CUM_MASS_BY_STAGE is "cum_mass".
global CRAFT_INFO_STAGE_ENGINES is "engines".

global PART_MODULE_DECOUPLER is "ModuleDecouple".
global PART_MODULE_ANCHORED_DECOUPLER is "ModuleAnchoredDecoupler".


function make_craft_info {
    local current_stage is stage:number.

    local dry_masses_per_stage is lexicon().
    local wet_masses_per_stage is lexicon().
    local cum_masses_per_stage is lexicon().

    local stage_engines is list().

    for i in range(-1, current_stage + 1) {
        dry_masses_per_stage:add(i, 0.0).
        wet_masses_per_stage:add(i, 0.0).
    }
    for i in range(current_stage + 1) {
        stage_engines:add(list()).
    }

    local part_uid_to_stage is lexicon().
    local root_part_stage_number is -1.
    assert(
        ship:rootpart:stage = root_part_stage_number,
        "Root part was not in stage -1, but was in " + ship:rootpart:stage).
    _recursively_calculate_stage_masses(
        part_uid_to_stage, dry_masses_per_stage, wet_masses_per_stage,
        ship:rootpart, root_part_stage_number).

    assert(
        ship:parts:length = part_uid_to_stage:length,
        "Ship part count did not match visited part count: " +
        ship:parts:length + " <> " + part_uid_to_stage:length).

    set cum_masses_per_stage[-1] to wet_masses_per_stage[-1].
    for i in range(current_stage + 1) {
        set cum_masses_per_stage[i] to cum_masses_per_stage[i - 1] + wet_masses_per_stage[i].
    }

    local engine_list is list().
    list engines in engine_list.
    for engine_part in engine_list {
        local stage_num is engine_part:stage.
        stage_engines[stage_num]:add(engine_part).
    }

    return lexicon(
        CRAFT_INFO_MAX_STAGE_NUM, current_stage,
        CRAFT_INFO_DRY_MASS_BY_STAGE, dry_masses_per_stage,
        CRAFT_INFO_WET_MASS_BY_STAGE, wet_masses_per_stage,
        CRAFT_INFO_CUM_MASS_BY_STAGE, cum_masses_per_stage,
        CRAFT_INFO_STAGE_ENGINES, stage_engines).
}


function _recursively_calculate_stage_masses {
    parameter part_uid_to_stage, dry_masses_per_stage, wet_masses_per_stage,
              current_part, current_stage.

    set part_uid_to_stage[current_part:uid] to current_stage.

    if current_part:hasphysics {
        // Convert masses to kg, since they are listed in tons.
        set dry_masses_per_stage[current_stage] to (
            dry_masses_per_stage[current_stage] + (current_part:drymass * 1000)).
        set wet_masses_per_stage[current_stage] to (
            wet_masses_per_stage[current_stage] + (current_part:wetmass * 1000)).
    }

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

            _recursively_calculate_stage_masses(
                part_uid_to_stage, dry_masses_per_stage, wet_masses_per_stage,
                part_info, part_stage).
        }
    }
}
