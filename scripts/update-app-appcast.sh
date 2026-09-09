#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_OUTPUT="${ROOT_DIR}/manifests/app/stable/appcast.xml"

version=""
build=""
minimum_system_version=""
asset_url=""
asset_length=""
ed_signature=""
release_url=""
notes_file=""
publication_date=""
output=""

usage() {
  cat <<'EOF'
Generate the stable CFFinder macOS Sparkle appcast.

Required options:
  --version VERSION
  --build BUILD
  --minimum-system-version VERSION
  --asset-url HTTPS_URL
  --asset-length BYTES
  --ed-signature SIGNATURE
  --release-url HTTPS_URL
  --notes-file PATH
  --publication-date RFC_2822_DATE
  --output manifests/app/stable/appcast.xml
EOF
}

die() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

require_value() {
  [[ $# -ge 2 ]] || die "missing value for $1"
  [[ -n "${2:-}" ]] || die "missing value for $1"
}

xml_escape() {
  printf '%s' "$1" | sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g' \
    -e "s/'/\&apos;/g"
}

while (($#)); do
  case "$1" in
    --version)
      require_value "$@"
      version="$2"
      shift 2
      ;;
    --build)
      require_value "$@"
      build="$2"
      shift 2
      ;;
    --minimum-system-version)
      require_value "$@"
      minimum_system_version="$2"
      shift 2
      ;;
    --asset-url)
      require_value "$@"
      asset_url="$2"
      shift 2
      ;;
    --asset-length)
      require_value "$@"
      asset_length="$2"
      shift 2
      ;;
    --ed-signature)
      require_value "$@"
      ed_signature="$2"
      shift 2
      ;;
    --release-url)
      require_value "$@"
      release_url="$2"
      shift 2
      ;;
    --notes-file)
      require_value "$@"
      notes_file="$2"
      shift 2
      ;;
    --publication-date)
      require_value "$@"
      publication_date="$2"
      shift 2
      ;;
    --output)
      require_value "$@"
      output="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

command -v xmllint >/dev/null 2>&1 || die "xmllint is required"
[[ "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$ ]] || die "invalid version"
[[ "$build" =~ ^[1-9][0-9]*$ ]] || die "build must be a positive integer"
[[ "$minimum_system_version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || die "invalid minimum system version"
[[ "$asset_length" =~ ^[1-9][0-9]*$ ]] || die "asset length must be a positive integer"
[[ "$asset_url" == https://* ]] || die "asset URL must use HTTPS"
[[ "$release_url" == https://* ]] || die "release URL must use HTTPS"
[[ -n "$ed_signature" ]] || die "EdDSA signature is required"
[[ -n "$publication_date" ]] || die "publication date is required"
[[ -f "$notes_file" && -r "$notes_file" ]] || die "release notes file is not readable"

mkdir -p "$(dirname "$EXPECTED_OUTPUT")"
[[ -n "$output" ]] || die "output path is required"
resolved_output="$(cd "$(dirname "$output")" 2>/dev/null && pwd -P)/$(basename "$output")" || die "output directory is invalid"
[[ "$resolved_output" == "$EXPECTED_OUTPUT" ]] || die "output is confined to manifests/app/stable/appcast.xml"

escaped_version="$(xml_escape "$version")"
escaped_build="$(xml_escape "$build")"
escaped_minimum="$(xml_escape "$minimum_system_version")"
escaped_asset_url="$(xml_escape "$asset_url")"
escaped_asset_length="$(xml_escape "$asset_length")"
escaped_signature="$(xml_escape "$ed_signature")"
escaped_release_url="$(xml_escape "$release_url")"
escaped_publication_date="$(xml_escape "$publication_date")"
notes="$(cat "$notes_file")"
notes_cdata="${notes//]]>/]]]]><![CDATA[>}"

temporary_output="$(mktemp "${EXPECTED_OUTPUT}.tmp.XXXXXX")"
cleanup() {
  rm -f "$temporary_output"
}
trap cleanup EXIT INT TERM

cat >"$temporary_output" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>CFFinder Updates</title>
    <link>https://github.com/wxyjay/cffinder-releases</link>
    <description>CFFinder macOS stable updates</description>
    <language>en</language>
    <item>
      <title>CFFinder ${escaped_version} (${escaped_build})</title>
      <pubDate>${escaped_publication_date}</pubDate>
      <link>${escaped_release_url}</link>
      <description><![CDATA[${notes_cdata}]]></description>
      <sparkle:version>${escaped_build}</sparkle:version>
      <sparkle:shortVersionString>${escaped_version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${escaped_minimum}</sparkle:minimumSystemVersion>
      <enclosure
        url="${escaped_asset_url}"
        length="${escaped_asset_length}"
        type="application/octet-stream"
        sparkle:edSignature="${escaped_signature}" />
    </item>
  </channel>
</rss>
EOF

xmllint --noout "$temporary_output"
chmod 0644 "$temporary_output"
mv -f "$temporary_output" "$EXPECTED_OUTPUT"
trap - EXIT INT TERM
printf 'Updated %s for CFFinder %s (%s).\n' "$EXPECTED_OUTPUT" "$version" "$build"
