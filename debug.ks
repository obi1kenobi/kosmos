@LAZYGLOBAL OFF.

run once stdlib.
run once os.
run once engine_info.
run once craft_info.
run once logging.


// Helper file for debugging things that are broken.
// Since kOS does not allow calling functions directly from the terminal,
// one can write said functions into this file and call them by running this file instead.
function main {
    //local craft_info is make_craft_info().
    //print craft_info.

    initialize_default_logging().

    local logger is get_logger("foobar").

    logger("hello world!").
}


main.
