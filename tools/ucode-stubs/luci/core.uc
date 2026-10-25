export function hash(s, h) { let x = h ?? 5381; for (let i = 0; i < length(`${s}`); i++) x = ((x * 33) + ord(`${s}`, i)) & 0x7fffffff; return x; };
export function load_catalog() { return true; };
export function change_catalog() { return true; };
export function translate(s) { return s; };
export function ntranslate(n, s, p) { return n == 1 ? s : p; };
export function getuid() { return 0; };
export function getspnam(u) { return { pwdp: '$1$x$y' }; };export function get_translations(cb) { return true; };
