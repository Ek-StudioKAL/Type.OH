#!/bin/bash
# Install Type.OH Quick Actions (Automator workflows) so they show up in the
# Touch Bar's "Quick Actions" button and in the Services menu.
#
#   ./touchbar/install.sh            install / refresh the three actions
#   ./touchbar/install.sh --strip    also put the Quick Actions button in the
#                                    compact Control Strip (reversible with
#                                    uninstall.sh --strip)
#
# Each action just runs:  open -g "typeoh://<action>"
# `-g` keeps your current app in front so dictation pastes into it.
#
# The Touch Bar shows each action's menu name ("Dictate", not "Type.OH
# Dictate") and icon. Quick Actions can only use Apple's NSTouchBar*Template
# icons: icon files in the workflow are ignored, and services declared by an
# app don't appear on the Touch Bar at all.
set -euo pipefail

DEST="$HOME/Library/Services"
mkdir -p "$DEST"

make_workflow() {   # name  url-action  touch-bar-icon
    local name="$1" action="$2" icon="$3"
    local wf="$DEST/Type.OH - $name.workflow"
    rm -rf "$wf"
    mkdir -p "$wf/Contents"
    local uuid_in uuid_out uuid_act
    uuid_in=$(uuidgen); uuid_out=$(uuidgen); uuid_act=$(uuidgen)

    cat > "$wf/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSServices</key>
	<array>
		<dict>
			<key>NSBackgroundColorName</key>
			<string>background</string>
			<key>NSIconName</key>
			<string>$icon</string>
			<key>NSMenuItem</key>
			<dict>
				<key>default</key>
				<string>$name</string>
			</dict>
			<key>NSMessage</key>
			<string>runWorkflowAsService</string>
		</dict>
	</array>
</dict>
</plist>
PLIST

    cat > "$wf/Contents/document.wflow" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AMApplicationBuild</key>
	<string>534</string>
	<key>AMApplicationVersion</key>
	<string>2.10</string>
	<key>AMDocumentVersion</key>
	<string>2</string>
	<key>actions</key>
	<array>
		<dict>
			<key>action</key>
			<dict>
				<key>AMAccepts</key>
				<dict>
					<key>Container</key>
					<string>List</string>
					<key>Optional</key>
					<true/>
					<key>Types</key>
					<array>
						<string>com.apple.cocoa.string</string>
					</array>
				</dict>
				<key>AMActionVersion</key>
				<string>2.0.3</string>
				<key>AMApplication</key>
				<array>
					<string>Automator</string>
				</array>
				<key>AMParameterProperties</key>
				<dict>
					<key>COMMAND_STRING</key>
					<dict/>
					<key>CheckedForUserDefaultShell</key>
					<dict/>
					<key>inputMethod</key>
					<dict/>
					<key>shell</key>
					<dict/>
					<key>source</key>
					<dict/>
				</dict>
				<key>AMProvides</key>
				<dict>
					<key>Container</key>
					<string>List</string>
					<key>Types</key>
					<array>
						<string>com.apple.cocoa.string</string>
					</array>
				</dict>
				<key>ActionBundlePath</key>
				<string>/System/Library/Automator/Run Shell Script.action</string>
				<key>ActionName</key>
				<string>Run Shell Script</string>
				<key>ActionParameters</key>
				<dict>
					<key>COMMAND_STRING</key>
					<string>open -g "typeoh://$action"</string>
					<key>CheckedForUserDefaultShell</key>
					<true/>
					<key>inputMethod</key>
					<integer>0</integer>
					<key>shell</key>
					<string>/bin/zsh</string>
					<key>source</key>
					<string></string>
				</dict>
				<key>BundleIdentifier</key>
				<string>com.apple.RunShellScript</string>
				<key>CFBundleVersion</key>
				<string>2.0.3</string>
				<key>CanShowSelectedItemsWhenRun</key>
				<false/>
				<key>CanShowWhenRun</key>
				<true/>
				<key>Category</key>
				<array>
					<string>AMCategoryUtilities</string>
				</array>
				<key>Class Name</key>
				<string>RunShellScriptAction</string>
				<key>InputUUID</key>
				<string>$uuid_in</string>
				<key>Keywords</key>
				<array>
					<string>Shell</string>
					<string>Script</string>
					<string>Command</string>
					<string>Run</string>
					<string>Unix</string>
				</array>
				<key>OutputUUID</key>
				<string>$uuid_out</string>
				<key>UUID</key>
				<string>$uuid_act</string>
				<key>UnlocalizedApplications</key>
				<array>
					<string>Automator</string>
				</array>
				<key>arguments</key>
				<dict>
					<key>0</key>
					<dict>
						<key>default value</key>
						<integer>0</integer>
						<key>name</key>
						<string>inputMethod</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>0</string>
					</dict>
					<key>1</key>
					<dict>
						<key>default value</key>
						<false/>
						<key>name</key>
						<string>CheckedForUserDefaultShell</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>1</string>
					</dict>
					<key>2</key>
					<dict>
						<key>default value</key>
						<string></string>
						<key>name</key>
						<string>source</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>2</string>
					</dict>
					<key>3</key>
					<dict>
						<key>default value</key>
						<string></string>
						<key>name</key>
						<string>COMMAND_STRING</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>3</string>
					</dict>
					<key>4</key>
					<dict>
						<key>default value</key>
						<string>/bin/sh</string>
						<key>name</key>
						<string>shell</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>4</string>
					</dict>
				</dict>
				<key>isViewVisible</key>
				<integer>1</integer>
				<key>location</key>
				<string>309.000000:305.000000</string>
				<key>nibPath</key>
				<string>/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib</string>
			</dict>
			<key>isViewVisible</key>
			<integer>1</integer>
		</dict>
	</array>
	<key>connectors</key>
	<dict/>
	<key>workflowMetaData</key>
	<dict>
		<key>applicationBundleIDsByPath</key>
		<dict/>
		<key>applicationPaths</key>
		<array/>
		<key>backgroundColorName</key>
		<string>background</string>
		<key>inputTypeIdentifier</key>
		<string>com.apple.Automator.nothing</string>
		<key>outputTypeIdentifier</key>
		<string>com.apple.Automator.nothing</string>
		<key>presentationMode</key>
		<integer>15</integer>
		<key>processesInput</key>
		<false/>
		<key>serviceInputTypeIdentifier</key>
		<string>com.apple.Automator.nothing</string>
		<key>serviceOutputTypeIdentifier</key>
		<string>com.apple.Automator.nothing</string>
		<key>serviceProcessesInput</key>
		<false/>
		<key>systemImageName</key>
		<string>$icon</string>
		<key>useAutomaticInputType</key>
		<false/>
		<key>workflowTypeIdentifier</key>
		<string>com.apple.Automator.servicesMenu</string>
	</dict>
</dict>
</plist>
PLIST
    plutil -lint "$wf/Contents/Info.plist" "$wf/Contents/document.wflow" >/dev/null
    echo "installed: $wf"
}

make_workflow "Dictate" "dictate" "NSTouchBarAudioInputTemplate"
make_workflow "ReType"  "retype"  "NSTouchBarTextBoxTemplate"
make_workflow "LazyPad" "lazypad" "NSTouchBarComposeTemplate"

# Show them on the Touch Bar. macOS keeps that switch per menu name
# (pbs NSServicesStatus "(null) - <name> - runWorkflowAsService"), so a
# renamed action starts hidden. Drop the entries for the old "Type.OH <name>"
# names too.
status=$(mktemp)
defaults export pbs "$status"
for name in Dictate ReType LazyPad; do
    plutil -replace "NSServicesStatus.(null) - $name - runWorkflowAsService" -json \
        '{"presentation_modes":{"ContextMenu":true,"ServicesMenu":true,"TouchBar":true}}' "$status"
    plutil -remove "NSServicesStatus.(null) - Type\.OH $name - runWorkflowAsService" "$status" 2>/dev/null || true
done
defaults import pbs "$status"
rm -f "$status"

# Refresh the Services registry so the Touch Bar / Services menu see them now.
/System/Library/CoreServices/pbs -flush 2>/dev/null || true
/System/Library/CoreServices/pbs -update 2>/dev/null || true

if [[ "${1:-}" == "--strip" ]]; then
    # Add the "Quick Actions" button to the compact Control Strip (the small
    # strip on the right) if it isn't there yet, then restart the strip.
    current=$(defaults read com.apple.controlstrip MiniCustomized 2>/dev/null || echo "")
    if ! grep -q "com.apple.system.workflows" <<<"$current"; then
        defaults write com.apple.controlstrip MiniCustomized -array \
            com.apple.system.brightness com.apple.system.volume \
            com.apple.system.mute com.apple.system.workflows
        killall ControlStrip 2>/dev/null || true
        echo "added Quick Actions to the compact Control Strip"
    fi
fi

cat <<'MSG'

Done. Where to find them:
  * Touch Bar: hold Fn (this Mac's Fn mode is already "Quick Actions"), or tap the
    Quick Actions button (⌘-like "workflow" icon) in the expanded Control Strip.
  * Services menu of any app, and System Settings > Keyboard > Keyboard Shortcuts >
    Services (to give them additional key shortcuts).
  * System Settings > Extensions > Touch Bar Quick Actions lets you hide any of them.
Type.OH must be running (or macOS will launch it) for the actions to work.
MSG
