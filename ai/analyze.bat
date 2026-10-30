@echo off
chcp 936 >nul
rem ============================================================
rem  Pi Agent - 离线批量 AI 分析
rem  把 reports\ 下所有还没有 AI 分析的报告逐份提交给 DeepSeek，
rem  分析结果写回各报告目录的 ai_analysis.txt。
rem  请在现代电脑（Win10/11）上运行。
rem  用法：analyze.bat [/force]
rem ============================================================
cscript //nologo "%~dp0analyze.vbs" %*
