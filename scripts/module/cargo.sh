#!/usr/bin/env bash

cargo_usage () {

    printf '    %s\n' \
        "cargo-ping       Ensure all is done (response 'Cargo Pong')" \
        ''

}
cmd_cargo_ping () {

    success "Cargo Pong"

}
