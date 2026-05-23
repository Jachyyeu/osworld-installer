#!/bin/bash
set -euo pipefail

MAX_ITERATIONS=5
ITERATION=0
LOG_DIR="/tmp/altos-tests"
mkdir -p "$LOG_DIR"

# Determine project root (parent of tools/)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

PASS_ICON="✓"
FAIL_ICON="✗"

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --max-iterations)
            MAX_ITERATIONS="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Suite definitions: name:::command:::working_dir:::category
SUITES=(
    "shellcheck:::find tools/ scripts/installer/ scripts/first-boot/ scripts/uninstaller/ scripts/recovery/ -type f -name '*.sh' | xargs shellcheck -S warning:::.:::scripts"
    "cargo_fmt:::cargo fmt --manifest-path src-tauri/Cargo.toml -- --check:::.:::rust"
    "cargo_clippy:::cargo clippy --manifest-path src-tauri/Cargo.toml -- -D warnings:::.:::rust"
    "cargo_test:::cargo test --manifest-path src-tauri/Cargo.toml --features test-mocks:::.:::rust"
    "npm_typecheck:::npx tsc --noEmit:::.:::frontend"
    "npm_build:::npm run build:::.:::frontend"
)

declare -A SUITE_STATUS
declare -A SUITE_FIXES
declare -A SUITE_LOG

for suite in "${SUITES[@]}"; do
    name="${suite%%:::*}"
    SUITE_STATUS[$name]="pending"
    SUITE_FIXES[$name]=0
    SUITE_LOG[$name]=""
done

parse_suite() {
    local def="$1"
    local name="${def%%:::*}"
    local rest="${def#*:::}"
    local cmd="${rest%%:::*}"
    rest="${rest#*:::}"
    local dir="${rest%%:::*}"
    local cat="${rest#*:::}"
    if [[ "$cat" == "$rest" ]]; then
        cat=""
    fi
    echo "$name"
    echo "$cmd"
    echo "$dir"
    echo "$cat"
}

run_suite() {
    local suite_def="$1"
    local parsed
    parsed=$(parse_suite "$suite_def")
    local name
    name=$(echo "$parsed" | sed -n '1p')
    local cmd
    cmd=$(echo "$parsed" | sed -n '2p')
    local dir
    dir=$(echo "$parsed" | sed -n '3p')
    local cat
    cat=$(echo "$parsed" | sed -n '4p')

    local logfile="$LOG_DIR/orchestrator-${ITERATION}-${name}.log"
    SUITE_LOG[$name]="$logfile"

    echo "Running $name..." >&2

    if (cd "$dir" && eval "$cmd") > "$logfile" 2>&1; then
        SUITE_STATUS[$name]="pass"
        echo -e "${GREEN}${PASS_ICON} ${name}${NC}"
        return 0
    else
        SUITE_STATUS[$name]="fail"
        echo -e "${RED}${FAIL_ICON} ${name}${NC}"
        echo "--- excerpt ---"
        tail -n 20 "$logfile"
        echo "---------------"
        return 1
    fi
}

attempt_fix() {
    local suite_def="$1"
    local parsed
    parsed=$(parse_suite "$suite_def")
    local name
    name=$(echo "$parsed" | sed -n '1p')
    local cmd
    cmd=$(echo "$parsed" | sed -n '2p')
    local dir
    dir=$(echo "$parsed" | sed -n '3p')
    local logfile="${SUITE_LOG[$name]}"

    case "$name" in
        cargo_fmt)
            echo "Auto-fix: running cargo fmt..."
            if (cd "$dir" && cargo fmt); then
                SUITE_FIXES[$name]=$((${SUITE_FIXES[$name]} + 1))
                return 0
            fi
            ;;
        shellcheck)
            if [[ -f "$logfile" ]]; then
                local fixed=0
                # Fix SC2039: bashism with sh shebang → change to #!/bin/bash
                while IFS= read -r line; do
                    if [[ "$line" == *"SC2039"* ]]; then
                        local file
                        file=$(echo "$line" | grep -oP '(?<=In ).*?(?= line)')
                        if [[ -f "$file" ]]; then
                            local shebang
                            shebang=$(head -n 1 "$file")
                            if [[ "$shebang" == "#!/bin/sh" ]]; then
                                echo "Auto-fix: changing shebang in $file to #!/bin/bash for SC2039"
                                sed -i '1s|#!/bin/sh|#!/bin/bash|' "$file"
                                fixed=1
                            fi
                        fi
                    fi
                done < <(grep "SC2039" "$logfile" || true)

                # Fix SC2086: unquoted variables → best-effort quoting
                while IFS= read -r line; do
                    if [[ "$line" == *"SC2086"* ]]; then
                        local file
                        file=$(echo "$line" | grep -oP '(?<=In ).*?(?= line)')
                        local linenum
                        linenum=$(echo "$line" | grep -oP '(?<=line )\d+')
                        if [[ -f "$file" && -n "$linenum" ]]; then
                            local target_line
                            target_line=$(sed -n "${linenum}p" "$file")
                            # Best-effort: find unquoted $VAR and quote them
                            local new_line="$target_line"
                            # Simple heuristic: quote bare $VAR patterns that aren't already quoted
                            new_line=$(echo "$new_line" | perl -pe 's/(?<!"|\x27)\$([A-Za-z_][A-Za-z0-9_]*)(?!"|\x27)/"\$$1"/g')
                            if [[ "$new_line" != "$target_line" ]]; then
                                echo "Auto-fix: quoting variables in $file line $linenum for SC2086"
                                sed -i "${linenum}s/.*/$(printf '%s\n' "$new_line" | sed -e 's/[\/&]/\\&/g')/" "$file"
                                fixed=1
                            fi
                        fi
                    fi
                done < <(grep "SC2086" "$logfile" || true)

                if [[ "$fixed" -eq 1 ]]; then
                    SUITE_FIXES[$name]=$((${SUITE_FIXES[$name]} + 1))
                    return 0
                fi
            fi
            ;;
    esac
    return 1
}

# Main loop
OVERALL="pass"
while true; do
    ITERATION=$((ITERATION + 1))
    echo ""
    echo "========== Iteration $ITERATION / $MAX_ITERATIONS =========="

    local_any_failed=0
    local_rerun=()

    for suite in "${SUITES[@]}"; do
        name="${suite%%:::*}"
        if [[ "$ITERATION" -eq 1 || "${SUITE_STATUS[$name]}" == "fail" ]]; then
            local_rerun+=("$suite")
        fi
    done

    if [[ ${#local_rerun[@]} -eq 0 ]]; then
        echo "All suites passed. Stopping early."
        break
    fi

    for suite in "${local_rerun[@]}"; do
        name="${suite%%:::*}"
        if ! run_suite "$suite"; then
            local_any_failed=1
            if attempt_fix "$suite"; then
                echo "Fix applied for $name. Will re-test next iteration."
            fi
        fi
    done

    if [[ "$local_any_failed" -eq 0 ]]; then
        break
    fi

    if [[ "$ITERATION" -ge "$MAX_ITERATIONS" ]]; then
        OVERALL="fail"
        echo "Reached max iterations ($MAX_ITERATIONS)."
        break
    fi
done

# Build JSON summary
echo ""
echo "========== Summary =========="

JSON='{"overall":"OVERALL_PLACEHOLDER","suites":{SUITE_PLACEHOLDER},"iterations":ITERATION_PLACEHOLDER,"remaining_issues":[]}'
JSON="${JSON/OVERALL_PLACEHOLDER/$OVERALL}"
JSON="${JSON/ITERATION_PLACEHOLDER/$ITERATION}"

SUITE_JSON=""
for suite in "${SUITES[@]}"; do
    name="${suite%%:::*}"
    status="${SUITE_STATUS[$name]}"
    fixes="${SUITE_FIXES[$name]}"
    if [[ -n "$SUITE_JSON" ]]; then
        SUITE_JSON="$SUITE_JSON,"
    fi
    SUITE_JSON="$SUITE_JSON\"$name\":{\"status\":\"$status\",\"fixes\":$fixes}"
done

JSON="${JSON/SUITE_PLACEHOLDER/$SUITE_JSON}"

# Remaining issues
issues=()
for suite in "${SUITES[@]}"; do
    name="${suite%%:::*}"
    if [[ "${SUITE_STATUS[$name]}" == "fail" ]]; then
        issues+=("\"$name failed after $ITERATION iterations\"")
    fi
done

issue_json=$(IFS=,; echo "${issues[*]}")
JSON="${JSON/\"remaining_issues\":\[\]/\"remaining_issues\":[$issue_json]}"

# Pretty print summary
python3 -c "import json,sys; print(json.dumps(json.loads(sys.argv[1]), indent=2))" "$JSON" || echo "$JSON"

# Also write to log
python3 -c "import json,sys; print(json.dumps(json.loads(sys.argv[1]), indent=2))" "$JSON" > "$LOG_DIR/orchestrator-summary.json" || echo "$JSON" > "$LOG_DIR/orchestrator-summary.json"

if [[ "$OVERALL" == "fail" ]]; then
    exit 1
else
    exit 0
fi
