#!/bin/bash

cat config.example | awk '{print "\t" $0}' > readme.tmp
perl -pe 's/^\<CONFIGURATION FILE\>$/`cat readme.tmp`/e' README.md.in > README.md

./qemu-test-iouring.sh -h | awk '{print "\t" $0}' > readme.tmp
perl -pe 's/^\<USAGE MESSAGE\>$/`cat readme.tmp`/e' -i README.md

rm -f readme.tmp
