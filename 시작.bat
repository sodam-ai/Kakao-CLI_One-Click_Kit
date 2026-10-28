@echo off
chcp 65001 >nul
title 카카오톡 키트
echo.
echo   카카오톡 키트 (Kakao Kit)
echo   준비 중입니다. (임시 화면)
echo.
rem call "%~dp0kakao.cmd" 처럼 경로를 call 에 넘기면 폴더 이름의 ^ 와 % 가 한 번 더 해석되어 조용히 실패한다.
rem 그래서 이 폴더로 들어간 뒤 특수 글자가 없는 상대 경로(.\kakao.cmd)를 부른다.
pushd "%~dp0" || goto :failed
call .\kakao.cmd version
rem 종료 코드가 음수일 수도 있어서(예: -196608) "if errorlevel 1" 로는 놓친다. 0 이 아니면 실패로 본다.
if not "%errorlevel%"=="0" goto :failed_popd
popd
goto :done

:failed_popd
popd
:failed
echo.
echo   실행하지 못했습니다. 압축을 완전히 풀었는지, 폴더 안에 kakao.cmd 와 src 폴더가 있는지 확인해 주세요.

:done
echo.
echo   아무 키나 누르면 닫힙니다.
pause >nul
