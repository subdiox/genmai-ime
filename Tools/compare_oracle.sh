#!/bin/bash
# Parity check of the Swift CLI `genmai-engine` against the C++ converter_main oracle.
#
# For each suite, the commands are run through genmai-engine with an EMPTY temporary --user_profile_dir (so
# the developer's learned data is never used) and the output is compared with the stored oracle output in
# Tests/Fixtures/oracle/ by Tools/compare_oracle.py (banner and debug `log:` lines excluded: the oracle is a
# fastbuild of converter_main, whose candidates carry MOZC_DEBUG logs).
#
# Suites (commands -> expected output, flags):
#   conversion         conversion_commands.txt -> conversion_top10.txt          --max_candidates_to_show 10
#   prediction         prediction_commands.txt -> prediction_top10.txt          --max_candidates_to_show 10
#   prediction_mobile  prediction_commands.txt -> prediction_mobile_top10.txt   --engine_type mobile ...
#   sessions           sessions_commands.txt   -> sessions_top5.txt             --max_candidates_to_show 5
#   sessions_mobile    sessions_mobile_commands.txt -> sessions_mobile_top5.txt --engine_type mobile ...
#                      (the sessions without resize: C++ converter_main CHECK-fails on resize with a mobile
#                      request, as it keeps create_partial_candidates = auto_partial_suggestion)
# sessions_commands.txt holds several scripted sessions ("=== name" header lines); every session is a
# separate process with its own empty profile directory.
#
# usage: Tools/compare_oracle.sh [--regenerate] [--swift BIN] [suite...]
#   --regenerate  re-run the C++ oracle (Tools/oracle.sh; needs Tools/build_oracle.sh) to rewrite the expected
#                 outputs first, and also check that both banners are identical.
#   --swift BIN   genmai-engine binary (default: build it with `swift build -c release --build-path .build-e1`).
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIX="$ROOT/Tests/Fixtures/oracle"
DATA="$ROOT/Data/genmai.data"
IDDEF="$ROOT/Vendor/mozc/src/data/dictionary_oss/id.def"

REGENERATE=0
SWIFT_BIN=""
SUITES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --regenerate) REGENERATE=1 ;;
    --swift) SWIFT_BIN="$2"; shift ;;
    *) SUITES+=("$1") ;;
  esac
  shift
done
[ ${#SUITES[@]} -eq 0 ] && SUITES=(conversion prediction prediction_mobile sessions sessions_mobile)

if [ -z "$SWIFT_BIN" ]; then
  (cd "$ROOT" && swift build -c release --build-path .build-e1 --product genmai-engine >&2)
  SWIFT_BIN="$ROOT/.build-e1/release/genmai-engine"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# prediction_commands.txt: "p <reading>" for the first 200 conversion inputs.
if [ ! -f "$FIX/prediction_commands.txt" ]; then
  head -200 "$FIX/conversion_inputs.txt" | sed 's/^/p /' > "$FIX/prediction_commands.txt"
fi

suite_spec() {  # name -> "commands expected flags..."
  case "$1" in
    conversion) echo "conversion_commands.txt conversion_top10.txt --max_candidates_to_show 10" ;;
    prediction) echo "prediction_commands.txt prediction_top10.txt --max_candidates_to_show 10" ;;
    prediction_mobile)
      echo "prediction_commands.txt prediction_mobile_top10.txt --engine_type mobile --max_candidates_to_show 10" ;;
    sessions) echo "sessions_commands.txt sessions_top5.txt --max_candidates_to_show 5" ;;
    sessions_mobile)
      echo "sessions_mobile_commands.txt sessions_mobile_top5.txt --engine_type mobile --max_candidates_to_show 5" ;;
    *) echo "unknown suite: $1" >&2; exit 2 ;;
  esac
}

# run_one <oracle|swift> <commands file> <fake time or ""> <flags...>: one converter_main run with a fresh
# empty profile. The swift run uses --fake_time_for_testing=<the time the oracle ran> when known, so date /
# time candidates (いま, きょう, ...) match.
run_one() {
  local kind="$1" commands="$2" fake_time="$3"
  shift 3
  local profile
  profile="$(mktemp -d "$TMP/profile.XXXXXX")"
  if [ "$kind" = oracle ]; then
    "$ROOT/Tools/oracle.sh" --engine_data_path="$DATA" --id_def="$IDDEF" --user_profile_dir="$profile" "$@" \
      < "$commands"
  else
    local time_flag=()
    [ -n "$fake_time" ] && time_flag=(--fake_time_for_testing="$fake_time")
    "$SWIFT_BIN" --engine_data_path="$DATA" --id_def="$IDDEF" --user_profile_dir="$profile" \
      ${time_flag[@]+"${time_flag[@]}"} "$@" < "$commands" 2>/dev/null
  fi | sed "s#^User profile dir: .*#User profile dir: <empty temporary directory>#; s#$ROOT#<root>#g"
}

# Waits for the next minute when the current one is about to end, so that one oracle run sees one minute.
wait_for_fresh_minute() {
  local sec
  sec=$((10#$(date +%S)))
  if [ "$sec" -gt 50 ]; then sleep $((61 - sec)); fi
}

# run_suite <oracle|swift> <commands file> <expected file> <flags...>
# Sessions files are split at "=== name" lines. Every run is preceded by "=== <name> @<unix time>" (the
# time the oracle ran). For swift, the times are read from the expected file; expected files without
# headers (the prediction fixtures) are compared without them, using the real clock.
run_suite() {
  local kind="$1" commands="$2" expected="$3"
  shift 3
  local dir="$TMP/runs.$kind"
  rm -rf "$dir"; mkdir -p "$dir"
  if head -1 "$commands" | grep -q '^=== '; then
    awk -v dir="$dir" '/^=== /{n++; f=sprintf("%s/%04d", dir, n); print substr($0,5) > (f ".name"); next}
      {print > (f ".txt")}' "$commands"
  else
    echo "$SUITE" > "$dir/0001.name"
    cp "$commands" "$dir/0001.txt"
  fi
  local headers=1 times=()
  if [ "$kind" = swift ]; then
    if head -1 "$expected" | grep -q '^=== '; then
      read -r -a times <<< "$(grep '^=== ' "$expected" | sed -n 's/.* @\([0-9]*\)$/\1/p' | tr '\n' ' ')"
    else
      headers=0
    fi
  fi
  local i=0
  for name in "$dir"/*.name; do
    local base="${name%.name}" t=""
    touch "$base.txt"
    if [ "$kind" = oracle ]; then
      wait_for_fresh_minute
      t="$(date +%s)"
    else
      t="${times[$i]:-}"
    fi
    [ "$headers" = 1 ] && echo "=== $(cat "$name") @$t"
    run_one "$kind" "$base.txt" "$t" "$@"
    i=$((i + 1))
  done
}

STATUS=0
for suite in "${SUITES[@]}"; do
  read -r -a spec <<< "$(suite_spec "$suite")"
  commands="$FIX/${spec[0]}"
  expected="$FIX/${spec[1]}"
  flags=("${spec[@]:2}")
  SUITE="$suite"
  if [ "$REGENERATE" = 1 ]; then
    # Debug logs are not part of the fixtures.
    run_suite oracle "$commands" "$expected" "${flags[@]}" | python3 -c '
import sys
sys.path.insert(0, sys.argv[1])
from compare_oracle import strip_logs
lines = sys.stdin.read().split("\n")
sys.stdout.write("\n".join(strip_logs(lines)))' "$ROOT/Tools" > "$expected"
    echo "regenerated $expected" >&2
  fi
  run_suite swift "$commands" "$expected" "${flags[@]}" > "$TMP/$suite.swift.txt"
  banner='^(Engine type|Data file|id\.def|User profile dir): '
  if [ "$REGENERATE" = 1 ] && ! diff <(grep -E "$banner" "$expected") <(grep -E "$banner" "$TMP/$suite.swift.txt") \
      > /dev/null; then
    echo "$suite: banner lines differ" >&2
    STATUS=1
  fi
  python3 "$ROOT/Tools/compare_oracle.py" "$expected" "$TMP/$suite.swift.txt" --name "$suite" \
    --commands "$commands" --show "${SHOW:-5}" || STATUS=1
done
exit $STATUS
