#!/bin/bash

cleanup(){
    # clean up makelove
    rm -rf makelove-build
}

# Initialize the variable
no_tests=false
# Function to parse arguments
parse_args() {
    for arg in "$@"
    do
        case $arg in
            --no-tests)
                no_tests=true
                shift # Remove --no-tests from processing
            ;;
            *)
                shift # Remove generic argument from processing
            ;;
        esac
    done
}
parse_args "$@"

trap cleanup EXIT

set -e

if [ $no_tests == false ]; then
    . setup.conf
    luaunit
fi

cleanup
makelove lovejs
unzip -o "makelove-build/lovejs/morphi-lovejs" -d makelove-build/html/
echo "http://localhost:8000/makelove-build/html/morphi/"
python3 -m http.server
cleanup
