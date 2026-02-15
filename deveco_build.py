"""
DevEco Studio Automation Script
Uses pyautogui to automate building HarmonyOS apps
"""
import pyautogui
import pygetwindow as gw
import time
import subprocess
import os
import sys

# Safety settings
pyautogui.FAILSAFE = True  # Move mouse to corner to abort
pyautogui.PAUSE = 0.5  # Pause between actions

PROJECT_PATH = r"C:\Users\Liuho\ClawdBotHarmony"
DEVECO_PATH = r"C:\Program Files\Huawei\DevEco Studio\bin\devecostudio64.exe"
HAP_PATH = r"C:\Users\Liuho\ClawdBotHarmony\entry\build\default\outputs\default\entry-default-signed.hap"
HDC_PATH = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"

def find_deveco_window():
    """Find DevEco Studio window"""
    windows = gw.getWindowsWithTitle('DevEco Studio')
    if windows:
        return windows[0]
    # Also try partial match
    for w in gw.getAllWindows():
        if 'DevEco' in w.title:
            return w
    return None

def open_deveco():
    """Open DevEco Studio if not running"""
    win = find_deveco_window()
    if win:
        print(f"DevEco Studio already open: {win.title}")
        win.activate()
        time.sleep(1)
        return True
    
    print("Opening DevEco Studio...")
    subprocess.Popen([DEVECO_PATH])
    
    # Wait for window to appear (up to 60 seconds)
    for i in range(60):
        time.sleep(1)
        win = find_deveco_window()
        if win:
            print(f"DevEco Studio opened: {win.title}")
            win.activate()
            time.sleep(3)  # Wait for UI to load
            return True
        print(f"Waiting... {i+1}s")
    
    print("Failed to open DevEco Studio")
    return False

def build_hap():
    """Trigger Build -> Build Hap(s)/APP(s) -> Build Hap(s)"""
    win = find_deveco_window()
    if not win:
        print("DevEco Studio not found")
        return False
    
    win.activate()
    time.sleep(0.5)
    
    print("Opening Build menu...")
    # Use keyboard shortcut or menu
    # Try Alt+B for Build menu
    pyautogui.hotkey('alt', 'b')
    time.sleep(0.5)
    
    # Look for "Build Hap" option and click it
    # This might need adjustment based on menu structure
    print("Selecting Build Hap(s)/APP(s)...")
    pyautogui.press('down')  # Navigate to Build Hap(s)
    time.sleep(0.2)
    pyautogui.press('down')
    time.sleep(0.2)
    pyautogui.press('right')  # Open submenu
    time.sleep(0.3)
    pyautogui.press('enter')  # Select Build Hap(s)
    
    print("Build triggered. Waiting for completion...")
    return True

def wait_for_build(timeout=300):
    """Wait for build to complete by checking for HAP file"""
    start = time.time()
    # Check for HAP file modification time
    initial_mtime = 0
    if os.path.exists(HAP_PATH):
        initial_mtime = os.path.getmtime(HAP_PATH)
    
    while time.time() - start < timeout:
        time.sleep(5)
        if os.path.exists(HAP_PATH):
            current_mtime = os.path.getmtime(HAP_PATH)
            if current_mtime > initial_mtime:
                print(f"Build completed! HAP updated at {time.ctime(current_mtime)}")
                return True
        print(f"Waiting for build... {int(time.time() - start)}s")
    
    print("Build timeout")
    return False

def install_hap():
    """Install HAP to device using hdc"""
    if not os.path.exists(HAP_PATH):
        print(f"HAP file not found: {HAP_PATH}")
        return False
    
    print(f"Installing HAP to device...")
    result = subprocess.run([HDC_PATH, "install", HAP_PATH], capture_output=True, text=True)
    print(result.stdout)
    if result.returncode == 0:
        print("Installation successful!")
        return True
    else:
        print(f"Installation failed: {result.stderr}")
        return False

def main():
    print("=" * 50)
    print("DevEco Studio Build Automation")
    print("=" * 50)
    
    # Step 1: Open DevEco Studio
    if not open_deveco():
        sys.exit(1)
    
    # Step 2: Build
    if not build_hap():
        sys.exit(1)
    
    # Step 3: Wait for build
    if not wait_for_build():
        sys.exit(1)
    
    # Step 4: Install
    if not install_hap():
        sys.exit(1)
    
    print("\n" + "=" * 50)
    print("SUCCESS: App built and installed!")
    print("=" * 50)

if __name__ == "__main__":
    main()
