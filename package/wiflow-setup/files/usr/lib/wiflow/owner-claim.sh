#!/bin/sh
# One first-owner physical WPS claim, bound to Gate session and client IP.
OWNER_CLAIM_DIR=/tmp/wiflow-owner-claim
owner_unclaimed(){
  [ "$(uci -q get wiflow.core 2>/dev/null)" = core ] || return 1
  [ -z "$(uci -q get wiflow.core.setup_password_hash 2>/dev/null)" ]
}
owner_token_ok(){
  [ "$(printf '%s' "$1" | wc -c | tr -d ' ')" = 64 ] || return 1
  case "$1" in *[!0-9a-f]*|'') return 1;; esac
}
owner_ip_ok(){ case "$1" in 10.0.0.*|10.10.10.*) return 0;; *) return 1;; esac; }
owner_claim_arm(){
(
  umask 077
  owner_unclaimed && owner_token_ok "$1" && owner_ip_ok "$2" || exit 1
  mkdir -p "$OWNER_CLAIM_DIR" && chmod 700 "$OWNER_CLAIM_DIR" || exit 1
  mkdir "$OWNER_CLAIM_DIR.lock" 2>/dev/null || exit 1
  trap 'rmdir "$OWNER_CLAIM_DIR.lock" 2>/dev/null || true' EXIT
  now="$(date +%s)"
  if [ -f "$OWNER_CLAIM_DIR/approved" ]; then
    IFS='|' read -r saved ip expiry < "$OWNER_CLAIM_DIR/approved" || true
    if [ "$expiry" -gt "$now" ] 2>/dev/null; then
      [ "$saved" = "$1" ] && [ "$ip" = "$2" ]; exit $?
    fi
    rm -f "$OWNER_CLAIM_DIR/approved"
  fi
  if [ -f "$OWNER_CLAIM_DIR/request" ]; then
    IFS='|' read -r saved ip expiry < "$OWNER_CLAIM_DIR/request" || true
    if [ "$expiry" -gt "$now" ] 2>/dev/null &&
       { [ "$saved" != "$1" ] || [ "$ip" != "$2" ]; }; then exit 1; fi
  fi
  printf '%s|%s|%s\n' "$1" "$2" "$((now + 60))" > "$OWNER_CLAIM_DIR/request.$$" || exit 1
  mv -f "$OWNER_CLAIM_DIR/request.$$" "$OWNER_CLAIM_DIR/request"
)
}
owner_claim_wps(){
(
  umask 077
  owner_unclaimed && [ -d "$OWNER_CLAIM_DIR" ] || exit 1
  mkdir "$OWNER_CLAIM_DIR.lock" 2>/dev/null || exit 1
  trap 'rmdir "$OWNER_CLAIM_DIR.lock" 2>/dev/null || true' EXIT
  [ -f "$OWNER_CLAIM_DIR/request" ] || exit 1
  IFS='|' read -r saved ip expiry < "$OWNER_CLAIM_DIR/request" || exit 1
  now="$(date +%s)"
  owner_token_ok "$saved" && owner_ip_ok "$ip" &&
    [ "$expiry" -gt "$now" ] 2>/dev/null || exit 1
  printf '%s|%s|%s\n' "$saved" "$ip" "$((now + 90))" > "$OWNER_CLAIM_DIR/approved.$$" || exit 1
  mv -f "$OWNER_CLAIM_DIR/approved.$$" "$OWNER_CLAIM_DIR/approved" || exit 1
  rm -f "$OWNER_CLAIM_DIR/request"
)
}
owner_claim_consume(){
(
  umask 077
  owner_unclaimed && owner_token_ok "$1" && owner_ip_ok "$2" || exit 1
  [ -d "$OWNER_CLAIM_DIR" ] || exit 1
  mkdir "$OWNER_CLAIM_DIR.lock" 2>/dev/null || exit 1
  trap 'rmdir "$OWNER_CLAIM_DIR.lock" 2>/dev/null || true' EXIT
  [ -f "$OWNER_CLAIM_DIR/approved" ] || exit 1
  IFS='|' read -r saved ip expiry < "$OWNER_CLAIM_DIR/approved" || exit 1
  now="$(date +%s)"
  [ "$saved" = "$1" ] && [ "$ip" = "$2" ] &&
    [ "$expiry" -gt "$now" ] 2>/dev/null || exit 1
  rm -f "$OWNER_CLAIM_DIR/approved" "$OWNER_CLAIM_DIR/request"
)
}
