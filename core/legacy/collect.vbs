' ============================================================
' Pi Agent - 老系统采集辅助（Windows XP / 2003）
' 输出：事件日志错误摘要、启动文件夹、杀毒软件状态（GBK 中文）
' ============================================================
Option Explicit
On Error Resume Next

Dim wmi, dt, wql, items, item, dict, key, total
Set wmi = GetObject("winmgmts:\\.\root\cimv2")
Set dt = CreateObject("WbemScripting.SWbemDateTime")
dt.SetVarDate DateAdd("h", -48, Now), True

wql = "SELECT SourceName, EventCode, Message FROM Win32_NTLogEvent WHERE " & _
      "(Logfile='System' OR Logfile='Application') AND Type='Error' AND " & _
      "TimeGenerated>'" & dt.Value & "'"

Set dict = CreateObject("Scripting.Dictionary")
total = 0
Set items = wmi.ExecQuery(wql)
For Each item In items
    total = total + 1
    key = item.SourceName & "|" & item.EventCode
    If dict.Exists(key) Then
        Dim a
        a = dict(key)
        a(0) = a(0) + 1
        If a(0) = 2 Then a(1) = Shorten(item.Message)
        dict(key) = a
    Else
        dict.Add key, Array(1, Shorten(item.Message))
    End If
Next

WScript.Echo "事件日志错误（最近 48 小时）："
If total = 0 Then
    WScript.Echo "  未发现错误事件。"
Else
    WScript.Echo "  错误事件总数：" & total
    Dim keys, i
    keys = dict.Keys
    ' 按出现次数降序排列（选择排序）
    Dim j, maxIdx, a1, a2, tmp
    For i = 0 To UBound(keys) - 1
        maxIdx = i
        For j = i + 1 To UBound(keys)
            a1 = dict(keys(j))
            a2 = dict(keys(maxIdx))
            If a1(0) > a2(0) Then maxIdx = j
        Next
        If maxIdx <> i Then tmp = keys(i) : keys(i) = keys(maxIdx) : keys(maxIdx) = tmp
    Next
    Dim limit
    limit = 25
    If UBound(keys) < limit Then limit = UBound(keys)
    WScript.Echo "  出现次数最多的错误："
    For i = 0 To limit
        Dim arr
        arr = dict(keys(i))
        WScript.Echo "  [" & arr(0) & " 次] " & keys(i) & "  " & arr(1)
    Next
End If

' --- 启动文件夹 ---
WScript.Echo ""
WScript.Echo "启动文件夹："
Dim shellObj, sfd, it
Set shellObj = CreateObject("Shell.Application")
Set sfd = shellObj.Namespace(7)
For Each it In sfd.Items
    WScript.Echo "  [当前用户] " & it.Name
Next
Set sfd = shellObj.Namespace(24)
For Each it In sfd.Items
    WScript.Echo "  [所有用户] " & it.Name
Next

' --- 杀毒软件状态 ---
WScript.Echo ""
WScript.Echo "杀毒软件状态："
Dim sec, av, avItems, foundAv
foundAv = False
Set sec = GetObject("winmgmts:\\.\root\SecurityCenter2")
If Not sec Is Nothing Then
    Set avItems = sec.ExecQuery("SELECT * FROM AntiVirusProduct")
    For Each av In avItems
        foundAv = True
        WScript.Echo "  " & av.displayName & "  状态码=0x" & Hex(av.productState)
    Next
End If
If Not foundAv Then WScript.Echo "  未检测到杀毒软件（SecurityCenter 不可用）。"

Function Shorten(s)
    If IsNull(s) Then
        Shorten = ""
    ElseIf Len(s) > 120 Then
        Shorten = Left(s, 120) & "..."
    Else
        Shorten = s
    End If
End Function
