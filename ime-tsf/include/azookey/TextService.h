#pragma once

#include <Windows.h>
#include <msctf.h>

#include <memory>
#include <string>

#include "azookey/core/IConverter.h"
#include "azookey/core/RomajiKanaConverter.h"

namespace azookey::tsf {

class TextService final : public ITfTextInputProcessorEx,
                          public ITfKeyEventSink,
                          public ITfCompositionSink {
 public:
  explicit TextService(std::unique_ptr<core::IConverter> converter);

  // IUnknown
  STDMETHODIMP QueryInterface(REFIID riid, void** ppvObj) override;
  STDMETHODIMP_(ULONG) AddRef() override;
  STDMETHODIMP_(ULONG) Release() override;

  // ITfTextInputProcessor
  STDMETHODIMP Activate(ITfThreadMgr* ptim, TfClientId tid) override;
  STDMETHODIMP Deactivate() override;

  // ITfTextInputProcessorEx
  STDMETHODIMP ActivateEx(ITfThreadMgr* ptim, TfClientId tid, DWORD dwFlags) override;

  // ITfKeyEventSink
  STDMETHODIMP OnSetFocus(BOOL foreground) override;
  STDMETHODIMP OnTestKeyDown(ITfContext* context, WPARAM wParam, LPARAM lParam, BOOL* eaten) override;
  STDMETHODIMP OnTestKeyUp(ITfContext* context, WPARAM wParam, LPARAM lParam, BOOL* eaten) override;
  STDMETHODIMP OnKeyDown(ITfContext* context, WPARAM wParam, LPARAM lParam, BOOL* eaten) override;
  STDMETHODIMP OnKeyUp(ITfContext* context, WPARAM wParam, LPARAM lParam, BOOL* eaten) override;
  STDMETHODIMP OnPreservedKey(ITfContext* context, REFGUID rguid, BOOL* eaten) override;

  // ITfCompositionSink
  STDMETHODIMP OnCompositionTerminated(TfEditCookie ecWrite, ITfComposition* pComposition) override;

 private:
  HRESULT StartComposition(ITfContext* context);
  HRESULT UpdateComposition(ITfContext* context);
  HRESULT CommitComposition(ITfContext* context);
  void CancelComposition();

  LONG ref_count_{1};
  TfClientId client_id_{TF_CLIENTID_NULL};
  ITfThreadMgr* thread_mgr_{nullptr};
  ITfContext* context_{nullptr};
  ITfComposition* composition_{nullptr};

  core::RomajiKanaConverter romaji_converter_;
  std::unique_ptr<core::IConverter> converter_;
  std::string preedit_kana_;
};

}  // namespace azookey::tsf
