import Foundation

/// This is a firmware-specific USB composition, not generic iOS modem support.
enum ModulePortabilityPolicy {
    static let verifiedFirmware = "QDC507GLEFM21_01.001.01.009"
    static let fullFunctions = "diag,serial,ecm,ffs,audio"
    static let mobileFunctions = "diag,serial,ecm,ffs"
    static let directory = "/run/celldock-portable"
    static let scriptPath = directory + "/host-session.sh"

    static func supports(firmware: String?) -> Bool {
        firmware?.split(whereSeparator: { $0.isWhitespace })
            .contains(Substring(verifiedFirmware)) == true
    }

    // No boot script or read-only firmware partition is changed. A power cycle
    // uses the saved audio=0 USBCFG. This detached process also handles a USB
    // cable swap when the modem remains externally powered.
    static let sessionScript = #"""
    #!/bin/sh
    set -eu
    base=/sys/class/android_usb/android0
    dir=/run/celldock-portable
    full=diag,serial,ecm,ffs,audio
    mobile=diag,serial,ecm,ffs
    current=$(cat "$base/functions")
    [ "$current" = "$full" ] || [ "$current" = "$mobile" ] || exit 20
    [ "$(cat "$base/enable")" = 1 ] || exit 21
    [ "$(cat /sys/class/android_usb/f_audio/audio_enable)" = 0 ] || exit 22
    restore() {
        current=$(cat "$base/functions") || return
        if [ "$current" = "$full" ] || [ "$current" = "$mobile" ]; then
            printf 0 > "$base/enable"
            printf '%s' "$mobile" > "$base/functions"
            printf 1 > "$base/enable"
        fi
    }
    cleanup() {
        trap - 0 HUP INT TERM
        restore || true
        rm -f "$dir/pid" "$dir/started"
    }
    trap cleanup 0
    trap 'exit 0' HUP INT TERM
    printf '%s' "$$" > "$dir/pid"
    printf '%s' "$current" > "$dir/started"
    if [ "$current" = "$mobile" ]; then
        # Let the ADB caller receive the launch receipt and close its handles.
        sleep 1
        printf 0 > "$base/enable"
        printf '%s' "$full" > "$base/functions"
        printf 1 > "$base/enable"
    fi
    n=0
    while [ "$(cat "$base/state")" != CONFIGURED ]; do
        n=$((n+1))
        [ "$n" -lt 150 ] || exit 23
        sleep 0.2
    done
    echo mac_ready
    disconnected=0
    while :; do
        [ "$(cat "$base/functions")" = "$full" ] || exit 24
        # audio_enable can briefly re-enumerate USB on some QDC507 builds.
        # VBUS loss is definitive; otherwise require a sustained disconnect.
        present=$(cat /sys/class/power_supply/usb/present 2>/dev/null || echo unknown)
        [ "$present" != 0 ] || break
        if [ "$(cat "$base/state")" = DISCONNECTED ]; then
            disconnected=$((disconnected+1))
            [ "$disconnected" -lt 15 ] || break
        else
            disconnected=0
        fi
        sleep 0.2
    done
    echo usb_detached
    """#
}
