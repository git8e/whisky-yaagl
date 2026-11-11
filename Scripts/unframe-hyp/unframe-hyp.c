/*
 * unframe-hyp.exe
 *
 * HoYoPlay's main window keeps WS_CAPTION set. Wine's macOS driver turns that
 * into a real NSWindow title bar, which appears above HoYoPlay's own header
 * (a double title bar). Wine 11 removed the old per-application "Decorated"
 * setting, so the window is made frameless from the Windows side instead: the
 * caption is removed while the window stays otherwise intact.
 *
 * Run this inside the same Wine prefix as HoYoPlay. It waits up to two minutes
 * for the main window, strips the caption once, and exits.
 */

#include <windows.h>

static BOOL CALLBACK strip_caption(HWND hwnd, LPARAM lParam)
{
    WCHAR title[512];
    WCHAR class_name[256];
    HWND *found = (HWND *)lParam;

    if (!IsWindowVisible(hwnd)) return TRUE;
    if (!GetWindowTextW(hwnd, title, ARRAYSIZE(title))) return TRUE;
    if (lstrcmpW(title, L"HoYoPlay") != 0) return TRUE;
    if (!GetClassNameW(hwnd, class_name, ARRAYSIZE(class_name))) return TRUE;
    if (wcsncmp(class_name, L"Qt5", 3) != 0) return TRUE;

    RECT rect;
    if (!GetWindowRect(hwnd, &rect)) return TRUE;
    if ((rect.right - rect.left) < 800) return TRUE;

    LONG_PTR style = GetWindowLongPtrW(hwnd, GWL_STYLE);
    if ((style & WS_CAPTION) == WS_CAPTION) {
        SetWindowLongPtrW(hwnd, GWL_STYLE, style & ~WS_CAPTION);
        SetWindowPos(hwnd, NULL, 0, 0, 0, 0,
                     SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                     SWP_NOACTIVATE | SWP_FRAMECHANGED);
    }

    *found = hwnd;
    return FALSE;
}

int wmain(void)
{
    HWND found = NULL;

    /* 120 s at 100 ms intervals. */
    for (int i = 0; i < 1200 && !found; i++) {
        EnumWindows(strip_caption, (LPARAM)&found);
        if (!found) Sleep(100);
    }

    return found ? 0 : 1;
}
