#!/bin/bash
set -euo pipefail

# --- Config you can override via env when needed ---
: "${AWS_PROFILE:=khaas}"
: "${AWS_REGION:=us-east-1}"
: "${LOG:=/tmp/call-bedrock.log}"
: "${OUTDIR:=$(pwd)}"
# Ensure aws is on PATH for non-interactive shells (Homebrew on Apple Silicon etc.)
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

MODEL_ID="$1"
BODY="$2"   # pass the full JSON body as a single argument

OUTFILE="$OUTDIR/${MODEL_ID//[:.]/_}.out"
BODYFILE="$(mktemp /tmp/bedrock_body.XXXXXXXXXX).json"


# Log stdout+stderr with timestamps
# replace your exec ... line with this
exec >>"$LOG" 2>&1


echo "=== call-bedrock start ==="
echo "whoami=$(whoami) PWD=$(pwd) HOME=${HOME:-<unset>}"
echo "aws=$(command -v aws || true)"
aws --version || true

# Write body to a file so no quoting games are needed
printf '%s' "$BODY" > "$BODYFILE"

# Touch a start marker in OUTDIR (absolute path avoids CWD surprises)
touch "$OUTDIR/start_${MODEL_ID//[:.]/_}.out"

aws bedrock-runtime invoke-model \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --model-id "$MODEL_ID" \
  --cli-binary-format raw-in-base64-out \
  --body "file://$BODYFILE" \
  "$OUTFILE"

echo "Output saved to: $OUTFILE"
echo "=== call-bedrock done ==="
