#!/usr/bin/env python3
"""
Auto build and run app via DevEco Studio using pyautogui
"""
import pyautogui
import time
import sys
import subprocess

def find_and_activate_deveco():
    """Find and activate DevEco Studio window using PowerShell"""
    ps_script = '''
Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    public class WinAPI {
        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);
        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    }
"@

$proc = Get-Process | Where-Object {$_.ProcessName -eq "devecostudio64" -and $_.MainWindowHandle -ne 0} | Select-Object -First 1
if ($proc) {
    [WinAPI]::ShowWindow($proc.MainWindowHandle, 9)  # SW_RESTORE
    [WinAPI]::SetForegroundWindow($proc.MainWindowHandle)
    Write-Host "OK"
} else {
    Write-Host "NOT_FOUND"
}
'''
    result = subprocess.run(
        ['powershell', '-Command', ps_script],
        capture_output=True,
        text=True
    )
    return 'OK' in result.stdout

def build_and_run():
    print("Activating DevEco Studio window...")
    
    if not find_and_activate_deveco():
        print("ERROR: Could not activate DevEco Studio!")
        return False
    
    print("Window activated. Waiting...")
    time.sleep(1.5)
    
    # First try Build Project (Ctrl+F9)
    print("Triggering Build (Ctrl+F9)...")
    pyautogui.hotkey('ctrl', 'F9')
    time.sleep(3)
    
    # Then Run (Shift+F10)
    print("Triggering Run (Shift+F10)...")
    pyautogui.hotkey('shift', 'F10')
    time.sleep(1)
    
    print("Build and Run triggered!")
    return True

if __name__ == '__main__':
    pyautogui.FAILSAFE = False
    success = build_and_run()
    sys.exit(0 if success else 1)
