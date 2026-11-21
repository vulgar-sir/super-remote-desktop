@echo off
chcp 65001 >nul
rem super远程桌面 一键部署：右键“以管理员身份运行”，按提示输入固定密码。
rem 批量部署（如组策略启动脚本）可直接传参：deploy-superdesk.bat 公司统一密码 [helper^|full]
setlocal
set "PW=%~1"
set "FLAVOR=%~2"
if "%FLAVOR%"=="" set "FLAVOR=helper"
if "%PW%"=="" set /p "PW=请输入固定密码（至少 8 位）: "
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy-superdesk.ps1" -Flavor %FLAVOR% -Password "%PW%"
if errorlevel 1 (echo 部署失败 & pause & exit /b 1)
if "%~1"=="" pause
