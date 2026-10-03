#!/usr/bin/env python3
"""Reproducible first Japanese demo edit. Originals are never overwritten."""
import json
import math
from pathlib import Path
import subprocess
from PIL import Image, ImageDraw, ImageFont

MARKETING = Path(__file__).resolve().parents[2]
OUT = MARKETING / 'out' / 'japanese-demo'
OUT.mkdir(parents=True, exist_ok=True)
SOURCE = MARKETING / 'assets' / 'Japanese demo' / '7.mov'
AUDIO = MARKETING / 'assets' / 'audio' / 'JP1.mov'
FONT = '/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc'

# Phone recording is BT.2020 HLG. Convert its decoded RGB through a 3D LUT
# to an SDR BT.709 display; merely relabeling HDR would wash out the footage.
def hlg(v):
    return v*v/3 if v <= .5 else (math.exp((v-.55991073)/.17883277)+.28466892)/12

def sdr(rgb):
    r,g,b = map(hlg, rgb)
    lum = max(1e-10, .2627*r+.6780*g+.0593*b)
    gain = 7.0 * lum**.2
    r,g,b = (1.660491*r-.587641*g-.072850*b,
             -.124550*r+1.132900*g-.008349*b,
             -.018151*r-.100579*g+1.118730*b)
    r,g,b = (max(0,v*gain) for v in (r,g,b))
    lum = max(1e-10, .2126*r+.7152*g+.0722*b)
    mapped = lum*(1+lum/16)/(1+lum)
    def encode(v):
        v = min(1,max(0,v*mapped/lum))
        return 4.5*v if v < .018 else 1.099*v**.45-.099
    return tuple(map(encode,(r,g,b)))

lut = OUT / 'hlg-to-sdr.cube'
with lut.open('w') as f:
    f.write('TITLE "Phone HLG to SDR"\nLUT_3D_SIZE 33\nDOMAIN_MIN 0 0 0\nDOMAIN_MAX 1 1 1\n')
    for b in range(33):
        for g in range(33):
            for r in range(33):
                f.write(' '.join(f'{v:.7f}' for v in sdr((r/32,g/32,b/32)))+'\n')

def title_image(name, lines):
    im = Image.new('RGBA',(1080,1920))
    draw = ImageDraw.Draw(im)
    for text,y,size in lines:
        font = ImageFont.truetype(FONT,size)
        left,top,right,bottom = draw.textbbox((540,y),text,font=font,anchor='mt')
        draw.rounded_rectangle((left-24,top-16,right+24,bottom+16),
                               radius=20,fill=(0,0,0,240))
        draw.text((540,y),text,font=font,anchor='mt',fill='white')
    path = OUT / name
    im.save(path)
    return path

hook = title_image('07-hook.png',[
    ('部長への返信',760,68),('これ使ったら簡単すぎて草',848,60)])
brand = title_image('07-product.png',[
    ('Slackのまま、AIで返信。',1736,45),('敬語ボタン',1806,38)])

# Source seconds were checked against sampled action frames.
segments = [
    {'name':'setup','from':0,'to':1/30,'speed':1,'hold':1.4666667},
    {'name':'typing','from':0,'to':12.2,'speed':2,'hold':0},
    {'name':'read_input','from':12.2,'to':13.4,'speed':1,'hold':0},
    {'name':'button_and_generation','from':13.4,'to':14.7,'speed':1/.75,'hold':0},
    {'name':'result_card','from':14.7,'to':16.8,'speed':1,'hold':1.2},
    {'name':'inserted_reply','from':16.8,'to':18.4,'speed':1,'hold':2},
]
duration = sum((s['to']-s['from'])/s['speed']+s['hold'] for s in segments)
graph = [f'[0:v]format=rgb48le,lut3d=file={lut}:interp=tetrahedral,format=yuv420p,fps=30,split=6'+''.join(f'[s{i}]' for i in range(6))]
for i,s in enumerate(segments):
    graph.append(f"[s{i}]trim=start={s['from']}:end={s['to']},setpts=(PTS-STARTPTS)/{s['speed']},tpad=stop_mode=clone:stop_duration={s['hold']},fps=30[v{i}]")
graph.append(''.join(f'[v{i}]' for i in range(6))+'concat=n=6:v=1:a=0[cut]')
graph.append('[cut][2:v]overlay=0:0:format=auto[titled]')
graph.append(f"[titled][3:v]overlay=0:0:format=auto:enable='gte(t,{duration-3.4})',format=yuv420p,sidedata=mode=delete,setparams=range=limited:color_primaries=bt709:color_trc=bt709:colorspace=bt709[v]")
graph.append(f'[1:a]atrim=start=0:end={duration},asetpts=PTS-STARTPTS,loudnorm=I=-16:TP=-1.5:LRA=11,afade=t=out:st={duration-.3}:d=0.3[a]')
filter_file = OUT / '07-filter.txt'
filter_file.write_text(';\n'.join(graph))
output = OUT / '07-preview-v3.mp4'
subprocess.run(['ffmpeg','-hide_banner','-loglevel','warning','-y','-i',str(SOURCE),
    '-i',str(AUDIO),'-loop','1','-i',str(hook),'-loop','1','-i',str(brand),
    '-filter_complex_script',str(filter_file),'-map','[v]','-map','[a]',
    '-t',str(duration),'-r','30','-c:v','libx264','-preset','medium','-crf','18',
    '-pix_fmt','yuv420p','-c:a','aac','-b:a','192k',
    '-color_primaries','bt709','-color_trc','bt709','-colorspace','bt709',
    '-map_metadata','-1','-movflags','+faststart',str(output)],check=True)
(OUT/'07-edit.json').write_text(json.dumps({'source':str(SOURCE),'audio':str(AUDIO),
    'hook':['部長への返信','これ使ったら簡単すぎて草'],'segments':segments,
    'duration':duration,'original_audio_removed':True,'output':str(output)},ensure_ascii=False,indent=2)+'\n')
print(output)
