#!/bin/bash

set -e

rm -rf makelove-build
makelove lovejs
unzip -o "makelove-build/lovejs/morphi-lovejs" -d makelove-build/html/
echo "http://localhost:8000/makelove-build/html/morphi/"
python3 -m http.server