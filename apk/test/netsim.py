#!/usr/bin/env python3
"""Network simulator for the Wiflow test bench (runs inside the test netns).

Rebuilds the router's uplink state from the uci configs plus a mock world:
  /tmp/mock/world.json  { "wan_cable": bool, "inet": {"wan": bool, "apcli0": bool, ...},
                          "aps": [ {ssid,bssid,band,channel,signal,enc,key,subnet} ],
                          "clients": {"ra0": [macs], "rax0": [macs]} }
Writes /tmp/mock/net.json (netifd interface status) and /tmp/mock/iw.json
(station info) and sets real addresses / routes on the veth devices.
"""
import json, subprocess, os, sys

UCI = os.environ.get('PFX', '/opt/pfx') + '/bin/uci'
W = '/tmp/mock/world.json'

def uci(path):
    r = subprocess.run([UCI, '-q', 'get', path], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None

def sh(*a):
    subprocess.run(list(a), capture_output=True)

def flush(dev):
    sh('ip', 'addr', 'flush', 'dev', dev)
    sh('ip', 'route', 'flush', 'dev', dev)

def up_iface(dev, ip, gw, metric):
    flush(dev)
    sh('ip', 'addr', 'add', ip + '/24', 'dev', dev)
    sh('ip', 'route', 'add', 'default', 'via', gw, 'dev', dev, 'metric', str(metric))

def main():
    world = json.load(open(W))
    net = {}
    iw = {}

    # cable WAN
    wan_dis = uci('network.wan.disabled') == '1'
    if world.get('wan_cable') and not wan_dis:
        m = int(uci('network.wan.metric') or 0)
        up_iface('wan', '192.168.1.10', '192.168.1.1', m)
        net['wan'] = {'up': True, 'device': 'wan', 'l3_device': 'wan',
                      'ipv4-address': [{'address': '192.168.1.10', 'mask': 24}],
                      'route': [{'target': '0.0.0.0', 'mask': 0, 'nexthop': '192.168.1.1'}]}
    else:
        flush('wan')
        net['wan'] = {'up': False, 'device': 'wan', 'ipv4-address': [], 'route': []}

    # source WiFi station
    radio = uci('wireless.wiflow_uplink.device')
    sta = 'apclix0' if radio == 'MT7981_1_2' else 'apcli0'
    for s in ('apcli0', 'apclix0'):
        iw[s] = {'ssid': None, 'bssid': None}
        flush(s)
    net['wiflow_wwan'] = {'up': False, 'device': sta, 'ipv4-address': [], 'route': []}
    if radio and uci('wireless.wiflow_uplink.disabled') != '1' and uci('wireless.wiflow_uplink.mode') == 'sta':
        ssid = uci('wireless.wiflow_uplink.ssid')
        key = uci('wireless.wiflow_uplink.key') or ''
        enc = uci('wireless.wiflow_uplink.encryption') or 'none'
        band = '5g' if radio == 'MT7981_1_2' else '2g'
        ap = next((a for a in world['aps'] if a['ssid'] == ssid and a['band'] == band), None)
        ok = ap is not None and (ap['enc'] == 'none' or ap.get('key') == key) and ((ap['enc'] == 'none') == (enc == 'none'))
        if ok:
            iw[sta] = {'ssid': ssid, 'bssid': ap['bssid'], 'signal': ap['signal'], 'channel': ap['channel']}
            if not ap.get('no_dhcp'):
                sub = ap.get('subnet', '192.168.31')
                m = int(uci('network.wiflow_wwan.metric') or 0)
                up_iface(sta, sub + '.124', sub + '.1', m)
                net['wiflow_wwan'] = {'up': True, 'device': sta, 'l3_device': sta,
                                      'ipv4-address': [{'address': sub + '.124', 'mask': 24}],
                                      'route': [{'target': '0.0.0.0', 'mask': 0, 'nexthop': sub + '.1'}]}
            else:
                flush(sta)
        else:
            flush(sta)

    net['lan'] = {'up': True, 'device': 'br-lan', 'l3_device': 'br-lan',
                  'ipv4-address': [{'address': '10.0.0.1', 'mask': 24}], 'route': []}
    net['wiflow_guest'] = {'up': uci('network.wiflow_guest') == 'interface', 'device': 'br-wiflow',
                           'ipv4-address': [{'address': '10.10.10.1', 'mask': 24}], 'route': []}
    json.dump(net, open('/tmp/mock/net.json.tmp', 'w'))
    os.replace('/tmp/mock/net.json.tmp', '/tmp/mock/net.json')
    json.dump(iw, open('/tmp/mock/iw.json.tmp', 'w'))
    os.replace('/tmp/mock/iw.json.tmp', '/tmp/mock/iw.json')
    with open('/tmp/mock/calls.log', 'a') as f:
        f.write('netsim %s\n' % ' '.join(sys.argv[1:]))

main()
