' ============================================================
' Pi Agent - 离线批量 AI 分析（analyze.vbs）
' 遍历 reports\ 下所有还没有 AI 分析的报告，逐份提交给 DeepSeek，
' 结果写回各报告目录的 ai_analysis.txt。
' 用法：cscript //nologo analyze.vbs [/force]
' 请在现代电脑（Win10/11）上运行。
' ============================================================
Option Explicit

Dim fso, sh, scriptDir, rootDir, askVbs, configPath
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
rootDir = fso.GetParentFolderName(scriptDir)
askVbs = scriptDir & "\ask_deepseek.vbs"
configPath = rootDir & "\config.ini"

Dim force
force = False
If WScript.Arguments.Count >= 1 Then
    If LCase(WScript.Arguments(0)) = "/force" Then force = True
End If

If ReadIniValue(configPath, "deepseek", "api_key") = "" Then
    WScript.Echo "[Pi Agent] 错误：尚未配置 DeepSeek API Key。"
    WScript.Echo "请先编辑 config.ini 填写 api_key，再运行 analyze.bat。"
    WScript.Quit 2
End If

Dim reportsDir, folder, reportFile, outFile, cmd, rc, count, skipCount, failCount
reportsDir = rootDir & "\reports"
If Not fso.FolderExists(reportsDir) Then
    WScript.Echo "[Pi Agent] 找不到报告目录：" & reportsDir
    WScript.Quit 0
End If

count = 0
skipCount = 0
failCount = 0
Dim summary
summary = "Pi Agent 离线批量分析汇总 - " & Now & vbCrLf & vbCrLf

For Each folder In fso.GetFolder(reportsDir).SubFolders
    reportFile = folder.Path & "\diagnosis.txt"
    If fso.FileExists(reportFile) Then
        outFile = folder.Path & "\ai_analysis.txt"
        If fso.FileExists(outFile) And Not force Then
            WScript.Echo "[跳过] " & folder.Name & "（已分析过）"
            skipCount = skipCount + 1
        Else
            WScript.Echo "[分析] " & folder.Name & " ..."
            cmd = "cscript //nologo """ & askVbs & """ """ & reportFile & """ """ & outFile & """"
            rc = sh.Run(cmd, 1, True)
            If rc = 0 Then
                count = count + 1
                summary = summary & "[成功] " & folder.Name & vbCrLf
            Else
                failCount = failCount + 1
                summary = summary & "[失败 代码=" & rc & "] " & folder.Name & vbCrLf
            End If
        End If
    End If
Next

summary = summary & vbCrLf & _
    "处理完成：成功 " & count & " 份，跳过 " & skipCount & " 份，失败 " & failCount & " 份。" & vbCrLf
WriteUtf8File rootDir & "\reports\analyze_summary.txt", summary
WScript.Echo ""
WScript.Echo "处理完成：成功 " & count & " 份，跳过 " & skipCount & " 份，失败 " & failCount & " 份。"
WScript.Echo "汇总文件：reports\analyze_summary.txt"

' ============================================================
Function ReadIniValue(path, section, key)
    ReadIniValue = ""
    If Not fso.FileExists(path) Then Exit Function
    Dim f, line, curSec
    Set f = fso.OpenTextFile(path, 1, False)
    curSec = ""
    Do While Not f.AtEndOfStream
        line = Trim(f.ReadLine)
        If Left(line, 1) = "[" And Right(line, 1) = "]" Then
            curSec = Mid(line, 2, Len(line) - 2)
        ElseIf InStr(line, "=") > 0 And curSec = section Then
            If LCase(Left(line, InStr(line, "=") - 1)) = LCase(key) Then
                ReadIniValue = Trim(Mid(line, InStr(line, "=") + 1))
                f.Close
                Exit Function
            End If
        End If
    Loop
    f.Close
End Function

Function WriteUtf8File(path, content)
    Dim st
    Set st = CreateObject("ADODB.Stream")
    st.Open
    st.Type = 2
    st.Charset = "utf-8"
    st.WriteText content
    st.SaveToFile path, 2
    st.Close
End Function
