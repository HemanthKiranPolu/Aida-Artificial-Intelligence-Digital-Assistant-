#!/usr/bin/env bash

set -euo pipefail

ACTION="${1:-install}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMPLATE_FILE="${PROJECT_ROOT}/launchd/com.hemanth.parakeet.plist"
LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"
TARGET_PLIST="${LAUNCH_AGENTS_DIR}/com.hemanth.parakeet.plist"
SERVICE_LABEL="com.hemanth.parakeet"
SERVICE_TARGET="gui/$UID/${SERVICE_LABEL}"

usage() {
  cat <<'EOF'
Usage: manage_parakeet_service.sh [install|uninstall|restart|status]

install   Render the launch agent plist into ~/Library/LaunchAgents,
          then load/enable it via launchctl.
uninstall Stop the agent (if running) and delete the plist.
restart   Reload the agent after picking up any changes.
status    Print the current service state from launchctl.
EOF
}

render_plist() {
  mkdir -p "${LAUNCH_AGENTS_DIR}"
  sed "s#__PROJECT_ROOT__#${PROJECT_ROOT}#g" "${TEMPLATE_FILE}" > "${TARGET_PLIST}"
}

bootstrap_agent() {
  launchctl bootout "${SERVICE_TARGET}" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$UID" "${TARGET_PLIST}"
  launchctl enable "${SERVICE_TARGET}"
}

case "${ACTION}" in
  install)
    if [[ ! -f "${TEMPLATE_FILE}" ]]; then
      echo "Template plist not found at ${TEMPLATE_FILE}" >&2
      exit 1
    fi
    render_plist
    bootstrap_agent
    echo "Installed Parakeet launch agent at ${TARGET_PLIST}."
    echo "Logs: /tmp/parakeet.log"
    ;;
  uninstall)
    launchctl bootout "${SERVICE_TARGET}" >/dev/null 2>&1 || true
    if [[ -f "${TARGET_PLIST}" ]]; then
      rm "${TARGET_PLIST}"
      echo "Removed ${TARGET_PLIST}"
    fi
    ;;
  restart)
    if [[ -f "${TARGET_PLIST}" ]]; then
      bootstrap_agent
      echo "Restarted ${SERVICE_LABEL}."
    else
      echo "Launch agent plist is missing. Run install first." >&2
      exit 1
    fi
    ;;
  status)
    launchctl print "${SERVICE_TARGET}"
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
