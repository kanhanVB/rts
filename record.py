"""录一段试玩视频：起游戏 -> gdigrab 录客户端区 -> 做几个操作 -> 出 mp4。

用法: python record.py <输出mp4> [时长秒]
"""
import ctypes
import ctypes.wintypes as wt
import subprocess
import sys
import time

GODOT = r"E:\godot\Godot_v4.7.2-stable_win64.exe"
FFMPEG = (r"C:\Users\34577\AppData\Local\Microsoft\WinGet\Packages"
          r"\Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe"
          r"\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe")
PROJ = r"E:\workbuddyspace\2026-10-14-09-48-45\rts-demo"
TITLE = "旗与铁 RTS 原型"
# 地图是随机生成的；固定种子才能"先量坐标、再录"。改种子 = 换一张图
SEED = 20261024

u = ctypes.windll.user32
try:
    ctypes.windll.shcore.SetProcessDPIAware()
except Exception:
    u.SetProcessDPIAware()


def find_hwnd(part, timeout=40.0):
    end = time.time() + timeout
    while time.time() < end:
        found = []

        @ctypes.WINFUNCTYPE(ctypes.c_bool, wt.HWND, wt.LPARAM)
        def cb(h, _l):
            n = ctypes.create_unicode_buffer(256)
            u.GetWindowTextW(h, n, 256)
            if part in n.value and u.IsWindowVisible(h):
                found.append(h)
            return True

        u.EnumWindows(cb, 0)
        if found:
            return found[0]
        time.sleep(0.3)
    return None


def client_box(h):
    r = wt.RECT()
    u.GetClientRect(h, ctypes.byref(r))
    pt = wt.POINT(0, 0)
    u.ClientToScreen(h, ctypes.byref(pt))
    return pt.x, pt.y, r.right, r.bottom


def to_screen(h, cx, cy):
    pt = wt.POINT(cx, cy)
    u.ClientToScreen(h, ctypes.byref(pt))
    return pt.x, pt.y


def move(h, cx, cy):
    u.SetCursorPos(*to_screen(h, cx, cy))


def click(h, cx, cy, right=False):
    u.SetCursorPos(*to_screen(h, cx, cy))
    time.sleep(0.05)
    if right:
        u.mouse_event(0x0008, 0, 0, 0, 0)
        u.mouse_event(0x0010, 0, 0, 0, 0)
    else:
        u.mouse_event(0x0002, 0, 0, 0, 0)
        u.mouse_event(0x0004, 0, 0, 0, 0)


def drag(h, x0, y0, x1, y1):
    u.SetCursorPos(*to_screen(h, x0, y0))
    time.sleep(0.1)
    u.mouse_event(0x0002, 0, 0, 0, 0)
    time.sleep(0.15)
    for i in range(1, 7):
        u.SetCursorPos(*to_screen(h, int(x0 + (x1 - x0) * i / 6), int(y0 + (y1 - y0) * i / 6)))
        time.sleep(0.06)
    u.mouse_event(0x0004, 0, 0, 0, 0)


def key(vk):
    u.keybd_event(vk, 0, 0, 0)
    time.sleep(0.05)
    u.keybd_event(vk, 0, 2, 0)


def hold(vk, sec):
    """按住不放：方向键推镜头就是靠按住来滚的"""
    u.keybd_event(vk, 0, 0, 0)
    time.sleep(sec)
    u.keybd_event(vk, 0, 2, 0)


def wheel(h, cx, cy, n):
    """滚轮缩放：n>0 放大（朝鼠标位置缩）"""
    u.SetCursorPos(*to_screen(h, cx, cy))
    time.sleep(0.1)
    step = 120 if n > 0 else -120
    for _ in range(abs(n)):
        u.mouse_event(0x0800, 0, 0, step, 0)
        time.sleep(0.12)


def focus(h):
    u.ShowWindow(h, 9)
    u.BringWindowToTop(h)
    try:
        u.SetForegroundWindow(h)
    except Exception:
        pass
    time.sleep(0.6)


def main():
    out = sys.argv[1]
    dur = float(sys.argv[2]) if len(sys.argv) > 2 else 45.0

    game = subprocess.Popen([GODOT, "--path", PROJ, "--", "--seed=%d" % SEED], cwd=PROJ)
    ff = None
    try:
        h = find_hwnd(TITLE)
        if h is None:
            print("NO_WINDOW")
            return
        time.sleep(13.0)         # 等加载 + 开盘镜头走完
        focus(h)
        x0, y0, w, hh = client_box(h)
        move(h, 640, 360)        # 鼠标先归中：不然贴边会滚屏

        ff = subprocess.Popen([
            FFMPEG, "-y", "-loglevel", "error",
            "-f", "gdigrab", "-framerate", "30", "-draw_mouse", "0",
            "-offset_x", str(x0), "-offset_y", str(y0),
            "-video_size", "%dx%d" % (w, hh), "-i", "desktop",
            "-t", str(dur),
            "-c:v", "libx264", "-preset", "veryfast", "-crf", "23",
            "-pix_fmt", "yuv420p", "-movflags", "+faststart",
            out,
        ])
        t0 = time.time()

        def at(sec):
            left = sec - (time.time() - t0)
            if left > 0:
                time.sleep(left)

        # ---- 脚本化的"试玩" ----
        # 镜头全程不动（动一下坐标就全废了），H 回主城 = 基准画面：
        #   矿堆 (392,215)、单棵大树 (467,150)、基地 (635,271)
        # Q = 基地命令卡第一格（造农民）、H = 选基地、空格 = 镜头跟选中单位
        at(1.5)
        key(0x48)                        # H：选中基地，镜头归位（命令卡出来）
        at(4.0)
        key(0x51)                        # Q：造一个农民
        at(6.5)
        drag(h, 120, 70, 1150, 540)      # 框选全场：农民 + 英雄
        at(8.5)
        click(h, 467, 150, right=True)   # 右键那棵大树：去砍
        at(16.0)
        drag(h, 120, 70, 1150, 540)      # 再框一次（人已经在树底下了）
        at(18.0)
        click(h, 392, 215, right=True)   # 右键矿堆：去挖（从树那边走过来，画面动）
        at(26.0)
        wheel(h, 420, 230, 3)            # 朝矿堆推近看采集
        at(31.5)
        wheel(h, 420, 230, -3)           # 拉回
        at(33.0)
        hold(0x27, 1.1)                  # 右方向键推一下镜头（露地图）
        at(35.5)
        key(0x48)                        # H：回主城收尾
        at(37.5)
        key(0x1B)                        # Esc：收起选中
        at(dur)

        if ff:
            ff.wait(timeout=dur + 60)
        print("DONE", out)
    finally:
        try:
            game.kill()
        except Exception:
            pass


main()
