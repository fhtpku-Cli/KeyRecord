#!/bin/bash
set -euo pipefail
export LC_ALL=C

if [[ $# -ne 1 || ! -f "$1" || -L "$1" ]]; then
    printf '%s\n' '{"status":"FAIL","reason":"expected one regular Mach-O executable"}'
    exit 1
fi
binary=$1
if ! /usr/bin/file -b "$binary" | /usr/bin/grep -q 'Mach-O.*executable'; then
    printf '%s\n' '{"status":"FAIL","reason":"not a Mach-O executable"}'
    exit 1
fi
scratch=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/keyrecord-network-audit.XXXXXX")
trap '/bin/rm -rf "$scratch"' EXIT
/usr/bin/nm -u -arch all "$binary" > "$scratch/nm"
/usr/bin/strings -a "$binary" > "$scratch/strings"
[[ -s "$scratch/nm" && -s "$scratch/strings" ]] || {
    printf '%s\n' '{"status":"FAIL","reason":"empty audit input"}'
    exit 1
}

# Match both imported symbols and strings used by dynamic Objective-C/network lookups.
pattern='URLSession|NSURLSession|URLRequest|NSURLRequest|NSURLConnection|CFNetwork|CFHTTP|CF(Read|Write)Stream(Create|Open|Set)|NWConnection|NWListener|NWPathMonitor|(^|[^[:alnum:]])nw_[[:alnum:]_]+|(^|[[:space:]])_?(socket|socketpair|connect|connectx|connectat|sendto|sendmsg|getaddrinfo|res_query|curl_[[:alnum:]_]+|SSL_connect|posix_spawn[p]?|execve|execvp|execl|popen|system)([[:space:]]|$)|https?://|/bin/(sh|bash|zsh)'
if /usr/bin/grep -Ein "$pattern" "$scratch/nm" "$scratch/strings"; then
    printf '%s\n' '{"status":"FAIL","reason":"network or shell capability reference","liveReceipt":false}'
    exit 1
fi
digest=$(/usr/bin/shasum -a 256 "$binary" | /usr/bin/cut -d ' ' -f 1)
symbols=$(/usr/bin/wc -l < "$scratch/nm" | /usr/bin/tr -d ' ')
strings=$(/usr/bin/wc -l < "$scratch/strings" | /usr/bin/tr -d ' ')
printf '{"status":"PASS","kind":"static-product-network-audit","sha256":"%s","undefinedSymbolLines":%s,"stringLines":%s,"matches":0,"liveReceipt":false}\n' "$digest" "$symbols" "$strings"
