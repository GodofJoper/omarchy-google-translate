#!/usr/bin/env python3
"""Google Translate backend for Omarchy overlay plugin.

No external dependencies — uses only Python stdlib (urllib, json).

The text to translate is read from stdin and sent in the HTTP POST body, so it
never appears in a URL or in process arguments. Input and response sizes are
strictly capped.

Commands:
    echo "hello" | translate.py translate --from auto --to ru
    translate.py languages
"""

import argparse
import json
import os
import select
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

HTTP_ERROR_CODES_FOR_RETRY = (429, 403, 500, 502, 503, 504)

MAX_INPUT_BYTES = 1048576
MAX_RESPONSE_BYTES = 8 * 1024 * 1024
STDIN_IDLE_TIMEOUT = 0.8
STDIN_TOTAL_TIMEOUT = 15.0

COMMON_LANGUAGES = [
    ("auto", "Auto Detect"),
    ("en", "English"),
    ("ru", "Russian"),
    ("de", "German"),
    ("fr", "French"),
    ("es", "Spanish"),
    ("ja", "Japanese"),
    ("zh-CN", "Chinese (Simplified)"),
    ("ko", "Korean"),
    ("pt", "Portuguese"),
    ("it", "Italian"),
    ("tr", "Turkish"),
    ("ar", "Arabic"),
    ("uk", "Ukrainian"),
    ("pl", "Polish"),
    ("nl", "Dutch"),
    ("hi", "Hindi"),
    ("th", "Thai"),
    ("vi", "Vietnamese"),
]

ALL_LANGUAGES = [
    ("af", "Afrikaans"), ("sq", "Albanian"), ("am", "Amharic"), ("ar", "Arabic"),
    ("hy", "Armenian"), ("az", "Azerbaijani"), ("eu", "Basque"), ("be", "Belarusian"),
    ("bn", "Bengali"), ("bs", "Bosnian"), ("bg", "Bulgarian"), ("ca", "Catalan"),
    ("ceb", "Cebuano"), ("zh-CN", "Chinese (Simplified)"), ("zh-TW", "Chinese (Traditional)"),
    ("hr", "Croatian"), ("cs", "Czech"), ("da", "Danish"), ("nl", "Dutch"),
    ("en", "English"), ("eo", "Esperanto"), ("et", "Estonian"), ("fi", "Finnish"),
    ("fr", "French"), ("gl", "Galician"), ("ka", "Georgian"), ("de", "German"),
    ("el", "Greek"), ("gu", "Gujarati"), ("ht", "Haitian Creole"), ("ha", "Hausa"),
    ("he", "Hebrew"), ("hi", "Hindi"), ("hu", "Hungarian"), ("is", "Icelandic"),
    ("id", "Indonesian"), ("ga", "Irish"), ("it", "Italian"), ("ja", "Japanese"),
    ("jv", "Javanese"), ("kn", "Kannada"), ("kk", "Kazakh"), ("km", "Khmer"),
    ("ko", "Korean"), ("ku", "Kurdish"), ("ky", "Kyrgyz"), ("lo", "Lao"),
    ("la", "Latin"), ("lv", "Latvian"), ("lt", "Lithuanian"), ("mk", "Macedonian"),
    ("ms", "Malay"), ("ml", "Malayalam"), ("mt", "Maltese"), ("mi", "Maori"),
    ("mr", "Marathi"), ("mn", "Mongolian"), ("my", "Myanmar"), ("ne", "Nepali"),
    ("no", "Norwegian"), ("ps", "Pashto"), ("fa", "Persian"), ("pl", "Polish"),
    ("pt", "Portuguese"), ("pa", "Punjabi"), ("ro", "Romanian"), ("ru", "Russian"),
    ("sr", "Serbian"), ("sn", "Shona"), ("sd", "Sindhi"), ("si", "Sinhala"),
    ("sk", "Slovak"), ("sl", "Slovenian"), ("so", "Somali"), ("es", "Spanish"),
    ("su", "Sundanese"), ("sw", "Swahili"), ("sv", "Swedish"), ("tg", "Tajik"),
    ("ta", "Tamil"), ("tt", "Tatar"), ("te", "Telugu"), ("th", "Thai"),
    ("tr", "Turkish"), ("uk", "Ukrainian"), ("ur", "Urdu"), ("ug", "Uyghur"),
    ("uz", "Uzbek"), ("vi", "Vietnamese"), ("cy", "Welsh"), ("xh", "Xhosa"),
    ("yi", "Yiddish"), ("yo", "Yoruba"), ("zu", "Zulu"),
]


def read_stdin_capped(max_bytes):
    """Read stdin up to max_bytes without relying on EOF.

    Quickshell keeps the child's stdin pipe open for the process lifetime, so
    we stop once no more data arrives for a short idle window or the cap is
    hit. Returns (bytes, truncated).
    """
    data = bytearray()
    start = time.monotonic()
    limit = max_bytes + 1
    while len(data) < limit:
        remaining = STDIN_TOTAL_TIMEOUT - (time.monotonic() - start)
        if remaining <= 0:
            break
        wait = min(STDIN_IDLE_TIMEOUT, remaining)
        ready, _, _ = select.select([sys.stdin], [], [], wait)
        if not ready:
            break
        chunk = os.read(sys.stdin.fileno(), 4096)
        if not chunk:
            break
        data += chunk
    truncated = len(data) > max_bytes
    return bytes(data[:max_bytes]), truncated


def translate_text(text, from_lang="auto", to_lang="en"):
    if not text or not text.strip():
        return {"translated": "", "from_lang": from_lang, "to_lang": to_lang}

    params = {
        "client": "dict-chrome-ex",
        "sl": from_lang,
        "tl": to_lang,
        "dt": "t",
        "q": text,
    }
    body = urllib.parse.urlencode(params).encode("utf-8")
    url = "https://translate.google.com/translate_a/single"

    headers = {
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Referer": "https://translate.google.com/",
        "Accept": "application/json, text/plain, */*",
        "Accept-Language": "en-US,en;q=0.9",
        "Content-Type": "application/x-www-form-urlencoded",
    }

    req = urllib.request.Request(url, data=body, headers=headers)

    data = None
    last_error = None
    for attempt in range(4):
        try:
            resp = urllib.request.urlopen(req, timeout=12)
            raw = resp.read(MAX_RESPONSE_BYTES + 1)
            if len(raw) > MAX_RESPONSE_BYTES:
                last_error = "Response too large"
                break
            data = json.loads(raw.decode("utf-8"))
            break
        except urllib.error.HTTPError as e:
            last_error = "HTTP Error %s: %s" % (e.code, e.reason)
            if e.code in HTTP_ERROR_CODES_FOR_RETRY and attempt < 3:
                time.sleep(1.0 * (attempt + 1))
                continue
            break
        except Exception as e:
            last_error = str(e)
            if attempt < 3:
                time.sleep(0.5 * (attempt + 1))
                continue
            break

    if data is None:
        return {"error": last_error or "Request failed", "from_lang": from_lang, "to_lang": to_lang}

    translated = ""
    detected_lang = from_lang

    if data[0]:
        translated = "".join(part[0] for part in data[0] if part[0])

    if data[2] and from_lang == "auto":
        detected_lang = data[2]

    return {
        "translated": translated,
        "from_lang": detected_lang,
        "to_lang": to_lang,
    }


def list_languages():
    langs = [{"code": c, "name": n} for c, n in ALL_LANGUAGES]
    print(json.dumps(langs))


def main():
    parser = argparse.ArgumentParser(description="Google Translate backend")
    sub = parser.add_subparsers(dest="command")

    tr = sub.add_parser("translate")
    tr.add_argument("--from", dest="from_lang", default="auto")
    tr.add_argument("--to", dest="to_lang", default="en")

    sub.add_parser("languages")

    args = parser.parse_args()

    if args.command == "translate":
        raw, truncated = read_stdin_capped(MAX_INPUT_BYTES)
        if truncated:
            result = {"error": "Input too large", "from_lang": args.from_lang, "to_lang": args.to_lang}
        else:
            result = translate_text(raw.decode("utf-8", errors="replace"), args.from_lang, args.to_lang)
        print(json.dumps(result))
    elif args.command == "languages":
        list_languages()
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()