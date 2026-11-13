"""Inventory public Legado releases without executing or following source rules."""

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from html import unescape
from http.client import HTTPException, HTTPSConnection
import json
from pathlib import Path
import re
from threading import local
import time
from urllib.error import HTTPError
from urllib.parse import urljoin, urlsplit, urlunsplit


BASE = "https://www.yckceo.com/yuedu/"
SECTIONS = ("rss", "rsss", "shuyuan", "shuyuans")
MAX_BYTES = 64 * 1024 * 1024
HOST = "www.yckceo.com"
WORKER = local()


def repository_host(parts):
    if parts.scheme == "https" and parts.netloc == HOST:
        return HOST
    if (parts.scheme == "https"
        and parts.netloc in {"gcore.jsdelivr.net", "cdn.jsdelivr.net", "fastly.jsdelivr.net"}
        and re.fullmatch(r"/gh/mumuceo/file\d+(?:@[\w.-]+)?/[\w/.-]+\.json", parts.path)
        and ".." not in parts.path):
        return "fastly.jsdelivr.net"
    raise ValueError("URL leaves source repository and its release CDN")


def request(url):
    for _ in range(4):
        parts = urlsplit(url)
        host = repository_host(parts)
        if not hasattr(WORKER, "connections"):
            WORKER.connections = {}
        if host not in WORKER.connections:
            WORKER.connections[host] = HTTPSConnection(host, timeout=12)
        connection = WORKER.connections[host]
        WORKER.connection = connection
        connection.request("GET", urlunsplit(("", "", parts.path, parts.query, "")),
                           headers={"User-Agent": "ZeroPlayer-SourceAudit/1.0"})
        with connection.getresponse() as response:
            payload = response.read(MAX_BYTES + 1)
            if len(payload) > MAX_BYTES:
                connection.close()
                raise ValueError("response exceeds 64 MiB")
            if response.status in {301, 302, 303, 307, 308}:
                url = urljoin(url, response.getheader("Location", ""))
                continue
            if response.status != 200:
                raise HTTPError(url, response.status, response.reason, response.headers, None)
            return payload.decode("utf-8-sig")
    raise ValueError("too many repository redirects")


def fetch(url):
    for attempt in range(3):
        try:
            return request(url)
        except (OSError, HTTPException) as error:
            WORKER.connection.close()
            if attempt == 2 or (
                isinstance(error, HTTPError)
                and error.code not in {408, 429, 500, 502, 503, 504}
            ):
                raise
            retry_after = error.headers.get("Retry-After", "") if isinstance(
                error, HTTPError
            ) else ""
            time.sleep(min(int(retry_after), 60) if retry_after.isdigit() else 2**attempt)


def save(path, data):
    pending = path.with_suffix(".pending")
    pending.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    pending.replace(path)


def index_page(section, page, folder):
    path = folder / f"{section}-page-{page}.json"
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8"))
    url = f"{BASE}{section}/index.html" + (f"?page={page}" if page > 1 else "")
    body = fetch(url)
    total = re.search(r"共有\s+(\d+)\s+条数据", body)
    entries = {
        ident: unescape(re.sub(r"<[^>]*>", "", label)).strip()
        for ident, label in re.findall(
            rf'<h2>\s*<a href="/yuedu/{section}/content/id/(\d+)\.html"[^>]*>(.*?)</a>',
            body,
            flags=re.S,
        )
    }
    if not total or not entries:
        raise ValueError(f"invalid index page {url}")
    count = int(total[1])
    pages = max(
        (int(value) for value in re.findall(
            rf'{section}/index\.html\?page=(\d+)', body
        )),
        default=1,
    )
    result = {"total": count, "pages": max(page, pages), "entries": entries}
    save(path, result)
    return result


def records(payload):
    data = json.loads(payload)
    values = data if isinstance(data, list) else [data]
    if not values or not all(isinstance(value, dict) for value in values):
        raise ValueError("empty or unsupported source JSON")
    return values


def detail(section, ident, label, folder):
    path = folder / f"{section}-{ident}.json"
    url = f"{BASE}{section}/content/id/{ident}.html"
    body = fetch(url)
    download = re.search(r'<input\b[^>]*\bid="jsonurl"[^>]*\bvalue="([^"]+)"', body)
    embedded = re.search(r'<pre\b[^>]*\bid="jsonpre"[^>]*>(.*?)</pre>', body, re.S)
    result = {"page": url, "label": label}
    if download:
        result["download"] = urljoin(url, unescape(download[1]))
    if embedded:
        try:
            result["records"] = records(unescape(embedded[1]))
        except ValueError:
            pass
    if "records" not in result:
        try:
            result["records"] = records(fetch(result["download"]))
        except (OSError, HTTPException, ValueError, KeyError) as error:
            members = []
            for row in re.findall(r"<tr>(.*?)</tr>", body, re.S):
                cells = [
                    unescape(re.sub(r"<[^>]*>", "", cell)).strip()
                    for cell in re.findall(r"<td[^>]*>(.*?)</td>", row, re.S)
                ]
                if len(cells) == 2:
                    members.append(cells)
            if not members:
                raise ValueError(f"no source data ({error})") from error
            result.update(members=members, download_error=str(error))
    save(path, result)
    return len(result.get("records", []))


def enumerate_section(section, indexes, pool):
    first = index_page(section, 1, indexes)
    entries = dict(first["entries"])
    pages = range(2, first["pages"] + 1)
    for page in pool.map(lambda number: index_page(section, number, indexes), pages):
        entries.update(page["entries"])
    print(f"{section}: {len(entries)}/{first['total']} entries, "
          f"{first['pages']} pages", flush=True)
    return entries, {"listed": first["total"], "seen": len(entries), "pages": first["pages"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="ignored cache directory for one snapshot")
    parser.add_argument("--workers", type=int, default=8, choices=range(1, 17))
    parser.add_argument("--sections", nargs="+", choices=SECTIONS, default=SECTIONS)
    parser.add_argument("--retry-downloads", action="store_true",
                        help="retry collection downloads previously recorded with only member metadata")
    args = parser.parse_args()
    indexes = args.output / "index"
    details = args.output / "details"
    indexes.mkdir(parents=True, exist_ok=True)
    details.mkdir(exist_ok=True)
    summary = {}
    failures = {}
    with ThreadPoolExecutor(args.workers) as pool:
        inventory = {}
        for section in args.sections:
            inventory[section], summary[section] = enumerate_section(section, indexes, pool)
        jobs = {
            pool.submit(detail, section, ident, label, details): f"{section}-{ident}"
            for section, entries in inventory.items()
            for ident, label in entries.items()
            if needs_detail(details / f"{section}-{ident}.json", args.retry_downloads)
        }
        for index, job in enumerate(as_completed(jobs), 1):
            try:
                job.result()
            except (OSError, HTTPException, ValueError) as error:
                failures[jobs[job]] = str(error)
            if index % 100 == 0 or index == len(jobs):
                print(f"details: {index}/{len(jobs)}, failed: {len(failures)}", flush=True)
    save(args.output / "crawl.json", {"sections": summary, "failures": failures})
    if failures or any(row["listed"] != row["seen"] for row in summary.values()):
        raise SystemExit("Incomplete snapshot; see crawl.json and retry with the same directory.")


def needs_detail(path, retry_downloads):
    return not path.exists() or (
        retry_downloads and "records" not in json.loads(path.read_bytes())
    )


if __name__ == "__main__":
    main()
