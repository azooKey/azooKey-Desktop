#include "azookey/tsf/TextService.h"

namespace azookey::tsf {

TextService::TextService() = default;

STDMETHODIMP TextService::QueryInterface(REFIID riid, void** ppvObj) {
  if (!ppvObj) return E_INVALIDARG;
  *ppvObj = nullptr;
  if (riid == IID_IUnknown || riid == IID_ITfTextInputProcessor || riid == IID_ITfTextInputProcessorEx) {
    *ppvObj = static_cast<ITfTextInputProcessorEx*>(this);
  } else if (riid == IID_ITfKeyEventSink) {
    *ppvObj = static_cast<ITfKeyEventSink*>(this);
  } else if (riid == IID_ITfThreadMgrEventSink) {
    *ppvObj = static_cast<ITfThreadMgrEventSink*>(this);
  } else if (riid == IID_ITfCompositionSink) {
    *ppvObj = static_cast<ITfCompositionSink*>(this);
  } else if (riid == IID_ITfDisplayAttributeProvider) {
    *ppvObj = static_cast<ITfDisplayAttributeProvider*>(this);
  } else {
    return E_NOINTERFACE;
  }
  AddRef();
  return S_OK;
}

STDMETHODIMP_(ULONG) TextService::AddRef() { return static_cast<ULONG>(InterlockedIncrement(&ref_count_)); }
STDMETHODIMP_(ULONG) TextService::Release() {
  const auto c = static_cast<ULONG>(InterlockedDecrement(&ref_count_));
  if (c == 0) delete this;
  return c;
}

STDMETHODIMP TextService::Activate(ITfThreadMgr* ptim, TfClientId tid) { return ActivateEx(ptim, tid, 0); }

STDMETHODIMP TextService::ActivateEx(ITfThreadMgr* ptim, TfClientId tid, DWORD dwFlags) {
  UNREFERENCED_PARAMETER(dwFlags);
  thread_mgr_ = ptim;
  client_id_ = tid;
  if (thread_mgr_) thread_mgr_->AddRef();
  return S_OK;
}

STDMETHODIMP TextService::Deactivate() {
  if (thread_mgr_) {
    thread_mgr_->Release();
    thread_mgr_ = nullptr;
  }
  return S_OK;
}

STDMETHODIMP TextService::OnSetFocus(BOOL foreground) {
  UNREFERENCED_PARAMETER(foreground);
  return S_OK;
}
STDMETHODIMP TextService::OnTestKeyDown(ITfContext* context, WPARAM wParam, LPARAM lParam, BOOL* eaten) {
  UNREFERENCED_PARAMETER(context); UNREFERENCED_PARAMETER(lParam);
  if (!eaten) return E_INVALIDARG;
  *eaten = (wParam == VK_SPACE || wParam == VK_RETURN || wParam == VK_ESCAPE || (wParam >= 'A' && wParam <= 'Z'));
  return S_OK;
}
STDMETHODIMP TextService::OnTestKeyUp(ITfContext* context, WPARAM wParam, LPARAM lParam, BOOL* eaten) {
  UNREFERENCED_PARAMETER(context); UNREFERENCED_PARAMETER(wParam); UNREFERENCED_PARAMETER(lParam);
  if (!eaten) return E_INVALIDARG;
  *eaten = FALSE;
  return S_OK;
}
STDMETHODIMP TextService::OnKeyDown(ITfContext* context, WPARAM wParam, LPARAM lParam, BOOL* eaten) {
  UNREFERENCED_PARAMETER(lParam);
  if (!eaten) return E_INVALIDARG;
  *eaten = FALSE;
  try {
    if (wParam >= 'A' && wParam <= 'Z') {
      preedit_kana_ += romaji_.Feed(static_cast<char>(wParam));
      RequestPreeditUpdate(context);
      *eaten = TRUE;
    } else if (wParam == VK_ESCAPE) {
      preedit_kana_.clear();
      romaji_.Reset();
      RequestPreeditUpdate(context);
      *eaten = TRUE;
    }
  } catch (...) {
    return E_FAIL;
  }
  return S_OK;
}
STDMETHODIMP TextService::OnKeyUp(ITfContext* context, WPARAM wParam, LPARAM lParam, BOOL* eaten) {
  UNREFERENCED_PARAMETER(context); UNREFERENCED_PARAMETER(wParam); UNREFERENCED_PARAMETER(lParam);
  if (!eaten) return E_INVALIDARG;
  *eaten = FALSE;
  return S_OK;
}
STDMETHODIMP TextService::OnPreservedKey(ITfContext* context, REFGUID rguid, BOOL* eaten) {
  UNREFERENCED_PARAMETER(context); UNREFERENCED_PARAMETER(rguid);
  if (!eaten) return E_INVALIDARG;
  *eaten = FALSE;
  return S_OK;
}

STDMETHODIMP TextService::OnInitDocumentMgr(ITfDocumentMgr* pdim) { UNREFERENCED_PARAMETER(pdim); return S_OK; }
STDMETHODIMP TextService::OnUninitDocumentMgr(ITfDocumentMgr* pdim) { UNREFERENCED_PARAMETER(pdim); return S_OK; }
STDMETHODIMP TextService::OnSetFocus(ITfDocumentMgr* pdimFocus, ITfDocumentMgr* pdimPrevFocus) {
  UNREFERENCED_PARAMETER(pdimFocus); UNREFERENCED_PARAMETER(pdimPrevFocus); return S_OK;
}
STDMETHODIMP TextService::OnPushContext(ITfContext* pic) { UNREFERENCED_PARAMETER(pic); return S_OK; }
STDMETHODIMP TextService::OnPopContext(ITfContext* pic) { UNREFERENCED_PARAMETER(pic); return S_OK; }

STDMETHODIMP TextService::OnCompositionTerminated(TfEditCookie ecWrite, ITfComposition* pComposition) {
  UNREFERENCED_PARAMETER(ecWrite); UNREFERENCED_PARAMETER(pComposition); return S_OK;
}

STDMETHODIMP TextService::EnumDisplayAttributeInfo(IEnumTfDisplayAttributeInfo** ppEnum) {
  if (!ppEnum) return E_INVALIDARG;
  *ppEnum = nullptr;
  return E_NOTIMPL;
}
STDMETHODIMP TextService::GetDisplayAttributeInfo(REFGUID guidInfo, ITfDisplayAttributeInfo** ppInfo) {
  UNREFERENCED_PARAMETER(guidInfo);
  if (!ppInfo) return E_INVALIDARG;
  *ppInfo = nullptr;
  return E_NOTIMPL;
}

HRESULT TextService::RequestPreeditUpdate(ITfContext* context) {
  if (!context) return E_INVALIDARG;
  ITfEditSession* edit = new EditSession(this, context);
  HRESULT hr = S_OK;
  context->RequestEditSession(client_id_, edit, TF_ES_ASYNCDONTCARE | TF_ES_READWRITE, &hr);
  edit->Release();
  return hr;
}

EditSession::EditSession(TextService* service, ITfContext* context) : service_(service), context_(context) {
  if (context_) context_->AddRef();
}
STDMETHODIMP EditSession::QueryInterface(REFIID riid, void** ppvObj) {
  if (!ppvObj) return E_INVALIDARG;
  *ppvObj = nullptr;
  if (riid == IID_IUnknown || riid == IID_ITfEditSession) {
    *ppvObj = static_cast<ITfEditSession*>(this);
    AddRef();
    return S_OK;
  }
  return E_NOINTERFACE;
}
STDMETHODIMP_(ULONG) EditSession::AddRef() { return static_cast<ULONG>(InterlockedIncrement(&ref_count_)); }
STDMETHODIMP_(ULONG) EditSession::Release() {
  const auto c = static_cast<ULONG>(InterlockedDecrement(&ref_count_));
  if (c == 0) {
    if (context_) context_->Release();
    delete this;
  }
  return c;
}
STDMETHODIMP EditSession::DoEditSession(TfEditCookie ec) {
  UNREFERENCED_PARAMETER(ec);
  // TODO: update composition range + display attribute.
  return S_OK;
}

}  // namespace azookey::tsf
