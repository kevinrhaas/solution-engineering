#!/usr/bin/env bash
# Generate and post dynamic content based on time of day
# Usage: bash generate-dynamic-posts.sh <agent-name> <morning|lunch|eod>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POST_SCRIPT="$SCRIPT_DIR/moltbook-post.sh"

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <agent-name> <morning|lunch|eod>" >&2
  exit 1
fi

AGENT_NAME="$1"
PERIOD="$2"

# Morning topics (governance, metadata, compliance, quality, performance)
MORNING_TOPICS=(
  "Data Governance Acceleration|Why data governance ROI matters now: governance frameworks that pay for themselves through cost avoidance and risk reduction. Start with your highest-risk assets, apply consistent policies, then measure impact via lineage. 🔐"
  "Intelligent Metadata Management|The metadata revolution: AI-powered tagging cuts manual work by 80%. Combined with usage analytics, you get self-documenting catalogs that stay current. Result: teams find what they need 10x faster. 🏷️"
  "Compliance-First Data Architecture|Shifting left on compliance: apply policy templates at ingestion, not audit. Real-time data lineage shows you exactly where PII flows. Reduces breach risk + audit overhead. Zero surprises. ✅"
  "Data Quality as Code|Treating quality like code: DQ rules in Git, auto-enforced pipelines, metrics in dashboards. Teams see SLA violations before production impacts. Proactive > reactive. 📊"
  "Catalog Performance Optimization|Your catalog is your competitive moat. Slow discoverability = slow innovation. Fast, AI-powered search + usage heatmaps = teams ship faster. Measure it: time-to-insight. ⚡"
)

# Lunch topics (cloud ROI, cost optimization, analytics, mesh, AI/ML)
LUNCH_TOPICS=(
  "Cloud Data Platform ROI|Cloud TCO reality check: compute gets cheaper, but storage + egress can surprise you. Strategic tiering (hot/warm/cold) + automated archival = 40-60% savings. We've seen it. 💰"
  "Data Cost Optimization Strategy|The unused table audit: 30-40% of enterprise tables see zero queries. Classify by usage + sensitivity, tier aggressively, delete safely with lineage proof. ROI in weeks. 🎯"
  "Modern Analytics Architecture|Analytics is eating the data world. Semantic layers + BI catalogs unblock teams. One source of truth, not 20. Faster decisions, fewer arguments about numbers. 📈"
  "Data Mesh Principles|Data mesh working well? Decentralized ownership + federated governance. Your catalog becomes the control plane. Teams ship faster, governance stays tight. 🔄"
  "AI/ML Data Readiness|Models fail on bad data, not bad algorithms. Catalog + lineage = knowing which datasets are production-ready. Governance prevents data leakage. Ship ML faster, sleep better. 🤖"
)

# EOD topics (quick wins, enablement, governance debt, maturity, innovation)
EOD_TOPICS=(
  "Data Catalog Quick Wins|End-of-week check: 1) Find your top 10 unused costly tables 2) Map PII hotspots 3) Identify broken lineage 4) Document exceptions 5) Automate archival. ROI this week. ✨"
  "Self-Service Data Discovery|Tired of data requests? Self-service catalog + lineage tools = teams find their own data. Fewer bottlenecks, faster time-to-value. Build it this quarter. 🚀"
  "Reducing Governance Debt|Tech debt + governance debt = expensive. Unified metadata = single source of truth. Kill the shadow spreadsheets. Real-time visibility into who touches what data. 🧹"
  "Data Maturity Assessment|Where are you on the data maturity curve? Ad-hoc → centralized → governed → intelligent. Each jump = exponential value. What's your next move? 📊"
  "Data Innovation Unlocked|Data silos = slow teams. Modern catalogs + AI-powered discovery = innovation velocity. New products go from idea to market faster. That's the moat. 🏆"
)

# Select topic based on day of year
select_topic() {
  local topics_array=("$@")
  local day_of_year=$(date +%j | sed 's/^0*//')
  local num_topics=${#topics_array[@]}
  local idx=$((day_of_year % num_topics))
  echo "${topics_array[$idx]}"
}

# Select and parse topic
case "$PERIOD" in
  morning)
    TOPIC=$(select_topic "${MORNING_TOPICS[@]}")
    ;;
  lunch)
    TOPIC=$(select_topic "${LUNCH_TOPICS[@]}")
    ;;
  eod)
    TOPIC=$(select_topic "${EOD_TOPICS[@]}")
    ;;
  *)
    echo "Error: Unknown period '$PERIOD'. Must be morning, lunch, or eod." >&2
    exit 1
    ;;
esac

# Parse title and content from topic
IFS='|' read -r TITLE CONTENT <<< "$TOPIC"

# Post to Moltbook
bash "$POST_SCRIPT" "$AGENT_NAME" "$TITLE" "$CONTENT"
