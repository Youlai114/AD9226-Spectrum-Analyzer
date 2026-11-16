# -*- coding: utf-8 -*-
"""
把 frames/m0, m1, m2 里的 PPM 帧合成动画:
    spectrum_anim.gif   —— 模式 0 的循环 GIF (1280x720 全彩)
    spectrum_anim.html  —— 三模式可切换的播放器 (帧内嵌 base64)

用法: python tools/make_anim.py <frames_root> <out_dir> [fps]
"""
import base64
import glob
import io
import os
import sys

from PIL import Image

MODES = [("10 dB/div", "m0"), ("5 dB/div", "m1"), ("2 dB/div", "m2")]


def load_frames(d):
    files = sorted(glob.glob(os.path.join(d, "frame_*.ppm")))
    if not files:
        raise SystemExit("没有找到帧文件: %s" % d)
    return [Image.open(f).convert("RGB") for f in files]


def build_gif(frames, path, fps):
    base = frames[0].quantize(colors=256, method=Image.MEDIANCUT)
    qframes = [im.quantize(palette=base, dither=0) for im in frames]
    dur = int(round(1000.0 / fps))
    qframes[0].save(path, save_all=True, append_images=qframes[1:],
                    duration=dur, loop=0, optimize=True, disposal=1)
    return path


def b64png(im):
    buf = io.BytesIO()
    im.save(buf, format="PNG", optimize=True)
    return base64.b64encode(buf.getvalue()).decode("ascii")


def build_html(groups, path, fps):
    dur = int(round(1000.0 / fps))
    js_groups = []
    for imgs in groups:
        items = ",".join('"data:image/png;base64,%s"' % b64png(im) for im in imgs)
        js_groups.append("[%s]" % items)

    names = "[" + ",".join('"%s"' % n for n, _ in MODES) + "]"
    w, h = groups[0][0].size

    html = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<title>频谱分析仪 · 动态演示</title>
<style>
  html,body{margin:0;min-height:100%%;background:#05070e;color:#9fd4f0;
            font-family:-apple-system,"Segoe UI","Microsoft YaHei",sans-serif;}
  .wrap{min-height:100vh;display:flex;flex-direction:column;align-items:center;
        justify-content:center;gap:14px;padding:20px;box-sizing:border-box;}
  img{width:min(94vw,1180px);border-radius:6px;display:block;
      box-shadow:0 0 0 1px #1b2c48,0 14px 44px rgba(0,0,0,.65);}
  .bar{display:flex;align-items:center;gap:12px;font-size:13px;flex-wrap:wrap;
       justify-content:center;}
  button{background:#0f1b30;color:#9fd4f0;border:1px solid #24405f;border-radius:5px;
         padding:6px 15px;font-size:13px;cursor:pointer;letter-spacing:.5px;}
  button:hover{background:#16263f;border-color:#2f5a8c;}
  button.on{background:#12365c;border-color:#3f7fc0;color:#dff4ff;}
  input[type=range]{width:240px;accent-color:#7df9ff;}
  .tag{opacity:.55;font-size:12px;letter-spacing:.5px;}
  .sep{width:1px;height:20px;background:#1b2c48;}
</style>
</head>
<body>
<div class="wrap">
  <img id="v" alt="spectrum">
  <div class="bar">
    <button class="m on" data-m="0">10dB/div</button>
    <button class="m" data-m="1">5dB/div</button>
    <button class="m" data-m="2">2dB/div</button>
    <div class="sep"></div>
    <button id="pp">暂停</button>
    <input id="sl" type="range" min="0" max="0" value="0">
    <span id="cnt" class="tag"></span>
  </div>
  <div class="tag">1280×720 · %(w)d×%(h)d 帧 · 数据由 spec_demo_gen 实时产生（每 8 个数据帧采样 1 帧）</div>
</div>
<script>
var M=[%(groups)s], NAMES=%(names)s;
var cur=0, i=0, playing=true, D=%(dur)d;
var v=document.getElementById('v'), sl=document.getElementById('sl'),
    cnt=document.getElementById('cnt'), pp=document.getElementById('pp');
function n(){ return M[cur].length; }
function show(k){
  var L=n(); i=((k%%L)+L)%%L;
  v.src=M[cur][i]; sl.max=L-1; sl.value=i;
  cnt.textContent=NAMES[cur]+'  '+(i+1)+'/'+L;
}
setInterval(function(){ if(playing) show(i+1); }, D);
pp.onclick=function(){ playing=!playing; pp.textContent=playing?'暂停':'播放'; };
sl.oninput=function(){ show(parseInt(sl.value)); };
document.querySelectorAll('.m').forEach(function(b){
  b.onclick=function(){
    document.querySelectorAll('.m').forEach(function(x){x.classList.remove('on');});
    b.classList.add('on'); cur=parseInt(b.dataset.m); show(i);
  };
});
document.addEventListener('keydown',function(e){
  if(e.key===' '){e.preventDefault(); pp.click();}
  if(e.key==='ArrowRight') show(i+1);
  if(e.key==='ArrowLeft')  show(i-1);
  if(e.key>='1'&&e.key<='3'){ cur=parseInt(e.key)-1;
    document.querySelectorAll('.m').forEach(function(x,i2){
      x.classList.toggle('on', i2===cur); }); show(i); }
});
show(0);
</script>
</body>
</html>
""" % {"groups": ",\n".join(js_groups), "names": names, "dur": dur, "w": w, "h": h}

    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(html)
    return path


if __name__ == "__main__":
    root = sys.argv[1]
    odir = sys.argv[2] if len(sys.argv) > 2 else root
    fps = float(sys.argv[3]) if len(sys.argv) > 3 else 15.0

    groups = []
    for name, sub in MODES:
        d = os.path.join(root, sub)
        if os.path.isdir(d):
            imgs = load_frames(d)
            print("%s: %d 帧 %s" % (name, len(imgs), imgs[0].size))
            groups.append(imgs)

    g = build_gif(groups[0], os.path.join(odir, "spectrum_anim.gif"), fps)
    print("GIF  %s  %.2f MB" % (g, os.path.getsize(g) / 1048576.0))

    h = build_html(groups, os.path.join(odir, "spectrum_anim.html"), fps)
    print("HTML %s  %.2f MB" % (h, os.path.getsize(h) / 1048576.0))
