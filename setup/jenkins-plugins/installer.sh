#!/usr/bin/env bash

set -euo pipefail

JENKINS_URL="${JENKINS_URL:-http://localhost:8080}"
JENKINS_USER="${JENKINS_USER:-admin}"
JENKINS_PASSWORD="${JENKINS_PASSWORD:-}"
JENKINS_URL="${JENKINS_URL%/}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COOKIE_JAR="$(mktemp)"
trap 'rm -f "$COOKIE_JAR"' EXIT

if [[ -z "$JENKINS_PASSWORD" ]]; then
  read -rsp "Jenkins password for ${JENKINS_USER}: " JENKINS_PASSWORD
  printf '\n'
fi

if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  echo "This script requires curl and jq." >&2
  exit 1
fi

CRUMB_JSON="$(curl --fail --silent --show-error --cookie-jar "$COOKIE_JAR" \
  --user "${JENKINS_USER}:${JENKINS_PASSWORD}" \
  "${JENKINS_URL}/crumbIssuer/api/json")"
CRUMB_FIELD="$(jq -er '.crumbRequestField' <<<"$CRUMB_JSON")"
CRUMB="$(jq -er '.crumb' <<<"$CRUMB_JSON")"
JENKINS_VERSION="$(curl --fail --silent --show-error \
  --user "${JENKINS_USER}:${JENKINS_PASSWORD}" \
  "${JENKINS_URL}/api/json?tree=version" | jq -er '.version')"
UPDATE_CENTER_JSON="$(curl --fail --silent --show-error \
  "https://updates.jenkins.io/update-center.actual.json?version=${JENKINS_VERSION}")"

while IFS= read -r plugin || [[ -n "$plugin" ]]; do
  [[ -z "$plugin" || "$plugin" == \#* ]] && continue

  plugin_version="$(jq -er --arg plugin "$plugin" '.plugins[$plugin].version' <<<"$UPDATE_CENTER_JSON")" || {
    echo "No compatible ${plugin} release was found for Jenkins ${JENKINS_VERSION}." >&2
    exit 1
  }

  echo "Requesting ${plugin}@${plugin_version} for Jenkins ${JENKINS_VERSION}"
  curl --fail --silent --show-error --cookie "$COOKIE_JAR" \
    --user "${JENKINS_USER}:${JENKINS_PASSWORD}" \
    --request POST \
    --header "${CRUMB_FIELD}: ${CRUMB}" \
    --header 'Content-Type: text/xml' \
    --data "<jenkins><install plugin='${plugin}@${plugin_version}' /></jenkins>" \
    "${JENKINS_URL}/pluginManager/installNecessaryPlugins"
  printf '\n'
done <"${SCRIPT_DIR}/plugins.txt"

echo "Plugin install requests completed. Review Manage Jenkins > Plugins and restart Jenkins if requested."
