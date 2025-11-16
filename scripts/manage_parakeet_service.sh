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
Usage: manage_parakeet_service.sh [install|uninstall|start|stop|restart|status]

install   Render the launch agent plist into ~/Library/LaunchAgents.
start     Bootstraps + kicks off the launch agent immediately.
stop      Boot out the agent (stops the server if we launched it).
restart   stop + start.
status    Print the current service state from launchctl.
uninstall Stop the agent (if running) and delete the plist.
EOF
}

render_plist() {
  mkdir -p "${LAUNCH_AGENTS_DIR}"
  sed "s#__PROJECT_ROOT__#${PROJECT_ROOT}#g" "${TEMPLATE_FILE}" > "${TARGET_PLIST}"
}

ensure_plist_exists() {
  if [[ ! -f "${TARGET_PLIST}" ]]; then
    echo "Launch agent plist not found. Run install first." >&2
    exit 1
  fi
}

start_agent() {
  ensure_plist_exists
  launchctl bootout "${SERVICE_TARGET}" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$UID" "${TARGET_PLIST}"
  launchctl kickstart -k "${SERVICE_TARGET}"
}

stop_agent() {
  launchctl bootout "${SERVICE_TARGET}" >/dev/null 2>&1 || true
}

case "${ACTION}" in
  install)
    if [[ ! -f "${TEMPLATE_FILE}" ]]; then
      echo "Template plist not found at ${TEMPLATE_FILE}" >&2
      exit 1
    fi
    render_plist
    echo "Installed Parakeet launch agent at ${TARGET_PLIST}."
    echo "Use 'start' to run it manually or open the ASR app (it auto-starts the agent)."
    ;;
  uninstall)
    stop_agent
    if [[ -f "${TARGET_PLIST}" ]]; then
      rm "${TARGET_PLIST}"
      echo "Removed ${TARGET_PLIST}"
    fi
    ;;
  start)
    start_agent
    echo "Started ${SERVICE_LABEL} via launchctl."
    ;;
  stop)
    stop_agent
    echo "Stopped ${SERVICE_LABEL}."
    ;;
  restart)
    start_agent
    echo "Restarted ${SERVICE_LABEL}."
    ;;
  status)
    ensure_plist_exists
    launchctl print "${SERVICE_TARGET}"
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
