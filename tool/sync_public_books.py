"""Refresh public bibliographic snapshots, never automated checkout or site search scraping.

Gutenberg uses its expressly permitted machine-readable catalog. DOAB uses OAI-PMH.
Haodoo uses public category pages; only metadata and original-site links are bundled.
"""
import argparse
import csv
import gzip
import html
import io
import json
import re
import time
from pathlib import Path
from urllib.parse import urljoin, urlencode
from urllib.request import urlopen
from xml.etree import ElementTree as ET


def fetch(url):
    with urlopen(url, timeout=40) as response:
        data = response.read(32 * 1024 * 1024 + 1)
        if len(data) > 32 * 1024 * 1024:
            raise ValueError('Catalog response too large')
        return data


def gutenberg():
    raw = fetch('https://www.gutenberg.org/cache/epub/feeds/pg_catalog.csv.gz')
    for row in csv.DictReader(io.StringIO(gzip.decompress(raw).decode('utf-8-sig'))):
        if row['Type'] != 'Text':
            continue
        identifier = row['Text#']
        yield dict(source='Gutenberg', title=row['Title'], author=row['Authors'],
                   language=row['Language'], version=row['Issued'], category=row['Bookshelves'],
                   license='作品权利以原站每书声明为准；书目元数据为公有领域',
                   url=f'https://www.gutenberg.org/ebooks/{identifier}',
                   download=f'https://www.gutenberg.org/cache/epub/{identifier}/pg{identifier}-images-3.epub')


def doab(pages):
    params = dict(verb='ListRecords', metadataPrefix='oai_dc')
    for _ in range(pages):
        root = ET.fromstring(fetch('https://directory.doabooks.org/oai/request?' + urlencode(params)))
        for record in root.findall('.//{*}record'):
            dc = record.find('.//{http://www.openarchives.org/OAI/2.0/oai_dc/}dc')
            if dc is None:
                continue
            def field(name):
                return '; '.join(e.text or '' for e in dc.findall('{*}' + name))
            urls = [e.text for e in dc.findall('{*}identifier') if (e.text or '').startswith('http')]
            if urls:
                yield dict(source='DOAB', title=field('title'), author=field('creator'),
                           translator=field('contributor'), language=field('language'),
                           version=field('date'), license=field('rights'), category=field('subject'),
                           url=urls[-1].replace('http://', 'https://'))
        token = root.find('.//{*}resumptionToken')
        if token is None or not token.text:
            break
        params = dict(verb='ListRecords', resumptionToken=token.text)
        time.sleep(2)


def haodoo(url, source):
    text = fetch(url).decode('utf-8')
    for address, label in re.findall(r'<a[^>]+href=["\']([^"\']+)["\'][^>]*>(.*?)</a>', text, re.S):
        label = html.unescape(re.sub('<[^>]+>', '', label)).strip()
        address = html.unescape(address)
        if source == '好读':
            if not ('M=book&' in address or 'M=Share&' in address):
                continue
        elif '好讀新書：' not in label or '?p=' not in address:
            continue
        label = label.split('：', 1)[-1]
        author, title = label.split('【', 1) if '【' in label else ('', label)
        yield dict(source=source, title=title.strip('【】《》'), author=author,
                   language='zh-Hant', category='出版图书', url=urljoin(url, address),
                   license='原站逐书说明；原站领取后手动导入')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--doab-pages', type=int, default=3)
    parser.add_argument('--output', type=Path, default=Path('assets/catalogs/books/public.json.gz'))
    args = parser.parse_args()
    rows = list(gutenberg()) + list(doab(max(1, min(args.doab_pages, 10))))
    for category in ['100-1', 'wisdom', 'history', 'martial', 'mystery', 'romance', 'scifi', 'fiction']:
        rows.extend(haodoo(f'https://haodoo.net/?M=hd&P={category}', '好读'))
    rows.extend(haodoo('https://haodoo.org/?' + urlencode({'s': '好讀新書'}), '好读二代'))
    rows.append(dict(source='书栈网', title='Docker 从入门到实践', author='Docker — 从入门到实践项目',
                     language='zh', version='1.10', license='以本书版权声明为准', category='技术图书',
                     url='https://www.bookstack.cn/books/docker_practice-1.10-zh'))
    unique = {r['url']: r for r in rows if r['title']}
    assert set(r['source'] for r in unique.values()) == {'Gutenberg', 'DOAB', '好读', '好读二代', '书栈网'}, 'A catalog is missing; keep the previous snapshot'
    args.output.write_bytes(gzip.compress(json.dumps(list(unique.values()), ensure_ascii=False, separators=(',', ':')).encode(), mtime=0))
    from collections import Counter
    print(dict(Counter(row['source'] for row in unique.values())))


if __name__ == '__main__':
    main()
