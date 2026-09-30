#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
qa_dir="$(mktemp -d "${TMPDIR:-/tmp}/mdrift-native-qa.XXXXXX")"
trap 'rm -rf "$qa_dir"' EXIT
MDRIFT_NATIVE_TESTS=1 MDRIFT_APP_PATH="$qa_dir/mdrift QA.app" "$project_dir/scripts/build.sh"
MDRIFT_QA_DATA="$qa_dir/fixtures" "$qa_dir/mdrift QA.app/Contents/MacOS/mdrift"
