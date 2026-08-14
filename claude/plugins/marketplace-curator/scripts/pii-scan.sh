#!/usr/bin/env bash
# pii-scan.sh — canonical PII / private-content scanner for this marketplace.
#
# This script is the single source of truth for detection patterns. Prose
# (references/pii-policy.md, the check-pii and onboard-to-marketplace skills)
# documents the contract but never re-implements a pattern. Invoke the script.
#
# Contract (CLI, output protocol, tiers, suppression rules, exit codes):
#   claude/plugins/marketplace-curator/references/pii-policy.md
#
# Self-immunity: pattern literals below wrap one character in a bracket group,
# which leaves the matched language unchanged while keeping this source text
# out of its own match set. Host literals keep their dots escaped for the same
# reason. Do not "simplify" those away — the scanner scans its own repo.

set -euo pipefail

SELF_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
BATCH=200
NL='
'

# ---------------------------------------------------------------------------
# Patterns
# ---------------------------------------------------------------------------

SQ=\'
# Path body: everything up to the next whitespace, quote or backtick.
PCH="[^[:space:]\"${SQ}\`]"
# URL body: as above, plus Markdown/HTML delimiters that never belong to a URL.
UCH="[^[:space:]\"${SQ}\`<>)]"

RE_EMAIL='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,24}'

RE_PATH="(/[U]sers/|/[h]ome/)${PCH}+|[A-Za-z]:\\\\[Uu]sers\\\\${PCH}+|-[U]sers-[A-Za-z0-9._-]+|~/(Developer|Documents|Desktop|Downloads|Projects)/${PCH}*|%USER[P]ROFILE%|/var/[f]olders/${PCH}+"

OCTET='(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])'
RE_IPV4="\\b${OCTET}\\.${OCTET}\\.${OCTET}\\.${OCTET}\\b"
RE_IPV6='[0-9A-Fa-f:]*::[0-9A-Fa-f:]*'

RE_SECRET='sk-ant-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{32,}|(AKIA|ASIA)[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{22,}|glpat-[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{35}|eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}|npm_[A-Za-z0-9]{36}|-----BEGIN [A-Z ]*PRIVATE KEY-----'

# E.164-ish: 1-3 digit country code, then a separator, then the subscriber
# number. The mandatory separator is what keeps '+'-prefixed ISO dates and bare
# numeric ids (routine in diff snippets and changelogs) out of the phone tier.
RE_PHONE='\+[0-9]{1,3}[ ().-][0-9 ().-]{4,}[0-9]'
RE_IBAN='\b[A-Z]{2}[0-9]{2}[A-Za-z0-9]{11,30}\b'
RE_TICKET='\b[A-Z]{2,6}-[0-9]{1,6}\b'
RE_NAME_BIGRAM='[A-Z][a-z]{2,}[-_ ][A-Z][a-z]{2,}'

# Known private hosts. Dots stay escaped: the list doubles as the ERE
# alternation and as the (unescaped at runtime) suffix-match table.
PRIVATE_HOSTS='
notion\.so
notion\.site
linear\.app
atlassian\.net
slack\.com
asana\.com
monday\.com
airtable\.com
figma\.com
miro\.com
lucid\.app
zendesk\.com
salesforce\.com
hubspot\.com
posthog\.com
sentry\.io
grafana\.net
grafana\.com
datadoghq\.com
datadoghq\.eu
pagerduty\.com
opsgenie\.com
bitbucket\.org
gitlab\.com
azure\.com
azurewebsites\.net
aws\.amazon\.com
googleapis\.com
sharepoint\.com
teams\.microsoft\.com
office\.com
onedrive\.live\.com
docs\.google\.com
drive\.google\.com
zoom\.us
calendly\.com
gist\.github\.com
dropbox\.com
t\.me
'

# Host labels that mean "somebody's internal infrastructure". Only ever
# evaluated against a parsed host, never as a bare substring of prose.
INTERNAL_LABELS='internal intranet corp vpn'

# Final labels that mark a dotted token as a filename or a code identifier
# rather than a host ('docs/internal.md', 'com.example.internal.util',
# 'corp.acme.Service'). Consulted only when no URL scheme anchors the token.
NONHOST_TAILS='md markdown json jsonl yaml yml toml ini cfg conf sh bash zsh fish txt text log lock tmp bak orig sql csv tsv html htm css scss sass js jsx ts tsx mjs cjs py rb go rs php pl java kt swift class impl util utils service services model models config helper helpers factory handler manager provider builder'

# Ticket-shaped tokens that are public technical vocabulary, not project codes.
TICKET_STOPLIST='UTF ISO RFC SHA AES RSA TLS SSL CVE PEP MIT GPL BSD HTTP HTTPS SPDX IPV EN DE'

RE_HOSTTOKEN=''

build_host_regex() {
  local h alt=''
  for h in $PRIVATE_HOSTS; do
    alt="${alt:+$alt|}$h"
  done
  for h in $INTERNAL_LABELS; do
    alt="$alt|$h"
  done
  RE_HOSTTOKEN="(https?://)?(\\*\\.)?[A-Za-z0-9_.-]*(${alt})[A-Za-z0-9_.-]*(/${UCH}*)?"
}

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

SCOPE=''
STAGED=0
AUTO_ONLY=0
SELF_TEST=0

N_FILES=0
N_HIT=0
N_CAND=0
N_SUPP=0
N_MANUAL=0

ALLOWLIST=''
ERRLOG=''
FILELIST_NL=''
SR_FILE=''
SR_LINE=''
SR_FRAG=''

ALL_FILES=()
TEXT_FILES=()
LICENSE_FILES=()

# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------

usage() {
  cat <<'USAGE'
usage: pii-scan.sh [--scope <path>] [--staged] [--auto-only] [--self-test]

  --scope <path>  restrict the scan to a path inside the repo
  --staged        scan the staged file set instead of the working tree
  --auto-only     emit HIT records only, skip the CAND (borderline) tier
  --self-test     run the built-in regression suite against synthetic fixtures

exit codes: 0 = no HIT, 1 = at least one HIT, 2 = scan error
USAGE
}

die() {
  echo "pii-scan: ERROR: $*" >&2
  if [ -n "$ERRLOG" ] && [ -s "$ERRLOG" ]; then
    echo "pii-scan: captured stderr:" >&2
    cat "$ERRLOG" >&2
  fi
  exit 2
}

cleanup() {
  [ -n "$ERRLOG" ] && rm -f "$ERRLOG"
  return 0
}

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

sanitize() { printf '%s' "$1" | tr '\t\r' '  '; }

emit() { # tier file line category fragment
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$(sanitize "$5")"
}

info() { printf 'INFO\t%s\t%s\n' "$1" "$(sanitize "$2")"; }

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --scope)
        [ $# -ge 2 ] || die "--scope needs a path argument"
        SCOPE=$2
        shift 2
        ;;
      --scope=*)
        SCOPE=${1#--scope=}
        shift
        ;;
      --staged) STAGED=1; shift ;;
      --auto-only) AUTO_ONLY=1; shift ;;
      --self-test) SELF_TEST=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) usage >&2; die "unknown argument: $1" ;;
    esac
  done
  [ -n "$SCOPE" ] || SCOPE=''
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

preflight() {
  local dep
  for dep in git grep file awk tr sort jq; do
    command -v "$dep" >/dev/null 2>&1 || die "missing dependency: $dep"
  done
  [ -n "${BASH_VERSION:-}" ] || die "missing dependency: bash"
}

# ---------------------------------------------------------------------------
# Allowlist
# ---------------------------------------------------------------------------

allowlist_add() {
  local v
  v=$(lower "$1")
  [ -n "$v" ] || return 0
  ALLOWLIST="${ALLOWLIST}${NL}${v}"
}

allowlist_has() { # $1 = token (case-insensitive whole-token match)
  local t
  t=$(lower "$1")
  [ -n "$t" ] || return 1
  case "$ALLOWLIST" in *"${NL}${t}${NL}"*) return 0 ;; esac
  return 1
}

allowlist_has_domain() { # $1 = lowercased domain
  local d=$1 second
  allowlist_has "$d" && return 0
  # second-level label, e.g. agentic in agentic.tld
  second=${d%.*}
  second=${second##*.}
  [ -n "$second" ] && allowlist_has "$second" && return 0
  return 1
}

allowlist_has_bigram() { # $1 = "First-Last" style token — the whole name or a half
  local f=$1 joined
  joined=$(printf '%s' "$f" | tr '_-' '  ')
  allowlist_has "$joined" && return 0
  allowlist_has "${f%%[-_ ]*}" && return 0
  allowlist_has "${f##*[-_ ]}" && return 0
  return 1
}

path_user_of() { # $1 = path fragment -> its user-directory component, if any
  local p rest
  # Backslashes folded to '/' so the Windows form shares one parser. The
  # bracket groups keep these literals out of the scanner's own path pattern.
  p=$(printf '%s' "$1" | tr '\\' '/')
  case "$p" in
    /[U]sers/*|/[h]ome/*)
      rest=${p#/}
      rest=${rest#*/}
      printf '%s' "${rest%%/*}"
      return 0
      ;;
    [A-Za-z]:/[Uu]sers/*)
      rest=${p#*:/}
      rest=${rest#*/}
      printf '%s' "${rest%%/*}"
      return 0
      ;;
    -[U]sers-*)
      rest=${p#-[U]sers-}
      printf '%s' "${rest%%-*}"
      return 0
      ;;
  esac
  printf ''
}

load_allowlist() {
  ALLOWLIST="$NL"
  local t
  for t in kelzenberg agentic-kelzenberg agentic anthropic claude; do
    allowlist_add "$t"
  done
  allowlist_add 'claude code'

  local manifest='.claude-plugin/marketplace.json'
  if [ ! -f "$manifest" ]; then
    info allowlist-tier2 'marketplace.json absent — tier-2 allowlist empty'
    return 0
  fi
  jq -e . "$manifest" >/dev/null 2>>"$ERRLOG" || die "marketplace.json is not valid JSON"

  local values value re='^[a-z0-9][a-z0-9 _-]{1,38}$'
  values=$(jq -r '[.owner.name, .name] | map(select(type == "string")) | .[]' "$manifest" 2>>"$ERRLOG") || die "cannot read allowlist from $manifest"
  while IFS= read -r value; do
    [ -n "$value" ] || continue
    local low
    low=$(lower "$value")
    if ! [[ $low =~ $re ]]; then
      die "allowlist value from $manifest is not a handle: '$value' (use a handle, never a legal name)"
    fi
    if [[ $value =~ $RE_EMAIL ]]; then
      die "allowlist value from $manifest looks like an email address: '$value'"
    fi
    allowlist_add "$value"
  done <<EOF
$values
EOF
  info allowlist-tier2 "$(printf '%s' "$values" | tr '\n' ' ')"
}

# ---------------------------------------------------------------------------
# Host helpers
# ---------------------------------------------------------------------------

host_of_fragment() { # $1 = raw fragment -> lowercased host
  local h=$1
  h=${h#\*.}
  h=${h#*://}
  h=${h%%/*}
  h=${h%%\?*}
  h=${h#*@}
  h=${h%%:*}
  h=${h%.}
  lower "$h"
}

host_is_listed_exact() { # $1 = host — equals a listed host, no suffix match
  local h p
  h=$(lower "$1")
  for p in $PRIVATE_HOSTS; do
    [ "$h" = "${p//\\/}" ] && return 0
  done
  return 1
}

host_matches_private() { # $1 = lowercased host
  local h=$1 p plain
  for p in $PRIVATE_HOSTS; do
    plain=${p//\\/}
    [ "$h" = "$plain" ] && return 0
    case "$h" in *".$plain") return 0 ;; esac
  done
  return 1
}

host_is_internal() { # $1 = lowercased host, $2 = 1 when a URL scheme anchored it
  local h=$1 anchored=${2:-0} last rest lbl l
  case "$h" in *..*|.*|*.|*[!a-z0-9.-]*) return 1 ;; esac
  case "$h" in *.*) ;; *) return 1 ;; esac
  last=${h##*.}
  for lbl in $INTERNAL_LABELS; do
    [ "$last" = "$lbl" ] && [ "$lbl" != vpn ] && return 0
  done
  # Host context is required before an internal label counts: without a scheme
  # the token is only a candidate host, so its final label must be able to be a
  # TLD and must not be a file extension or a code-identifier tail.
  if [ "$anchored" != 1 ]; then
    [[ $last =~ ^[a-z]{2,24}$ ]] || return 1
    for l in $NONHOST_TAILS; do
      [ "$last" = "$l" ] && return 1
    done
  fi
  rest=$h
  while [ -n "$rest" ]; do
    lbl=${rest%%.*}
    for l in $INTERNAL_LABELS; do
      [ "$lbl" = "$l" ] && return 0
    done
    case "$rest" in *.*) rest=${rest#*.} ;; *) rest='' ;; esac
  done
  return 1
}

host_is_public() { # $1 = lowercased host — public docs / public code hosting
  local h=$1
  # gist URLs are per-person pastes, never "public docs": keep them private.
  case "$h" in gist.[g]ithub.com|*.gist.[g]ithub.com) return 1 ;; esac
  case "$h" in
    github.com|*.github.com) return 0 ;;
    claude.com|*.claude.com) return 0 ;;
    anthropic.com|*.anthropic.com) return 0 ;;
  esac
  return 1
}

is_rfc2606_host() { # $1 = lowercased host or email domain
  local h=$1
  case "$h" in
    example.com|*.example.com|example.org|*.example.org|example.net|*.example.net) return 0 ;;
    example|*.example|*.invalid|*.test|*.localhost|localhost|invalid|test) return 0 ;;
  esac
  return 1
}

ip_is_private() { # $1 = dotted quad
  case "$1" in
    10.*|127.*|192.168.*|169.254.*|0.0.0.[0]) return 0 ;;
    172.1[6-9].*|172.2[0-9].*|172.3[01].*) return 0 ;;
  esac
  return 1
}

count_chars() { # $1 = string, $2 = tr keep-set — length of what survives
  local kept
  kept=$(printf '%s' "$1" | tr -cd "$2")
  printf '%s' "${#kept}"
}

count_digits() { count_chars "$1" '0-9'; }

# ---------------------------------------------------------------------------
# Suppression rules
# ---------------------------------------------------------------------------

is_placeholder_fragment() { # rule 1 — the fragment ITSELF is a placeholder
  local f=$1
  local re_ph='^[<][a-zA-Z0-9._ -]+[>]$'
  local re_glob='^[*]\.[a-zA-Z0-9.-]+$'
  [[ $f =~ $re_ph ]] && return 0
  [[ $f =~ $re_glob ]] && return 0
  [ "$f" = '/...' ] && return 0
  return 1
}

line_has_marker() { # rule 2 — a pii-ok marker in comment position on that line
  local file=$1 line=$2 txt
  local re_html='<!--[[:space:]]*pii-ok:[^>]*-->'
  local re_hash='#[[:space:]]*pii-ok:'
  [ "$line" = '-' ] && return 1
  [ -f "$file" ] || return 1
  # JSON has no comment syntax, so a marker there can only be a string value —
  # i.e. attacker- or accident-controlled data. Refuse it: the record stays a
  # HIT. Without this, any data field carrying the text silences the line.
  case "$(lower "${file##*/}")" in *.json|*.jsonl) return 1 ;; esac
  txt=$(awk -v n="$line" 'NR == n { print; exit }' <"$file" 2>/dev/null) || return 1
  [[ $txt =~ $re_html ]] && return 0
  [[ $txt =~ $re_hash ]] && return 0
  return 1
}

# ---------------------------------------------------------------------------
# Record handling
# ---------------------------------------------------------------------------

is_scanned_file() {
  case "$FILELIST_NL" in *"${NL}${1}${NL}"*) return 0 ;; esac
  return 1
}

split_record() { # $1 = "file:line:fragment" -> SR_FILE SR_LINE SR_FRAG
  local rec=$1 cand='' rest=$1 head
  while [[ $rest == *:* ]]; do
    head=${rest%%:*}
    rest=${rest#*:}
    if [ -z "$cand" ]; then cand=$head; else cand="$cand:$head"; fi
    is_scanned_file "$cand" || continue
    [[ $rest == *:* ]] || continue
    head=${rest%%:*}
    case "$head" in
      ''|*[!0-9]*) continue ;;
    esac
    SR_FILE=$cand
    SR_LINE=$head
    SR_FRAG=${rest#*:}
    return 0
  done
  return 1
}

process_record() { # eval-category tier file line fragment [emit-category]
  local cat=$1 tier=$2 file=$3 line=$4 frag=$5
  local emit_cat=${6:-}
  local host domain localpart digits token hostpart t anchored

  # --- classification: is this a finding at all, and in which tier? ---------
  case "$cat" in
    email)
      case "$frag" in *@*) ;; *) return 0 ;; esac
      domain=$(lower "${frag#*@}")
      localpart=${frag%%@*}
      ;;
    host)
      host=$(host_of_fragment "$frag")
      [ -n "$host" ] || return 0
      case "$frag" in *://*) anchored=1 ;; *) anchored=0 ;; esac
      if ! host_matches_private "$host" && ! host_is_internal "$host" "$anchored"; then
        return 0
      fi
      ;;
    ipv4)
      if ip_is_private "$frag"; then
        cat=ip-private
        tier=HIT
      else
        cat=ip
        tier=CAND
      fi
      ;;
    ipv6)
      case "$frag" in *::*) ;; *) return 0 ;; esac
      digits=$(count_chars "$frag" '0-9A-Fa-f')
      [ "$digits" -ge 3 ] || return 0
      cat=ip
      ;;
    phone)
      # A '+'-prefixed ISO date in a diff hunk or a changelog is not a number.
      case "$frag" in
        +[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]*) return 0 ;;
      esac
      digits=$(count_digits "$frag")
      { [ "$digits" -ge 8 ] && [ "$digits" -le 15 ]; } || return 0
      ;;
    iban)
      digits=$(count_digits "$frag")
      [ "$digits" -ge 6 ] || return 0
      ;;
    ticket)
      token=${frag%%-*}
      for t in $TICKET_STOPLIST; do
        [ "$token" = "$t" ] && return 0
      done
      ;;
  esac

  [ "$AUTO_ONLY" -eq 1 ] && [ "$tier" = CAND ] && return 0

  # --- rule 1: fragment-scoped placeholder / reserved-example filter -------
  case "$cat" in
    host)
      hostpart=${frag%%/*}
      case "$hostpart" in
        '*.'*)
          # A wildcard over a whole registrable domain is a host family and
          # names nobody, so it drops; a wildcard over a subdomain still names
          # the tenant in that subdomain label, so it stays a HIT.
          host_is_listed_exact "${hostpart#\*.}" && return 0
          ;;
        *) is_placeholder_fragment "$hostpart" && return 0 ;;
      esac
      is_rfc2606_host "$host" && return 0
      ;;
    email)
      is_placeholder_fragment "$frag" && return 0
      is_rfc2606_host "$domain" && return 0
      ;;
    *)
      is_placeholder_fragment "$frag" && return 0
      ;;
  esac

  # --- rule 2: line marker -------------------------------------------------
  if line_has_marker "$file" "$line"; then
    emit SUPPRESSED "$file" "$line" "${emit_cat:-$cat}" "$frag"
    N_SUPP=$((N_SUPP + 1))
    return 0
  fi

  # --- rule 3: allowlist (identifying component only, never substring) -----
  # Every category is routed here. The ones with no person- or org-identifying
  # component (secret, ip, ip-private, phone, iban, ticket) fall through by
  # design: no allowlist literal can clear a credential or an address.
  case "$cat" in
    email)
      if [ "$domain" = 'users.noreply.github.com' ]; then
        allowlist_has "${localpart##*+}" && return 0
      fi
      allowlist_has_domain "$domain" && return 0
      ;;
    host)
      allowlist_has_domain "$host" && return 0
      ;;
    name)
      allowlist_has_bigram "$frag" && return 0
      ;;
    path)
      allowlist_has "$(path_user_of "$frag")" && return 0
      ;;
  esac

  # --- rule 4: public-URL allowance ---------------------------------------
  case "$cat" in
    host) host_is_public "$host" && return 0 ;;
  esac

  emit "$tier" "$file" "$line" "${emit_cat:-$cat}" "$frag"
  case "$tier" in
    HIT) N_HIT=$((N_HIT + 1)) ;;
    CAND) N_CAND=$((N_CAND + 1)) ;;
  esac
  return 0
}

# ---------------------------------------------------------------------------
# Enumeration
# ---------------------------------------------------------------------------

enumerate() {
  if [ "$STAGED" -eq 1 ]; then
    if [ -n "$SCOPE" ]; then
      git diff --cached --name-only -z --diff-filter=ACMR -- "$SCOPE"
    else
      git diff --cached --name-only -z --diff-filter=ACMR
    fi
  else
    if [ -n "$SCOPE" ]; then
      git ls-files -z --cached --others --exclude-standard -- "$SCOPE"
    else
      git ls-files -z --cached --others --exclude-standard
    fi
  fi
}

count_untracked() {
  local n=0 f
  [ "$STAGED" -eq 1 ] && { printf '0'; return 0; }
  while IFS= read -r -d '' f; do
    n=$((n + 1))
  done < <(if [ -n "$SCOPE" ]; then
             git ls-files -z --others --exclude-standard -- "$SCOPE"
           else
             git ls-files -z --others --exclude-standard
           fi)
  printf '%s' "$n"
}

is_license_path() {
  case "${1##*/}" in LICENSE|LICENSE.*|LICENCE|LICENCE.*) return 0 ;; esac
  return 1
}

has_binary_extension() {
  case "$(lower "${1##*/}")" in
    *.png|*.jpg|*.jpeg|*.gif|*.webp|*.pdf|*.zip|*.ico|*.woff|*.woff2|*.ttf|*.eot|*.mp3|*.mp4|*.mov)
      return 0 ;;
  esac
  return 1
}

mime_of() { file -b --mime-type "./$1" 2>/dev/null || printf 'unknown'; }

is_textual_mime() {
  case "$1" in
    text/*) return 0 ;;
    application/json|application/xml|application/javascript|application/x-javascript) return 0 ;;
    application/x-shellscript|application/x-sh|application/x-yaml|application/yaml|application/toml) return 0 ;;
    application/x-empty|inode/x-empty) return 0 ;;
  esac
  return 1
}

collect_files() {
  local f missing=0
  # Leading separator: membership tests below match "${NL}name${NL}", so the
  # index must open with one or the first file is never recognized.
  FILELIST_NL="$NL"
  while IFS= read -r -d '' f; do
    [ -n "$f" ] || continue
    case "$FILELIST_NL" in *"${NL}${f}${NL}"*) continue ;; esac
    if [ ! -f "$f" ]; then
      missing=$((missing + 1))
      continue
    fi
    FILELIST_NL="${FILELIST_NL}${f}${NL}"
    ALL_FILES[${#ALL_FILES[@]}]=$f
  done < <(enumerate)
  [ "$missing" -gt 0 ] && info missing-in-worktree "$missing"
  return 0
}

partition_files() {
  local f mime
  for f in "${ALL_FILES[@]}"; do
    if is_license_path "$f"; then
      LICENSE_FILES[${#LICENSE_FILES[@]}]=$f
      continue
    fi
    case "$f" in
      *"$NL"*|*"	"*)
        emit MANUAL "$(sanitize "$f")" '-' unreadable 'filename-contains-control-character'
        N_MANUAL=$((N_MANUAL + 1))
        continue
        ;;
    esac
    if has_binary_extension "$f"; then
      emit MANUAL "$f" '-' binary "$(mime_of "$f")"
      N_MANUAL=$((N_MANUAL + 1))
      continue
    fi
    mime=$(mime_of "$f")
    if ! is_textual_mime "$mime"; then
      emit MANUAL "$f" '-' binary "$mime"
      N_MANUAL=$((N_MANUAL + 1))
      continue
    fi
    if [ -s "$f" ] && ! LC_ALL=C grep -Iq '' -- "$f" 2>/dev/null; then
      emit MANUAL "$f" '-' binary "$mime"
      N_MANUAL=$((N_MANUAL + 1))
      continue
    fi
    TEXT_FILES[${#TEXT_FILES[@]}]=$f
    # The semantic pass in check-pii derives its read set from these records:
    # findings alone would name only the files that already failed.
    printf 'SCANNED\t%s\n' "$f"
  done
  N_FILES=${#TEXT_FILES[@]}
  return 0
}

# ---------------------------------------------------------------------------
# Passes
# ---------------------------------------------------------------------------

grep_pass() { # category tier regex icase
  local cat=$1 tier=$2 re=$3 icase=$4
  local i=0 n=${#TEXT_FILES[@]} out rc rec
  local -a batch
  [ "$n" -gt 0 ] || return 0
  while [ "$i" -lt "$n" ]; do
    batch=("${TEXT_FILES[@]:i:BATCH}")
    i=$((i + BATCH))
    set +e
    if [ "$icase" = 1 ]; then
      out=$(LC_ALL=C grep -IoHnEi -e "$re" -- "${batch[@]}" 2>>"$ERRLOG")
    else
      out=$(LC_ALL=C grep -IoHnE -e "$re" -- "${batch[@]}" 2>>"$ERRLOG")
    fi
    rc=$?
    set -e
    [ "$rc" -ge 2 ] && die "grep exited $rc during the '$cat' pass"
    [ "$rc" -eq 0 ] || continue
    while IFS= read -r rec; do
      [ -n "$rec" ] || continue
      split_record "$rec" || continue
      process_record "$cat" "$tier" "$SR_FILE" "$SR_LINE" "$SR_FRAG"
    done <<EOF
$out
EOF
  done
  return 0
}

filename_pass() {
  local f low
  for f in "${ALL_FILES[@]}"; do
    case "$f" in *"$NL"*) continue ;; esac
    if [[ $f =~ $RE_EMAIL ]]; then
      process_record email HIT "$f" '-' "${BASH_REMATCH[0]}" filename
    fi
    low=$(lower "$f")
    if [[ $low =~ $RE_HOSTTOKEN ]]; then
      process_record host HIT "$f" '-' "${BASH_REMATCH[0]}" filename
    fi
    if [[ $f =~ $RE_PATH ]]; then
      process_record path HIT "$f" '-' "${BASH_REMATCH[0]}" filename
    fi
    # A title-case filename is a borderline signal, not an auto-fail: there is
    # no line to mark, so a HIT here would block the hook and CI until the file
    # were renamed. It is judged in the semantic pass instead.
    if [[ $f =~ $RE_NAME_BIGRAM ]]; then
      process_record name CAND "$f" '-' "${BASH_REMATCH[0]}" filename
    fi
  done
  return 0
}

gitmeta_identity_ok() { # $1 = email
  local e d lp
  e=$(lower "$1")
  case "$e" in *@*) ;; *) return 0 ;; esac
  d=${e#*@}
  # The users.noreply.github.com domain covers both contributor no-reply
  # addresses and the '<app>[bot]' identities GitHub Apps commit under.
  [ "$d" = 'users.noreply.github.com' ] && return 0
  case "$d" in *.users.noreply.github.com) return 0 ;; esac
  # GitHub's own machine identity: the synthetic merge commit on
  # refs/pull/N/merge is authored by GitHub's noreply address at github.com,
  # which a pull_request CI run cannot avoid and a contributor cannot fix.
  # Assembled so this line does not match the scanner's own email pattern.
  [ "$e" = 'noreply@''github.com' ] && return 0
  is_rfc2606_host "$d" && return 0
  allowlist_has_domain "$d" && return 0
  lp=${e%%@*}
  allowlist_has "${lp##*+}" && return 0
  return 1
}

gitmeta_pass() {
  local out rc rec ae ce ref seen="$NL"
  set +e
  out=$(git log --all --format='%ae%n%ce' 2>>"$ERRLOG" | sort -u)
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    info git-meta 'commit history unavailable'
  else
    while IFS= read -r rec; do
      [ -n "$rec" ] || continue
      gitmeta_identity_ok "$rec" && continue
      emit HIT git-history '-' git-meta "$rec"
      N_HIT=$((N_HIT + 1))
    done <<EOF
$out
EOF
  fi

  set +e
  out=$(git for-each-ref --format='%(refname)' 2>>"$ERRLOG")
  rc=$?
  set -e
  [ "$rc" -eq 0 ] || return 0
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    if [[ $ref =~ $RE_EMAIL ]]; then
      emit HIT git-refs '-' git-meta "$ref"
      N_HIT=$((N_HIT + 1))
      continue
    fi
    local lowref
    lowref=$(lower "$ref")
    if [[ $lowref =~ $RE_HOSTTOKEN ]]; then
      local h
      h=$(host_of_fragment "${BASH_REMATCH[0]}")
      if host_matches_private "$h" || host_is_internal "$h"; then
        emit HIT git-refs '-' git-meta "$ref"
        N_HIT=$((N_HIT + 1))
      fi
    fi
  done <<EOF
$out
EOF
  return 0
}

license_pass() {
  local f cl
  for f in "${LICENSE_FILES[@]:-}"; do
    [ -n "$f" ] || continue
    set +e
    cl=$(LC_ALL=C grep -m1 -iE 'copyright' -- "$f" 2>>"$ERRLOG")
    set -e
    info license-copyright "${cl:-no copyright line found in $f}"
  done
  return 0
}

content_passes() {
  grep_pass email HIT "$RE_EMAIL" 0
  grep_pass path HIT "$RE_PATH" 0
  grep_pass host HIT "$RE_HOSTTOKEN" 1
  grep_pass secret HIT "$RE_SECRET" 0
  grep_pass ipv4 HIT "$RE_IPV4" 0
  grep_pass phone HIT "$RE_PHONE" 0
  grep_pass iban HIT "$RE_IBAN" 0
  if [ "$AUTO_ONLY" -eq 0 ]; then
    grep_pass ipv6 CAND "$RE_IPV6" 0
    grep_pass ticket CAND "$RE_TICKET" 0
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Scan
# ---------------------------------------------------------------------------

summarize() {
  local mode scope_label
  if [ "$AUTO_ONLY" -eq 1 ]; then mode='auto-only'; else mode='full'; fi
  scope_label=${SCOPE:-full-tree}
  [ "$STAGED" -eq 1 ] && scope_label="staged:${SCOPE:-all}"
  printf 'SUMMARY\tfiles=%s hits=%s cand=%s suppressed=%s manual=%s mode=%s scope=%s\n' \
    "$N_FILES" "$N_HIT" "$N_CAND" "$N_SUPP" "$N_MANUAL" "$mode" "$scope_label"
}

run_scan() {
  local root abs staged_any

  root=$(git rev-parse --show-toplevel 2>>"$ERRLOG") || die "not inside a git repository"

  if [ -n "$SCOPE" ] && [ -e "$SCOPE" ]; then
    # pwd -P: git reports the physical toplevel, so a logical path picked up
    # through a symlinked parent (/tmp, /var) would never compare equal.
    if [ -d "$SCOPE" ]; then
      abs=$(cd "$SCOPE" && pwd -P)
    else
      abs=$(cd "$(dirname "$SCOPE")" && pwd -P)/$(basename "$SCOPE")
    fi
    case "$abs" in
      # A scope that resolves to the repository root IS a full-tree run: it must
      # keep the full-tree label and the git-history pass, not degrade to a
      # scoped run that silently drops them.
      "$root") SCOPE='' ;;
      "$root"/*) SCOPE=${abs#"$root"/} ;;
    esac
  fi

  cd "$root"

  load_allowlist
  collect_files

  if [ ${#ALL_FILES[@]} -eq 0 ]; then
    if [ "$STAGED" -eq 1 ]; then
      set +e
      staged_any=$(git diff --cached --name-only 2>>"$ERRLOG" | head -n 1)
      set -e
      if [ -n "$staged_any" ]; then
        # Deletions and mode-only changes: the index is not empty, there is
        # simply no content left to read. A normal commit shape, not an error.
        info staged-content none
        summarize
        exit 0
      fi
      die "the staged file set is empty — nothing was scanned"
    fi
    die "scope resolved to zero files: ${SCOPE:-full-tree}"
  fi

  info untracked-count "$(count_untracked)"
  partition_files
  license_pass

  if [ -n "$SCOPE" ] || [ "$STAGED" -eq 1 ]; then
    info git-meta 'skipped (scoped or staged run)'
  fi

  filename_pass
  content_passes
  if [ -z "$SCOPE" ] && [ "$STAGED" -eq 0 ]; then
    gitmeta_pass
  fi

  # Unscannable is not clean: a scope holding only binaries produced no
  # coverage at all, so it must not exit 0 into a hook or a CI job.
  if [ "$N_FILES" -eq 0 ] && [ "$N_MANUAL" -gt 0 ]; then
    emit HIT scan-scope '-' unscannable \
      "no text file was scanned; $N_MANUAL file(s) need manual review"
    N_HIT=$((N_HIT + 1))
  fi

  summarize

  if [ "$N_HIT" -gt 0 ]; then exit 1; fi
  exit 0
}

# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------

ST_PASS=0
ST_FAIL=0
ST_OUT=''
ST_RC=0

st_run() { # dir, args...
  local dir=$1
  shift
  set +e
  # Invoked through bash, not as an executable: a lost +x bit must fail the
  # scan it guards, not every case in this suite.
  ST_OUT=$(cd "$dir" && bash "$SELF_PATH" "$@" 2>/dev/null)
  ST_RC=$?
  set -e
}

st_ok() { printf 'PASS\t%s\n' "$1"; ST_PASS=$((ST_PASS + 1)); }

st_no() {
  printf 'FAIL\t%s\n' "$1"
  [ $# -gt 1 ] && printf '     \texpected: %s\n' "$2"
  ST_FAIL=$((ST_FAIL + 1))
}

st_expect() { # description, ERE that must match the captured output
  if printf '%s\n' "$ST_OUT" | LC_ALL=C grep -qE "$2"; then st_ok "$1"; else st_no "$1" "$2"; fi
}

st_expect_absent() { # description, ERE that must NOT match
  if printf '%s\n' "$ST_OUT" | LC_ALL=C grep -qE "$2"; then st_no "$1" "absent: $2"; else st_ok "$1"; fi
}

st_expect_rc() { # description, expected exit code
  if [ "$ST_RC" = "$2" ]; then st_ok "$1"; else st_no "$1" "exit $2, got $ST_RC"; fi
}

st_repo() { # $1 = directory — init a fixture repo with no inherited excludes
  local at='@'
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" config core.excludesFile /dev/null
  # A committer identity the fixtures can use; reserved domain, never a finding.
  git -C "$1" config user.name kelzenberg
  git -C "$1" config user.email "ci${at}example.com"
  git -C "$1" config commit.gpgsign false
}

# Fixture text is assembled at runtime (printf "%s" for the @, the backslash,
# the dot) so that the literal PII shapes never appear in this file — the
# scanner scans its own repository, including this script.
st_build_leaky() {
  local d=$1 at='@' bs='\' dot='.'
  st_repo "$d"
  {
    printf 'Contact jdoe%sexample-corp.tld for access (see <internal-url> for details).\n' "$at"
    printf 'Placeholder only: <email> and glob *.md and *%sexample-corp.tld\n' "$dot"
    printf 'Docs example: jane.doe%sexample.com stays out of the report.\n' "$at"
    printf 'Board: https://ACME.NOTION%sSO/roadmap-2026\n' "$dot"
    printf 'Windows path C:%sUsers%sjdoe%sdev%srepo\n' "$bs" "$bs" "$bs" "$bs"
    printf 'CI token ghp%saBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789\n' '_'
    printf 'Marked leak: jroe%sexample-corp.tld <!-- pii-ok: fixture line -->\n' "$at"
    printf 'Jump host %s.2.3.4 responded.\n' '1'
    printf 'Router at 192.168%s1.1 on the office LAN.\n' "$dot"
    printf 'Call %s49 151 5550123 for support.\n' '+'
    printf 'Transfer to %s370400440532013000 today.\n' 'DE89'
    printf 'Ticket TAS%s1397 tracks the rollout.\n' '-'
    printf 'Repo lives at /Users%sjdoe/Developer/secret-client and mirrors *.example.com.\n' '/'
    printf 'Scratchpad %sUsers-jdoe-Developer-agentic/state.json\n' '-'
    printf 'Deck: https://acme-my.sharepoint%scom/personal/jane_doe/Documents/plan.pptx\n' "$dot"
    printf 'Health: https://api.prod.acme-labs%scorp/health\n' "$dot"
    printf 'Signed-off by kelzenberg%susers.noreply.github.com\n' "$at"
    printf 'Public docs: https://github%scom/kelzenberg/agentic\n' "$dot"
    printf 'Host family *.notion%sso versus tenant *.acme.notion%sso/page\n' "$dot" "$dot"
  } >"$d/notes.md"
  # NUL-safety: a name that a line-oriented file-list filter would mangle.
  printf 'Second file leak: jdoe%sexample-corp.tld\n' "$at" >"$d/a file with spaces & '\''quotes'\''.md"
  printf 'MIT License\n\nCopyright (c) 2026 kelzenberg\n' >"$d/LICENSE"
  printf 'PNG\r\n\032\n binary-ish payload' >"$d/shot.png"
  printf 'nothing to see here\n' >"$d/notes-jdoe${at}example-corp.tld.md"

  # Marker mechanics: a YAML/shell comment marks, a JSON string value does not.
  printf 'board_url: https://acme.notion%sso/roadmap  # pii-ok: fixture\n' "$dot" >"$d/config.yml"
  printf '{"note": "pii-ok: fixture", "key": "%s%s"}\n' 'AKIA' 'IOSFODNN7EXAMPLE' >"$d/data.json"

  # Shapes that look like hosts or phone numbers but are neither.
  {
    printf 'See docs/internal.md for the details.\n'
    printf 'The callback lives in corp.acme.Service today.\n'
    printf 'Package com.example.internal.util is public API.\n'
    printf 'Changelog line %s2026-08-14 shipped the scanner.\n' '+'
    printf 'Build id %s1234567890 identifies the artifact.\n' '+'
  } >"$d/false-positives.md"

  # Filename tier: an allowlisted bigram must clear, an ordinary title-case
  # filename must never harden into a HIT nobody can suppress.
  printf 'Attribution filename, nothing private inside.\n' >"$d/Claude-Code.md"
  printf 'Ordinary documentation filename.\n' >"$d/Getting-Started.md"
}

st_build_gitmeta() { # history authored by a machine identity CI cannot avoid
  local d=$1 at='@'
  st_repo "$d"
  printf 'Nothing private in this fixture.\n' >"$d/readme.md"
  git -C "$d" add -A
  git -C "$d" -c user.name=GitHub -c "user.email=noreply${at}github.com" \
    commit -q -m 'ci: synthetic merge commit'
}

st_build_deletion() { # a staged set that is non-empty but has no content
  local d=$1
  st_repo "$d"
  printf 'This file exists only to be removed again.\n' >"$d/gone.md"
  git -C "$d" add -A
  git -C "$d" commit -q -m 'seed the fixture'
  git -C "$d" rm -q gone.md
}

st_build_clean() {
  local d=$1
  st_repo "$d"
  {
    printf 'Replace <email> with your address and <path-to-repo> with your checkout.\n'
    printf 'Private hosts include *.notion.so and *.slack.com — see the policy.\n'
    printf 'Docs mail: jane.doe@example.org — reserved by RFC 2606.\n'
    printf 'Attribution stays: kelzenberg, agentic-kelzenberg, Claude Code.\n'
  } >"$d/clean.md"
}

self_test() {
  local tmp leaky clean gitmeta deletion sum_full sum_dot
  preflight
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/pii-scan-selftest.XXXXXX") || die 'cannot create a temporary directory'
  trap 'rm -rf "$tmp"; cleanup' EXIT
  leaky="$tmp/leaky"
  clean="$tmp/clean"
  gitmeta="$tmp/gitmeta"
  deletion="$tmp/deletion"
  st_build_leaky "$leaky"
  st_build_clean "$clean"
  st_build_gitmeta "$gitmeta"
  st_build_deletion "$deletion"

  st_run "$leaky"
  st_expect_rc 'exit code 1 when the tree contains HIT records' 1
  st_expect 'uppercase private host is caught' '^HIT.*host.*ACME\.NOTION'
  st_expect 'Windows path C:\\Users\\... is caught' '^HIT.*path.*Users'
  st_expect 'real email beside a <placeholder> on the same line is caught' '^HIT.*email.*jdoe@example-corp'
  st_expect_absent '<email> placeholder alone is not flagged' 'HIT.*<email>'
  st_expect_absent 'reserved example.com email is not flagged' 'HIT.*jane\.doe@example\.com'
  st_expect_absent 'glob host *.example.com is not flagged' 'HIT.*\*\.example\.com'
  st_expect 'secret ghp_ token is caught' '^HIT.*secret.*ghp'
  st_expect 'pii-ok marker downgrades a HIT to SUPPRESSED' '^SUPPRESSED.*email.*jroe@example-corp'
  st_expect_absent 'pii-ok marked line emits no HIT' '^HIT.*jroe@example-corp'
  st_expect 'public IPv4 is CAND, not HIT' '^CAND.*	ip	1\.2\.3\.4'
  st_expect 'RFC 1918 IPv4 is HIT' '^HIT.*ip-private.*192\.168\.1\.1'
  st_expect 'international phone number is caught' '^HIT.*phone'
  st_expect 'IBAN is caught' '^HIT.*iban'
  st_expect 'ticket code is CAND' '^CAND.*ticket.*TAS[-]1397'
  st_expect 'full home path is matched to its end' '^HIT.*path.*jdoe/Developer/secret-client'
  st_expect 'dash-encoded project path is caught' '^HIT.*path.*[-]Users-jdoe-Developer'
  st_expect 'SharePoint URL is caught' '^HIT.*host.*sharepoint'
  st_expect 'internal host label is caught' '^HIT.*host.*acme-labs'
  st_expect_absent 'wildcard over a whole registrable domain is dropped' 'HIT.*[*]\.notion\.so'
  st_expect 'wildcard over a tenant subdomain stays a HIT' '^HIT.*host.*acme\.notion'
  st_expect_absent 'allowlisted users.noreply address is dropped' 'HIT.*noreply'
  st_expect_absent 'public github.com URL is dropped' 'HIT.*github\.com/kelzenberg'
  st_expect 'NUL-safe list keeps the odd filename scanned' '^HIT.*a file with spaces'
  st_expect 'other files are still scanned alongside it' '^HIT.*notes\.md'
  st_expect 'binary file is reported MANUAL, never scanned' '^MANUAL.*shot\.png.*binary'
  st_expect 'LICENSE copyright line is reported as INFO' '^INFO	license-copyright	.*Copyright'
  st_expect_absent 'LICENSE content is not pattern-matched' '^(HIT|CAND).*LICENSE'
  st_expect 'PII in a filename is caught' '^HIT.*filename.*notes-jdoe@example-corp'
  st_expect 'untracked files are counted in an INFO line' '^INFO	untracked-count	[0-9]+'
  st_expect 'summary reports mode and scope' '^SUMMARY	files=[0-9]+ hits=[0-9]+ cand=[0-9]+ suppressed=[0-9]+ manual=[0-9]+ mode=full scope=full-tree$'
  st_expect 'every scanned text file gets a SCANNED record' '^SCANNED	notes\.md$'
  st_expect 'the SCANNED set covers files that produced no finding' '^SCANNED	Getting[-]Started\.md$'

  st_expect 'a pii-ok marker in a YAML comment suppresses' '^SUPPRESSED.*host.*acme\.notion'
  st_expect 'a pii-ok string value in JSON does not suppress' '^HIT.*data\.json.*secret.*AKIA'
  st_expect_absent 'JSON never yields a marker-suppressed record' '^SUPPRESSED.*data\.json'

  st_expect_absent 'a dotted filename is not an internal host' '^(HIT|CAND).*internal\.md'
  st_expect_absent 'a dotted code identifier is not an internal host' '^(HIT|CAND).*acme\.Service'
  st_expect_absent 'a package path with an internal label is not a host' '^(HIT|CAND).*example\.internal\.util'
  st_expect 'a scheme-anchored internal host is still a HIT' '^HIT.*host.*acme-labs'

  st_expect_absent "a '+'-prefixed ISO date is not a phone number" 'phone.*2026[-]08[-]14'
  st_expect_absent 'a bare numeric id is not a phone number' 'phone.*1234567890'

  st_expect_absent 'an allowlisted name bigram in a filename is dropped' '^(HIT|CAND).*Claude[-]Code'
  st_expect 'a title-case filename is a CAND' '^CAND.*filename.*Getting[-]Started'
  st_expect_absent 'a title-case filename never blocks as a HIT' '^HIT.*Getting[-]Started'

  st_run "$leaky" --scope notes.md
  st_expect_rc 'scoped scan still exits 1' 1
  st_expect 'single-file scope still prints the filename' '^HIT	notes\.md	[0-9]+	'
  st_expect_absent 'single-file scope excludes other files' 'a file with spaces'
  st_expect 'scoped summary names the scope' 'mode=full scope=notes\.md$'

  st_run "$leaky" --auto-only
  st_expect_rc 'auto-only still exits 1 on HIT records' 1
  st_expect_absent 'auto-only emits no CAND records' '^CAND'
  st_expect 'auto-only keeps private-IP HIT records' '^HIT.*ip-private'
  st_expect 'auto-only summary reports mode=auto-only' 'mode=auto-only'

  st_run "$clean"
  st_expect_rc 'exit code 0 on a clean tree' 0
  st_expect_absent 'clean tree emits no HIT records' '^HIT'
  st_expect 'clean tree still emits a summary' '^SUMMARY	files=[0-9]+ hits=0 '

  st_run "$leaky" --scope shot.png
  st_expect_rc 'a scope holding only unscannable files is not clean' 1
  st_expect 'an unscannable-only scope explains itself' '^HIT	scan-scope	-	unscannable'
  st_expect 'an unscannable-only summary reports zero scanned files' '^SUMMARY	files=0 hits=1 .*manual=1'

  st_run "$leaky"
  sum_full=$(printf '%s\n' "$ST_OUT" | LC_ALL=C grep '^SUMMARY') || sum_full=''
  st_run "$leaky" --scope .
  sum_dot=$(printf '%s\n' "$ST_OUT" | LC_ALL=C grep '^SUMMARY') || sum_dot=''
  if [ -n "$sum_full" ] && [ "$sum_full" = "$sum_dot" ]; then
    st_ok 'a scope of the repo root runs as a full-tree scan'
  else
    st_no 'a scope of the repo root runs as a full-tree scan' "'$sum_full' == '$sum_dot'"
  fi

  st_run "$gitmeta"
  st_expect_rc 'a GitHub machine identity in history is not a finding' 0
  st_expect_absent 'no git-meta HIT for the GitHub noreply identity' '^HIT.*git-meta'

  st_run "$deletion" --staged
  st_expect_rc 'a deletion-only staged set is not a scan error' 0
  st_expect 'a deletion-only staged set is reported explicitly' '^INFO	staged-content	none$'
  st_expect 'a deletion-only staged set still prints a summary' '^SUMMARY	files=0 hits=0 '

  st_run "$clean" --scope no-such-directory
  st_expect_rc 'exit code 2 when the scope resolves to zero files' 2

  st_run "$clean" --staged
  st_expect_rc 'exit code 2 when the staged set is empty' 2

  st_run "$clean" --nonsense-flag
  st_expect_rc 'exit code 2 on an unknown argument' 2

  printf 'SELFTEST\tpass=%s fail=%s\n' "$ST_PASS" "$ST_FAIL"
  [ "$ST_FAIL" -eq 0 ] || exit 2
  exit 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  parse_args "$@"
  build_host_regex
  ERRLOG=$(mktemp "${TMPDIR:-/tmp}/pii-scan-err.XXXXXX") || die 'cannot create a temporary file'
  trap cleanup EXIT
  if [ "$SELF_TEST" -eq 1 ]; then
    self_test
  fi
  preflight
  run_scan
}

main "$@"
