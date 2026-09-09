#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATER="${ROOT_DIR}/scripts/update-app-appcast.sh"
OUTPUT="${ROOT_DIR}/manifests/app/stable/appcast.xml"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cffinder-appcast-tests.XXXXXX")"
BACKUP="${TMP_DIR}/appcast.backup"

cleanup() {
  if [[ -f "$BACKUP" ]]; then
    cp "$BACKUP" "$OUTPUT"
  else
    rm -f "$OUTPUT"
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_failure() {
  if "$@" >/dev/null 2>&1; then
    fail "expected failure: $*"
  fi
}

[[ -x "$UPDATER" ]] || fail "appcast updater is missing or not executable"
mkdir -p "$(dirname "$OUTPUT")"
if [[ -f "$OUTPUT" ]]; then
  cp "$OUTPUT" "$BACKUP"
fi

NOTES="${TMP_DIR}/notes.md"
cat >"$NOTES" <<'NOTES'
Fixed A & B < C > D.
Literal CDATA terminator: ]]>
NOTES

"$UPDATER" \
  --version '1.2.3' \
  --build '42' \
  --minimum-system-version '15.0' \
  --asset-url 'https://github.com/wxyjay/cffinder-releases/releases/download/cffinder-app-v1.2.3-b42/CFFinder-App-1.2.3-42-macos-universal.dmg?x=1&y=2' \
  --asset-length '123456' \
  --ed-signature 'abc+/=' \
  --release-url 'https://github.com/wxyjay/cffinder-releases/releases/tag/cffinder-app-v1.2.3-b42?x=1&y=2' \
  --notes-file "$NOTES" \
  --publication-date 'Sat, 05 Sep 2026 12:00:00 +0000' \
  --output "$OUTPUT"

xmllint --noout "$OUTPUT"
grep -Fq '<sparkle:version>42</sparkle:version>' "$OUTPUT"
grep -Fq '<sparkle:shortVersionString>1.2.3</sparkle:shortVersionString>' "$OUTPUT"
grep -Fq '<sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>' "$OUTPUT"
grep -Fq 'sparkle:edSignature="abc+/="' "$OUTPUT"
grep -Fq 'x=1&amp;y=2' "$OUTPUT"
grep -Fq ']]]]><![CDATA[>' "$OUTPUT"

assert_failure "$UPDATER" \
  --version '1.2.3' --build 'not-a-number' --minimum-system-version '15.0' \
  --asset-url 'https://example.com/a.dmg' --asset-length '1' --ed-signature 'sig' \
  --release-url 'https://example.com/release' --notes-file "$NOTES" \
  --publication-date 'Sat, 05 Sep 2026 12:00:00 +0000' --output "$OUTPUT"

assert_failure "$UPDATER" --version

assert_failure "$UPDATER" \
  --version '1.2.3' --build '43' --minimum-system-version '15.0' \
  --asset-url 'https://example.com/a.dmg' --asset-length '1' --ed-signature 'sig' \
  --release-url 'https://example.com/release' --notes-file "$NOTES" \
  --publication-date 'Sat, 05 Sep 2026 12:00:00 +0000' --output "${TMP_DIR}/outside.xml"

printf 'App appcast tests passed.\n'
