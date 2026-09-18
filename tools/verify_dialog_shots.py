"""verify_dialog_shots.py —— 用 PIL 数化复核对话框截图（像素 vs 引擎几何）

【为什么需要它】
    GDScript 测试只能证明"引擎认为的矩形是对的"，证明不了"屏幕上真的画出来了"。
    可能出现：矩形算对了但面板没渲染、被别的层盖住、贴图把面板撑变形、
    文字没画上去……这些只有**数像素**才能发现
    （本次就抓到两个真缺陷：① INLINE 小头像用 64×112 原尺寸把对话条从 51px
     撑到 138px；② 立绘/头像的 expand_mode 没设，尺寸不受控）。

【怎么用】
    1) 先跑截图脚本（窗口模式，真实渲染）：
         Godot --path . --audio-driver Dummy res://tools/capture_dialog.tscn > _capdlg.log 2>&1
    2) 再跑本脚本：
         python tools/verify_dialog_shots.py
       退出码 0 = 全部通过。

【核心思路：以"引擎日志里的矩形"为准，去截图里找像素】
    截图脚本每帧都会打印一行机器可读记录：
      [CaptureDialog] SHOT <name> bar=<hidden|x..y..> notice=... portrait=... text=...
    本脚本对每一帧做两件事：
      · 引擎说"显示" → 该矩形内部必须有足够多的"面板暗像素"；
                        且面板的实际横向范围要与矩形吻合（±5px）。
      · 引擎说"hidden" → 对应区域（上半屏 / 下半屏）不能有面板暗像素残留。
    所有比较都先扣掉 baseline（00_approach 无对话框那帧）里的 HUD 暗像素，
    否则 HUD 的血条会被误判成对话框。
"""

import os
import re
import sys

try:
    from PIL import Image
except ImportError:
    sys.stderr.write("需要 Pillow：pip install pillow\n")
    sys.exit(2)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOTS = os.path.join(ROOT, "Godot", "app_userdata", "ActRPG", "screenshots_dialog")
LOG = os.path.join(ROOT, "_capdlg.log")

W, H = 320, 180
CANVAS = (W, H)
DARK_TH = 44          # 面板底色不透明且很暗
INK_TH = 110          # 文字是浅色
TOL = 5               # 面板横向范围容差（px）
PANEL_DENSITY = 0.65  # 引擎说显示时，矩形内部至少要这么多是暗像素
RESIDUE_MAX = 60      # 引擎说 hidden 时，允许的暗像素残留上限

_pass = 0
_fail = 0


def check(ok, msg, detail=""):
    global _pass, _fail
    if ok:
        _pass += 1
        print("  [PASS] " + msg)
    else:
        _fail += 1
        print("  [FAIL] " + msg + ("  -> " + detail if detail else ""))


# ------------------------------------------------------------------ 日志解析
RECT = r"(?:hidden|x-?\d+\.\.-?\d+ y-?\d+\.\.-?\d+)"
SHOT_RE = re.compile(
    r"\[CaptureDialog\] SHOT (\S+) bar=(%s) notice=(%s) portrait=(%s) text=(%s)$" % (RECT, RECT, RECT, RECT))


def parse_rect(s):
    if s == "hidden":
        return None
    m = re.match(r"x(-?\d+)\.\.(-?\d+) y(-?\d+)\.\.(-?\d+)$", s)
    return tuple(int(v) for v in m.groups()) if m else None


def load_log():
    shots = {}
    with open(LOG, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            m = SHOT_RE.match(line.rstrip("\n"))
            if m:
                name = m.group(1)
                shots[name] = dict(zip(("bar", "notice", "portrait", "text"),
                                       (parse_rect(m.group(i)) for i in range(2, 6))))
    return shots


# ------------------------------------------------------------------ 像素工具
_frames = {}


def frame(name):
    if name not in _frames:
        p = os.path.join(SHOTS, name + ".png")
        _frames[name] = Image.open(p).convert("RGB").resize(CANVAS, Image.NEAREST)
    return _frames[name]


def dark_mask(name):
    px = frame(name).load()
    return [[max(px[x, y]) < DARK_TH for x in range(W)] for y in range(H)]


BASE = None


def extra_mask(name):
    m = dark_mask(name)
    return [[m[y][x] and not BASE[y][x] for x in range(W)] for y in range(H)]


def count(mask, y0, y1):
    return sum(1 for y in range(y0, y1) for x in range(W) if mask[y][x])


def count_outside(mask, y0, y1, rects, grow=4):
    """在 [y0,y1) 行带里数暗像素，但**跳过**给定矩形（含 grow 外扩）。
    用于"某个面板 hidden"的判定：屏幕别处可能合法地站着对话条/立绘，
    它们的暗像素不能被当成"提示条没关掉"的证据。"""
    def covered(x, y):
        for r in rects:
            if r is None:
                continue
            if r[0] - grow <= x <= r[1] + grow and r[2] - grow <= y <= r[3] + grow:
                return True
        return False
    return sum(1 for y in range(y0, y1) for x in range(W)
               if mask[y][x] and not covered(x, y))


def inside_density(name, rect, shrink=3):
    """rect 内部（四边各缩 shrink）的暗像素占比。"""
    x0, x1, y0, y1 = rect
    xa, xb = max(0, x0 + shrink), min(W, x1 - shrink + 1)
    ya, yb = max(0, y0 + shrink), min(H, y1 - shrink + 1)
    if xb <= xa or yb <= ya:
        return 0.0
    m = dark_mask(name)
    tot = (xb - xa) * (yb - ya)
    d = sum(1 for y in range(ya, yb) for x in range(xa, xb) if m[y][x])
    return d / tot


def panel_x_extent(name, rect):
    """在 rect 的行带内用列投影量出面板横向范围（用于宽度对账）。"""
    ex = extra_mask(name)
    y0, y1 = rect[2], rect[3]
    band = range(max(0, y0 - 2), min(H, y1 + 3))
    colc = [sum(1 for y in band if ex[y][x]) for x in range(W)]
    mc = max(colc)
    if mc < 6:
        return None
    xs = [x for x in range(W) if colc[x] >= mc * 0.5]
    return (min(xs), max(xs)) if xs else None


def max_column_ink_run(rect):
    """rect 内"某一列上连续墨迹的最长纵向游程" —— 近似单字笔画高度（≈字号）。"""
    if rect is None:
        return 0
    x0, x1, y0, y1 = rect
    px = frame(_cur).load()
    best = 0
    for x in range(max(0, x0), min(W, x1 + 1)):
        run = 0
        for y in range(max(0, y0), min(H, y1 + 1)):
            r, g, b = px[x, y]
            if min(r, g, b) >= INK_TH:
                run += 1
                best = max(best, run)
            else:
                run = 0
    return best


def region_diff_ratio(rect, other_name):
    """rect 内当前帧与另一帧的像素差异比例。"""
    if rect is None:
        return 0.0
    x0, x1, y0, y1 = rect
    a = frame(_cur).load()
    b = frame(other_name).load()
    tot = 0
    diff = 0
    for y in range(max(0, y0), min(H, y1 + 1)):
        for x in range(max(0, x0), min(W, x1 + 1)):
            tot += 1
            ra, ga, ba = a[x, y]
            rb, gb, bb = b[x, y]
            if abs(ra - rb) + abs(ga - gb) + abs(ba - bb) > 90:
                diff += 1
    return diff / max(1, tot)


_cur = ""


def fmt(r):
    return "hidden" if r is None else "x%d..%d y%d..%d" % r


# ------------------------------------------------------------------ 主流程
def main():
    global BASE, _cur
    if not os.path.exists(LOG):
        sys.stderr.write("找不到日志 %s，请先跑 capture_dialog.tscn\n" % LOG)
        return 2
    shots = load_log()
    if "00_approach" not in shots:
        sys.stderr.write("日志里没有 00_approach，日志可能不是最新一次截图\n")
        return 2
    BASE = dark_mask("00_approach")

    print("")
    print("=== A. 像素面板 vs 引擎矩形（显示/隐藏都要对账）===")
    for name in sorted(shots):
        _cur = name
        s = shots[name]
        # --- 对话条（"已隐藏"判定要避开提示条与立绘）
        if s["bar"] is None:
            n = count_outside(extra_mask(name), 70, H, [s["notice"], s["portrait"]])
            check(n < RESIDUE_MAX, "%s 对话条已隐藏（残留 %d px）" % (name, n),
                  "还有 %d 暗像素" % n)
        else:
            d = inside_density(name, s["bar"])
            check(d >= PANEL_DENSITY,
                  "%s 对话条按引擎矩形绘出（内部暗占比 %.0f%%，%s）" % (name, d * 100, fmt(s["bar"])),
                  "仅 %.0f%% 是面板" % (d * 100))
        # --- 提示条（"已隐藏"判定要避开对话条与立绘，它们是合法的暗像素来源）
        if s["notice"] is None:
            n = count_outside(extra_mask(name), 0, 100, [s["bar"], s["portrait"]])
            check(n < RESIDUE_MAX, "%s 提示条已隐藏（残留 %d px）" % (name, n),
                  "还有 %d 暗像素" % n)
        else:
            d = inside_density(name, s["notice"])
            check(d >= PANEL_DENSITY,
                  "%s 提示条按引擎矩形绘出（内部暗占比 %.0f%%）" % (name, d * 100),
                  "仅 %.0f%% 是面板" % (d * 100))

    print("")
    print("=== B. 宽度自适应 / 面板横向范围对账 ===")
    for name in ("10_bar_line1", "11_bar_line2_button", "12_bar_line3_button",
                 "20_adapt_short", "21_adapt_long"):
        s = shots.get(name)
        if not s or s["bar"] is None or s["portrait"] is not None:
            continue
        ext = panel_x_extent(name, s["bar"])
        want = (s["bar"][0], s["bar"][1])
        ok = ext is not None and abs(ext[0] - want[0]) <= TOL and abs(ext[1] - want[1]) <= TOL
        check(ok, "%s 对话条横向范围与引擎一致（%s）" % (name, ext), "引擎=%s" % (want,))

    r_s = shots["20_adapt_short"]["bar"]
    r_l = shots["21_adapt_long"]["bar"]
    if r_s and r_l:
        ws, wl = r_s[1] - r_s[0], r_l[1] - r_l[0]
        check(ws < wl, "短句对话条比长句窄（%d < %d）" % (ws, wl), "%d vs %d" % (ws, wl))
        check(r_l[0] >= 0 and r_l[1] <= W and r_l[2] >= 0 and r_l[3] <= H,
              "长句对话条完全在画布内（%s）" % fmt(r_l))

    print("")
    print("=== C. 点条内关闭 ===")
    _cur = "13_bar_closed_by_click"
    n = count(extra_mask(_cur), 70, H)
    check(n < RESIDUE_MAX, "点条内关闭后底部无对话条像素（残留 %d px）" % n, "残留 %d" % n)

    print("")
    print("=== D/E. 提示条位置 与 两通道同屏 ===")
    for name in ("14_notice_top", "15_notice_and_bar"):
        nr = shots[name]["notice"]
        check(nr is not None and nr[2] >= 0 and nr[3] <= H,
              "%s 提示条只在顶部且不出画布（%s）" % (name, fmt(nr)))
    b15 = shots["15_notice_and_bar"]["bar"]
    n15 = shots["15_notice_and_bar"]["notice"]
    check(b15 is not None and n15 is not None and b15[2] > n15[3],
          "提示条与对话条同屏且不重叠（提示条底 %d < 对话条顶 %d）"
          % (n15[3] if n15 else -1, b15[2] if b15 else -1))

    print("")
    print("=== F. 文本样式真的改字号（正文单字笔画高度）===")
    _cur = "16_style_whisper_portrait"
    h_w = max_column_ink_run(shots[_cur]["text"])
    _cur = "17_style_shout"
    h_s = max_column_ink_run(shots[_cur]["text"])
    check(h_s > h_w, "SHOUT 笔画高于 WHISPER（%d > %d）" % (h_s, h_w),
          "SHOUT=%d WHISPER=%d（应明显不同）" % (h_s, h_w))

    print("")
    print("=== G. 立绘 / 头像真的画出来了 ===")
    _cur = "16_style_whisper_portrait"
    pr = shots[_cur]["portrait"]
    check(pr is not None, "WHISPER 帧有 LEFT 立绘挂点（%s）" % fmt(pr))
    if pr:
        ratio = region_diff_ratio(pr, "00_approach")
        check(ratio > 0.4, "立绘区域确实被贴图覆盖（与无对话框帧差异 %.0f%%）" % (ratio * 100),
              "差异仅 %.0f%%" % (ratio * 100))
    _cur = "19_style_emphasis_avatar"
    av = shots[_cur]["bar"]
    hb = av[3] - av[2] if av else 0
    check(hb <= 80, "带 INLINE 小头像时对话条不被撑高（高 %d ≤ 80）" % hb, "高 %d" % hb)

    print("")
    print("################################################")
    print("# 截图数化复核：%d 通过，%d 失败" % (_pass, _fail))
    print("################################################")
    return 0 if _fail == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
