#!/bin/bash

# Re-exec with bash if invoked via sh or without bash
if [ -z "${BASH_VERSION-}" ]; then
    exec bash "$0" "$@"
fi

# Script to create multiple PRs with mixed changes (docs/code/config)
# Usage: ./scripts/gh-pr-create.sh [-n|--number NUM] [-w|--wait SECONDS] [-h|--help]

set -euo pipefail

# Defaults
DEFAULT_NUMBER=600
DEFAULT_WAIT=3
BASE_BRANCH="main"

NUMBER_OF_PRS=$DEFAULT_NUMBER
WAIT_SECONDS=$DEFAULT_WAIT

print_help() {
    echo "Usage: $0 [-n|--number NUM] [-w|--wait SECONDS] [-h|--help]"
    echo ""
    echo "Options:"
    echo "  -n, --number NUM     Number of PRs to create (default: $DEFAULT_NUMBER)"
    echo "  -w, --wait SECONDS   Seconds to wait between PRs (default: $DEFAULT_WAIT)"
    echo "  -h, --help           Show this help message"
}

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--number)
            if [[ -z "${2-}" || "${2#-}" != "$2" ]]; then
                NUMBER_OF_PRS="$DEFAULT_NUMBER"; shift 1
            else
                NUMBER_OF_PRS="$2"; shift 2
            fi;;
        -w|--wait)
            if [[ -z "${2-}" || "${2#-}" != "$2" ]]; then
                WAIT_SECONDS="$DEFAULT_WAIT"; shift 1
            else
                WAIT_SECONDS="$2"; shift 2
            fi;;
        -h|--help)
            print_help; exit 0;;
        *)
            echo "Unknown option: $1" >&2
            print_help
            exit 1;;
    esac
done

# Preconditions
if ! command -v gh >/dev/null 2>&1; then
    echo "Error: GitHub CLI (gh) not found in PATH" >&2
    exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
    echo "Error: gh CLI is not authenticated. Run: gh auth login" >&2
    exit 1
fi

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "Error: Not in a git repository" >&2
    exit 1
fi

# Ensure base branch exists locally and is up to date
git fetch origin "$BASE_BRANCH" >/dev/null 2>&1 || true
if ! git show-ref --verify --quiet "refs/heads/$BASE_BRANCH"; then
    git checkout -B "$BASE_BRANCH" "origin/$BASE_BRANCH"
else
    git checkout "$BASE_BRANCH"
    git pull --ff-only origin "$BASE_BRANCH"
fi

echo "Starting PR creation"
echo "Base branch: $BASE_BRANCH"
echo "Number of PRs: $NUMBER_OF_PRS"
echo "Wait seconds: $WAIT_SECONDS"
echo "=========================================="

# Helpers
random_choice() {
    # Choose a random element from arguments
    local len=$#
    local idx=$((RANDOM % len + 1))
    local i=1
    for item in "$@"; do
        if [ "$i" -eq "$idx" ]; then
            echo "$item"
            return 0
        fi
        i=$((i+1))
    done
}

timestamp() {
    date +%Y%m%d-%H%M%S
}

PR_TITLES=(
    "Docs: Improve README section"
    "Chore: Update contributor guide"
    "Feat: Add tiny utility script"
    "Refactor: Tidy scripts layout"
    "Docs: Add blog note"
    "Build: Update config snippet"
    "Docs: Add troubleshooting tips"
    "Chore: Add example code file"
)

PR_BODIES=(
    "This PR updates documentation and adds small examples for clarity."
    "Introduce a minor utility and accompanying docs to aid maintainers."
    "Refreshing docs and adding a lightweight script for demonstration."
)

# Weighted selection: 60% docs, 30% code, 10% config
pick_change_kind() {
    local roll=$((RANDOM % 100))
    if (( roll < 60 )); then
        echo "docs"
    elif (( roll < 90 )); then
        echo "code"
    else
        echo "config"
    fi
}

# Non-conflicting change generators (unique files/lines per PR)
make_docs_change() {
    mkdir -p docs
    local file="docs/pr-note-$(timestamp)-$RANDOM.md"
    cat > "$file" <<EOF
# PR Note

Created at: $(date -u)

This file is generated to support testing of PR workflows.
EOF
    git add "$file"
}

make_code_change() {
    mkdir -p scripts/examples
    local file="scripts/examples/util_$((RANDOM % 100000)).sh"
    cat > "$file" <<'EOF'
#!/bin/bash
# Auto-generated example utility
echo "Utility generated at $(date -u)"
EOF
    chmod +x "$file"
    git add "$file"
}

make_config_change() {
    local file=".pr-test-config.ini"
    touch "$file"
    echo "entry_$(timestamp)_$RANDOM=true" >> "$file"
    git add "$file"
}

create_pr_iteration() {
    local idx="$1"
    local kind=$(pick_change_kind)
    local branch="pr-test/$(timestamp)-$RANDOM-$kind"
    local title=$(random_choice "${PR_TITLES[@]}")
    local body=$(random_choice "${PR_BODIES[@]}")

    echo "[$idx/$NUMBER_OF_PRS] Creating branch: $branch (kind: $kind)"
    git checkout -B "$branch" "$BASE_BRANCH"

    case "$kind" in
        docs) make_docs_change ;;
        code) make_code_change ;;
        config) make_config_change ;;
    esac

    git commit -m "$title"
    git push -u origin "$branch"

    echo "Opening PR..."
    pr_url=$(gh pr create --base "$BASE_BRANCH" --head "$branch" --title "$title" --body "$body")
    echo "PR created: $pr_url"

    echo "Auto-merging branch '$branch' into '$BASE_BRANCH'..."
    git pull origin "$BASE_BRANCH"
    git checkout "$BASE_BRANCH"
    git merge --no-edit "$branch"
    git push -u origin "$BASE_BRANCH"
    echo "Merged '$branch' into '$BASE_BRANCH' and pushed."
}

for i in $(seq 1 "$NUMBER_OF_PRS"); do
    create_pr_iteration "$i"
    if [[ "$i" -lt "$NUMBER_OF_PRS" ]]; then
        echo "Waiting $WAIT_SECONDS seconds before next PR..."
        sleep "$WAIT_SECONDS"
    fi
done

echo "=========================================="
echo "Done. Created $NUMBER_OF_PRS PR(s)."


