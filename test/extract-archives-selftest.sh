#!/usr/bin/bash

# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

extractor=${EXTRACTOR:-clamav-extract-archives}
extract_test_dir=$(mktemp -d)
trap 'rm -rf "${extract_test_dir}"' EXIT

echo "----------- Checking archive extractor -----------"
# Nested, extensionless archives must be expanded recursively.
mkdir -p "${extract_test_dir}/inner" "${extract_test_dir}/outer"
printf 'nested payload\n' > "${extract_test_dir}/inner/payload.txt"
bsdtar --no-xattrs -cf "${extract_test_dir}/outer/nested" \
    -C "${extract_test_dir}/inner" payload.txt
bsdtar --no-xattrs -cf "${extract_test_dir}/archive" \
    -C "${extract_test_dir}/outer" nested

# Use a valid archive with a test bsdtar that writes partial output and fails.
mkdir -p "${extract_test_dir}/partial-source"
printf 'partial payload\n' > "${extract_test_dir}/partial-source/payload.txt"
bsdtar --no-xattrs -cf "${extract_test_dir}/partial-failure" \
    -C "${extract_test_dir}/partial-source" payload.txt

# Keep a damaged archive to verify that failed extraction retains the input.
printf '%1024s' payload > "${extract_test_dir}/damaged-source"
bsdtar --no-xattrs -cf "${extract_test_dir}/damaged" \
    -C "${extract_test_dir}" damaged-source
dd if="${extract_test_dir}/damaged" of="${extract_test_dir}/damaged.tmp" \
    bs=1 count=600 status=none
mv "${extract_test_dir}/damaged.tmp" "${extract_test_dir}/damaged"

rm -rf "${extract_test_dir}/inner" "${extract_test_dir}/outer" \
    "${extract_test_dir}/damaged-source" "${extract_test_dir}/partial-source"
# Ordinary files and filenames containing newlines must remain present.
printf 'not an archive\n' > "${extract_test_dir}/plain-file"
printf 'unusual filename\n' > "${extract_test_dir}/line
break"
# Mtree-like JSON must remain unchanged when detection yields ARCHIVE_WARN.
cat > "${extract_test_dir}/mtree-like.json" <<'EOF'
[
  {
    "interfaces": [
      "org.apache.http.pool.ConnPoolControl",
      "org.apache.http.conn.HttpClientConnectionManager"
    ]
  }
]
EOF
mtree_checksum=$(sha256sum "${extract_test_dir}/mtree-like.json")

# Simulate bsdtar writing partial output before reporting extraction failure.
real_bsdtar=$(command -v bsdtar)
mkdir -p "${extract_test_dir}/bin"
cat > "${extract_test_dir}/bin/bsdtar" <<'EOF'
#!/usr/bin/bash
set -euo pipefail

if [[ $1 == -xf && $2 == */partial-failure ]]; then
    while (( $# )); do
        if [[ $1 == -C ]]; then
            shift
            printf 'partial output\n' > "$1/partial-output"
            printf 'simulated extraction failure\n' >&2
            # More than pipe capacity: the extractor must drain, not just truncate.
            python3 -c 'import sys; sys.stderr.write("x" * 131072 + "discarded-stderr-tail")'
            exit 23
        fi
        shift
    done
fi

if [[ $1 == -xf && ( $2 == */archive || $2 == */nested ) ]]; then
    printf 'successful extraction diagnostic\n' >&2
fi
exec "${REAL_BSDTAR}" "$@"
EOF
chmod +x "${extract_test_dir}/bin/bsdtar"

# Run all fixtures with two extraction workers and capture diagnostics.
if REAL_BSDTAR="${real_bsdtar}" \
    PATH="${extract_test_dir}/bin:${PATH}" \
    "${extractor}" --workers 2 "${extract_test_dir}" \
    2> "${extract_test_dir}/extractor-errors"; then
    echo "incomplete extraction was reported as successful" >&2
    exit 1
fi

# Successful recursive extraction removes both archives and retains the payload.
test ! -e "${extract_test_dir}/archive"
test ! -e "${extract_test_dir}/archive.d/nested"
test -f "${extract_test_dir}/archive.d/nested.d/payload.txt"
# Damaged or partially extracted archives retain their inputs without .d output.
test -f "${extract_test_dir}/damaged"
test ! -e "${extract_test_dir}/damaged.d"
test -f "${extract_test_dir}/partial-failure"
test ! -e "${extract_test_dir}/partial-failure.d"
# Non-archives remain present; warned JSON also keeps its original checksum.
test -f "${extract_test_dir}/plain-file"
test -f "${extract_test_dir}/line
break"
test "$(sha256sum "${extract_test_dir}/mtree-like.json")" = "${mtree_checksum}"
test ! -e "${extract_test_dir}/mtree-like.json.d"
# Temporary output is cleaned up, and failures identify the affected archive.
test -z "$(find "${extract_test_dir}" -name '.clamav-extract-*' -print -quit)"
grep -Fq "could not extract archive" "${extract_test_dir}/extractor-errors"
grep -Fq "partial-failure" "${extract_test_dir}/extractor-errors"
grep -Fq "simulated extraction failure" "${extract_test_dir}/extractor-errors"
grep -Fq "bsdtar exit 23" "${extract_test_dir}/extractor-errors"
grep -Fq "stderr truncated after 8192 bytes" "${extract_test_dir}/extractor-errors"
test "$(wc -c < "${extract_test_dir}/extractor-errors")" -lt 10000
if grep -Eq 'discarded-stderr-tail|successful extraction diagnostic' \
    "${extract_test_dir}/extractor-errors"; then
    echo "discarded or successful stderr leaked into diagnostics" >&2
    exit 1
fi
grep -Fq "archive extraction incomplete" "${extract_test_dir}/extractor-errors"
# Rejected mtree detections must not leak libarchive warnings into task logs.
if grep -Fq "Missing type keyword in mtree specification" \
    "${extract_test_dir}/extractor-errors"; then
    echo "libarchive warning was not suppressed" >&2
    exit 1
fi
# A tree with no remaining failed archives must return success.
rm "${extract_test_dir}/damaged" "${extract_test_dir}/partial-failure"
"${extractor}" --workers 2 "${extract_test_dir}"
# Output collisions must fail without changing the archive or existing output.
for collision in directory file symlink; do
    collision_root="${extract_test_dir}/collision-${collision}"
    mkdir "${collision_root}"
    bsdtar --no-xattrs -cf "${collision_root}/archive" \
        -C "${extract_test_dir}/archive.d/nested.d" payload.txt
    archive_checksum=$(sha256sum "${collision_root}/archive")
    case "${collision}" in
        directory)
            mkdir "${collision_root}/archive.d"
            printf 'existing content\n' > "${collision_root}/archive.d/marker"
            ;;
        file) printf 'existing content\n' > "${collision_root}/archive.d" ;;
        symlink) ln -s missing-target "${collision_root}/archive.d" ;;
    esac
    if "${extractor}" --workers 2 "${collision_root}" \
        2> "${collision_root}/errors"; then
        echo "output collision was reported as successful" >&2
        exit 1
    fi
    test "$(sha256sum "${collision_root}/archive")" = "${archive_checksum}"
    case "${collision}" in
        directory)
            test "$(cat "${collision_root}/archive.d/marker")" = 'existing content'
            test "$(find "${collision_root}/archive.d" -type f | wc -l)" -eq 1
            ;;
        file) test "$(cat "${collision_root}/archive.d")" = 'existing content' ;;
        symlink) test "$(readlink "${collision_root}/archive.d")" = missing-target ;;
    esac
    test -z "$(find "${collision_root}" -name '.clamav-extract-*' -print -quit)"
    grep -Fq 'extraction output already exists' "${collision_root}/errors"
done
echo PASS
