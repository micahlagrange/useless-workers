#!/bin/bash

set -e

trap cleanup EXIT

cleanup(){
    # clean up makelove
    rm -rf makelove-build
}

cleanup

. setup.conf
luaunit

makelove lovejs
unzip -o "makelove-build/lovejs/morphi-lovejs" -d makelove-build/html/
echo "http://localhost:8000/makelove-build/html/morphi/"
python3 -m http.server

cleanup

