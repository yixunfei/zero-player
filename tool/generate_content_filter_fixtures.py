"""Generate synthetic filter fixtures; requires Pillow and an FFmpeg binary."""
import argparse
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


def render_frame(path, text, color, font_path):
    image = Image.new('RGB', (640, 360), color)
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype(str(font_path), 66)
    bounds = draw.textbbox((0, 0), text, font=font)
    width = bounds[2] - bounds[0]
    draw.text(((640 - width) / 2, 115), text, font=font, fill='white')
    image.save(path)


def run(ffmpeg, args):
    subprocess.run([str(ffmpeg), '-hide_banner', '-loglevel', 'error', '-y', *args],
                   check=True)


def encode(ffmpeg, folder, video, durations):
    inputs = []
    for name, duration in zip(('normal.png', 'advert.png', 'resume.png'), durations):
        inputs.extend(['-loop', '1', '-framerate', '25', '-t', str(duration),
                       '-i', str(folder / name)])
    run(ffmpeg, [*inputs,
        '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=48000',
        '-filter_complex', '[0:v][1:v][2:v]concat=n=3:v=1:a=0[video]',
        '-map', '[video]', '-map', '3:a', '-t', str(sum(durations)),
        '-r', '25', '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p',
        '-g', '25', '-keyint_min', '25', '-sc_threshold', '0',
        '-c:a', 'aac', '-b:a', '96k', '-movflags', '+faststart', str(video)])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--ffmpeg', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = root / 'test_support' / 'generated' / 'content_filter'
    output.mkdir(parents=True, exist_ok=True)
    font = root / 'assets' / 'fonts' / 'NotoSansSC.ttf'
    frames = [('normal.png', '正常影片', '#164b38'),
              ('advert.png', '澳门新葡京赌场', '#b00020'),
              ('resume.png', '继续观看影片', '#164b38')]
    for name, text, color in frames:
        render_frame(output / name, text, color, font)
    video = output / 'sample.mp4'
    encode(args.ffmpeg, output, video, (4, 8, 4))
    encode(args.ffmpeg, output, output / 'long.mp4', (16, 8, 24))
    run(args.ffmpeg, ['-i', str(video), '-c', 'copy', '-f', 'flv', str(output / 'sample.flv')])
    hls = output / 'hls'
    hls.mkdir(exist_ok=True)
    run(args.ffmpeg, ['-i', str(video), '-c', 'copy', '-hls_time', '4',
        '-hls_playlist_type', 'vod', '-hls_segment_filename', str(hls / 'seg_%03d.ts'),
        str(hls / 'index.m3u8')])
    speech = output / 'speech.wav'
    if speech.exists():
        run(args.ffmpeg, ['-i', str(video), '-i', str(speech),
            '-filter_complex', '[1:a]atrim=duration=8,asetpts=PTS-STARTPTS,adelay=4000,apad[a]',
            '-map', '0:v', '-map', '[a]', '-c:v', 'copy', '-c:a', 'aac', '-t', '16',
            str(output / 'voice.mp4')])
    print(output)


if __name__ == '__main__':
    main()
