#include "azookey/tsf/CandidateWindow.h"

#include <algorithm>
#include <string>

namespace azookey::tsf {

namespace {
constexpr wchar_t kClassName[] = L"azooKeyCandidateWnd";

HMODULE GetTipModuleHandle() {
  HMODULE module = nullptr;
  if (GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                             GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                         reinterpret_cast<LPCWSTR>(&GetTipModuleHandle), &module)) {
    return module;
  }
  return nullptr;
}
}

CandidateWindow::CandidateWindow() = default;

CandidateWindow::~CandidateWindow() { Destroy(); }

// static
ATOM CandidateWindow::RegisterWindowClass() {
  WNDCLASSEXW wc{};
  wc.cbSize = sizeof(wc);
  wc.style = CS_HREDRAW | CS_VREDRAW | CS_DROPSHADOW;
  wc.lpfnWndProc = WndProc;
  wc.hInstance = GetTipModuleHandle();
  wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
  wc.lpszClassName = kClassName;
  ATOM a = RegisterClassExW(&wc);
  if (!a && GetLastError() == ERROR_CLASS_ALREADY_EXISTS) {
    // Already registered from a previous activation; retrieve the atom.
    WNDCLASSEXW existing{};
    existing.cbSize = sizeof(existing);
    GetClassInfoExW(GetTipModuleHandle(), kClassName, &existing);
    a = static_cast<ATOM>(GetClassLongW(
        FindWindowW(kClassName, nullptr) ? FindWindowW(kClassName, nullptr)
                                         : HWND_DESKTOP,
        GCW_ATOM));
    // Fallback: return a non-zero sentinel so Create() proceeds.
    if (!a) a = 1;
  }
  return a;
}

bool CandidateWindow::Create() {
  static ATOM s_atom = RegisterWindowClass();
  (void)s_atom;

  hwnd_ = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
      kClassName, nullptr,
      WS_POPUP | WS_BORDER,
      0, 0, 200, kItemHeight,
      nullptr, nullptr,
      GetTipModuleHandle(), this);
  return hwnd_ != nullptr;
}

void CandidateWindow::Destroy() {
  if (hwnd_) {
    DestroyWindow(hwnd_);
    // hwnd_ is cleared in WM_DESTROY handler.
  }
}

void CandidateWindow::Show(POINT pt, const std::vector<std::wstring>& items, int selected_idx) {
  if (!hwnd_ || items.empty()) return;

  items_ = items;
  selected_idx_ = std::clamp(selected_idx, 0, static_cast<int>(items_.size()) - 1);

  // Measure maximum text width using the window's DC.
  HDC hdc = GetDC(hwnd_);
  HFONT font = static_cast<HFONT>(GetStockObject(DEFAULT_GUI_FONT));
  HFONT old_font = static_cast<HFONT>(SelectObject(hdc, font));
  int max_text_w = 60;
  for (int i = 0; i < static_cast<int>(items_.size()); ++i) {
    std::wstring label = std::to_wstring(i + 1) + L". " + items_[i];
    SIZE sz{};
    GetTextExtentPoint32W(hdc, label.c_str(), static_cast<int>(label.size()), &sz);
    max_text_w = std::max(max_text_w, static_cast<int>(sz.cx));
  }
  SelectObject(hdc, old_font);
  ReleaseDC(hwnd_, hdc);

  int width = std::min(max_text_w + kHorzPad * 2 + 4, kMaxWidth);
  int height = kItemHeight * static_cast<int>(items_.size());

  // Keep window on-screen: flip above caret if it would overflow below.
  HMONITOR mon = MonitorFromPoint(pt, MONITOR_DEFAULTTONEAREST);
  MONITORINFO mi{};
  mi.cbSize = sizeof(mi);
  GetMonitorInfoW(mon, &mi);
  if (pt.x + width > mi.rcWork.right) pt.x = mi.rcWork.right - width;
  if (pt.x < mi.rcWork.left) pt.x = mi.rcWork.left;
  if (pt.y + height > mi.rcWork.bottom) {
    // Estimate caret height ~20px — flip to open upward.
    pt.y = pt.y - height - 20;
  }
  if (pt.y < mi.rcWork.top) pt.y = mi.rcWork.top;

  SetWindowPos(hwnd_, HWND_TOPMOST, pt.x, pt.y, width, height,
               SWP_SHOWWINDOW | SWP_NOACTIVATE);
  InvalidateRect(hwnd_, nullptr, TRUE);
}

void CandidateWindow::Hide() {
  if (hwnd_) ShowWindow(hwnd_, SW_HIDE);
}

bool CandidateWindow::IsVisible() const {
  return hwnd_ && IsWindowVisible(hwnd_);
}

void CandidateWindow::MoveSelection(int delta) {
  if (items_.empty()) return;
  int n = static_cast<int>(items_.size());
  selected_idx_ = (selected_idx_ + delta % n + n) % n;
  Repaint();
}

void CandidateWindow::SetSelected(int idx) {
  if (items_.empty()) return;
  selected_idx_ = std::clamp(idx, 0, static_cast<int>(items_.size()) - 1);
  Repaint();
}

void CandidateWindow::Repaint() const {
  if (hwnd_) InvalidateRect(hwnd_, nullptr, FALSE);
}

// static
LRESULT CALLBACK CandidateWindow::WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
  CandidateWindow* self = nullptr;
  if (msg == WM_NCCREATE) {
    auto* cs = reinterpret_cast<CREATESTRUCTW*>(lParam);
    self = static_cast<CandidateWindow*>(cs->lpCreateParams);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    self->hwnd_ = hwnd;
  } else {
    self = reinterpret_cast<CandidateWindow*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  }
  if (self) return self->HandleMessage(hwnd, msg, wParam, lParam);
  return DefWindowProcW(hwnd, msg, wParam, lParam);
}

LRESULT CandidateWindow::HandleMessage(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
  switch (msg) {
    case WM_MOUSEACTIVATE:
      return MA_NOACTIVATE;

    case WM_PAINT: {
      PAINTSTRUCT ps;
      HDC hdc = BeginPaint(hwnd_, &ps);
      HFONT font = static_cast<HFONT>(GetStockObject(DEFAULT_GUI_FONT));
      HFONT old_font = static_cast<HFONT>(SelectObject(hdc, font));
      SetBkMode(hdc, TRANSPARENT);

      RECT client_rc{};
      GetClientRect(hwnd_, &client_rc);

      for (int i = 0; i < static_cast<int>(items_.size()); ++i) {
        RECT row_rc = {0, i * kItemHeight, client_rc.right, (i + 1) * kItemHeight};
        if (i == selected_idx_) {
          FillRect(hdc, &row_rc,
                   reinterpret_cast<HBRUSH>(static_cast<INT_PTR>(COLOR_HIGHLIGHT + 1)));
          SetTextColor(hdc, GetSysColor(COLOR_HIGHLIGHTTEXT));
        } else {
          FillRect(hdc, &row_rc,
                   reinterpret_cast<HBRUSH>(static_cast<INT_PTR>(COLOR_WINDOW + 1)));
          SetTextColor(hdc, GetSysColor(COLOR_WINDOWTEXT));
        }
        std::wstring label = std::to_wstring(i + 1) + L". " + items_[i];
        RECT text_rc = row_rc;
        text_rc.left += kHorzPad;
        DrawTextW(hdc, label.c_str(), static_cast<int>(label.size()), &text_rc,
                  DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX | DT_END_ELLIPSIS);
      }
      SelectObject(hdc, old_font);
      EndPaint(hwnd_, &ps);
      return 0;
    }

    case WM_LBUTTONDOWN: {
      int y = static_cast<int>(HIWORD(lParam));
      int idx = y / kItemHeight;
      if (idx >= 0 && idx < static_cast<int>(items_.size())) {
        selected_idx_ = idx;
        Repaint();
        if (on_click_) on_click_(idx);
      }
      return 0;
    }

    case WM_DESTROY:
      hwnd_ = nullptr;
      return 0;

    default:
      // Use the hwnd parameter from WndProc, not the hwnd_ member: after
      // WM_DESTROY sets hwnd_ to nullptr, trailing messages (e.g. WM_NCDESTROY)
      // would otherwise forward with a null handle.
      return DefWindowProcW(hwnd, msg, wParam, lParam);
  }
}

}  // namespace azookey::tsf
