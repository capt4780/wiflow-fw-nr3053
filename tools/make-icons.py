#!/usr/bin/env python3
"""Writes the flat Wiflow icon set for LuCI (radio, signal, ports) into
rom/overlay/www/luci-static/resources/icons. Blue = active, grey = disabled."""
import os, sys
D = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), '..', 'rom/overlay/www/luci-static/resources/icons')
B, G, L = '#0054F0', '#9AA6BF', '#D3DCEB'
def svg(body): return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" width="32" height="32">' + body + '</svg>\n'
def wifi(c): return svg(f'<g fill="none" stroke="{c}" stroke-width="2.6" stroke-linecap="round"><path d="M4.5 12.2a16 16 0 0 1 23 0"/><path d="M8.6 16.6a10.2 10.2 0 0 1 14.8 0"/><path d="M12.7 21a4.4 4.4 0 0 1 6.6 0"/></g><circle cx="16" cy="25.2" r="1.9" fill="{c}"/>')
def bars(n, slash=False):
    s = ''.join(f'<rect x="{5 + i * 6}" y="{27 - h}" width="4" height="{h}" rx="1.2" fill="{B if i < n else L}"/>' for i, h in enumerate((6, 11, 16, 21)))
    return svg(s + (f'<path d="M5 5l22 22" stroke="{G}" stroke-width="2.4" stroke-linecap="round"/>' if slash else ''))
def eth(c): return svg(f'<rect x="4.5" y="8" width="23" height="14" rx="3" fill="none" stroke="{c}" stroke-width="2.4"/><path d="M10 22v3.5M16 22v3.5M22 22v3.5M10 13v4M16 13v4M22 13v4" stroke="{c}" stroke-width="2.4" stroke-linecap="round" fill="none"/>')
def bridge(c): return svg(f'<g fill="none" stroke="{c}" stroke-width="2.4" stroke-linejoin="round" stroke-linecap="round"><rect x="3.5" y="11" width="8" height="10" rx="2.4"/><rect x="20.5" y="11" width="8" height="10" rx="2.4"/><path d="M11.5 16h9"/></g>')
def alias(c): return svg(f'<g fill="none" stroke="{c}" stroke-width="2.4" stroke-linejoin="round" stroke-linecap="round"><path d="M5 5h10l12 12-10 10L5 15z"/></g><circle cx="11" cy="11" r="1.8" fill="{c}"/>')
files = {'wifi.svg': wifi(B), 'wifi_disabled.svg': wifi(G),
         'signal-000-000.svg': bars(0), 'signal-000-025.svg': bars(1), 'signal-025-050.svg': bars(2), 'signal-050-075.svg': bars(3), 'signal-075-100.svg': bars(4), 'signal-none.svg': bars(0, True),
         'ethernet.svg': eth(B), 'ethernet_disabled.svg': eth(G), 'port_up.svg': eth(B), 'port_down.svg': eth(G),
         'bridge.svg': bridge(B), 'bridge_disabled.svg': bridge(G), 'alias.svg': alias(B), 'alias_disabled.svg': alias(G)}
os.makedirs(D, exist_ok=True)
for n, v in files.items(): open(os.path.join(D, n), 'w').write(v)
