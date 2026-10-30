' ============================================================
' Pi Agent - DeepSeek 调用组件（ask_deepseek.vbs）
' 适用 Windows XP/2003 及以上（MSXML2 + ADODB.Stream）
' 文本读取：带 UTF-8 BOM 的按 UTF-8，否则按 GBK（老系统报告为 GBK）
' 用法：cscript //nologo ask_deepseek.vbs <报告文件> <输出文件> [API Key]
' 退出码：0 成功，1 参数错误，2 未配置 Key，3 网络/HTTP 错误，4 文件错误
' ============================================================
Option Explicit

Dim fso, sh, scriptDir, rootDir, configPath, promptPath
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
rootDir = fso.GetParentFolderName(scriptDir)
configPath = rootDir & "\config.ini"
promptPath = scriptDir & "\prompt.txt"

Dim reportFile, outFile, apiKey
If WScript.Arguments.Count < 2 Then
    WScript.Echo "用法：cscript //nologo ask_deepseek.vbs <报告文件> <输出文件> [API Key]"
    WScript.Quit 1
End If
reportFile = WScript.Arguments(0)
outFile = WScript.Arguments(1)
If WScript.Arguments.Count >= 3 Then
    apiKey = WScript.Arguments(2)
Else
    apiKey = ReadIniValue(configPath, "deepseek", "api_key")
End If
If apiKey = "" Then
    WScript.Echo "[Pi Agent] 错误：尚未配置 DeepSeek API Key。"
    WScript.Echo "请编辑 config.ini 填写 api_key，或在菜单里选择「设置 API Key」。"
    WScript.Quit 2
End If

' Explicit consent for actual report upload; fails closed on redirected stdin.
Dim consent
consent = ""
If LCase(fso.GetFileName(WScript.FullName)) <> "cscript.exe" Then WScript.Quit 5
WScript.Echo "AI upload: report may contain names, IPs, proxy credentials and event text. Review it first."
WScript.Echo "Type UPLOAD to send this report to your configured provider (anything else cancels):"
On Error Resume Next
consent = WScript.StdIn.ReadLine
If Err.Number <> 0 Then WScript.Quit 5
On Error GoTo 0
If consent <> "UPLOAD" Then WScript.Quit 5

If Not fso.FileExists(reportFile) Then
    WScript.Echo "[Pi Agent] 错误：找不到报告文件：" & reportFile
    WScript.Quit 4
End If

Dim reportText, sysPrompt
reportText = ReadAnyText(reportFile)
sysPrompt = "你是 Pi Agent，一名资深的 Windows 系统维修工程师。"
If fso.FileExists(promptPath) Then
    sysPrompt = ReadAnyText(promptPath)
End If

' --- 脱敏 ---
reportText = SanitizeText(reportText)
reportText = TruncateText(reportText, 12000)

' --- 构造 JSON 请求 ---
Dim body, modelName
modelName = ReadIniValue(configPath, "deepseek", "model")
If modelName = "" Then modelName = "deepseek-chat"
body = "{""model"":""" & JsonEscape(modelName) & """," & _
       """messages"":[" & _
       "{""role"":""system"",""content"":""" & JsonEscape(sysPrompt) & """}," & _
       "{""role"":""user"",""content"":""" & JsonEscape(reportText) & """}" & _
       "],""temperature"":0.3,""max_tokens"":2048,""stream"":false}"

' --- 发送请求 ---
Dim req, url, respText
On Error Resume Next
Set req = CreateObject("MSXML2.ServerXMLHTTP.6.0")
If Err.Number <> 0 Then
    Err.Clear
    Set req = CreateObject("MSXML2.ServerXMLHTTP")
End If
url = ReadIniValue(configPath, "deepseek", "base_url")
If url = "" Then url = "https://api.deepseek.com"
url = url & "/chat/completions"

req.setTimeouts 30000, 180000, 180000, 180000
req.Open "POST", url, False
req.setRequestHeader "Content-Type", "application/json; charset=utf-8"
req.setRequestHeader "Authorization", "Bearer " & apiKey
req.send EncodeUtf8Body(body)
If Err.Number <> 0 Then
    WScript.Echo "[Pi Agent] 错误：网络请求失败：" & Err.Description
    WScript.Echo "XP/2003 等老系统可能不支持 TLS，请把 U 盘拿到现代电脑上运行 analyze.bat。"
    WScript.Quit 3
End If
On Error GoTo 0

Dim status
status = req.status
If status <> 200 Then
    WScript.Echo "[Pi Agent] 错误：HTTP 状态码 " & status
    WScript.Echo "Service response withheld to avoid disclosing sensitive data."
    WScript.Quit 3
End If

respText = DecodeUtf8Bytes(req.responseBody)

' --- 提取模型回复 ---
Dim content, rawFile
content = ExtractContent(respText)
rawFile = Replace(outFile, ".txt", "_raw.json")
WriteUtf8File rawFile, respText

Dim outHeader
outHeader = "===== Pi Agent AI 智能分析（DeepSeek）=====" & vbCrLf & _
            "分析时间：" & Now & vbCrLf & _
            "报告来源：" & reportFile & vbCrLf & vbCrLf
WriteUtf8File outFile, outHeader & content & vbCrLf & vbCrLf & _
            "----- 原始响应已保存为：" & fso.GetFileName(rawFile) & " -----"

WScript.Echo "[Pi Agent] AI 分析已保存到：" & outFile
WScript.Quit 0

' ============================================================
' 函数
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

' 读取文本：有 UTF-8 BOM 用 UTF-8，否则用 GBK
Function ReadAnyText(path)
    Dim st, b, isUtf8
    Set st = CreateObject("ADODB.Stream")
    st.Open
    st.Type = 1
    st.LoadFromFile path
    isUtf8 = False
    If st.Size >= 3 Then
        b = st.Read(3)
        If b(0) = &HEF And b(1) = &HBB And b(2) = &HBF Then isUtf8 = True
    End If
    st.Position = 0
    st.Type = 2
    If isUtf8 Then
        st.Charset = "utf-8"
        ReadAnyText = st.ReadText
    Else
        ReadAnyText = DecodeAnsi(st)
    End If
    st.Close
End Function

Function DecodeAnsi(st)
    Dim names, i, txt
    names = Array("gb2312", "gbk", "gb18030")
    For i = 0 To UBound(names)
        txt = TryDecode(st, names(i))
        If Len(txt) > 0 Then
            DecodeAnsi = txt
            Exit Function
        End If
    Next
    DecodeAnsi = TryDecode(st, "")
End Function

Function TryDecode(st, cs)
    On Error Resume Next
    Err.Clear
    st.Position = 0
    st.Charset = cs
    If Err.Number <> 0 Then
        TryDecode = ""
        Exit Function
    End If
    TryDecode = st.ReadText
    If Err.Number <> 0 Then TryDecode = ""
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

Function EncodeUtf8Body(text)
    Dim st
    Set st = CreateObject("ADODB.Stream")
    st.Open
    st.Type = 2
    st.Charset = "utf-8"
    st.WriteText text
    st.Position = 0
    st.Type = 1
    EncodeUtf8Body = st.Read
    st.Close
End Function

Function DecodeUtf8Bytes(bytes)
    Dim st
    Set st = CreateObject("ADODB.Stream")
    st.Open
    st.Type = 1
    st.Write bytes
    st.Position = 0
    st.Type = 2
    st.Charset = "utf-8"
    DecodeUtf8Bytes = st.ReadText
    st.Close
End Function

Function JsonEscape(s)
    s = Replace(s, "\", "\\")
    s = Replace(s, """", "\""")
    s = Replace(s, vbCr, "\n")
    s = Replace(s, vbLf, "")
    s = Replace(s, vbTab, " ")
    JsonEscape = s
End Function

Function SanitizeText(txt)
    Dim lines, i, toks, k, out
    lines = Split(txt, vbCrLf)
    out = ""
    toks = Empty
    For i = 0 To UBound(lines)
        If Left(lines(i), 10) = "SENSITIVE:" Then
            toks = Split(Mid(lines(i), 12), "|")
        Else
            out = out & lines(i) & vbCrLf
        End If
    Next
    If Not IsEmpty(toks) Then
        For k = 0 To UBound(toks)
            If Len(Trim(toks(k))) > 1 Then
                out = Replace(out, Trim(toks(k)), "***")
            End If
        Next
    End If
    SanitizeText = out
End Function

Function TruncateText(txt, maxLen)
    If Len(txt) <= maxLen Then
        TruncateText = txt
        Exit Function
    End If
    Dim head, tail
    head = Left(txt, maxLen \ 2)
    tail = Right(txt, maxLen \ 2)
    TruncateText = head & vbCrLf & "...[中间部分已省略]..." & vbCrLf & tail
End Function

Function ExtractContent(json)
    Dim re, found, c
    Set re = New RegExp
    re.Pattern = """content"":""(([^""\\]|\\.)*)"""
    re.Global = False
    found = re.Execute(json)
    If found.Count = 0 Then
        ExtractContent = "[无法解析模型回复，原始响应见 _raw.json 文件]"
        Exit Function
    End If
    c = found(0).SubMatches(0)
    c = Replace(c, "\\", Chr(1))
    c = Replace(c, "\""", """")
    c = Replace(c, "\n", vbCrLf)
    c = Replace(c, "\r", "")
    c = Replace(c, "\t", "  ")
    c = Replace(c, Chr(1), "\")
    ExtractContent = c
End Function
