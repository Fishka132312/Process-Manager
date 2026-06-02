#NoEnv
#SingleInstance Force
SetWorkingDir %A_ScriptDir%

if not A_IsAdmin
{
    Run *RunAs "%A_ScriptFullPath%"
    ExitApp
}

; Глобальный массив для хранения цветов процессов (Ключ - PID)
global ProcessColors := {}

; Регистрация сообщения перерисовки GUI для кастомного цвета ячеек
OnMessage(0x4E, "WM_NOTIFY")

IsMultiMode := true
OptimizedPID := 0 

PriorityMap := { 0x00000020: "Normal"
               , 0x00000040: "Idle (Low)"
               , 0x00000080: "High"
               , 0x00000100: "Realtime"
               , 0x00004000: "Below Normal"
               , 0x00008000: "Above Normal" }

Menu, ContextMenu, Add, Kill Process, CloseProcess
Menu, ContextMenu, Add, Priority: Realtime, SetRealtime
Menu, ContextMenu, Add, Priority: Low + Eco, SetLowPriority
Menu, ContextMenu, Add 

; --- СУПЕР ПУПЕР X100 ДИЗАЙН (DARK CYBERPUNK THEME) ---
Gui, Color, 121214, 1E1E22
Gui, +AlwaysOnTop +Resize -DPIScale

; Подключаем сочные шрифты
Gui, Font, s11 cC5C6C7, Consolas
ImageListID := IL_Create(100, 10, 0)

; Создаем ListView. Убрали "+c00F5D4", чтобы дефолтный цвет не ломал кастомный рендер
Gui, Add, ListView, x20 y20 r22 w714 vProcessList gListEvent ImageList%ImageListID% +Grid +HwndhwndLV +Checked +Background1E1E22, Icon|Application|Total Memory|Priority|Eco Mode|Main PID

; Секция кнопок управления списком
Gui, Font, s10 Bold, Segoe UI
Gui, Add, Button, x20 y+15 w110 h35 vBtnCheckAll gCheckAll, ✔️ Select All
Gui, Add, Button, x+10 w120 h35 vBtnUncheckAll gUncheckAll, ❌ Unselect Al

; Разделительная неоновая линия
Gui, Add, Progress, x20 y+15 w714 h2 Background00F5D4 c00F5D4, 100

; Мощные кастомные кнопки управления процессами
Gui, Font, s10 Bold, Segoe UI
Gui, Add, Button, x20 y+15 w140 h38 gCloseProcess, 💀 Kill Process
Gui, Add, Button, x+15 w170 h38 gSetRealtime, 卐 Priority: Realtime
Gui, Add, Button, x+15 w170 h38 gSetLowPriority, 🍃 Priority: Low + Eco

; Фирменный футер (Теперь окно h720 — ничего не режется!)
Gui, Font, s9 Italic, Consolas
Gui, Add, Text, x20 y+25 w714 Center c00F5D4, — Created by fi6ka —

Gui, Show, w800 h720, Process Manager v1.0.0-beta
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

SelectedPIDsBefore := {}
RowNumber := 0
Loop {
    RowNumber := LV_GetNext(RowNumber, "Selected")
    if not RowNumber
        break
    LV_GetText(SelPID, RowNumber, 6) 
    SelectedPIDsBefore[SelPID] := true
}

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

for pid, info in CurrentProcesses 
{
    CurrentProcesses[pid].Ram := Round(info.RamRaw, 1) . " MB"
    
    hProcess := DllCall("OpenProcess", "UInt", 0x1000, "Int", false, "UInt", pid, "Ptr") 
    if (hProcess) {
        pClass := DllCall("GetPriorityClass", "Ptr", hProcess, "UInt")
        CurrentProcesses[pid].Priority := PriorityMap.HasKey(pClass) ? PriorityMap[pClass] : "Unknown"
        
        VarSetCapacity(PowerThrottling, 12, 0)
        NumPut(1, PowerThrottling, 0, "UInt") 
        
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

Loop % LV_GetCount()
{
    RowIdx := LV_GetCount() - A_Index + 1
    LV_GetText(RowPID, RowIdx, 6)
    if (!CurrentProcesses.HasKey(RowPID))
        LV_Delete(RowIdx)
}

GuiControl, -g, ProcessList
ProcessColors := {} ; Очищаем старый кэш цветов процессов перед заполнением
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
    
    ; --- Палитра цветов (Формат в Win32 API строго BGR: 0xBBGGRR) ---
    appColor := 0xD4F500  ; Мятный / Светло-зеленый (По умолчанию для процессов с иконками)
    ramColor := 0xC7C6C5  ; Светло-серый для RAM колонки
    pidColor := 0x888888  ; Серый для PID колонки
    
    ; Сортировка Priority
    if (info.Priority = "Realtime")
        prioColor := 0x00FF00 ; Яркий чистый зеленый
    else if (info.Priority = "High" || info.Priority = "Above Normal")
        prioColor := 0x00FFFF ; Сочный желтый
    else if (info.Priority = "Idle (Low)" || info.Priority = "Below Normal")
        prioColor := 0x0000FF ; Огненно-красный
    else
        prioColor := 0xFFFFFF ; Чистый белый для Normal
        
    ; Сортировка Eco Mode
    ecoColor := (info.Eco = "Enabled") ? 0x00FF00 : 0x0000FF ; Зеленый / Красный
    
    if (RowFound > 0) {
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
        if (iconIndex = 0) {
            iconIndex := IL_Add(ImageListID, "shell32.dll", 3)
            appColor := 0x555555 ; Если иконки нет (черный/темный фон системы) -> делаем текст темным
        }
            
        LV_Add("Icon" . iconIndex . (IsMultiMode && CheckedPIDs.HasKey(pid) ? " Check" : "")
            , "", info.Name, info.Ram, info.Priority, info.Eco, pid)
    }
    
    ; Сохраняем цвета в кэш, привязывая К PID процесса, а не к строке!
    ProcessColors[pid] := {2: appColor, 3: ramColor, 4: prioColor, 5: ecoColor, 6: pidColor}
}
GuiControl, +gListEvent, ProcessList

LV_ModifyCol(1, 55)
LV_ModifyCol(2, 215)
LV_ModifyCol(3, 115)
LV_ModifyCol(4, 125)
LV_ModifyCol(5, 115)
LV_ModifyCol(6, "AutoHdr")
LV_ModifyCol(2, "Sort")

Loop % LV_GetCount()
{
    varPID := 0
    LV_GetText(varPID, A_Index, 6)
    if (SelectedPIDsBefore.HasKey(varPID))
        LV_Modify(A_Index, "Select Focus")
    else
        LV_Modify(A_Index, "-Select -Focus")
}

; Обновляем окно для моментального рендера цветов
WinSet, Redraw,, ahk_id %hwndLV%
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

; --- ОПТИМИЗИРОВАННАЯ ЛОГИКА ---

SetPriorityWin32(PID, PriorityCode) {
    hProcess := DllCall("OpenProcess", "UInt", 0x0200, "Int", false, "UInt", PID, "Ptr") 
    if (hProcess) {
        DllCall("SetPriorityClass", "Ptr", hProcess, "UInt", PriorityCode)
        DllCall("CloseHandle", "Ptr", hProcess)
        return true
    }
    return false
}

ApplyOptimization:
RowNumber := LV_GetNext(0)
if not RowNumber
    return
LV_GetText(TargetPID, RowNumber, 6)

if (OptimizedPID && OptimizedPID != TargetPID) {
    GoSub, RemoveOptimization
}

OptimizedPID := TargetPID

SetProcessEcoMode(OptimizedPID, false)
SetPriorityWin32(OptimizedPID, 0x00000100)

GoSub, EnforceEcoOnOthers
SetTimer, EcoTracker, 5000
return

RemoveOptimization:
if (!OptimizedPID)
    return

SetTimer, EcoTracker, Off

SetProcessEcoMode(OptimizedPID, false)
SetPriorityWin32(OptimizedPID, 0x00000020)

Loop % LV_GetCount()
{
    LV_GetText(CurrentPID, A_Index, 6)
    if (CurrentPID = OptimizedPID)
        continue
        
    SetProcessEcoMode(CurrentPID, false)
    SetPriorityWin32(CurrentPID, 0x00000020)
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
        
    SetPriorityWin32(CurrentPID, 0x00000040)
    SetProcessEcoMode(CurrentPID, true)
}
return

; --- ИСПРАВЛЕННЫЙ И НАДЕЖНЫЙ КАСТОМНЫЙ РЕНДЕР (ДИНАМИЧЕСКИЙ PID ПОИСК) ---
WM_NOTIFY(wParam, lParam) {
    static NM_CUSTOMDRAW := -12
    static CDDS_PREPAINT := 0x00000001
    static CDDS_ITEMPREPAINT := 0x00010001
    static CDDS_SUBITEM := 0x00020000
    static CDRF_NOTIFYITEMDRAW := 0x00000020
    static CDRF_NOTIFYSUBITEMDRAW := 0x00000020
    static CDRF_DODEFAULT := 0x00000000
    
    critical
    code := NumGet(lParam + 0, A_PtrSize * 2, "Int")
    
    if (code = NM_CUSTOMDRAW) {
        drawStage := NumGet(lParam + 0, A_PtrSize * 3, "UInt")
        
        if (drawStage = CDDS_PREPAINT)
            return CDRF_NOTIFYITEMDRAW
            
        if (drawStage = CDDS_ITEMPREPAINT)
            return CDRF_NOTIFYSUBITEMDRAW
            
        if (drawStage = (CDDS_ITEMPREPAINT | CDDS_SUBITEM)) {
            ; Получаем индекс строки внутри самого Win32 элемента напрямую
            rowIdx := NumGet(lParam + 0, A_PtrSize * 4, "Ptr") + 1
            colIdx := NumGet(lParam + 0, (A_PtrSize * 5) + 4, "Int") + 1
            
            ; Вытаскиваем PID процесса из 6-й колонки этой строки, чтобы узнать точный цвет
            VarSetCapacity(LVITEM, 16 + (A_PtrSize * 3), 0)
            NumPut(4, LVITEM, 0, "UInt") ; LVIF_TEXT
            NumPut(rowIdx - 1, LVITEM, 4, "Int") ; iItem
            NumPut(5, LVITEM, 8, "Int") ; iSubItem (6-я колонка, индекс 5)
            VarSetCapacity(textBuf, 16, 0)
            NumPut(&textBuf, LVITEM, 16 + A_PtrSize, "Ptr") ; pszText
            NumPut(16, LVITEM, 16 + (A_PtrSize * 2), "Int") ; cchTextMax
            
            ; Посылаем сообщение системе LVM_GETITEMTEXT
            DllCall("SendMessage", "Ptr", wParam, "UInt", 0x102D, "Ptr", rowIdx - 1, "Ptr", &LVITEM)
            cellPID := StrGet(&textBuf)
            
            ; Красим ячейку на основе сохраненной карты цветов PID
            if (cellPID && ProcessColors.HasKey(cellPID) && ProcessColors[cellPID].HasKey(colIdx)) {
                NumPut(ProcessColors[cellPID][colIdx], lParam + 0, (A_PtrSize * 8) + 4, "UInt")
            }
            return CDRF_DODEFAULT
        }
    }
}

GetSelectedTargets:
TargetPIDs := []
SelectedNames := {}

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
    SetPriorityWin32(CurrentPID, 0x00000100)
}
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
    SetPriorityWin32(CurrentPID, 0x00000040)
    Sleep, 10
    SetProcessEcoMode(CurrentPID, true)
}
Loop % LV_GetCount()
    LV_Modify(A_Index, "-Check")

GoSub, RefreshList
return

SetProcessEcoMode(PID, Enable := true) {
    hProcess := DllCall("OpenProcess", "UInt", 0x1F0FFF, "Int", false, "UInt", PID, "Ptr")  
    if (!hProcess)
        return false
    VarSetCapacity(PowerThrottling, 12, 0)  
    NumPut(1, PowerThrottling, 0, "UInt")  
    NumPut(1, PowerThrottling, 4, "UInt")  
    if (Enable)
        NumPut(1, PowerThrottling, 8, "UInt")  
    else
        NumPut(0, PowerThrottling, 8, "UInt")  
    result := DllCall("kernel32.dll\SetProcessInformation"
        , "Ptr", hProcess
        , "Int", 4                                             
        , "Ptr", &PowerThrottling
        , "UInt", 12                                           
        , "Int")                                               
    DllCall("CloseHandle", "Ptr", hProcess)
    return result ? true : false
}

ListEvent:
if (A_GuiEvent == "Normal" || A_GuiEvent == "K") {
    ClickedRow := A_EventInfo
    if (ClickedRow > 0) {
        IsChecked := LV_GetNext(ClickedRow - 1, "Checked") == ClickedRow
        if (IsChecked)
            LV_Modify(ClickedRow, "-Check")
        else
            LV_Modify(ClickedRow, "+Check")
    }
}
return

GuiClose:
ExitApp