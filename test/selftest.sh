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

# we don't have clamDB in this image, fetching full DB would take ages, let's use fake data
# The integration task has no workingDir, so cwd is /. The image user cannot write there.
scan_dir=$(mktemp -d)
virus_file="${scan_dir}/virus-test.txt"
signature_file="${scan_dir}/test.hdb"
result_file="${scan_dir}/clamscan-result.txt"
echo "this is for a test" > "${virus_file}"
sigtool --sha256 "${virus_file}" > "${signature_file}"
clamscan -d "${signature_file}" "${virus_file}" > "${result_file}" || true  # return code is 1

EXPECTED_LINES="${virus_file}: virus-test.txt.UNOFFICIAL FOUND
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
    if ! grep -F -- "${line}" "${result_file}"; then
        echo "Expected pattern not found: \"${line}\"" >&2
        exit 1
    fi
done <<< "${EXPECTED_LINES}"

# END clamscan test

/extract-archives-selftest.sh
python3 /extract-archives-queue-selftest.py /usr/local/bin/clamav-extract-archives
