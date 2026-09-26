#!/usr/bin/env bash
set -u

# Public username OSINT + alias-correlation wrapper for Google Cloud Shell
# Runs public username-oriented checks and automatically discovers email addresses that are actually public.
# It does NOT attempt to reveal private IPs, hidden contact details, or bypass access controls.

USERNAME=""
FULL_NAME=""

usage() {
  echo "Usage:"
  echo "  $0 --username USERNAME"
  echo "  $0 --name \"Full Name\""
  echo "  $0 --username USERNAME --name \"Full Name\""
}

while [ $# -gt 0 ]; do
  case "$1" in
    --username|-u)
      [ $# -ge 2 ] || { usage; exit 1; }
      USERNAME="$2"
      shift 2
      ;;
    --name|-n)
      [ $# -ge 2 ] || { usage; exit 1; }
      FULL_NAME="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

if [ -z "$USERNAME" ] && [ -z "$FULL_NAME" ]; then
  usage
  exit 1
fi

if [ -n "$USERNAME" ] && ! [[ "$USERNAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Error: username may contain only letters, numbers, dot, underscore, and hyphen."
  exit 1
fi

if [ -n "$FULL_NAME" ] && [ ${#FULL_NAME} -lt 2 ]; then
  echo "Error: name is too short."
  exit 1
fi

# Safe case key.
if [ -n "$USERNAME" ]; then
  CASE_KEY="$USERNAME"
else
  CASE_KEY="$(printf '%s' "$FULL_NAME" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')"
  [ -n "$CASE_KEY" ] || CASE_KEY="name-case"
fi

CASE_DIR="$HOME/osint-reports/$CASE_KEY"
SHERLOCK_DIR="$CASE_DIR/sherlock"
MAIGRET_DIR="$CASE_DIR/maigret"
SOCIAL_ANALYZER_DIR="$CASE_DIR/social-analyzer"
SOCIALSCAN_DIR="$CASE_DIR/socialscan"
WHATS_DIR="$CASE_DIR/whatsmyname"
HOLEHE_DIR="$CASE_DIR/holehe"
GHUNT_DIR="$CASE_DIR/ghunt"
PUBLIC_EMAIL_DIR="$CASE_DIR/public-email-discovery"
NAME_DISCOVERY_DIR="$CASE_DIR/name-discovery"
THEHARVESTER_DIR="$CASE_DIR/theharvester"
FINAL_DIR="$CASE_DIR/final-report"

mkdir -p \
  "$SHERLOCK_DIR" \
  "$MAIGRET_DIR" \
  "$SOCIAL_ANALYZER_DIR" \
  "$SOCIALSCAN_DIR" \
  "$WHATS_DIR" \
  "$HOLEHE_DIR" \
  "$GHUNT_DIR" \
  "$PUBLIC_EMAIL_DIR" \
  "$NAME_DISCOVERY_DIR" \
  "$THEHARVESTER_DIR" \
  "$FINAL_DIR"

LOG="$CASE_DIR/run.log"
: > "$LOG"

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

log() {
  echo "[$(timestamp)] $*" | tee -a "$LOG"
}

find_sherlock() {
  if command -v sherlock >/dev/null 2>&1; then
    command -v sherlock
    return 0
  fi
  if [ -x "$HOME/.local/bin/sherlock" ]; then
    echo "$HOME/.local/bin/sherlock"
    return 0
  fi
  if [ -x "$HOME/sherlock-venv/bin/sherlock" ]; then
    echo "$HOME/sherlock-venv/bin/sherlock"
    return 0
  fi
  return 1
}

SHERLOCK_BIN="$(find_sherlock || true)"
MAIGRET_BIN="$HOME/maigret-venv/bin/maigret"
SOCIAL_ANALYZER_PY="$HOME/social-analyzer-venv/bin/python3"
SOCIALSCAN_BIN="$HOME/socialscan-venv/bin/socialscan"
WMN_PY="$HOME/whatsmyname-venv/bin/python3"
WMN_MAIN="$HOME/whatsmyname/main.py"
WMN_DATA="$HOME/whatsmyname/wmn-data.json"
THEHARVESTER_REPO="$HOME/theHarvester"
HOLEHE_BIN="$HOME/holehe-venv/bin/holehe"
GHUNT_BIN="$(command -v ghunt 2>/dev/null || true)"
if [ -z "$GHUNT_BIN" ] && [ -x "$HOME/.local/bin/ghunt" ]; then
  GHUNT_BIN="$HOME/.local/bin/ghunt"
fi

log "Starting public account correlation case: $CASE_KEY"
if [ -n "$USERNAME" ]; then log "Username seed: $USERNAME"; fi
if [ -n "$FULL_NAME" ]; then log "Name seed: $FULL_NAME"; fi
log "Case directory: $CASE_DIR"
log "Tools run sequentially to reduce rate-limit pressure."
log "Automatic public-email discovery enabled; guessed mailboxes are not generated."

if [ -n "$USERNAME" ]; then
# -------------------------------------------------------------------
# 1) Sherlock
# -------------------------------------------------------------------
if [ -n "$SHERLOCK_BIN" ] && [ -x "$SHERLOCK_BIN" ]; then
  log "Running Sherlock..."
  timeout 15m "$SHERLOCK_BIN" "$USERNAME" \
    --timeout 10 \
    --output "$SHERLOCK_DIR/sherlock-results.txt" \
    > "$SHERLOCK_DIR/sherlock-console.log" 2>&1
  RC=$?
  if [ ! -s "$SHERLOCK_DIR/sherlock-results.txt" ] && [ -s "$SHERLOCK_DIR/sherlock-console.log" ]; then
    cp -f "$SHERLOCK_DIR/sherlock-console.log" "$SHERLOCK_DIR/sherlock-results.txt"
  fi
  log "Sherlock finished with exit code $RC"
else
  log "Sherlock not found; skipping."
fi

sleep 5

# -------------------------------------------------------------------
# 2) Maigret
# -------------------------------------------------------------------
if [ -x "$MAIGRET_BIN" ]; then
  log "Running Maigret..."
  (
    cd "$MAIGRET_DIR" || exit 1
    timeout 20m "$MAIGRET_BIN" "$USERNAME" --html \
      > maigret-console.log 2>&1
  )
  RC=$?
  log "Maigret finished with exit code $RC"
else
  log "Maigret not found at $MAIGRET_BIN; skipping."
fi

sleep 5

# -------------------------------------------------------------------
# 3) Social Analyzer
# -------------------------------------------------------------------
if [ -x "$SOCIAL_ANALYZER_PY" ]; then
  log "Running Social Analyzer..."
  (
    cd "$SOCIAL_ANALYZER_DIR" || exit 1
    timeout 10m "$SOCIAL_ANALYZER_PY" -m social-analyzer \
      --username "$USERNAME" \
      --metadata \
      --extract \
      --top 25 \
      --timeout 10 \
      --output json \
      > social-analyzer-results.json \
      2> social-analyzer-errors.log
  )
  RC=$?
  log "Social Analyzer finished with exit code $RC"
else
  log "Social Analyzer environment not found; skipping."
fi

sleep 5

# -------------------------------------------------------------------
# 4) SocialScan
# -------------------------------------------------------------------
if [ -x "$SOCIALSCAN_BIN" ]; then
  log "Running SocialScan..."
  timeout 5m "$SOCIALSCAN_BIN" "$USERNAME" \
    --show-urls \
    --json "$SOCIALSCAN_DIR/socialscan-results.json" \
    > "$SOCIALSCAN_DIR/socialscan-console.log" 2>&1
  RC=$?
  log "SocialScan finished with exit code $RC"
else
  log "SocialScan not found at $SOCIALSCAN_BIN; skipping."
fi

sleep 5

else
  log "Username scanners skipped because no username seed was supplied."
fi

# -------------------------------------------------------------------
# WhatsMyName
# -------------------------------------------------------------------
if [ -n "$USERNAME" ]; then
  if [ -x "$WMN_PY" ] && [ -f "$WMN_MAIN" ]; then
    log "Running WhatsMyName legacy CLI..."
    touch "$WHATS_DIR/.run-start"
    (
      cd "$HOME/whatsmyname" || exit 1
      timeout 15m "$WMN_PY" main.py "$USERNAME" --export both > "$WHATS_DIR/whatsmyname-console.log" 2>&1
    )
    RC=$?
    find "$HOME/whatsmyname" -maxdepth 2 -type f \( -name "*.json" -o -name "*.csv" \) -newer "$WHATS_DIR/.run-start" -exec cp -f {} "$WHATS_DIR/" \; 2>/dev/null || true
    log "WhatsMyName finished with exit code $RC"
  elif [ -f "$WMN_DATA" ]; then
    printf '%s\n' "DATASET ONLY / SCANNER UNAVAILABLE" > "$WHATS_DIR/status.txt"
    log "WhatsMyName dataset detected, but no compatible scanner CLI is installed; skipping scan."
  else
    printf '%s\n' "UNAVAILABLE" > "$WHATS_DIR/status.txt"
    log "WhatsMyName unavailable; skipping."
  fi
else
  log "WhatsMyName skipped (name-only mode)."
fi

# -------------------------------------------------------------------
# 6) Name discovery (best-effort public web search)
# -------------------------------------------------------------------
if [ -n "$FULL_NAME" ]; then
  log "Name discovery enabled. Public web discovery is best-effort and may be rate-limited."
else
  log "No name supplied; name discovery skipped."
fi

# -------------------------------------------------------------------
# 5) Automatic public-email discovery
# -------------------------------------------------------------------
log "Public-email discovery will run during report generation."

# -------------------------------------------------------------------
# Build consolidated HTML report from existing outputs
# -------------------------------------------------------------------
log "Building consolidated report..."

python3 - "$USERNAME" "$FULL_NAME" "$CASE_DIR" <<'PY'
import sys, json, re, html, math
from pathlib import Path
from urllib.parse import urlparse
from datetime import datetime
from collections import defaultdict

username = sys.argv[1]
full_name = sys.argv[2]
base = Path(sys.argv[3])
email = ""
final_dir = base / "final-report"
final_dir.mkdir(parents=True, exist_ok=True)

def safe_read(p):
    try:
        return p.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        return ""

def urls_from_text(text):
    return re.findall(r'https?://[^\s<>"\']+', text or "")

def urls_from_obj(obj):
    out = []
    if isinstance(obj, dict):
        for v in obj.values():
            out.extend(urls_from_obj(v))
    elif isinstance(obj, list):
        for v in obj:
            out.extend(urls_from_obj(v))
    elif isinstance(obj, str):
        out.extend(urls_from_text(obj))
    return out

def normalize_host(url):
    try:
        h = urlparse(url).netloc.lower()
        if h.startswith("www."):
            h = h[4:]
        return h
    except Exception:
        return ""

def extract_public_fields(obj):
    """
    Conservative extraction of public/self-declared profile metadata.
    Generic HTML/meta keys are intentionally excluded to reduce false positives.
    """
    names, bios, locations, websites, aliases = set(), set(), set(), set(), set()

    name_keys = {
        "fullname", "full_name", "display_name", "profile_name",
        "author_name", "given_name", "family_name"
    }
    bio_keys = {
        "bio", "biography", "about", "profile_bio", "profile_description"
    }
    location_keys = {
        "location", "city", "country", "region", "state", "province"
    }
    website_keys = {
        "website", "homepage", "external_url", "profile_url", "channel_url"
    }
    alias_keys = {
        "username", "user_name", "handle", "screen_name", "nickname", "alias"
    }

    noise_values = {
        "facebook", "rating", "description", "filtered", "keywords",
        "twitter:card", "twitter:site", "msapplication-tileimage",
        "msvalidate.01", "bingbot", "website", "profile", "user"
    }

    def add_value(bucket, value, max_len=300):
        if not isinstance(value, (str, int, float, bool)):
            return
        s = str(value).strip()
        if not s or len(s) > max_len:
            return
        if s.lower() in noise_values:
            return
        bucket.add(s)

    def walk(x):
        if isinstance(x, dict):
            for k, v in x.items():
                lk = str(k).lower().strip()

                if lk in name_keys:
                    add_value(names, v, 120)
                elif lk in bio_keys:
                    add_value(bios, v, 500)
                elif lk in location_keys:
                    add_value(locations, v, 160)
                elif lk in website_keys:
                    if isinstance(v, str) and v.startswith(("http://", "https://")):
                        add_value(websites, v, 500)
                elif lk in alias_keys:
                    add_value(aliases, v, 80)

                if isinstance(v, (dict, list)):
                    walk(v)

        elif isinstance(x, list):
            for item in x:
                walk(item)

    walk(obj)
    return {
        "names": sorted(names),
        "bios": sorted(bios),
        "locations": sorted(locations),
        "websites": sorted(websites),
        "aliases": sorted(aliases),
    }

tool_urls = {}
tool_notes = {}
public_fields = {
    "names": set(),
    "bios": set(),
    "locations": set(),
    "websites": set(),
    "aliases": set(),
}

email_notes = []
email_platforms = set()

def masked_email(value):
    if not value or "@" not in value:
        return "Not supplied"
    local, domain = value.split("@", 1)
    lead = local[:1] if local else "*"
    return f"{lead}***@{domain}"


# Sherlock
sherlock = base / "sherlock" / "sherlock-results.txt"
sherlock_console = base / "sherlock" / "sherlock-console.log"
if sherlock.exists() or sherlock_console.exists():
    txt = safe_read(sherlock) + "\n" + safe_read(sherlock_console)
    tool_urls["Sherlock"] = sorted(set(urls_from_text(txt)))
    tool_notes["Sherlock"] = f"{len(tool_urls['Sherlock'])} URL references."
else:
    tool_notes["Sherlock"] = "No saved result."

# Maigret
maigret_reports = list((base / "maigret").rglob("*.html"))
if maigret_reports:
    txt = "\n".join(safe_read(p) for p in maigret_reports)
    tool_urls["Maigret"] = sorted(set(urls_from_text(txt)))
    tool_notes["Maigret"] = f"{len(tool_urls['Maigret'])} URL references across {len(maigret_reports)} HTML report(s)."
else:
    tool_notes["Maigret"] = "No HTML report."

# Social Analyzer
sa = base / "social-analyzer" / "social-analyzer-results.json"
if sa.exists() and sa.stat().st_size > 0:
    try:
        obj = json.loads(safe_read(sa))
        tool_urls["Social Analyzer"] = sorted(set(urls_from_obj(obj)))
        pf = extract_public_fields(obj)
        for k in public_fields:
            public_fields[k].update(pf[k])
        detected = obj.get("detected") if isinstance(obj, dict) else None
        dcount = len(detected) if isinstance(detected, list) else "unknown"
        tool_notes["Social Analyzer"] = f"Valid JSON; detected entries: {dcount}; URL references: {len(tool_urls['Social Analyzer'])}."
    except Exception as e:
        tool_notes["Social Analyzer"] = f"JSON parse error: {e}"
else:
    tool_notes["Social Analyzer"] = "No non-empty JSON result."

# SocialScan
ss = base / "socialscan" / "socialscan-results.json"
if ss.exists() and ss.stat().st_size > 0:
    try:
        obj = json.loads(safe_read(ss))
        tool_urls["SocialScan"] = sorted(set(urls_from_obj(obj)))
        pf = extract_public_fields(obj)
        for k in public_fields:
            public_fields[k].update(pf[k])
        tool_notes["SocialScan"] = f"Valid JSON; URL references: {len(tool_urls['SocialScan'])}."
    except Exception as e:
        tool_notes["SocialScan"] = f"JSON parse error: {e}"
else:
    tool_notes["SocialScan"] = "No non-empty JSON result."

# Optional WhatsMyName ingestion if user has exported results already
whats_dir = base / "whatsmyname"
whats_files = []
if whats_dir.exists():
    whats_files = [p for p in whats_dir.rglob("*") if p.suffix.lower() in {".json",".csv",".html",".txt"} and p.is_file()]
if whats_files:
    txt = "\n".join(safe_read(p) for p in whats_files)
    tool_urls["WhatsMyName"] = sorted(set(urls_from_text(txt)))
    tool_notes["WhatsMyName"] = f"{len(tool_urls['WhatsMyName'])} URL references from {len(whats_files)} exported file(s)."
else:
    wmn_status = safe_read(base / "whatsmyname" / "status.txt").strip()
    tool_notes["WhatsMyName"] = wmn_status or "No exported WhatsMyName result found (optional)."

# ------------------------------------------------------------------
# Name-based public web discovery (best effort)
# ------------------------------------------------------------------
name_discovery_dir = base / "name-discovery"
name_discovery_dir.mkdir(parents=True, exist_ok=True)
name_candidates = []

if full_name:
    import subprocess, urllib.parse, html as htmlmod

    queries = [
        f'"{full_name}"',
        f'"{full_name}" profile',
        f'"{full_name}" social',
    ]

    discovered = []
    seen = set()

    for q in queries:
        try:
            url = "https://html.duckduckgo.com/html/?q=" + urllib.parse.quote_plus(q)
            proc = subprocess.run(
                [
                    "curl", "-L", "--max-redirs", "3",
                    "--connect-timeout", "6", "--max-time", "12",
                    "-A", "Mozilla/5.0 (compatible; PublicOSINTCorrelation/1.0)",
                    "-sS", url
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                errors="ignore",
                timeout=18,
            )
            page = proc.stdout
            # DuckDuckGo result links commonly contain uddg=<encoded target>.
            for enc in re.findall(r'uddg=([^&"<>]+)', page):
                target = urllib.parse.unquote(enc)
                if target.startswith(("http://", "https://")) and target not in seen:
                    seen.add(target)
                    discovered.append(target)
            if len(discovered) >= 30:
                break
        except Exception:
            pass

    discovered = discovered[:20]

    for url in discovered:
        record = {"url": url, "exact_name_found": False, "title": ""}
        try:
            proc = subprocess.run(
                [
                    "curl", "-L", "--max-redirs", "3",
                    "--connect-timeout", "5", "--max-time", "10",
                    "-A", "Mozilla/5.0 (compatible; PublicOSINTCorrelation/1.0)",
                    "-sS", url
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                errors="ignore",
                timeout=15,
            )
            body = proc.stdout[:1_500_000]
            record["exact_name_found"] = full_name.lower() in body.lower()

            tm = re.search(r'(?is)<title[^>]*>(.*?)</title>', body)
            if tm:
                title = re.sub(r'\s+', ' ', re.sub(r'<[^>]+>', '', tm.group(1))).strip()
                record["title"] = htmlmod.unescape(title)[:300]

            # Only add to correlation URL set when the exact name is present.
            if record["exact_name_found"]:
                tool_urls.setdefault("Name Web Discovery", []).append(url)

        except Exception as exc:
            record["error"] = str(exc)

        name_candidates.append(record)

    tool_urls["Name Web Discovery"] = sorted(set(tool_urls.get("Name Web Discovery", [])))
    tool_notes["Name Web Discovery"] = (
        f"{len(tool_urls['Name Web Discovery'])} pages contained the exact supplied name "
        f"out of {len(name_candidates)} public results checked."
    )

    (name_discovery_dir / "name-candidates.json").write_text(
        json.dumps(name_candidates, indent=2, ensure_ascii=False),
        encoding="utf-8"
    )
else:
    tool_notes["Name Web Discovery"] = "No name seed supplied."

# ------------------------------------------------------------------
# theHarvester enrichment for externally linked public domains
# ------------------------------------------------------------------
theharvester_dir = base / "theharvester"
theharvester_dir.mkdir(parents=True, exist_ok=True)
theharvester_records = []

SOCIAL_OR_PLATFORM_HOSTS = {
    "facebook.com", "instagram.com", "threads.com", "twitter.com", "x.com",
    "youtube.com", "youtu.be", "tiktok.com", "pinterest.com", "reddit.com",
    "github.com", "gitlab.com", "linkedin.com", "tumblr.com", "snapchat.com",
    "telegram.org", "t.me", "imgur.com", "archive.org", "archive.is",
    "cloudflare.com", "sentry.io"
}

def rootish_host(url):
    try:
        host = urlparse(url).hostname or ""
        host = host.lower().strip(".")
        if host.startswith("www."):
            host = host[4:]
        return host
    except Exception:
        return ""

domain_candidates = []
for w in sorted(public_fields["websites"]):
    h = rootish_host(w)
    if not h or h in SOCIAL_OR_PLATFORM_HOSTS:
        continue
    if any(h.endswith("." + p) for p in SOCIAL_OR_PLATFORM_HOSTS):
        continue
    if re.fullmatch(r"(?:\d{1,3}\.){3}\d{1,3}", h):
        continue
    if h not in domain_candidates:
        domain_candidates.append(h)

domain_candidates = domain_candidates[:3]

import shutil, subprocess
uv_bin = shutil.which("uv")
harvester_repo = Path.home() / "theHarvester"

if domain_candidates and uv_bin and (harvester_repo / "pyproject.toml").exists():
    for idx, domain in enumerate(domain_candidates, 1):
        prefix = theharvester_dir / f"domain-{idx}-{re.sub(r'[^a-z0-9.-]+', '-', domain)}"
        rec = {"domain": domain, "sources": ["crtsh", "certspotter"]}
        try:
            proc = subprocess.run(
                [
                    uv_bin, "run", "theHarvester",
                    "-d", domain,
                    "-b", "crtsh,certspotter",
                    "-f", str(prefix)
                ],
                cwd=str(harvester_repo),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                errors="ignore",
                timeout=180,
            )
            rec["returncode"] = proc.returncode
            rec["stdout_tail"] = proc.stdout[-4000:]
            rec["stderr_tail"] = proc.stderr[-4000:]

            # Read generated JSON when available.
            json_path = Path(str(prefix) + ".json")
            if json_path.exists():
                try:
                    rec["json"] = json.loads(safe_read(json_path))
                except Exception:
                    rec["json_parse_error"] = True

        except Exception as exc:
            rec["error"] = str(exc)

        theharvester_records.append(rec)

elif domain_candidates:
    theharvester_records.append({
        "status": "skipped",
        "reason": "uv/theHarvester source checkout not ready",
        "domains": domain_candidates,
    })

(theharvester_dir / "theharvester-summary.json").write_text(
    json.dumps(theharvester_records, indent=2, ensure_ascii=False),
    encoding="utf-8"
)

# Automatic public-email discovery.
# V7 does not manufacture addresses such as username@gmail.com.
# It classifies observed addresses to reduce site-support and telemetry false positives.
public_email_dir = base / "public-email-discovery"
public_email_dir.mkdir(parents=True, exist_ok=True)

EMAIL_RE = re.compile(
    r'(?i)(?<![A-Z0-9._%+-])([A-Z0-9._%+-]{1,64}@[A-Z0-9.-]+\.[A-Z]{2,63})(?![A-Z0-9._%+-])'
)

GENERIC_LOCALPARTS = {
    "admin", "abuse", "billing", "contact", "hello", "help", "info",
    "jobs", "marketing", "noreply", "no-reply", "privacy", "sales",
    "security", "support", "webmaster", "press", "service"
}

INFRA_DOMAINS = {
    "sentry.io"
}

def extract_emails(text):
    result = set()
    for raw in EMAIL_RE.findall(text or ""):
        addr = raw.strip(".,;:()[]<>\\\"'")
        low = addr.lower()

        if any(x in low for x in ("example.com", "example.org", "example.net")):
            continue
        result.add(addr)
    return result

def classify_email(addr, sources, source_texts):
    local, _, domain = addr.lower().partition("@")
    reasons = []

    if local in GENERIC_LOCALPARTS:
        return "SITE/GENERIC CONTACT", ["generic mailbox local-part"]

    if domain in INFRA_DOMAINS:
        return "TECHNICAL/INFRASTRUCTURE", ["known infrastructure/telemetry domain"]

    if len(local) >= 20 and re.fullmatch(r"[0-9a-f._-]+", local):
        return "TECHNICAL/INFRASTRUCTURE", ["hash-like mailbox local-part"]

    proximity_hits = 0
    for source_id, body in source_texts.items():
        low_body = body.lower()
        for m in re.finditer(re.escape(addr.lower()), low_body):
            lo = max(0, m.start() - 300)
            hi = min(len(low_body), m.end() + 300)
            if username.lower() in low_body[lo:hi]:
                proximity_hits += 1
                break

    if proximity_hits:
        reasons.append(f"username appears near email in {proximity_hits} source(s)")

    if len(sources) >= 2:
        reasons.append(f"email observed in {len(sources)} independent public sources")

    if proximity_hits and len(sources) >= 2:
        return "STRONG PUBLIC CONTACT CANDIDATE", reasons
    if proximity_hits or len(sources) >= 2:
        return "REVIEW PUBLIC CONTACT CANDIDATE", reasons

    return "UNATTRIBUTED PUBLIC EMAIL", ["email appears publicly, but no strong account-level link was found"]

email_sources = defaultdict(set)
source_texts = {}

# Scan raw evidence files.
for sub in ("sherlock", "maigret", "social-analyzer", "socialscan", "whatsmyname"):
    d = base / sub
    if not d.exists():
        continue
    for p in d.rglob("*"):
        if not p.is_file() or p.suffix.lower() not in {".txt", ".log", ".json", ".html", ".csv"}:
            continue
        body = safe_read(p)
        sid = f"saved:{p.relative_to(base)}"
        source_texts[sid] = body
        for addr in extract_emails(body):
            email_sources[addr].add(sid)

# Fetch at most 20 discovered public profile URLs with conservative limits.
all_urls = set()
for urls in tool_urls.values():
    all_urls.update(urls)

ranked_urls = sorted(
    all_urls,
    key=lambda u: (0 if username.lower() in u.lower() else 1, len(u))
)[:20]

import subprocess, time
fetch_log = []

for url in ranked_urls:
    try:
        parsed = urlparse(url)
        if parsed.scheme not in {"http", "https"}:
            continue

        proc = subprocess.run(
            [
                "curl", "-L", "--max-redirs", "3",
                "--connect-timeout", "5", "--max-time", "10",
                "-A", "Mozilla/5.0 (compatible; PublicOSINTCorrelation/1.0)",
                "-sS", url
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            errors="ignore",
            timeout=15,
        )

        body = proc.stdout[:2_000_000]
        source_texts[url] = body
        found = sorted(extract_emails(body))

        for addr in found:
            email_sources[addr].add(url)

        fetch_log.append({
            "url": url,
            "returncode": proc.returncode,
            "bytes": len(body),
            "emails_found": found,
        })

    except Exception as exc:
        fetch_log.append({"url": url, "error": str(exc)})

    time.sleep(1.5)

(public_email_dir / "fetch-log.json").write_text(
    json.dumps(fetch_log, indent=2, ensure_ascii=False),
    encoding="utf-8"
)

public_email_records = []
for addr, sources in sorted(email_sources.items(), key=lambda kv: (-len(kv[1]), kv[0].lower())):
    classification, reasons = classify_email(addr, sources, source_texts)

    public_email_records.append({
        "email": addr,
        "classification": classification,
        "reasons": reasons,
        "source_count": len(sources),
        "sources": sorted(sources),
    })

(public_email_dir / "public-emails-v7.json").write_text(
    json.dumps(public_email_records, indent=2, ensure_ascii=False),
    encoding="utf-8"
)

# ------------------------------------------------------------------
# Public alias-correlation layer
# ------------------------------------------------------------------
# V7 extracts only plausible account handles. Static assets, libraries,
# domains, versions, generic path elements, and obvious page resources are rejected.

alias_dir = base / "alias-correlation"
alias_dir.mkdir(parents=True, exist_ok=True)

seed = username.lower()
alias_evidence = defaultdict(lambda: {"tools": set(), "urls": set(), "reasons": set()})

BLOCKED_ALIAS_WORDS = {
    "about", "account", "accounts", "ajax", "api", "assets", "bootstrap",
    "cdn", "channel", "channels", "contact", "css", "explore", "favicon",
    "favicons", "help", "home", "images", "img", "js", "jquery", "libs",
    "login", "logout", "media", "newest", "post", "posts", "privacy",
    "profile", "profiles", "search", "settings", "share", "signup",
    "static", "status", "terms", "user", "users", "watch", "web", "www",
    "maigret", "sherlock", "socialscan", "social-analyzer", "whatsmyname",
    "instagramosint", "instagram-osint", "report", "reports"
}

FILE_EXTENSIONS = {
    ".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp", ".ico",
    ".css", ".js", ".json", ".xml", ".woff", ".woff2", ".ttf",
    ".map", ".txt", ".html", ".htm"
}

def plausible_alias(value):
    value = (value or "").strip().strip("@")
    if not value or len(value) < 3 or len(value) > 64:
        return None

    low = value.lower()

    if low in BLOCKED_ALIAS_WORDS:
        return None

    if any(low.endswith(ext) for ext in FILE_EXTENSIONS):
        return None

    # Reject domains and hostnames.
    if re.fullmatch(r"(?:[a-z0-9-]+\.)+[a-z]{2,63}", low):
        return None

    # Reject software/version strings.
    if re.fullmatch(r"\d+(?:\.\d+){1,4}", low):
        return None

    # Require a handle-like token.
    if not re.fullmatch(r"[A-Za-z0-9._-]+", value):
        return None

    # Avoid mostly punctuation/numbers.
    if sum(c.isalpha() for c in value) < 2:
        return None

    return value

# Stronger source: structured alias/handle metadata.
for a in public_fields["aliases"]:
    pa = plausible_alias(a)
    if pa and pa.lower() != seed:
        alias_evidence[pa]["reasons"].add("structured public alias/handle metadata")

# URL extraction: prefer the final meaningful path component.
for tool, urls in tool_urls.items():
    for u in urls:
        try:
            p = urlparse(u)
            parts = [x for x in p.path.split("/") if x]

            if not parts:
                continue

            candidates = []
            # Profile URLs usually place the handle at the final path component.
            candidates.append(parts[-1])

            # Common /users/handle or /user/handle pattern.
            for idx, part in enumerate(parts[:-1]):
                if part.lower() in {"user", "users", "u", "profile", "profiles", "member", "members", "channel"}:
                    candidates.append(parts[idx + 1])

            for raw in candidates:
                pa = plausible_alias(raw)
                if not pa or pa.lower() == seed:
                    continue

                alias_evidence[pa]["tools"].add(tool)
                alias_evidence[pa]["urls"].add(u)
                alias_evidence[pa]["reasons"].add("handle-like token in discovered public profile URL")

        except Exception:
            pass

import difflib

alias_records = []
for alias, ev in alias_evidence.items():
    tools = sorted(ev["tools"])
    urls = sorted(ev["urls"])

    score = 0
    evidence = []

    if "structured public alias/handle metadata" in ev["reasons"]:
        score += 30
        evidence.append("+30 structured public alias metadata")

    if len(tools) >= 2:
        add = min(30, (len(tools) - 1) * 15)
        score += add
        evidence.append(f"+{add} multi-tool URL corroboration")
    elif len(tools) == 1:
        score += 5
        evidence.append("+5 single-tool profile URL occurrence")

    similarity = difflib.SequenceMatcher(None, seed, alias.lower()).ratio()
    if similarity >= 0.85:
        score += 10
        evidence.append("+10 high handle-string similarity")
    elif similarity >= 0.70:
        score += 5
        evidence.append("+5 moderate handle-string similarity")

    score = min(score, 70)

    if score >= 50:
        status = "STRONG CANDIDATE — MANUAL REVIEW"
    elif score >= 30:
        status = "MODERATE CANDIDATE — MANUAL REVIEW"
    elif score >= 15:
        status = "WEAK CANDIDATE"
    else:
        status = "INSUFFICIENT EVIDENCE"

    alias_records.append({
        "alias": alias,
        "score": score,
        "status": status,
        "tools": tools,
        "urls": urls,
        "evidence": evidence,
    })

alias_records.sort(key=lambda r: (-r["score"], r["alias"].lower()))

(alias_dir / "alias-candidates-v7.json").write_text(
    json.dumps(alias_records, indent=2, ensure_ascii=False),
    encoding="utf-8"
)

graph = {
    "seed": username,
    "nodes": [{"id": username, "type": "seed"}] + [
        {"id": r["alias"], "type": "candidate", "status": r["status"], "score": r["score"]}
        for r in alias_records
    ],
    "edges": [
        {
            "source": username,
            "target": r["alias"],
            "score": r["score"],
            "status": r["status"],
            "evidence": r["evidence"],
        }
        for r in alias_records
    ],
}

(alias_dir / "alias-graph-v7.json").write_text(
    json.dumps(graph, indent=2, ensure_ascii=False),
    encoding="utf-8"
)

# Correlate hostnames
INFRA_HOSTS = {
    "cdnjs.cloudflare.com", "code.jquery.com", "stackpath.bootstrapcdn.com",
    "i.imgur.com", "i.pinimg.com", "yt3.googleusercontent.com"
}
INFRA_SUFFIXES = (".googleusercontent.com", ".cloudfront.net")

def candidate_profile_host(host):
    h = (host or "").lower()
    return bool(h) and h not in INFRA_HOSTS and not any(h.endswith(x) for x in INFRA_SUFFIXES)

host_tools = defaultdict(set)
host_urls = defaultdict(set)
for tool, urls in tool_urls.items():
    for u in urls:
        h = normalize_host(u)
        if h and candidate_profile_host(h):
            host_tools[h].add(tool)
            host_urls[h].add(u)

available_tools = max(1, len([t for t in tool_urls if tool_urls[t]]))

rows = []
for host in sorted(host_tools, key=lambda h: (-len(host_tools[h]), h)):
    tools = sorted(host_tools[host])
    refs = sorted(host_urls[host])
    overlap = len(tools)
    tool_score = round((overlap / available_tools) * 100)

    # Evidence score is NOT identity probability.
    # It is a transparent profile-correlation score based on public clues.
    evidence_points = 0
    evidence = []

    # Same username is weak evidence.
    if any(username.lower() in u.lower() for u in refs):
        evidence_points += 10
        evidence.append("+10 exact username in public profile URL")

    # Multi-tool confirmation adds moderate evidence.
    if overlap >= 2:
        add = min(30, (overlap - 1) * 15)
        evidence_points += add
        evidence.append(f"+{add} independent-tool agreement")

    # Directly-linked public website on same host is useful but not decisive.
    if any(normalize_host(w) == host for w in public_fields["websites"]):
        evidence_points += 15
        evidence.append("+15 matching public linked website")

    # Public alias match from structured metadata.
    if any(a.lower() == username.lower() for a in public_fields["aliases"]):
        evidence_points += 10
        evidence.append("+10 structured public alias match")

    evidence_points = min(65, evidence_points)

    if evidence_points >= 50:
        assessment = "STRONG PUBLIC CORRELATION"
    elif evidence_points >= 30:
        assessment = "MODERATE PUBLIC CORRELATION"
    elif evidence_points >= 15:
        assessment = "WEAK PUBLIC CORRELATION"
    else:
        assessment = "INSUFFICIENT EVIDENCE"

    rows.append({
        "host": host,
        "tools": tools,
        "tool_score": tool_score,
        "evidence_score": evidence_points,
        "assessment": assessment,
        "evidence": evidence,
        "sample": refs[0] if refs else "",
    })

def esc(x):
    return html.escape(str(x))

def list_html(values, limit=20):
    vals = [v for v in values if v]
    if not vals:
        return "<li>Not found in saved public metadata.</li>"
    return "".join(f"<li>{esc(v)}</li>" for v in vals[:limit])

summary_items = "\n".join(
    f"<li><b>{esc(tool)}:</b> {esc(note)}</li>"
    for tool, note in tool_notes.items()
)

table_rows = "\n".join(
    f"<tr>"
    f"<td>{esc(r['host'])}</td>"
    f"<td>{esc(', '.join(r['tools']))}</td>"
    f"<td>{r['tool_score']}%</td>"
    f"<td>{r['evidence_score']}/100*</td>"
    f"<td>{esc(r['assessment'])}</td>"
    f"<td>{esc('; '.join(r['evidence']) or 'No additional public evidence')}</td>"
    f"<td>{('<a href=' + repr(r['sample']) + '>sample</a>') if r['sample'] else ''}</td>"
    f"</tr>"
    for r in rows
)

generated = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

report = f"""<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>Public Account Correlation Report - {esc(username or full_name)}</title>
<style>
body {{ font-family: Arial, sans-serif; max-width: 1250px; margin: 40px auto; line-height: 1.5; }}
h1, h2 {{ border-bottom: 1px solid #ccc; padding-bottom: 8px; }}
table {{ border-collapse: collapse; width: 100%; margin: 20px 0; }}
th, td {{ border: 1px solid #ccc; padding: 8px; text-align: left; vertical-align: top; }}
.notice {{ background: #fff4d6; padding: 14px; border-radius: 8px; }}
.info {{ background: #eef6ff; padding: 14px; border-radius: 8px; }}
.small {{ color: #555; font-size: 0.9em; }}
code {{ background: #f3f3f3; padding: 2px 4px; }}
</style>
</head>
<body>

<h1>Public Account Correlation Report</h1>
<p><b>Target:</b> {esc(username or full_name)}</p>
<p><b>Generated:</b> {esc(generated)}</p>

<div class="notice">
This report correlates public username/profile evidence only. It does not attempt to reveal
private home addresses, private email/phone details, login/source IP addresses, credentials,
or other non-public identifying information.
</div>

<h2>Search Inputs</h2>
<ul>
<li><b>Username seed:</b> {esc(username) if username else "Not supplied"}</li>
<li><b>Name seed:</b> {esc(full_name) if full_name else "Not supplied"}</li>
</ul>
<p class="small">
Name-only discovery is inherently ambiguous. Exact-name public web matches are candidate leads,
not proof that the pages refer to the same real-world person.
</p>

<h2>Tool Summary</h2>
<ul>
{summary_items}
</ul>

<h2>Automatically Discovered Public Emails</h2>
<p>
V8.2 reports only email addresses actually observed in public evidence. It classifies generic
site mailboxes and technical/telemetry addresses separately so they do not strengthen identity correlation.
</p>

<table>
<tr>
  <th>Email</th>
  <th>Classification</th>
  <th>Public source count</th>
  <th>Reason</th>
  <th>Observed sources</th>
</tr>
{''.join(
    f"<tr><td>{esc(r['email'])}</td>"
    f"<td>{esc(r['classification'])}</td>"
    f"<td>{r['source_count']}</td>"
    f"<td>{esc('; '.join(r['reasons']))}</td>"
    f"<td>{'<br>'.join(esc(s) for s in r['sources'][:10])}</td></tr>"
    for r in public_email_records
) if public_email_records else '<tr><td colspan="5">No public email address was discovered.</td></tr>'}
</table>

<p class="small">
Only addresses classified as public-contact candidates should be considered for manual correlation review.
Generic site support mailboxes and technical/telemetry addresses are excluded from identity evidence.
</p>

<h2>Name-Based Candidate Pages</h2>
<table>
<tr>
  <th>URL</th>
  <th>Exact supplied name observed</th>
  <th>Page title</th>
</tr>
{''.join(
    f"<tr><td>{('<a href=' + repr(r['url']) + '>' + esc(r['url']) + '</a>')}</td>"
    f"<td>{'YES' if r.get('exact_name_found') else 'NO'}</td>"
    f"<td>{esc(r.get('title',''))}</td></tr>"
    for r in name_candidates[:20]
) if name_candidates else '<tr><td colspan="3">No name-based web discovery results were available.</td></tr>'}
</table>

<h2>theHarvester Domain Enrichment</h2>
<p>
theHarvester is run only when the profile metadata exposes an external public website/domain.
It is not run against arbitrary social-platform domains.
</p>
<ul>
{''.join(
    f"<li>{esc(r.get('domain', ', '.join(r.get('domains', [])) or 'n/a'))}: "
    f"{esc('completed' if r.get('returncode') == 0 else r.get('reason','review output'))}</li>"
    for r in theharvester_records
) if theharvester_records else '<li>No eligible external public domain was available for enrichment.</li>'}
</ul>

<h2>Public Identity Clues</h2>
<div class="info">
<p>These values come only from structured public metadata already returned by the tools.</p>
</div>

<h3>Display names / names observed</h3>
<ul>{list_html(sorted(public_fields['names']))}</ul>

<h3>Self-declared locations observed</h3>
<ul>{list_html(sorted(public_fields['locations']))}</ul>

<h3>Public aliases / handles observed</h3>
<ul>{list_html(sorted(public_fields['aliases']))}</ul>

<h3>Public linked websites observed</h3>
<ul>{list_html(sorted(public_fields['websites']))}</ul>

<h3>Public bios / descriptions observed</h3>
<ul>{list_html(sorted(public_fields['bios']), limit=10)}</ul>

<h2>Data Quality Controls</h2>
<ul>
<li>Static assets, JavaScript/CSS libraries, domains, software versions, and generic URL paths are excluded from alias candidates.</li>
<li>Generic site emails such as support/info/admin are not treated as identity evidence.</li>
<li>Technical/telemetry mailboxes are separated from public-contact candidates.</li>
<li>Display-name extraction uses explicit profile-oriented fields rather than arbitrary HTML metadata keys.</li>
<li>Tool agreement confirms profile discovery only; it does not prove common real-world ownership.</li>
</ul>

<h2>Candidate Alias Graph</h2>
<p>
V8.2 extracts possible additional handles from public profile URLs and structured metadata.
Candidates are <b>not automatically searched or treated as the same person</b>. They are
ranked for analyst review so a false positive does not recursively contaminate the case.
</p>

<table>
<tr>
  <th>Candidate alias</th>
  <th>Evidence score</th>
  <th>Status</th>
  <th>Tools</th>
  <th>Evidence</th>
</tr>
{''.join(
    f"<tr><td>{esc(r['alias'])}</td><td>{r['score']}/100*</td>"
    f"<td>{esc(r['status'])}</td><td>{esc(', '.join(r['tools']) or 'metadata')}</td>"
    f"<td>{esc('; '.join(r['evidence']) or 'No additional evidence')}</td></tr>"
    for r in alias_records
) if alias_records else '<tr><td colspan="5">No additional public alias candidates were extracted.</td></tr>'}
</table>

<p class="small">
*Alias evidence scores measure the strength of public linking clues, not the probability that
two handles belong to the same real-world person. Review the underlying URLs before using a
candidate as a new search seed.
</p>

<h2>Contradiction Review</h2>
<p>
V8.2 flags multiple distinct public names or self-declared locations for analyst review instead
of silently treating them as consistent identity evidence.
</p>
<ul>
<li><b>Distinct public names observed:</b> {len(public_fields['names'])}</li>
<li><b>Distinct public locations observed:</b> {len(public_fields['locations'])}</li>
<li><b>Name contradiction flag:</b> {"REVIEW" if len(public_fields['names']) > 1 else "NONE/INSUFFICIENT DATA"}</li>
<li><b>Location contradiction flag:</b> {"REVIEW" if len(public_fields['locations']) > 1 else "NONE/INSUFFICIENT DATA"}</li>
</ul>

<h2>Profile Discovery and Account Correlation</h2>
<p>
<b>Discovery agreement</b> measures whether multiple scanners independently referenced the same hostname. <b>Identity evidence</b> is kept separate and remains conservative. Scanner agreement confirms a lead, not a person.
</p>

<table>
<tr>
  <th>Hostname</th>
  <th>Tools</th>
  <th>Tool agreement</th>
  <th>Evidence score</th>
  <th>Assessment</th>
  <th>Evidence</th>
  <th>Example</th>
</tr>
{table_rows}
</table>

<p class="small">
*The evidence score is intentionally capped when only automated username-level evidence is
available. A stronger same-operator assessment requires profile-level public evidence such as
direct account cross-links, the same distinctive public profile image, matching self-declared
name/location, or the same linked website.
</p>

<h2>Raw Evidence Locations</h2>
<ul>
  <li><code>{esc(base / "sherlock")}</code></li>
  <li><code>{esc(base / "maigret")}</code></li>
  <li><code>{esc(base / "social-analyzer")}</code></li>
  <li><code>{esc(base / "socialscan")}</code></li>
  <li><code>{esc(base / "whatsmyname")}</code> (optional export)</li>
  <li><code>{esc(base / "holehe")}</code> (when email supplied)</li>
  <li><code>{esc(base / "ghunt")}</code> (manual/legacy evidence if present)</li>
  <li><code>{esc(base / "public-email-discovery")}</code></li>
  <li><code>{esc(base / "alias-correlation")}</code></li>
  <li><code>{esc(base / "name-discovery")}</code></li>
  <li><code>{esc(base / "theharvester")}</code></li>
  <li><code>{esc(base / "run.log")}</code></li>
</ul>

</body>
</html>
"""

out = final_dir / "combined-report-v8.2.html"
out.write_text(report, encoding="utf-8")
print(out)
PY
RC=$?
if [ $RC -eq 0 ]; then
  log "Report created: $FINAL_DIR/combined-report-v8.2.html"
else
  log "Report generation failed with exit code $RC"
fi

echo
echo "============================================================"
echo "DONE"
echo "Case:   $CASE_DIR"
echo "Report: $FINAL_DIR/combined-report-v8.2.html"
echo "Log:    $LOG"
echo "============================================================"
