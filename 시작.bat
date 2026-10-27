@echo off
chcp 65001 >nul
title 카카오톡 키트
echo.
echo   카카오톡 키트 (Kakao Kit)
echo   준비 중입니다. (임시 화면)
echo.
call "%~dp0kakao.cmd" version
echo.
echo   아무 키나 누르면 닫힙니다.
pause >nul
