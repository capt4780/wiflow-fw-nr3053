#!/usr/bin/env python3
"""The guest page UI (css, html, head and tail scripts) is shared by the three
templates. Edit it in template-image.html, then run this to copy the regions to
template-video.html and template-website.html.  Usage: tools/sync-portal-ui.py <dir>"""
import re, sys
d = sys.argv[1].rstrip('/')
src = open(f'{d}/template-image.html', encoding='utf-8').read()
REG = [(r'/\*@ui-css\*/.*?/\*@/ui-css\*/', 'css'), (r'<!--@ui-html-->.*?<!--@/ui-html-->', 'html'),
       (r'/\*@ui-head\*/.*?/\*@/ui-head\*/', 'head'), (r'/\*@ui-tail\*/.*(?=</script>)', 'tail')]
for t in ('video', 'website'):
    f = f'{d}/template-{t}.html'
    s = open(f, encoding='utf-8').read()
    for rx, name in REG:
        a = re.search(rx, src, re.S); b = re.search(rx, s, re.S)
        assert a and b, (t, name)
        s = s[:b.start()] + a.group(0) + s[b.end():]
    open(f, 'w', encoding='utf-8').write(s)
print('synced')
