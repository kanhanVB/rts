@echo off
rem 双击即玩：用 Godot 直接跑当前目录的工程（不打开编辑器）
set GODOT=E:\godot\Godot_v4.7.2-stable_win64.exe
if not exist "%GODOT%" (
  echo 找不到 Godot：%GODOT%
  echo 如果装在别处，改这一行里的路径。
  pause
  exit /b 1
)
start "" "%GODOT%" --path "%~dp0."
