# Wiflow NR3053 — Hybrid CAPPORT HTTPS release gate (NO FLASH)

**2026-10-10:** Approved direction: standardized CAPPORT + HTTP fallback + local Portal + no-navigation final confirmation. This document separates the implemented HTTP fallback from unimplemented HTTPS CAPPORT.

## Phase 1 — HTTP fallback hardening implemented in PR #29

- Unauthorized HTTP probe with a foreign Host header receives a fixed pre-auth redirect to http://10.10.10.1:2080/cgi-bin/portal. This is an initial captive detection redirect; the final confirmation NEVER redirects the browser.
- Explicit final confirmation sends a same-origin POST using fetch. A 204 result means the local router completed authorization. If the response is interrupted, POST action=status checks the specific session and live nft authorization pair before showing success; errors keep a retry option.
- WordPress is not needed to authenticate a guest or process final confirmation.
- Prior code unconditionally advertised DHCPv4 Option 114 with an HTTP CGI URL and offered an HTTP application/captive+json CGI. Those are invalid for RFC 8908/8910. Both are now removed; the HTTP fallback remains.
- The built FIT auditor blocks obsolete HTTP CAPPORT advertisement and requires non-navigation confirmation across all three Portal templates.

## Phase 2 — RFC 8908/8910 (design requirements, NOT YET IMPLEMENTED)

The DHCPv4 Option 114 URI MUST be the HTTPS URL of the RFC 8908 Captive Portal JSON API, not the HTML login page. The API must respond with Content-Type application/captive+json, valid JSON with captive:true when that client is blocked and captive:false only when the SAME CLIENT is authorized by the local firewall. The user-portal-url field must itself be an HTTPS URL. Do not advertise the option before TLS works on unmodified iOS/Android/Windows clients.

Required evidence before enabling DHCP Option 114:

1. Stable operator-controlled HTTPS hostname, publicly trusted certificate, hostname match, expiry monitoring and automated renewal; ensure the intended HTTPS service is available to pre-auth guests.
2. Pre-auth DNS returns the correct address for the HTTPS CAPPORT hostname. Split-horizon DNS pointing to the local router listener is allowed only with a valid certificate for that name. Never rewrite unrelated DNS or intercept arbitrary HTTPS.
3. The HTTPS API and user-facing Portal listeners remain isolated from Wiflow Setup and LuCI; firewall allows specific endpoints, not unrestricted external TCP/443, DNS-over-TLS tunnels or generic WAN.
4. When CAPPORT is remote, it must securely bind client identity and authorization to the local router; do not trust client-supplied X-Forwarded-For as an identity. Prefer truly local TLS CAPPORT with the local IP/MAC nft truth source.
5. Cache-Control no-store for any client-specific response; no leakage of session IDs, customer tokens or device identity into external URLs, redirects or logs.
6. Full packet and browser testing: DHCP Option 114 encoding, captive=true/false transitions, cert validation, legacy HTTP fallback, iOS/Android/Windows/macOS captive windows, Private DNS and VPN behavior, IP changes, disconnect, revoked grants, WordPress outage, and controlled restarts.
7. Fail closed. If TLS or provisioning fails, do not advertise CAPPORT; preserve HTTP fallback and keep unauthorized guests offline.

Never advertise placeholder HTTPS endpoints merely to pass source checks.

Official specifications:
- RFC 8910: https://www.rfc-editor.org/rfc/rfc8910
- RFC 8908: https://www.rfc-editor.org/rfc/rfc8908
- Android Captive Portal API: https://developer.android.com/about/versions/11/features/captive-portal

**Release gates:** A successful host CI or FIT static audit does not prove an NR3053 boot, Wi-Fi, captive mini-browser compatibility or physical recovery. S5 and S6 remain BLOCK pending independent real-device and UART/bootloader evidence. NO FLASH.
