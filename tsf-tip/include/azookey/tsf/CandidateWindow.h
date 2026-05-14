#pragma once

#include <Windows.h>
#include <functional>
#include <string>
#include <vector>

namespace azookey::tsf {

// Popup window that displays the IME candidate list.
// Must be created and used on the same thread (no internal locking).
class CandidateWindow {
 public:
  CandidateWindow();
  ~CandidateWindow();

  CandidateWindow(const CandidateWindow&) = delete;
  CandidateWindow& operator=(const CandidateWindow&) = delete;

  // Create the underlying HWND. Call once after the TIP is activated.
  bool Create();
  void Destroy();

  // Show at screen point 'pt' (bottom-left of the caret rect) with given items.
  // selected_idx is clamped to [0, items.size()).
  void Show(POINT pt, const std::vector<std::wstring>& items, int selected_idx);
  void Hide();
  bool IsVisible() const;

  // Move selection by delta (+1 = down, -1 = up). Wraps around.
  void MoveSelection(int delta);
  void SetSelected(int idx);
  int GetSelected() const { return selected_idx_; }
  int GetCount() const { return static_cast<int>(items_.size()); }

  // Invoked when the user left-clicks a candidate row.
  using OnClickFn = std::function<void(int idx)>;
  void SetOnClick(OnClickFn fn) { on_click_ = std::move(fn); }

 private:
  HWND hwnd_{nullptr};
  std::vector<std::wstring> items_;
  int selected_idx_{0};
  OnClickFn on_click_;

  static constexpr int kItemHeight = 24;
  static constexpr int kHorzPad = 8;
  static constexpr int kMaxWidth = 400;

  static ATOM RegisterWindowClass();
  static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam);
  LRESULT HandleMessage(UINT msg, WPARAM wParam, LPARAM lParam);
  void Repaint() const;
};

}  // namespace azookey::tsf
