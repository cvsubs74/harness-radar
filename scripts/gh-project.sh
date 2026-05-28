#!/usr/bin/env bash
# gh-project.sh — Projects v2 wrappers (add-item, set-status, set-field).
#
# Usage:
#   gh-project.sh add-item <issue-number>
#   gh-project.sh set-status <issue-number> <Todo|In progress|In review|Done>
#   gh-project.sh set-field <issue-number> <field-name> <value>
#
# Reads project number + owner from .github/project-config.json (written by
# scripts/gh-bootstrap.sh). All mutations go through `gh api graphql`.

set -euo pipefail

if [ $# -lt 2 ]; then
  cat >&2 <<EOF
usage: $0 <subcommand> <args...>
  add-item   <issue-number>
  set-status <issue-number> <value>
  set-field  <issue-number> <field-name> <value>
EOF
  exit 2
fi

ROOT="$(git rev-parse --show-toplevel)"
CFG="$ROOT/.github/project-config.json"
if [ ! -f "$CFG" ]; then
  echo "error: $CFG missing. Run scripts/gh-bootstrap.sh first." >&2
  exit 1
fi

OWNER=$(jq -r .owner "$CFG")
PROJECT_NUMBER=$(jq -r .project_number "$CFG")
REPO_NWO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"

# Resolve project node id (try user, then org)
PROJECT_ID=$(gh api graphql -f query='
  query($owner: String!, $number: Int!) {
    user(login: $owner) { projectV2(number: $number) { id } }
  }' -F owner="$OWNER" -F number="$PROJECT_NUMBER" --jq '.data.user.projectV2.id' 2>/dev/null || true)

if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "null" ]; then
  PROJECT_ID=$(gh api graphql -f query='
    query($owner: String!, $number: Int!) {
      organization(login: $owner) { projectV2(number: $number) { id } }
    }' -F owner="$OWNER" -F number="$PROJECT_NUMBER" --jq '.data.organization.projectV2.id' 2>/dev/null || true)
fi

if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "null" ]; then
  echo "error: could not resolve project $PROJECT_NUMBER for owner $OWNER" >&2
  exit 1
fi

sub="$1"; shift

resolve_item_id() {
  local issue="$1"
  local issue_node_id
  issue_node_id=$(gh api "repos/$REPO_NWO/issues/$issue" --jq .node_id)
  gh api graphql -f query='
    query($project: ID!) {
      node(id: $project) {
        ... on ProjectV2 {
          items(first: 200) {
            nodes { id content { ... on Issue { id } } }
          }
        }
      }
    }' -F project="$PROJECT_ID" \
    --jq ".data.node.items.nodes[] | select(.content.id == \"$issue_node_id\") | .id"
}

resolve_field_info() {
  gh api graphql -f query='
    query($project: ID!) {
      node(id: $project) {
        ... on ProjectV2 {
          fields(first: 50) {
            nodes {
              __typename
              ... on ProjectV2FieldCommon { id name dataType }
              ... on ProjectV2SingleSelectField { options { id name } }
            }
          }
        }
      }
    }' -F project="$PROJECT_ID"
}

case "$sub" in
  add-item)
    [ $# -eq 1 ] || { echo "usage: $0 add-item <issue-number>" >&2; exit 2; }
    issue="${1#\#}"
    issue_node_id=$(gh api "repos/$REPO_NWO/issues/$issue" --jq .node_id)
    gh api graphql -f query='
      mutation($project: ID!, $issue: ID!) {
        addProjectV2ItemById(input: { projectId: $project, contentId: $issue }) {
          item { id }
        }
      }' -F project="$PROJECT_ID" -F issue="$issue_node_id" >/dev/null
    echo "Added #$issue to project $PROJECT_NUMBER"
    ;;

  set-status|set-field)
    if [ "$sub" = "set-status" ]; then
      [ $# -eq 2 ] || { echo "usage: $0 set-status <issue-number> <value>" >&2; exit 2; }
      issue="${1#\#}"
      field_name="Status"
      value="$2"
    else
      [ $# -eq 3 ] || { echo "usage: $0 set-field <issue-number> <field-name> <value>" >&2; exit 2; }
      issue="${1#\#}"
      field_name="$2"
      value="$3"
    fi

    item_id=$(resolve_item_id "$issue")
    if [ -z "$item_id" ]; then
      # Auto-add to project, then resolve again
      issue_node_id=$(gh api "repos/$REPO_NWO/issues/$issue" --jq .node_id)
      gh api graphql -f query='
        mutation($project: ID!, $issue: ID!) {
          addProjectV2ItemById(input: { projectId: $project, contentId: $issue }) {
            item { id }
          }
        }' -F project="$PROJECT_ID" -F issue="$issue_node_id" \
        --jq '.data.addProjectV2ItemById.item.id' > /tmp/gh-project-item.$$ 2>/dev/null || true
      item_id="$(cat /tmp/gh-project-item.$$ 2>/dev/null || true)"
      rm -f /tmp/gh-project-item.$$
    fi
    if [ -z "$item_id" ] || [ "$item_id" = "null" ]; then
      echo "error: could not add or resolve item for issue #$issue" >&2
      exit 1
    fi

    field_info=$(resolve_field_info)
    field_id=$(echo "$field_info" | jq -r ".data.node.fields.nodes[] | select(.name == \"$field_name\") | .id")
    field_type=$(echo "$field_info" | jq -r ".data.node.fields.nodes[] | select(.name == \"$field_name\") | .dataType")
    if [ -z "$field_id" ] || [ "$field_id" = "null" ]; then
      echo "error: field '$field_name' not found on project" >&2
      exit 1
    fi

    case "$field_type" in
      SINGLE_SELECT)
        option_id=$(echo "$field_info" | jq -r ".data.node.fields.nodes[] | select(.name == \"$field_name\") | .options[] | select(.name == \"$value\") | .id")
        if [ -z "$option_id" ] || [ "$option_id" = "null" ]; then
          echo "error: option '$value' not found on field '$field_name'" >&2
          exit 1
        fi
        gh api graphql -f query='
          mutation($project: ID!, $item: ID!, $field: ID!, $option: String!) {
            updateProjectV2ItemFieldValue(input: {
              projectId: $project, itemId: $item, fieldId: $field,
              value: { singleSelectOptionId: $option }
            }) { projectV2Item { id } }
          }' -F project="$PROJECT_ID" -F item="$item_id" -F field="$field_id" -F option="$option_id" >/dev/null
        ;;
      TEXT)
        gh api graphql -f query='
          mutation($project: ID!, $item: ID!, $field: ID!, $text: String!) {
            updateProjectV2ItemFieldValue(input: {
              projectId: $project, itemId: $item, fieldId: $field,
              value: { text: $text }
            }) { projectV2Item { id } }
          }' -F project="$PROJECT_ID" -F item="$item_id" -F field="$field_id" -F text="$value" >/dev/null
        ;;
      NUMBER)
        gh api graphql -f query='
          mutation($project: ID!, $item: ID!, $field: ID!, $num: Float!) {
            updateProjectV2ItemFieldValue(input: {
              projectId: $project, itemId: $item, fieldId: $field,
              value: { number: $num }
            }) { projectV2Item { id } }
          }' -F project="$PROJECT_ID" -F item="$item_id" -F field="$field_id" -F num="$value" >/dev/null
        ;;
      *)
        echo "error: unsupported field type '$field_type' for field '$field_name'" >&2
        exit 1
        ;;
    esac
    echo "Set '$field_name' = '$value' for #$issue"
    ;;

  *)
    echo "error: unknown subcommand '$sub'" >&2
    exit 2
    ;;
esac
