# Wiflow auto fair-share controller (reads one ping reply per second on stdin).
# Latency-driven: when the Internet queue grows, the guest rate is cut; when the
# link is busy and the delay is low, it grows again. Guests share it equally.
# -v BR= -v IFB= -v TC= -v GCMD= -v SYS= -v MAXDN= -v MAXUP= -v START_DN= -v START_UP= -v STATUS= -v SIM=
function rd(f,  v){ v = 0; if ((getline v < f) > 0) { } close(f); return v + 0 }
function tcb(s){ buf = buf s "\n" }
function flush(  rc){
	if (buf == "") return 0
	print buf | CMD; rc = close(CMD); buf = ""
	return rc
}
function hx(n){ return sprintf("%x", n) }
function cid(k){ return hx(k + 16) }
function dev(d){ return d == 1 ? BR : IFB }
function hdr(d){ return "dev " dev(d) }
function mx(d){ return d == 1 ? MAXDN + 0 : MAXUP + 0 }
function ceilof(d,  c){ c = R[d]; if (mx(d) > 0 && mx(d) < c) c = mx(d); return int(c) }
function rateof(d,  r, c){ r = int(R[d] / (N > 0 ? N : 1)); if (r < 100) r = 100; c = ceilof(d); if (r > c) r = c; return r }
function setup(  d){
	for (d = 1; d <= 2; d++) {
		tcb("qdisc replace " hdr(d) " root handle 1: htb default fff r2q 10")
		tcb("class replace " hdr(d) " parent 1: classid 1:1 htb rate " int(R[d]) "kbit ceil " int(R[d]) "kbit")
		tcb("class replace " hdr(d) " parent 1:1 classid 1:fff htb rate 1000mbit ceil 1000mbit")
		tcb("qdisc replace " hdr(d) " parent 1:fff fq_codel")
		tcb("filter replace " hdr(d) " parent 1: protocol ip prio 1 handle 2: u32 divisor 256")
		tcb("filter replace " hdr(d) " parent 1: protocol ip prio 1 u32 ht 800:: match ip " (d == 1 ? "dst" : "src") " 10.10.10.0/24 hashkey mask 0x000000ff at " (d == 1 ? 16 : 12) " link 2:")
	}
	tcb("qdisc replace dev " BR " handle ffff: ingress")
	tcb("filter replace dev " BR " parent ffff: protocol ip prio 1 u32 match u32 0 0 action mirred egress redirect dev " IFB)
	return flush()
}
function gadd(k,  d){
	for (d = 1; d <= 2; d++) {
		tcb("class add " hdr(d) " parent 1:1 classid 1:" cid(k) " htb rate " rateof(d) "kbit ceil " ceilof(d) "kbit quantum 3000")
		tcb("qdisc add " hdr(d) " parent 1:" cid(k) " fq_codel limit 512")
		tcb("filter add " hdr(d) " parent 1: protocol ip prio 1 u32 ht 2:" hx(k) ": match ip " (d == 1 ? "dst" : "src") " 10.10.10." k " flowid 1:" cid(k))
	}
}
function gdel(k,  d){
	for (d = 1; d <= 2; d++) {
		tcb("filter del " hdr(d) " parent 1: protocol ip prio 1 handle 2:" hx(k) ":800 u32")
		tcb("class del " hdr(d) " classid 1:" cid(k))
	}
}
function gchg(  d, k){
	for (d = 1; d <= 2; d++) {
		tcb("class change " hdr(d) " parent 1: classid 1:1 htb rate " int(R[d]) "kbit ceil " int(R[d]) "kbit")
		for (k in cur) tcb("class change " hdr(d) " parent 1:1 classid 1:" cid(k) " htb rate " rateof(d) "kbit ceil " ceilof(d) "kbit quantum 3000")
		AP[d] = R[d]
	}
}
function sync(  ip, o, k, dels, nd, i, ch){
	delete seen
	if (SIM == "") { while ((GCMD | getline ip) > 0) if (ip ~ /^10\.10\.10\.[0-9]+$/) { split(ip, o, "."); if (o[4] + 0 > 0 && o[4] + 0 < 255) seen[o[4] + 0] = 1 }; close(GCMD) }
	ch = 0; nd = 0
	for (k in cur) if (!(k in seen)) dels[++nd] = k
	for (i = 1; i <= nd; i++) { gdel(dels[i]); delete cur[dels[i]]; N--; ch = 1 }
	for (k in seen) if (!(k in cur)) { cur[k] = 1; N++; gadd(k); ch = 1 }
	return ch
}
# One control step for direction d (1 = download, 2 = upload).
function ctl(d, rtt, load, t,  util, delay, b, nb, i, newr, fast, surplus){
	delay = rtt - base
	hist[d] = substr(hist[d] "" (delay > THR ? "1" : "0"), length(hist[d] "" (delay > THR ? "1" : "0")) - WIN + 1)
	nb = gsub(/1/, "1", hist[d])
	util = R[d] > 0 ? load / R[d] : 0
	if (nb >= NEED) {
		if (util > 0.3 && (t - lastcut[d] >= GAP || delay > 3 * THR)) {
			newr = R[d] * CUT; if (load * CUTLOAD < newr) newr = load * CUTLOAD
			if (newr < RMIN) newr = RMIN
			R[d] = newr; lastcut[d] = t; hold[d] = HOLD; quiet[d] = 0; hist[d] = ""
		}
	} else {
		quiet[d]++
		if (quiet[d] >= 10 && util > 0.6 && R[d] > peak[d]) peak[d] = R[d]
		peak[d] *= PDEC
		if (hold[d] > 0) hold[d]--
		else if (util > UTIL) {
			fast = (peak[d] == 0 || R[d] < FASTB * peak[d])
			R[d] = R[d] * (1 + (fast ? UPF : UP)) + UPABS
			if (R[d] > RMAX) R[d] = RMAX
		}
	}
}
function status(  s){
	s = sprintf("%d %d %d %d %d %.0f %.0f %d %s", T, int(R[1]), int(R[2]), int(L[1]), int(L[2]), rtt, base, N, state)
	if (STATUS != "") { print s > STATUS; close(STATUS) } else { print s; fflush() }
}
BEGIN {
	CMD = TC " -batch -"; THR = 15; WIN = 4; NEED = 2; CUT = 0.90; CUTLOAD = 0.95; HOLD = 6; GAP = 2
	UTIL = 0.75; UP = 0.03; UPF = 0.06; FASTB = 0.85; PDEC = 0.998; UPABS = 500; RMIN = 2000; RMAX = 1000000
	R[1] = START_DN + 0 > 0 ? START_DN + 0 : 20000; R[2] = START_UP + 0 > 0 ? START_UP + 0 : 20000
	AP[1] = R[1]; AP[2] = R[2]; N = 0; T = 0; state = "learning"; base = 0; fails = 0; empty = 0
	for (i = 0; i < 60; i++) bk[i] = 1e9
	curmin = 1e9; if (SIM == "") { prev_t = rd("/proc/uptime"); pb1 = rd(SYS "/tx_bytes"); pb2 = rd(SYS "/rx_bytes") }
	if (SIM == "" && setup() != 0) { print "wiflow-shaper: tc setup failed" > "/dev/stderr"; exit 3 }
}
{
	if (SIM != "") { rtt = $1 + 0; L[1] = $2 + 0; L[2] = $3 + 0 }
	else {
		if ($0 !~ /time=/) next
		sub(/.*time=/, ""); rtt = $1 + 0
		t = rd("/proc/uptime"); b1 = rd(SYS "/tx_bytes"); b2 = rd(SYS "/rx_bytes"); dt = t - prev_t
		if (dt < 0.2) dt = 0.2
		L[1] = (b1 - pb1) * 8 / 1000 / dt; L[2] = (b2 - pb2) * 8 / 1000 / dt
		if (L[1] < 0) L[1] = 0; if (L[2] < 0) L[2] = 0
		prev_t = t; pb1 = b1; pb2 = b2
	}
	T++
	if (rtt < curmin) curmin = rtt
	if (T % 10 == 0) { bk[bi] = curmin; bi = (bi + 1) % 60; curmin = 1e9 }
	base = curmin; for (i = 0; i < 60; i++) if (bk[i] < base) base = bk[i]
	if (T > 30) { ctl(1, rtt, L[1], T); ctl(2, rtt, L[2], T); state = "on" }
	if (SIM == "") {
		ch = 0
		if (T % 10 == 1) ch = sync()
		for (d = 1; d <= 2; d++) { diff = R[d] - AP[d]; if (diff < 0) diff = -diff; if (AP[d] > 0 && diff / AP[d] >= 0.02) ch = 1 }
		if (ch) { if (N > 0) gchg(); rc = flush(); if (rc != 0) fails++; else fails = 0; if (fails >= 5) { print "wiflow-shaper: tc update failed" > "/dev/stderr"; state = "error"; status(); exit 3 } }
		if (N == 0) empty++; else empty = 0
		if (empty >= 120) { state = "idle"; status(); exit 0 }
	}
	status()
}
