#NoEnv
#SingleInstance Force
SetWorkingDir %A_ScriptDir%

if not A_IsAdmin
{
    Run *RunAs "%A_ScriptFullPath%"
    ExitApp
}

IsMultiMode := true
OptimizedPID := 0 ; Хранит PID процесса, который мы оптимизировали

; Карта кодов приоритетов Windows в понятный текст
PriorityMap := { 0x00000020: "Normal"
               , 0x00000040: "Idle (Low)"
               , 0x00000080: "High"
               , 0x00000100: "Realtime"
               , 0x00004000: "Below Normal"
               , 0x00008000: "Above Normal" }

; Изначально создаем меню, пункты Оптимизации будут меняться динамически в GuiContextMenu
Menu, ContextMenu, Add, Kill Process, CloseProcess
Menu, ContextMenu, Add, Priority: Realtime, SetRealtime
Menu, ContextMenu, Add, Priority: Low + Eco, SetLowPriority
Menu, ContextMenu, Add ; Разделитель

Gui, +AlwaysOnTop +Resize
Gui, Font, s10, Segoe UI
ImageListID := IL_Create(100, 10, 0)

; Добавили колонки Priority и Eco Mode + включили чекбоксы по умолчанию (+Checked)
Gui, Add, ListView, x20 y20 r20 w750 vProcessList gListEvent ImageList%ImageListID% +Grid +HwndhwndLV +Checked, Icon|Application|Total Memory|Priority|Eco Mode|Main PID
OnMessage(0x4E, "WM_NOTIFY")

; Кнопку переключения режима стерли. Кнопки «Выделить все» теперь активны сразу (убрали слово hidden)
Gui, Add, Button, x20 y+10 w90 h30 vBtnCheckAll gCheckAll, Check All
Gui, Add, Button, x+5 w95 h30 vBtnUncheckAll gUncheckAll, Uncheck All

; Кнопки управления приоритетами (сместили x20 y+10 на следующую строку, чтобы было ровно)
Gui, Add, Button, x20 y+10 w140 h30 gCloseProcess, Kill Process
Gui, Add, Button, x+10 w170 h30 gSetRealtime, Priority: Realtime
Gui, Add, Button, x+10 w150 h30 gSetLowPriority, Priority: Low + Eco
Gui, Add, Text, x20 y+15 w750 Center cGray +Disabled, Created by fi6ka

Gui, Show, w790, Process Manager
GoSub, RefreshList
SetTimer, AutoRefresh, 3000
return

AutoRefresh:
GoSub, RefreshList
return

CheckAll:
Loop % LV_GetCount()
    LV_Modify(A_Index, "+Check")
return

UncheckAll:
Loop % LV_GetCount()
    LV_Modify(A_Index, "-Check")
return

RefreshList:
SetTimer, AutoRefresh, Off

; --- Сохраняем синее выделение (по PID) ---
SelectedPIDsBefore := {}
RowNumber := 0
Loop {
    RowNumber := LV_GetNext(RowNumber, "Selected")
    if not RowNumber
        break
    LV_GetText(SelPID, RowNumber, 6) ; PID теперь в 6-й колонке
    SelectedPIDsBefore[SelPID] := true
}

; --- Сохраняем чекбоксы (по PID) ---
CheckedPIDs := {}
if (IsMultiMode) {
    RowNumber := 0
    Loop {
        RowNumber := LV_GetNext(RowNumber, "Checked")
        if not RowNumber
            break
        LV_GetText(CheckedPID, RowNumber, 6)
        CheckedPIDs[CheckedPID] := true
    }
}

DetectHiddenWindows, On
WinGet, OpenWindows, List
HasWindowPID := {}
Loop, %OpenWindows%
{
    WinID := OpenWindows%A_Index%
    WinGetTitle, Title, ahk_id %WinID%
    if (Title != "") {
        WinGet, WinPID, PID, ahk_id %WinID%
        HasWindowPID[WinPID] := true
    }
}
DetectHiddenWindows, Off

CurrentProcesses := {}
ProcessNameToMainPID := {}
WMI := ComObjGet("winmgmts:{impersonationLevel=impersonate}!\\.\root\cimv2")
for process in WMI.ExecQuery("Select ProcessId, Name, ExecutablePath, WorkingSetSize from Win32_Process")
{
    pid := process.ProcessId
    name := Format("{:L}", process.Name)
    if (name = "svchost.exe" || name = "sihost.exe" || name = "shellexperiencehost.exe"
        || name = "explorer.exe" || name = "runtimebroker.exe" || name = "spoolsv.exe"
        || name = "lsass.exe" || name = "csrss.exe" || name = "smss.exe"
        || name = "services.exe" || name = "wininit.exe" || name = "winlogon.exe"
        || name = "conhost.exe" || name = "taskhostw.exe" || name = "ctfmon.exe"
        || name = "smartscreen.exe" || name = "searchhost.exe" || name = "applicationframehost.exe")
        continue
        
    if (!HasWindowPID[pid] || pid = 0 || process.ExecutablePath = "")
        continue
        
    ramMB := process.WorkingSetSize / 1024 / 1024
    if (ProcessNameToMainPID.HasKey(name)) {
        mainPID := ProcessNameToMainPID[name]
        CurrentProcesses[mainPID].RamRaw += ramMB
    } else {
        ProcessNameToMainPID[name] := pid
        CurrentProcesses[pid] := {Name: process.Name, Path: process.ExecutablePath, RamRaw: ramMB}
    }
}

; Получаем Приоритет и Эко-режим для каждого процесса
for pid, info in CurrentProcesses 
{
    CurrentProcesses[pid].Ram := Round(info.RamRaw, 1) . " MB"
    
    ; Читаем свойства через Win32 API
    hProcess := DllCall("OpenProcess", "UInt", 0x1000, "Int", false, "UInt", pid, "Ptr") ; PROCESS_QUERY_LIMITED_INFORMATION
    if (hProcess) {
        ; 1. Приоритет
        pClass := DllCall("GetPriorityClass", "Ptr", hProcess, "UInt")
        CurrentProcesses[pid].Priority := PriorityMap.HasKey(pClass) ? PriorityMap[pClass] : "Unknown"
        
        ; 2. Эко Режим (Power Throttling)
        VarSetCapacity(PowerThrottling, 12, 0)
        NumPut(1, PowerThrottling, 0, "UInt") ; Version = 1
        
        ; Вызов SetProcessInformation/GetProcessInformation (инфо-класс 4 = ProcessPowerThrottling)
        result := DllCall("kernel32.dll\GetProcessInformation", "Ptr", hProcess, "Int", 4, "Ptr", &PowerThrottling, "UInt", 12, "Int")
        if (result) {
            ecoState := NumGet(PowerThrottling, 8, "UInt")
            CurrentProcesses[pid].Eco := (ecoState = 1) ? "Enabled" : "Disabled"
        } else {
            CurrentProcesses[pid].Eco := "Disabled"
        }
        DllCall("CloseHandle", "Ptr", hProcess)
    } else {
        CurrentProcesses[pid].Priority := "Access Denied"
        CurrentProcesses[pid].Eco := "Unknown"
    }
}

LV_SetImageList(ImageListID, 1)

; Удаляем строки которых больше нет
Loop % LV_GetCount()
{
    RowIdx := LV_GetCount() - A_Index + 1
    LV_GetText(RowPID, RowIdx, 6)
    if (!CurrentProcesses.HasKey(RowPID))
        LV_Delete(RowIdx)
}

; Обновляем/добавляем строки
GuiControl, -g, ProcessList
for pid, info in CurrentProcesses
{
    RowFound := 0
    Loop % LV_GetCount()
    {
        LV_GetText(RowPID, A_Index, 6)
        if (RowPID = pid) {
            RowFound := A_Index
            break
        }
    }
    if (RowFound > 0) {
        ; Обновляем динамические данные (ОЗУ, Приоритет, Эко)
        LV_GetText(CurrentRowRam, RowFound, 3)
        if (CurrentRowRam != info.Ram)
            LV_Modify(RowFound, "Col3", info.Ram)
            
        LV_Modify(RowFound, "Col4", info.Priority)
        LV_Modify(RowFound, "Col5", info.Eco)
            
        if (IsMultiMode) {
            if (CheckedPIDs.HasKey(pid))
                LV_Modify(RowFound, "+Check")
            else
                LV_Modify(RowFound, "-Check")
        }
    } else {
        iconIndex := 0
        if (info.Path != "")
            iconIndex := IL_Add(ImageListID, info.Path, 1)
        if (iconIndex = 0)
            iconIndex := IL_Add(ImageListID, "shell32.dll", 3)
            
        ; Добавляем строку: Иконка, Имя, Память, Приоритет, Эко, ПИД
        LV_Add("Icon" . iconIndex . (IsMultiMode && CheckedPIDs.HasKey(pid) ? " Check" : "")
            , "", info.Name, info.Ram, info.Priority, info.Eco, pid)
    }
}
GuiControl, +gListEvent, ProcessList

LV_ModifyCol(1, 60)
LV_ModifyCol(2, 220)
LV_ModifyCol(3, 110)
LV_ModifyCol(4, 120)
LV_ModifyCol(5, 110)
LV_ModifyCol(6, 80)
LV_ModifyCol(2, "Sort")

; Восстанавливаем синее выделение и фокус жестко
Loop % LV_GetCount()
{
    LV_GetText(RowPID, A_Index, 6)
    if (SelectedPIDsBefore.HasKey(RowPID))
        LV_Modify(A_Index, "Select Focus")
    else
        LV_Modify(A_Index, "-Select -Focus")
}

SetTimer, AutoRefresh, 3000
return

GuiContextMenu:
if (A_GuiControl != "ProcessList")
    return
RowNumber := LV_GetNext(0)
if not RowNumber
    return

LV_GetText(ClickedPID, RowNumber, 6)

try Menu, ContextMenu, Delete, Optimize Process
try Menu, ContextMenu, Delete, Restore Normal Mode

if (OptimizedPID = ClickedPID) {
    Menu, ContextMenu, Add, Restore Normal Mode, RemoveOptimization
} else {
    Menu, ContextMenu, Add, Optimize Process, ApplyOptimization
}

Menu, ContextMenu, Show, %A_GuiX%, %A_GuiY%
return

; --- ЛОГИКА ОПТИМИЗАЦИИ ---

ApplyOptimization:
RowNumber := LV_GetNext(0)
if not RowNumber
    return
LV_GetText(TargetPID, RowNumber, 6)

if (OptimizedPID && OptimizedPID != TargetPID) {
    GoSub, RemoveOptimization
}

OptimizedPID := TargetPID

; 1. Главный процесс -> Realtime, Eco -> OFF
SetProcessEcoMode(OptimizedPID, false)
Run, powershell.exe -Command "(Get-Process -Id %OptimizedPID%).PriorityClass = 'RealTime'",, Hide

; 2. Все остальные процессы из нашего списка -> Low + Eco
GoSub, EnforceEcoOnOthers

; Включаем проверку каждые 5 сек
SetTimer, EcoTracker, 5000
return

RemoveOptimization:
if (!OptimizedPID)
    return

SetTimer, EcoTracker, Off

; Главный процесс возвращаем в Normal
SetProcessEcoMode(OptimizedPID, false)
Run, powershell.exe -Command "(Get-Process -Id %OptimizedPID%).PriorityClass = 'Normal'",, Hide

; Все остальные из таблицы тоже возвращаем в Normal
Loop % LV_GetCount()
{
    LV_GetText(CurrentPID, A_Index, 6)
    if (CurrentPID = OptimizedPID)
        continue
        
    SetProcessEcoMode(CurrentPID, false)
    Run, powershell.exe -Command "(Get-Process -Id %CurrentPID%).PriorityClass = 'Normal'",, Hide
}

OptimizedPID := 0
GoSub, RefreshList
return

EcoTracker:
GoSub, RefreshList
GoSub, EnforceEcoOnOthers
return

EnforceEcoOnOthers:
if (!OptimizedPID)
    return

Loop % LV_GetCount()
{
    LV_GetText(CurrentPID, A_Index, 6)
    if (CurrentPID = OptimizedPID)
        continue
        
    Run, powershell.exe -Command "(Get-Process -Id %CurrentPID%).PriorityClass = 'Idle'",, Hide
    SetProcessEcoMode(CurrentPID, true)
}
return

; --- КОНЕЦ ЛОГИКИ ОПТИМИЗАЦИИ ---

WM_NOTIFY(wParam, lParam) {
    critical
    code := NumGet(lParam + 0, A_PtrSize * 2, "Int")
    if (code = -109 || code = -149)
        return 1
}

GetSelectedTargets:
TargetPIDs := []
SelectedNames := {}

; Собираем процессы, на которых стоят галочки
RowNumber := 0
Loop {
    RowNumber := LV_GetNext(RowNumber, "Checked")
    if not RowNumber
        break
    LV_GetText(RowName, RowNumber, 2)
    SelectedNames[Format("{:L}", RowName)] := true
}

HasNames := false
for k, v in SelectedNames {
    HasNames := true
    break
}
if (!HasNames) {
    MsgBox, 48, Attention, Please check at least one application!
    return
}
WMI := ComObjGet("winmgmts:{impersonationLevel=impersonate}!\\.\root\cimv2")
for process in WMI.ExecQuery("Select ProcessId, Name from Win32_Process")
{
    pName := Format("{:L}", process.Name)
    if (SelectedNames.HasKey(pName))
        TargetPIDs.Push(process.ProcessId)
}
return
CloseProcess:
GoSub, GetSelectedTargets
if (TargetPIDs.Length() = 0)
    return
Loop % TargetPIDs.Length()
{
    CurrentPID := TargetPIDs[A_Index]
    Process, Close, %CurrentPID%
}
GoSub, RefreshList
return

SetRealtime:
GoSub, GetSelectedTargets
if (TargetPIDs.Length() = 0)
    return
Loop % TargetPIDs.Length()
{
    CurrentPID := TargetPIDs[A_Index]
    SetProcessEcoMode(CurrentPID, false)
    Run, powershell.exe -Command "(Get-Process -Id %CurrentPID%).PriorityClass = 'RealTime'",, Hide
}
; Снимаем галочки со всех процессов в таблице, так как задача выполнена
Loop % LV_GetCount()
    LV_Modify(A_Index, "-Check")

GoSub, RefreshList
return

SetLowPriority:
GoSub, GetSelectedTargets
if (TargetPIDs.Length() = 0)
    return
Loop % TargetPIDs.Length()
{
    CurrentPID := TargetPIDs[A_Index]
    Run, powershell.exe -Command "(Get-Process -Id %CurrentPID%).PriorityClass = 'Idle'",, Hide
    Sleep, 100
    SetProcessEcoMode(CurrentPID, true)
}
; Снимаем галочки со всех процессов в таблице, так как задача выполнена
Loop % LV_GetCount()
    LV_Modify(A_Index, "-Check")

GoSub, RefreshList
return

SetProcessEcoMode(PID, Enable := true) {
    hProcess := DllCall("OpenProcess", "UInt", 0x1F0FFF, "Int", false, "UInt", PID, "Ptr")  ; PROCESS_ALL_ACCESS
    if (!hProcess)
        return false
    VarSetCapacity(PowerThrottling, 12, 0)  ; 3 * UInt = 12 байт
    NumPut(1, PowerThrottling, 0, "UInt")  ; Version = 1
    NumPut(1, PowerThrottling, 4, "UInt")  ; ControlMask = PROCESS_POWER_THROTTLING_EXECUTION_SPEED
    if (Enable)
        NumPut(1, PowerThrottling, 8, "UInt")  ; StateMask = 1 → Eco ON
    else
        NumPut(0, PowerThrottling, 8, "UInt")  ; StateMask = 0 → Eco OFF
    result := DllCall("kernel32.dll\SetProcessInformation"
        , "Ptr", hProcess
        , "Int", 4                                          ; ProcessPowerThrottling
        , "Ptr", &PowerThrottling
        , "UInt", 12                                        ; sizeof(struct)
        , "Int")                                            ; возвращает BOOL
    DllCall("CloseHandle", "Ptr", hProcess)
    return result ? true : false
}

ListEvent:
; Переключаем чекбокс только при одиночном клике (Normal) или нажатии Space/Enter (K)
if (A_GuiEvent == "Normal" || A_GuiEvent == "K") {
    ClickedRow := A_EventInfo
    if (ClickedRow > 0) {
        ; Узнаем текущее состояние чекбокса напрямую через встроенную функцию AHK
        IsChecked := LV_GetNext(ClickedRow - 1, "Checked") == ClickedRow
        
        ; Переключаем на противоположное
        if (IsChecked)
            LV_Modify(ClickedRow, "-Check")
        else
            LV_Modify(ClickedRow, "+Check")
    }
}
return

GuiClose:
ExitApp
