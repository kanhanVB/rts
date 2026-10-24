@echo off
rem 双击即玩：用 Godot 直接跑当前目录的工程（不打开编辑器）
rem 不用 start：start 在某些环境下会把参数和引号拆散，双击后黑窗一闪就没
set GODOT=E:\godot\Godot_v4.7.2-stable_win64.exe
if not exist "%GODOT%" (
  echo 找不到 Godot：%GODOT%
  echo 如果装在别处，改这一行里的路径。
  pause
  exit /b 1
)
echo 正在启动旗与铁……这个黑窗要留着，游戏关掉它才关。
"%GODOT%" --path "%~dp0."
if errorlevel 1 pause
