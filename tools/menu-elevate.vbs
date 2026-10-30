' ============================================================
'  Pi Agent - ??????????
'  ? wscript ???????????ShellExecute "runas" ??
' ============================================================
Option Explicit
Dim sh, env, fso, root, ps, wt, menuPath, wtArgs, psArgs
Set sh  = CreateObject("Shell.Application")
Set env = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

root = fso.GetParentFolderName(fso.GetParentFolderName(WScript.ScriptFullName))
If Right(root, 1) = "\" Then root = Left(root, Len(root) - 1)
ps = env.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
wt = env.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\Microsoft\WindowsApps\wt.exe"
menuPath = root & "\menu\pi_menu.ps1"
psArgs = "-NoProfile -ExecutionPolicy Bypass -File """ & menuPath & """"

If WScript.Arguments.Count > 0 Then
  If WScript.Arguments(0) = "--check" Then
    WScript.Echo "ROOT=" & root
    WScript.Echo "PS=" & ps
    WScript.Echo "WT=" & wt
    WScript.Echo "MENU_EXISTS=" & fso.FileExists(menuPath)
    WScript.Quit 0
  End If
End If

If Not fso.FileExists(menuPath) Then
    MsgBox "????????" & menuPath, 16, "Pi Agent"
    WScript.Quit 2
End If

env.Environment("PROCESS")("PI_HARDWARE_CURSOR") = "1"

On Error Resume Next
If fso.FileExists(wt) Then
    wtArgs = "-w 0 new-tab --title ""Pi Agent"" """ & ps & """ " & psArgs
    sh.ShellExecute wt, wtArgs, root, "runas", 1
Else
    sh.ShellExecute ps, psArgs, root, "runas", 1
End If
If Err.Number <> 0 Then
    MsgBox "?????" & Err.Number & "?" & Err.Description & "?", 48, "Pi Agent"
End If
On Error GoTo 0