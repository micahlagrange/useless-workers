#!/bin/bash
# Build the web version and serve it locally. Pass --no-tests to skip the unit tests.

cleanup(){
    rm -rf makelove-build
}

no_tests=false
for arg in "$@"; do
    case $arg in
        --no-tests) no_tests=true ;;
    esac
done

trap cleanup EXIT
set -e

if [ "$no_tests" = false ]; then
    ./test.sh
fi

cleanup
makelove lovejs
unzip -o "makelove-build/lovejs/human-resources-lovejs.zip" -d makelove-build/html/
echo "http://localhost:8000/makelove-build/html/human-resources/"
python3 -m http.server
