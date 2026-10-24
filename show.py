"""录一段"轻 RTS 防线"演示：游戏自己演（--showcase），这个脚本只负责开机、录屏、收尾。

游戏里那条脚本会：路口盖兵营 -> 出 6 个兵自己走过去站好 -> 一只只放怪来撞 ->
最后把集结点往前挪，整队跟着搬。人不用动手，鼠标不用碰（碰了反而会被贴边滚屏带跑镜头）。

用法: python show.py <输出mp4> [时长秒]
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
SEED = 20261024

u = ctypes.windll.user32
try:
    ctypes.windll.shcore.SetProcessDPIAware()
except Exception:
    u.SetProcessDPIAware()


def find_hwnd(part, timeout=45.0):
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
    dur = float(sys.argv[2]) if len(sys.argv) > 2 else 52.0

    game = subprocess.Popen(
        [GODOT, "--path", PROJ, "--", "--showcase", "--nofog", "--seed=%d" % SEED],
        cwd=PROJ)
    ff = None
    try:
        h = find_hwnd(TITLE)
        if h is None:
            print("NO_WINDOW")
            return
        time.sleep(4.5)          # 窗口出来后再等场景初始化 + 贴图载入
        focus(h)
        x0, y0, w, hh = client_box(h)
        # 鼠标挪到画面正中：贴边会自动滚镜头，演示画面就跑了
        u.SetCursorPos(x0 + w // 2, y0 + hh // 2)

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
        ff.wait(timeout=dur + 90)
        print("DONE", out)
    finally:
        try:
            game.kill()
        except Exception:
            pass


main()
