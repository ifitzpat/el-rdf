#!/bin/bash
# check-ci.sh - Check GitHub Actions CI status for cl-rdf
# This script uses the public GitHub API (no auth required)

REPO="ifitzpat/el-rdf"
BRANCH="claude/cl-port-011CUpNDW7sG6n2sHxzXJPCp"
API_BASE="https://api.github.com/repos/${REPO}"

echo "Checking CI status for ${BRANCH}..."
echo ""

# Get latest workflow run
RUNS=$(curl -s "${API_BASE}/actions/runs?branch=${BRANCH}&per_page=1")

# Extract details using grep/sed (simple parsing)
RUN_ID=$(echo "$RUNS" | grep -o '"id": [0-9]*' | head -1 | grep -o '[0-9]*')
STATUS=$(echo "$RUNS" | grep -o '"status": "[^"]*"' | head -1 | cut -d'"' -f4)
CONCLUSION=$(echo "$RUNS" | grep -o '"conclusion": "[^"]*"' | head -1 | cut -d'"' -f4)
TITLE=$(echo "$RUNS" | grep -o '"display_title": "[^"]*"' | head -1 | cut -d'"' -f4)
CREATED=$(echo "$RUNS" | grep -o '"created_at": "[^"]*"' | head -1 | cut -d'"' -f4)

echo "Latest Run: $TITLE"
echo "Run ID: $RUN_ID"
echo "Created: $CREATED"
echo "Status: $STATUS"
echo "Conclusion: $CONCLUSION"
echo ""

# Get job details for more info
if [ ! -z "$RUN_ID" ]; then
    echo "Fetching job details..."
    JOBS=$(curl -s "${API_BASE}/actions/runs/${RUN_ID}/jobs")

    echo ""
    echo "Jobs:"
    echo "$JOBS" | grep -E '"name":|"conclusion":' | head -20
    echo ""

    # Show failed step if any
    FAILED_STEP=$(echo "$JOBS" | grep -B2 '"conclusion": "failure"' | grep '"name"' | head -1 | cut -d'"' -f4)
    if [ ! -z "$FAILED_STEP" ]; then
        echo "❌ Failed step: $FAILED_STEP"
    fi
fi

# Summary
echo ""
if [ "$CONCLUSION" = "success" ]; then
    echo "✅ CI PASSED"
    exit 0
elif [ "$CONCLUSION" = "failure" ]; then
    echo "❌ CI FAILED"
    echo ""
    echo "View details at: https://github.com/${REPO}/actions/runs/${RUN_ID}"
    exit 1
elif [ "$STATUS" = "in_progress" ] || [ "$STATUS" = "queued" ]; then
    echo "⏳ CI IN PROGRESS"
    echo ""
    echo "View live at: https://github.com/${REPO}/actions/runs/${RUN_ID}"
    exit 2
else
    echo "❓ UNKNOWN STATUS"
    exit 3
fi
