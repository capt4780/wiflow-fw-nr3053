#!/bin/sh
# Single authoritative Gate verifier for Wiflow Setup and LuCI.
# This is a permanent, PUBLIC emergency code. It opens the Gate only;
# Wiflow Setup / LuCI account authentication is a separate required step.
# Keep emergency-code use restricted to the management subnet.
WIFLOW_EMERGENCY_GATE_CODE='WIFDIDNR3053'

wiflow_gate_code_allowed(){
    wf_gate_entered="$1"
    wf_gate_expected="$2"
    [ -n "$wf_gate_expected" ] || return 1
    case "$wf_gate_entered" in
        [0-9][0-9][0-9][0-9][0-9][0-9])
            [ "$wf_gate_entered" = "$wf_gate_expected" ]
            ;;
        "$WIFLOW_EMERGENCY_GATE_CODE")
            case "${REMOTE_ADDR:-}" in
                10.0.0.*) return 0 ;;
                *) return 1 ;;
            esac
            ;;
        *) return 1 ;;
    esac
}
