#!/bin/bash
# Remove the Type.OH Quick Actions installed by install.sh.
#   ./touchbar/uninstall.sh          remove the three workflows
#   ./touchbar/uninstall.sh --strip  also remove Quick Actions from the compact Control Strip
set -euo pipefail
for n in Dictate ReType LazyPad; do
    rm -rf "$HOME/Library/Services/Type.OH - $n.workflow" && echo "removed: Type.OH - $n"
done
# Forget their Touch Bar switches (see install.sh).
status=$(mktemp)
defaults export pbs "$status"
for n in Dictate ReType LazyPad; do
    plutil -remove "NSServicesStatus.(null) - $n - runWorkflowAsService" "$status" 2>/dev/null || true
done
defaults import pbs "$status"
rm -f "$status"
/System/Library/CoreServices/pbs -update 2>/dev/null || true
if [[ "${1:-}" == "--strip" ]]; then
    defaults write com.apple.controlstrip MiniCustomized -array \
        com.apple.system.brightness com.apple.system.volume \
        com.apple.system.mute com.apple.system.mission-control
    killall ControlStrip 2>/dev/null || true
    echo "restored the compact Control Strip"
fi
