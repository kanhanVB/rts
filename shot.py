"""启动旗与铁并截图（1280x720 窗口内 1:1 抓客户端区）。

用法: python shot.py <等待秒数> <输出文件名> [--box x0,y0,x1,y1] [--right x,y]
--box  : 拖框选择（屏幕像素，相对窗口客户区）
--right: 在某像素点右键一次（先框选再右键 = 指派交货点）
"""
import ctypes
import ctypes.wintypes as wt
import subprocess
import sys
import time
from PIL import ImageGrab

GODOT = r"E:\godot\Godot_v4.7.2-stable_win64.exe"
PROJ = r"E:\workbuddyspace\2026-10-14-09-48-45\rts-demo"
TITLE = "旗与铁 RTS 原型"

u = ctypes.windll.user32
try:
    ctypes.windll.shcore.SetProcessDPIAware()
except Exception:
    u.SetProcessDPIAware()


def find_hwnd(title_part, timeout=40.0):
    end = time.time() + timeout
    while time.time() < end:
        found = []

        @ctypes.WINFUNCTYPE(ctypes.c_bool, wt.HWND, wt.LPARAM)
        def cb(h, _l):
            n = ctypes.create_unicode_buffer(256)
            u.GetWindowTextW(h, n, 256)
            if title_part in n.value:
                found.append(h)
            return True

        u.EnumWindows(cb, 0)
        if found:
            return found[0]
        time.sleep(0.3)
    return None


def client_rect(h):
    r = wt.RECT()
    u.GetClientRect(h, ctypes.byref(r))
    pt = wt.POINT(r.left, r.top)
    u.ClientToScreen(h, ctypes.byref(pt))
    return pt.x, pt.y, pt.x + r.right, pt.y + r.bottom


def click(h, cx, cy, right=False):
    r = wt.RECT()
    u.GetClientRect(h, ctypes.byref(r))
    pt = wt.POINT(cx, cy)
    u.ClientToScreen(h, ctypes.byref(pt))
    x = int(pt.x * 65536 / max(u.GetSystemMetrics(0) - 1, 1))
    y = int(pt.y * 65536 / max(u.GetSystemMetrics(1) - 1, 1))
    u.SetCursorPos(pt.x, pt.y)
    if right:
        u.mouse_event(0x0008, x, y, 0, 0)
        u.mouse_event(0x0010, x, y, 0, 0)
    else:
        u.mouse_event(0x0002, x, y, 0, 0)
        u.mouse_event(0x0004, x, y, 0, 0)


def drag(h, x0, y0, x1, y1):
    """按下 -> 移动 -> 抬起，才是真的拖框（两次独立点击只会变成两次单选）"""
    u.SetCursorPos(*to_screen(h, x0, y0))
    mouse_btn(h, x0, y0, down=True)
    time.sleep(0.2)
    steps = 6
    for i in range(1, steps + 1):
        u.SetCursorPos(*to_screen(h, int(x0 + (x1 - x0) * i / steps), int(y0 + (y1 - y0) * i / steps)))
        time.sleep(0.05)
    mouse_btn(h, x1, y1, down=False)


def drag_hold(h, x0, y0, x1, y1):
    """按下 -> 移动，**不抬起**：截图要拍"拖框中"的样子（框里那个已选 N）"""
    u.SetCursorPos(*to_screen(h, x0, y0))
    mouse_btn(h, x0, y0, down=True)
    time.sleep(0.15)
    steps = 6
    for i in range(1, steps + 1):
        u.SetCursorPos(*to_screen(h, int(x0 + (x1 - x0) * i / steps), int(y0 + (y1 - y0) * i / steps)))
        time.sleep(0.05)


def to_screen(h, cx, cy):
    pt = wt.POINT(cx, cy)
    u.ClientToScreen(h, ctypes.byref(pt))
    return pt.x, pt.y


def mouse_btn(h, cx, cy, down):
    pt = wt.POINT(cx, cy)
    u.ClientToScreen(h, ctypes.byref(pt))
    x = int(pt.x * 65536 / max(u.GetSystemMetrics(0) - 1, 1))
    y = int(pt.y * 65536 / max(u.GetSystemMetrics(1) - 1, 1))
    u.mouse_event(0x0002 if down else 0x0004, x, y, 0, 0)


def focus(h):
    """把游戏窗口拉到前台：Godot 在非活动窗口下不进帧，点什么都白点"""
    u.ShowWindow(h, 9)          # SW_RESTORE
    u.BringWindowToTop(h)
    try:
        u.SetForegroundWindow(h)
    except Exception:
        pass
    time.sleep(0.6)


def press_key(vk):
    """发一次按键（vk = 虚拟键码，F1=112、P=80 之类）。窗口必须已经在前台"""
    u.keybd_event(vk, 0, 0, 0)
    time.sleep(0.05)
    u.keybd_event(vk, 0, 2, 0)


def main():
    args = sys.argv[1:]
    wait = float(args[0])
    steps = []          # 顺序执行的动作：("box",(x0,y0,x1,y1)) / ("right",(x,y)) / ("shot",path)
    i = 1
    box = None
    rclick = None
    while i < len(args):
        a = args[i]
        if a == "--wait":
            steps.append(("wait", float(args[i + 1])))
            i += 2
        elif a == "--box":
            box = [int(v) for v in args[i + 1].split(",")]
            i += 2
        elif a == "--right":
            rclick = [int(v) for v in args[i + 1].split(",")]
            i += 2
        elif a == "--key":
            steps.append(("key", int(args[i + 1])))
            i += 2
        elif a == "--holdbox":
            steps.append(("hold", [int(v) for v in args[i + 1].split(",")]))
            i += 2
        elif a == "--mouse":
            steps.append(("mouse", [int(v) for v in args[i + 1].split(",")]))
            i += 2
        elif a == "--shot":
            steps.append(("shot", args[i + 1]))
            i += 2
        else:
            i += 1
    if box:
        steps.insert(0, ("box", box))
    if rclick:
        steps.insert(1 if box else 0, ("right", rclick))

    p = subprocess.Popen([GODOT, "--path", PROJ], cwd=PROJ)
    try:
        h = find_hwnd(TITLE)
        if h is None:
            print("NO_WINDOW")
            return
        time.sleep(wait)
        focus(h)
        for kind, val in steps:
            if kind == "box":
                drag(h, val[0], val[1], val[2], val[3])
                time.sleep(1.0)
            elif kind == "hold":
                drag_hold(h, val[0], val[1], val[2], val[3])
                time.sleep(0.3)
            elif kind == "right":
                click(h, val[0], val[1], right=True)
                time.sleep(1.5)
            elif kind == "mouse":
                u.SetCursorPos(*to_screen(h, val[0], val[1]))
                time.sleep(0.3)
            elif kind == "key":
                press_key(val)
            elif kind == "wait":
                time.sleep(val)
            else:
                x0, y0, x1, y1 = client_rect(h)
                img = ImageGrab.grab(bbox=(x0, y0, x1, y1))
                img.save(val)
                print("SAVED", val, img.size)
    finally:
        try:
            p.wait(timeout=1)
        except Exception:
            p.kill()


main()
