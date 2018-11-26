@LAZYGLOBAL OFF.

run once stdlib.
run once engine_info.


global CRAFT_INFO_MAX_STAGE_NUM is "max_stage_num".
global CRAFT_INFO_DRY_MASS_BY_STAGE is "dry_mass".
global CRAFT_INFO_WET_MASS_BY_STAGE is "wet_mass".
global CRAFT_INFO_CUM_MASS_BY_STAGE is "cum_mass".
global CRAFT_INFO_STAGE_ENGINES is "engines".


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

    for part_info in ship:parts {
        local stage_num is part_info:stage.

        // Convert masses to kg, since they are listed in tons.
        set dry_masses_per_stage[stage_num] to (
            dry_masses_per_stage[stage_num] + (part_info:drymass * 1000)).
        set wet_masses_per_stage[stage_num] to (
            wet_masses_per_stage[stage_num] + (part_info:wetmass * 1000)).
    }

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
