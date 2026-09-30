#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
app_dir="$project_dir/build/mdrift.app"
stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/mdrift-installer.XXXXXX")"
trap 'rm -rf "$stage_dir"' EXIT
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_dir/Contents/Info.plist")"
codesign --verify --deep --strict "$app_dir"
mkdir -p "$project_dir/dist"
ditto "$app_dir" "$stage_dir/mdrift.app"
ditto "$project_dir/dist/New Markdown File.workflow" "$stage_dir/New Markdown File.workflow"
ln -s /Applications "$stage_dir/Applications"
hdiutil create -volname "mdrift $version" -srcfolder "$stage_dir" -format UDZO -ov "$project_dir/dist/mdrift.dmg"
hdiutil verify "$project_dir/dist/mdrift.dmg"
print "Installer: $project_dir/dist/mdrift.dmg"
