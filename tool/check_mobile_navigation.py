"""Check the installed app using real Android gestures on an isolated emulator.

Install the normal app APK first. No application data is cleared.
Usage: python tool/check_mobile_navigation.py --serial emulator-5582 --adb <path>
"""

import argparse
import json
import re
import subprocess
import time
import xml.etree.ElementTree as ET
from pathlib import Path

PACKAGE = 'dev.zeroplayer.zero_player'


class Device:
    def __init__(self, args):
        if not args.serial.startswith('emulator-'):
            raise ValueError('Use an isolated Android emulator for this check.')
        self.command = [args.adb, '-s', args.serial]
        self.output = Path(args.output)
        self.output.mkdir(parents=True, exist_ok=True)
        self.steps = []
        size = self.adb('shell', 'wm', 'size')
        self.width, self.height = map(int, re.findall(r'(\d+)x(\d+)', size)[-1])
        assert self.adb('shell', 'settings', 'get', 'secure', 'navigation_mode').strip() == '2', 'Enable Android gesture navigation first.'

    def adb(self, *args):
        return subprocess.run(
            self.command + list(args), check=True, capture_output=True,
            text=True, encoding='utf-8', timeout=30,
        ).stdout

    def tree(self):
        self.adb('shell', 'uiautomator', 'dump', '/sdcard/zero-navigation.xml')
        return ET.fromstring(self.adb('shell', 'cat', '/sdcard/zero-navigation.xml'))

    def find(self, label, tree=None):
        if tree is None:
            tree = self.tree()
        for node in tree.iter('node'):
            value = node.get('content-desc') or node.get('text', '')
            if value == label or value.startswith(label + '\n'):
                return node
        raise AssertionError(f'Visible control missing: {label}')

    def has(self, label, tree):
        try:
            self.find(label, tree)
            return True
        except AssertionError:
            return False

    def tap(self, label):
        node = self.find(label)
        left, top, right, bottom = map(int, re.findall(r'\d+', node.get('bounds')))
        self.adb('shell', 'input', 'tap', str((left + right) // 2), str((top + bottom) // 2))
        time.sleep(.6)

    def back(self, right=False):
        start = self.width - 2 if right else 2
        end = int(self.width * (.6 if right else .4))
        y = str(self.height // 2)
        self.adb('shell', 'input', 'swipe', str(start), y, str(end), y, '400')
        time.sleep(.6)

    def scroll(self, down):
        x = str(self.width // 2)
        begin, end = (.75, .3) if down else (.3, .7)
        self.adb('shell', 'input', 'swipe', x, str(int(self.height * begin)), x, str(int(self.height * end)), '500')
        time.sleep(.8)

    def record(self, name, tree=None):
        if tree is None:
            tree = self.tree()
        ET.ElementTree(tree).write(self.output / f'{name}.xml', encoding='utf-8')
        screen = subprocess.run(
            self.command + ['exec-out', 'screencap', '-p'],
            check=True, capture_output=True, timeout=15,
        ).stdout
        (self.output / f'{name}.png').write_bytes(screen)
        if name != 'failure':
            self.steps.append(name)
        print(f'{"FAIL" if name == "failure" else "PASS"} {name}', flush=True)

    def home(self):
        tree = self.tree()
        self.find('搜索影片', tree)
        self.find('更多', tree)
        assert not self.has('退出 Zero Player？', tree)
        return tree


def prepare_home(device):
    device.adb('shell', 'am', 'start', '-n', PACKAGE + '/.MainActivity')
    for _ in range(15):
        tree = device.tree()
        if device.has('从这里开始探索', tree):
            device.tap('我知道了，开始使用')
        elif device.has('搜索影片', tree) and device.has('更多', tree):
            return
        time.sleep(.5)
    raise AssertionError('Start the normal application at the discovery page.')


def check_scrolling(device):
    device.record('01-home-system-bars', device.home())
    device.scroll(True)
    tree = device.tree()
    assert not device.has('更多', tree), 'Bottom navigation must hide while scrolling down.'
    assert not device.has('展开导航', tree), 'Floating menu must not cover phone content.'
    device.record('02-scroll-down-navigation-hidden', tree)
    device.scroll(False)
    tree = device.tree()
    device.find('更多', tree)
    device.record('03-scroll-up-navigation-visible', tree)
    device.scroll(False)
    device.tap('推荐频道')
    device.record('04-channel-popup')
    device.back()
    device.home()


def check_routes(device):
    device.tap('更多')
    device.find('收起导航')
    device.back(right=True)
    device.record('05-back-closes-drawer', device.home())
    device.tap('管理视频源')
    device.record('06-pushed-source-page')
    device.back()
    device.record('07-back-returns-from-source-page', device.home())


def check_search(device):
    device.tap('搜索')
    device.find('清空输入')
    device.record('08-search-keyboard')
    device.back()
    tree = device.tree()
    device.find('清空输入', tree)
    device.find('更多', tree)
    device.record('09-back-closes-keyboard', tree)
    device.back(right=True)
    device.record('10-back-returns-from-search', device.home())


def check_exit(device):
    device.back()
    device.find('退出 Zero Player？')
    device.record('11-root-back-confirmation')
    device.back(right=True)
    device.record('12-back-dismisses-confirmation', device.home())
    device.back()
    device.tap('继续使用')
    device.home()
    device.back()
    device.tap('退出')
    for _ in range(20):
        activity = device.adb('shell', 'dumpsys', 'activity', 'activities')
        resumed = '\n'.join(line for line in activity.splitlines() if 'ResumedActivity' in line)
        if PACKAGE not in resumed:
            device.record('13-explicit-exit')
            return
        time.sleep(.3)
    raise AssertionError('Explicit exit did not finish the activity.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--adb', default='adb')
    parser.add_argument('--output', default='build/mobile-regression/native')
    parser.add_argument('--phase', choices=['all', 'search', 'exit'], default='all')
    args = parser.parse_args()
    device = Device(args)
    result = {'serial': args.serial, 'passed': False, 'steps': device.steps}
    try:
        if args.phase == 'all':
            prepare_home(device)
            check_scrolling(device)
            check_routes(device)
        if args.phase in ['all', 'search']:
            check_search(device)
        check_exit(device)
        result['passed'] = True
    except Exception as error:
        result['error'] = str(error)
        device.record('failure')
        raise
    finally:
        (device.output / f'result-{args.phase}.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
