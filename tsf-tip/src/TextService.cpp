#include "azookey/tsf/TextService.h"

#include <chrono>
#include <optional>
#include <thread>

#include "azookey/ipc/NamedPipeTransport.h"
#include "azookey/ipc/Payloads.h"
#include "azookey/tsf/DisplayAttribute.h"

namespace {

constexpr const char* kTipVersion = "0.1.0";

void DebugLog(const std::string& message) {
#ifdef _DEBUG
  OutputDebugStringA(("[azooKey TIP] " + message + "\n").c_str());
#else
  UNREFERENCED_PARAMETER(message);
#endif
}

// Convert UTF-8 string to UTF-16.
std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) return {};
  const int len = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()),
                                      nullptr, 0);
  if (len <= 0) return {};
  std::wstring result(len, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()), result.data(), len);
  return result;
}

}  // namespace

namespace azookey::tsf {

TextService::TextService() = default;

TextService::~TextService() {
  StopIpcWorker();
}

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
  StartIpcWorker();
  return S_OK;
}

STDMETHODIMP TextService::Deactivate() {
  StopIpcWorker();

  // Properly end any active composition via a synchronous write edit session
  // so TSF can clean up the composing range in the document (P2).
  if (composition_ && active_context_) {
    preedit_kana_.clear();
    romaji_.Reset();
    ITfEditSession* edit = new EditSession(this, active_context_);
    HRESULT hr = S_OK;
    active_context_->RequestEditSession(client_id_, edit, TF_ES_SYNC | TF_ES_READWRITE, &hr);
    edit->Release();
  } else if (composition_) {
    composition_->Release();
    composition_ = nullptr;
  }

  if (active_context_) {
    active_context_->Release();
    active_context_ = nullptr;
  }
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
  *eaten = (wParam == VK_BACK || wParam == VK_SPACE || wParam == VK_RETURN ||
            wParam == VK_ESCAPE || (wParam >= 'A' && wParam <= 'Z'));
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
      PostQueryCandidates(preedit_kana_);
      *eaten = TRUE;
    } else if (wParam == VK_BACK) {
      if (!preedit_kana_.empty()) {
        // Remove last UTF-8 character (may be multi-byte).
        auto& s = preedit_kana_;
        size_t i = s.size();
        // Walk back past continuation bytes (10xxxxxx).
        while (i > 0 && (s[i - 1] & 0xC0) == 0x80) --i;
        if (i > 0) --i;  // remove the leading byte
        s.erase(i);
        romaji_.Reset();
        RequestPreeditUpdate(context);
        if (!preedit_kana_.empty()) PostQueryCandidates(preedit_kana_);
        *eaten = TRUE;
      }
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

STDMETHODIMP TextService::OnCompositionTerminated(TfEditCookie /*ecWrite*/, ITfComposition* pComposition) {
  if (composition_ == pComposition) {
    composition_->Release();
    composition_ = nullptr;
  }
  preedit_kana_.clear();
  romaji_.Reset();
  return S_OK;
}

STDMETHODIMP TextService::EnumDisplayAttributeInfo(IEnumTfDisplayAttributeInfo** ppEnum) {
  if (!ppEnum) return E_INVALIDARG;
  *ppEnum = new azookey::tsf::EnumDisplayAttributeInfo();
  return S_OK;
}

STDMETHODIMP TextService::GetDisplayAttributeInfo(REFGUID guidInfo, ITfDisplayAttributeInfo** ppInfo) {
  if (!ppInfo) return E_INVALIDARG;
  *ppInfo = nullptr;
  if (IsEqualGUID(guidInfo, kInputAttributeGuid)) {
    *ppInfo = new InputDisplayAttributeInfo();
    return S_OK;
  }
  return E_INVALIDARG;
}

HRESULT TextService::RequestPreeditUpdate(ITfContext* context) {
  if (!context) return E_INVALIDARG;
  // Keep a reference to the last active context so Deactivate can end composition.
  if (active_context_ != context) {
    if (active_context_) active_context_->Release();
    active_context_ = context;
    active_context_->AddRef();
  }
  ITfEditSession* edit = new EditSession(this, context);
  HRESULT hr = S_OK;
  context->RequestEditSession(client_id_, edit, TF_ES_ASYNCDONTCARE | TF_ES_READWRITE, &hr);
  edit->Release();
  return hr;
}

// --- IPC worker ---

void TextService::StartIpcWorker() {
  ipc_stop_.store(false);
  ipc_thread_ = std::thread(&TextService::IpcWorkerThread, this);
}

void TextService::StopIpcWorker() {
  if (!ipc_thread_.joinable()) return;
  {
    std::lock_guard<std::mutex> lock(ipc_mtx_);
    ipc_stop_.store(true);
  }
  ipc_cv_.notify_one();
  // Disconnect the pipe so any blocking Receive() in the worker returns
  // immediately with an error rather than waiting for the next message (P1).
  ipc_client_.Disconnect();
  ipc_thread_.join();
}

void TextService::IpcWorkerThread() {
  using namespace azookey::ipc;

  const auto pipe_name = DefaultPipeName();
  if (!ipc_client_.Connect(pipe_name, 5000)) {
    DebugLog("IPC: host pipe unavailable: " + pipe_name);
    return;
  }

  // Handshake
  HandshakeRequest hs;
  hs.tip_version = kTipVersion;
  hs.protocol_version = 1;
  hs.capabilities = {"ping", "query_candidates"};

  Envelope henv;
  henv.version = 1;
  henv.request_id = 1;
  henv.trace_id = "tip-activate-handshake";
  henv.type = MessageType::Handshake;
  henv.payload_json = BuildHandshakeRequest(hs);

  if (!ipc_client_.Send(henv)) { DebugLog("IPC: handshake send failed"); return; }
  auto hres = ipc_client_.Receive();
  auto hpayload = hres ? ParseHandshakeResponse(hres->payload_json) : std::nullopt;
  if (!hpayload || !hpayload->accepted) { DebugLog("IPC: handshake rejected"); return; }
  DebugLog("IPC: connected to host " + hpayload->host_version);

  uint64_t next_id = 2;

  while (true) {
    std::string reading;
    uint64_t req_id = 0;

    {
      std::unique_lock<std::mutex> lock(ipc_mtx_);
      ipc_cv_.wait(lock, [this] { return ipc_stop_.load() || ipc_has_request_; });
      if (ipc_stop_.load()) break;
      reading = ipc_pending_reading_;
      req_id = ipc_pending_id_;
      ipc_has_request_ = false;
    }

    if (reading.empty()) continue;

    QueryCandidatesRequest qreq;
    qreq.reading = reading;
    qreq.left_context = "";
    qreq.max_candidates = 10;
    qreq.live = true;

    Envelope qenv;
    qenv.version = 1;
    qenv.request_id = req_id;
    qenv.trace_id = "tip-key-query";
    qenv.type = MessageType::QueryCandidates;
    qenv.payload_json = BuildQueryCandidatesRequest(qreq);

    if (!ipc_client_.Send(qenv)) { DebugLog("IPC: QueryCandidates send failed"); break; }

    // Receive() returns nullopt if Disconnect() closed the pipe during shutdown.
    auto qres = ipc_client_.Receive();
    if (!qres) {
      if (!ipc_stop_.load()) DebugLog("IPC: QueryCandidates receive failed");
      break;
    }

    auto qpayload = ParseQueryCandidatesResponse(qres->payload_json);
    if (qpayload && !qpayload->candidates.empty()) {
      DebugLog("IPC: " + std::to_string(qpayload->candidates.size()) +
               " candidates for [" + reading + "] top=" + qpayload->candidates[0].surface);
      std::lock_guard<std::mutex> lock(candidates_mtx_);
      candidates_ = qpayload->candidates;
    }

    ++next_id;
  }

  DebugLog("IPC: worker exiting");
}

void TextService::PostQueryCandidates(const std::string& reading) {
  std::lock_guard<std::mutex> lock(ipc_mtx_);
  ipc_pending_reading_ = reading;
  ++ipc_pending_id_;
  ipc_has_request_ = true;
  ipc_cv_.notify_one();
}

// --- EditSession ---

EditSession::EditSession(TextService* service, ITfContext* context)
    : service_(service), context_(context) {
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
  const std::wstring kana = Utf8ToWide(service_->preedit_kana_);

  // End composition when preedit is empty.
  if (kana.empty()) {
    if (service_->composition_) {
      service_->composition_->EndComposition(ec);
      service_->composition_->Release();
      service_->composition_ = nullptr;
    }
    return S_OK;
  }

  // Create composition if not active.
  if (!service_->composition_) {
    ITfContextComposition* pCtxComp = nullptr;
    if (FAILED(context_->QueryInterface(IID_ITfContextComposition,
                                        reinterpret_cast<void**>(&pCtxComp))) ||
        !pCtxComp)
      return E_FAIL;

    TF_SELECTION sel{};
    ULONG fetched = 0;
    context_->GetSelection(ec, TF_DEFAULT_SELECTION, 1, &sel, &fetched);
    if (fetched == 0) {
      pCtxComp->Release();
      return E_FAIL;
    }

    sel.range->Collapse(ec, TF_ANCHOR_END);
    HRESULT hr = pCtxComp->StartComposition(ec, sel.range, service_,
                                             &service_->composition_);
    sel.range->Release();
    pCtxComp->Release();
    if (FAILED(hr) || !service_->composition_) return hr;
  }

  // Update composition text.
  ITfRange* pRange = nullptr;
  if (FAILED(service_->composition_->GetRange(&pRange)) || !pRange) return E_FAIL;

  pRange->SetText(ec, 0, kana.c_str(), static_cast<LONG>(kana.size()));

  // Apply underline display attribute via GUID_PROP_ATTRIBUTE.
  ITfProperty* pProp = nullptr;
  if (SUCCEEDED(context_->GetProperty(GUID_PROP_ATTRIBUTE, &pProp)) && pProp) {
    // Register the GUID as a TfGuidAtom via ITfCategoryMgr.
    ITfCategoryMgr* pCatMgr = nullptr;
    if (SUCCEEDED(CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER,
                                   IID_ITfCategoryMgr, reinterpret_cast<void**>(&pCatMgr))) &&
        pCatMgr) {
      TfGuidAtom atom = TF_INVALID_GUIDATOM;
      pCatMgr->RegisterGUID(kInputAttributeGuid, &atom);
      if (atom != TF_INVALID_GUIDATOM) {
        VARIANT var;
        var.vt = VT_I4;
        var.lVal = static_cast<LONG>(atom);
        pProp->SetValue(ec, pRange, &var);
      }
      pCatMgr->Release();
    }
    pProp->Release();
  }

  pRange->Release();
  return S_OK;
}

}  // namespace azookey::tsf
