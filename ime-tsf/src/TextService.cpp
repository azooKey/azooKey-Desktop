#include "azookey/TextService.h"

#include <exception>
#include <utility>

namespace azookey::tsf {

TextService::TextService(std::unique_ptr<core::IConverter> converter) : converter_(std::move(converter)) {}

STDMETHODIMP TextService::QueryInterface(REFIID riid, void** ppvObj) {
  if (!ppvObj) {
    return E_INVALIDARG;
  }
  *ppvObj = nullptr;

  if (riid == IID_IUnknown || riid == IID_ITfTextInputProcessor || riid == IID_ITfTextInputProcessorEx) {
    *ppvObj = static_cast<ITfTextInputProcessorEx*>(this);
  } else if (riid == IID_ITfKeyEventSink) {
    *ppvObj = static_cast<ITfKeyEventSink*>(this);
  } else if (riid == IID_ITfCompositionSink) {
    *ppvObj = static_cast<ITfCompositionSink*>(this);
  } else {
    return E_NOINTERFACE;
  }

  AddRef();
  return S_OK;
}

STDMETHODIMP_(ULONG) TextService::AddRef() { return static_cast<ULONG>(InterlockedIncrement(&ref_count_)); }

STDMETHODIMP_(ULONG) TextService::Release() {
  const ULONG current = static_cast<ULONG>(InterlockedDecrement(&ref_count_));
  if (current == 0) {
    delete this;
  }
  return current;
}

STDMETHODIMP TextService::Activate(ITfThreadMgr* ptim, TfClientId tid) { return ActivateEx(ptim, tid, 0); }

STDMETHODIMP TextService::ActivateEx(ITfThreadMgr* ptim, TfClientId tid, DWORD dwFlags) {
  UNREFERENCED_PARAMETER(dwFlags);
  thread_mgr_ = ptim;
  client_id_ = tid;
  if (thread_mgr_) {
    thread_mgr_->AddRef();
  }
  return S_OK;
}

STDMETHODIMP TextService::Deactivate() {
  CancelComposition();
  if (context_) {
    context_->Release();
    context_ = nullptr;
  }
  if (thread_mgr_) {
    thread_mgr_->Release();
    thread_mgr_ = nullptr;
  }
  client_id_ = TF_CLIENTID_NULL;
  return S_OK;
}

STDMETHODIMP TextService::OnSetFocus(BOOL foreground) {
  UNREFERENCED_PARAMETER(foreground);
  return S_OK;
}

STDMETHODIMP TextService::OnTestKeyDown(ITfContext* context, WPARAM wParam, LPARAM lParam, BOOL* eaten) {
  UNREFERENCED_PARAMETER(context);
  UNREFERENCED_PARAMETER(lParam);
  if (!eaten) {
    return E_INVALIDARG;
  }
  *eaten = (wParam == VK_SPACE || wParam == VK_RETURN || wParam == VK_ESCAPE || (wParam >= 'A' && wParam <= 'Z'));
  return S_OK;
}

STDMETHODIMP TextService::OnTestKeyUp(ITfContext* context, WPARAM wParam, LPARAM lParam, BOOL* eaten) {
  UNREFERENCED_PARAMETER(context);
  UNREFERENCED_PARAMETER(wParam);
  UNREFERENCED_PARAMETER(lParam);
  if (!eaten) {
    return E_INVALIDARG;
  }
  *eaten = FALSE;
  return S_OK;
}

STDMETHODIMP TextService::OnKeyDown(ITfContext* context, WPARAM wParam, LPARAM lParam, BOOL* eaten) {
  UNREFERENCED_PARAMETER(lParam);
  if (!eaten) {
    return E_INVALIDARG;
  }
  *eaten = FALSE;

  try {
    if (!context_) {
      context_ = context;
      if (context_) {
        context_->AddRef();
      }
    }

    if (wParam >= 'A' && wParam <= 'Z') {
      preedit_kana_ += romaji_converter_.Feed(static_cast<char>(wParam));
      StartComposition(context);
      UpdateComposition(context);
      *eaten = TRUE;
      return S_OK;
    }

    if (wParam == VK_SPACE && !preedit_kana_.empty()) {
      (void)converter_->Convert(preedit_kana_, "");
      *eaten = TRUE;
      return S_OK;
    }

    if (wParam == VK_RETURN && !preedit_kana_.empty()) {
      CommitComposition(context);
      *eaten = TRUE;
      return S_OK;
    }

    if (wParam == VK_ESCAPE && !preedit_kana_.empty()) {
      CancelComposition();
      preedit_kana_.clear();
      romaji_converter_.Reset();
      *eaten = TRUE;
      return S_OK;
    }
  } catch (...) {
    // COM boundary: never throw.
    *eaten = FALSE;
    return E_FAIL;
  }

  return S_OK;
}

STDMETHODIMP TextService::OnKeyUp(ITfContext* context, WPARAM wParam, LPARAM lParam, BOOL* eaten) {
  UNREFERENCED_PARAMETER(context);
  UNREFERENCED_PARAMETER(wParam);
  UNREFERENCED_PARAMETER(lParam);
  if (!eaten) {
    return E_INVALIDARG;
  }
  *eaten = FALSE;
  return S_OK;
}

STDMETHODIMP TextService::OnPreservedKey(ITfContext* context, REFGUID rguid, BOOL* eaten) {
  UNREFERENCED_PARAMETER(context);
  UNREFERENCED_PARAMETER(rguid);
  if (!eaten) {
    return E_INVALIDARG;
  }
  *eaten = FALSE;
  return S_OK;
}

STDMETHODIMP TextService::OnCompositionTerminated(TfEditCookie ecWrite, ITfComposition* pComposition) {
  UNREFERENCED_PARAMETER(ecWrite);
  UNREFERENCED_PARAMETER(pComposition);
  composition_ = nullptr;
  return S_OK;
}

HRESULT TextService::StartComposition(ITfContext* context) {
  UNREFERENCED_PARAMETER(context);
  return S_OK;
}

HRESULT TextService::UpdateComposition(ITfContext* context) {
  UNREFERENCED_PARAMETER(context);
  return S_OK;
}

HRESULT TextService::CommitComposition(ITfContext* context) {
  UNREFERENCED_PARAMETER(context);
  preedit_kana_.clear();
  romaji_converter_.Reset();
  CancelComposition();
  return S_OK;
}

void TextService::CancelComposition() {
  if (composition_) {
    composition_->EndComposition(TFEC_READWRITE);
    composition_->Release();
    composition_ = nullptr;
  }
}

}  // namespace azookey::tsf
