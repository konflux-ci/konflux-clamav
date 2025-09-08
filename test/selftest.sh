#!/usr/bin/bash

# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

check_return_code () {
   if [ $? -eq 0 ]; then
     echo PASS
   else
     echo FAIL
     exit 1
   fi
}

# Test to verify ClamAV binaries are available
echo "----------- Checking ClamAV binaries -----------"
clamdscan --version
clamscan --version
freshclam --version
check_return_code

# Test clamscan output format, we are parsing it so we relay on it (including foramt of virus report)
echo "Test clamscan output format"
echo "this is for a test" >> /tmp/virus-test.txt

# we don't have clamDB in this image, fetching full DB would take ages, let's use fake data
sigtool --sha256 /tmp/virus-test.txt > test.hdb
clamscan -d test.hdb /tmp/virus-test.txt > clamscan-result.txt || true  # return code is 1

EXPECTED_LINES="/tmp/virus-test.txt: virus-test.txt.UNOFFICIAL FOUND
----------- SCAN SUMMARY -----------
Known viruses:
Engine version:
Scanned directories:
Scanned files:
Infected files:
Data scanned:
Data read:
Time:
Start Date:
End Date:"

while IFS= read -r line; do
    if ! grep -- "${line}" clamscan-result.txt; then
        echo "Expected pattern not found: \"${line}\"" >&2
        exit 1
    fi
done <<< "${EXPECTED_LINES}"

# END clamscan test
