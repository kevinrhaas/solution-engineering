#!/usr/bin/env bash
#
# create-agent.sh — Register a new agent on Moltbook
#
# Interactive wizard that:
#   1. Prompts for agent name, description, and API key
#   2. Registers the agent with the Moltbook API
#   3. Saves credentials to agents/<name>/agent-config.json
#   4. Stores the API key at ~/.config/moltbook/credentials.json
#   5. Provides a claim URL to verify ownership
#
# After running this, deploy the agent to OpenClaw with:
#   openclaw agents add --id <name> --workspace ~/.openclaw/agents/<name>
#
# Usage:
#   bash create-agent.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_header() {
  echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
}

print_success() {
  echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
  echo -e "${RED}✗ $1${NC}"
}

print_warning() {
  echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
  echo -e "${BLUE}ℹ $1${NC}"
}

# Check required tools
check_requirements() {
  print_header "Checking Requirements"
  
  if ! command -v curl &> /dev/null; then
    print_error "curl is not installed"
    exit 1
  fi
  
  if ! command -v python3 &> /dev/null; then
    print_error "python3 is not installed"
    exit 1
  fi
  
  print_success "All requirements met"
}

# Get agent details from user
get_agent_details() {
  print_header "Agent Configuration"
  
  read -p "Enter agent name (e.g., my-analytics-bot): " AGENT_NAME
  if [[ -z "$AGENT_NAME" ]]; then
    print_error "Agent name cannot be empty"
    exit 1
  fi
  
  read -p "Enter agent description (one sentence): " AGENT_DESCRIPTION
  if [[ -z "$AGENT_DESCRIPTION" ]]; then
    print_error "Agent description cannot be empty"
    exit 1
  fi
  
  echo ""
  echo "Agent Details:"
  echo "  Name: $AGENT_NAME"
  echo "  Description: $AGENT_DESCRIPTION"
}

# Register agent with Moltbook
register_agent() {
  print_header "Registering Agent with Moltbook"
  
  # Check if we have an API key from environment
  if [[ -z "${MOLTBOOK_API_KEY:-}" ]]; then
    read -sp "Enter your Moltbook API key (hidden): " MOLTBOOK_API_KEY
    echo ""
  fi
  
  if [[ -z "$MOLTBOOK_API_KEY" ]]; then
    print_error "API key is required"
    exit 1
  fi
  
  # Save API key for future use
  CONFIG_DIR="$HOME/.config/moltbook"
  mkdir -p "$CONFIG_DIR"
  echo "{\"api_key\": \"$MOLTBOOK_API_KEY\"}" > "$CONFIG_DIR/credentials.json"
  chmod 600 "$CONFIG_DIR/credentials.json"
  print_success "API key saved to $CONFIG_DIR/credentials.json"
  
  # Register the agent
  print_info "Registering agent..."
  
  REGISTER_RESPONSE=$(curl -sS -X POST https://www.moltbook.com/api/v1/agents/register \
    -H "Authorization: Bearer $MOLTBOOK_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"$AGENT_NAME\",
      \"description\": \"$AGENT_DESCRIPTION\"
    }")
  
  # Extract agent info
  AGENT_ID=$(echo "$REGISTER_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('agent', {}).get('id', ''))" 2>/dev/null || echo "")
  CLAIM_URL=$(echo "$REGISTER_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('claim_url', ''))" 2>/dev/null || echo "")
  
  if [[ -z "$AGENT_ID" ]]; then
    print_error "Failed to register agent"
    echo "Response: $REGISTER_RESPONSE"
    exit 1
  fi
  
  print_success "Agent registered!"
  print_info "Agent ID: $AGENT_ID"
}

# Display claim instructions
show_claim_instructions() {
  print_header "Agent Claim Instructions"
  
  echo ""
  echo "Your agent is registered but needs to be claimed to activate it."
  echo ""
  echo "Send this claim URL to your human owner for verification:"
  echo ""
  echo -e "${YELLOW}$CLAIM_URL${NC}"
  echo ""
  echo "Alternatively, open this link in your browser:"
  echo "https://www.moltbook.com/claim/${CLAIM_URL##*/}"
  echo ""
  print_info "Once claimed, the agent will be fully active."
  echo ""
}

# Create directory structure for agent
setup_agent_directory() {
  print_header "Setting Up Agent Directory"
  
  AGENT_DIR="$SCRIPT_DIR/agents/$AGENT_NAME"
  mkdir -p "$AGENT_DIR"
  
  # Create agent config
  cat > "$AGENT_DIR/agent-config.json" <<EOF
{
  "name": "$AGENT_NAME",
  "description": "$AGENT_DESCRIPTION",
  "agent_id": "$AGENT_ID",
  "api_key": "$MOLTBOOK_API_KEY",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "status": "pending_claim",
  "claim_url": "$CLAIM_URL"
}
EOF
  
  print_success "Agent directory created at: $AGENT_DIR"
}

# Generate setup summary
create_setup_summary() {
  print_header "Agent Setup Summary"
  
  SUMMARY_FILE="$AGENT_DIR/AGENT_SETUP.md"
  
  cat > "$SUMMARY_FILE" <<EOF
# Agent Setup: $AGENT_NAME

## Overview
- **Name**: $AGENT_NAME
- **Description**: $AGENT_DESCRIPTION
- **Agent ID**: $AGENT_ID
- **Created**: $(date)

## Status
**Pending Claim** - The agent is registered but not yet claimed.

## Claim Process
Send this link to your human owner to verify ownership:
\`\`\`
$CLAIM_URL
\`\`\`

## Files
- \`agent-config.json\` - Agent configuration and credentials
- \`moltbook-post.sh\` - Post individual messages to moltbook
- \`generate-dynamic-posts.sh\` - Generate topic-based posts
- \`schedule-daily-posts.sh\` - Schedule daily posts

## Usage

### Post a message
\`\`\`bash
./moltbook-post.sh <submolt> "<title>" "<content>"
./moltbook-post.sh general "My Title" "My content here"
\`\`\`

### Generate dynamic post
\`\`\`bash
./generate-dynamic-posts.sh <morning|lunch|eod>
\`\`\`

### Schedule daily posts
\`\`\`bash
./schedule-daily-posts.sh <morning|lunch|eod>
\`\`\`

## Setup Cron Jobs (Optional)
To post 3x daily, add these to your crontab:

\`\`\`
0 8 * * * cd $AGENT_DIR && ./schedule-daily-posts.sh morning
0 12 * * * cd $AGENT_DIR && ./schedule-daily-posts.sh lunch
0 17 * * * cd $AGENT_DIR && ./schedule-daily-posts.sh eod
\`\`\`

## Next Steps
1. ✅ Agent created and registered
2. ⏳ **Claim the agent** using the claim URL above
3. 📝 Customize topics in \`generate-dynamic-posts.sh\`
4. 🕐 Set up cron jobs for automated posting
5. 📊 Monitor posts in \`moltbook-posts.log\`

## Support
For issues or feature requests, refer to moltbook documentation.
EOF
  
  print_success "Setup summary created at: $SUMMARY_FILE"
}

# Main execution
main() {
  print_header "Moltbook Agent Creator"
  
  check_requirements
  get_agent_details
  register_agent
  setup_agent_directory
  create_setup_summary
  show_claim_instructions
  
  echo ""
  print_success "Agent setup complete!"
  echo ""
  echo "Next steps:"
  echo "  1. Claim the agent using the URL above"
  echo "  2. Check the setup guide: $SUMMARY_FILE"
  echo "  3. Configure and test your agent"
  echo ""
}

main "$@"
