@LAZYGLOBAL OFF.

run once stdlib.


global DEFAULT_LOGGING_PATH is "0:/current_logs/".

global UNIFIED_LOGGER_NAME is "unified".

global LOG_EXTENSION is ".txt".


function get_logger_at_path {
    parameter logger_path, logger_name.

    assert(
        logger_name <> UNIFIED_LOGGER_NAME,
        "logger_name must not be set to the unified logger name: " + UNIFIED_LOGGER_NAME).
    assert(
        logger_path[logger_path:length - 1] = "/",
        "logger_path must end in '/', but was: " + logger_path).

    local unified_logger is logger_path + UNIFIED_LOGGER_NAME + LOG_EXTENSION.
    local specific_logger is logger_path + logger_name + LOG_EXTENSION.

    function logger_function {
        parameter log_message.
        local current_time is round(time:seconds, 3).

        local ts_and_message is current_time + ": " + log_message.

        log ("[" + logger_name + "] " + ts_and_message) to unified_logger.
        log ts_and_message to specific_logger.
    }

    return logger_function@.
}


function get_logger {
    parameter logger_name.

    return get_logger_at_path(DEFAULT_LOGGING_PATH, logger_name)@.
}


local function _initialize_default_logging {
    if not exists(DEFAULT_LOGGING_PATH) {
        createdir(DEFAULT_LOGGING_PATH).
    }
}
_initialize_default_logging().
