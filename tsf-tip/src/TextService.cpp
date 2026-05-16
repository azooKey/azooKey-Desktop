#include "azookey/tsf/TextService.h"

#include <utility>

#include "azookey/ipc/Payloads.h"

namespace azookey::tsf {

namespace {

void DebugLog(const wchar_t* message) {
  OutputDebugStringW(L"azooKey TIP: ");
  OutputDebugStringW(message);
  OutputDebugStringW(L"\n");
}

void DebugLog(const std::wstring& message) {
  DebugLog(message.c_str());
}

std::wstring Utf8ToWideString(const std::string& text) {
  if (text.empty()) return std::wstring();
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(),
                                         static_cast<int>(text.size()), nullptr, 0);
  if (length <= 0) return std::wstring();

  std::wstring result(static_cast<size_t>(length), L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(),
                      static_cast<int>(text.size()), result.data(), length);
  return result;
}

void PopLastAscii(std::string* text) {
  if (!text || text->empty()) return;
  text->pop_back();
}

}  // namespace

TextService::TextService() = default;
TextService::~TextService() {
  Deactivate();
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
  if (thread_mgr_) {
    thread_mgr_->AddRef();

    ITfKeystrokeMgr* keystroke_mgr = nullptr;
    if (SUCCEEDED(thread_mgr_->QueryInterface(IID_ITfKeystrokeMgr,
                                              reinterpret_cast<void**>(&keystroke_mgr)))) {
      if (SUCCEEDED(keystroke_mgr->AdviseKeyEventSink(
              client_id_, static_cast<ITfKeyEventSink*>(this), TRUE))) {
        key_event_sink_advised_ = true;
      }
      keystroke_mgr->Release();
    }

    ITfSource* source = nullptr;
    if (SUCCEEDED(thread_mgr_->QueryInterface(IID_ITfSource,
                                              reinterpret_cast<void**>(&source)))) {
      DWORD cookie = TF_INVALID_COOKIE;
      if (SUCCEEDED(source->AdviseSink(IID_ITfThreadMgrEventSink,
                                       static_cast<ITfThreadMgrEventSink*>(this),
                                       &cookie))) {
        thread_mgr_sink_cookie_ = cookie;
      }
      source->Release();
    }
  }
  ConnectHost();
  return S_OK;
}

STDMETHODIMP TextService::Deactivate() {
  DisconnectHost();
  if (composition_) {
    composition_->Release();
    composition_ = nullptr;
  }
  if (thread_mgr_) {
    if (key_event_sink_advised_) {
      ITfKeystrokeMgr* keystroke_mgr = nullptr;
      if (SUCCEEDED(thread_mgr_->QueryInterface(IID_ITfKeystrokeMgr,
                                                reinterpret_cast<void**>(&keystroke_mgr)))) {
        keystroke_mgr->UnadviseKeyEventSink(client_id_);
        keystroke_mgr->Release();
      }
      key_event_sink_advised_ = false;
    }

    if (thread_mgr_sink_cookie_ != TF_INVALID_COOKIE) {
      ITfSource* source = nullptr;
      if (SUCCEEDED(thread_mgr_->QueryInterface(IID_ITfSource,
                                                reinterpret_cast<void**>(&source)))) {
        source->UnadviseSink(thread_mgr_sink_cookie_);
        source->Release();
      }
      thread_mgr_sink_cookie_ = TF_INVALID_COOKIE;
    }

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
  UNREFERENCED_PARAMETER(context); UNREFERENCED_PARAMETER(lParam);
  if (!eaten) return E_INVALIDARG;
  const bool has_preedit = !preedit_raw_.empty() || !preedit_kana_.empty();
  *eaten = ((wParam == VK_ESCAPE && has_preedit) || (wParam == VK_RETURN && has_preedit) ||
            (wParam == VK_BACK && !preedit_raw_.empty()) || (wParam >= 'A' && wParam <= 'Z'));
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
    if (!host_connected_) {
      ConnectHost();
    }
    if (wParam >= 'A' && wParam <= 'Z') {
      const char key = static_cast<char>('a' + (wParam - 'A'));
      preedit_raw_.push_back(key);
      RebuildPreedit();
      RequestPreeditUpdate(context);
      SendHostQueryCandidates();
      *eaten = TRUE;
    } else if (wParam == VK_RETURN && !preedit_kana_.empty()) {
      commit_text_ = core::RomajiKanaConverter::ConvertForCommit(preedit_raw_);
      RequestPreeditCommit(context);
      preedit_raw_.clear();
      preedit_kana_.clear();
      *eaten = TRUE;
    } else if (wParam == VK_ESCAPE && (!preedit_raw_.empty() || !preedit_kana_.empty())) {
      preedit_raw_.clear();
      preedit_kana_.clear();
      commit_text_.clear();
      RequestPreeditUpdate(context);
      *eaten = TRUE;
    } else if (wParam == VK_BACK && !preedit_raw_.empty()) {
      PopLastAscii(&preedit_raw_);
      RebuildPreedit();
      RequestPreeditUpdate(context);
      SendHostQueryCandidates();
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
  UNREFERENCED_PARAMETER(ecWrite);
  if (composition_ == pComposition) {
    composition_->Release();
    composition_ = nullptr;
  }
  preedit_raw_.clear();
  preedit_kana_.clear();
  commit_text_.clear();
  return S_OK;
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
  return RequestEditSession(context, EditSessionMode::UpdatePreedit);
}

HRESULT TextService::RequestPreeditCommit(ITfContext* context) {
  return RequestEditSession(context, EditSessionMode::CommitPreedit);
}

HRESULT TextService::RequestEditSession(ITfContext* context, EditSessionMode mode) {
  if (!context) return E_INVALIDARG;
  ITfEditSession* edit = new EditSession(this, context, mode);
  HRESULT session_hr = S_OK;
  const HRESULT request_hr =
      context->RequestEditSession(client_id_, edit, TF_ES_ASYNCDONTCARE | TF_ES_READWRITE,
                                  &session_hr);
  edit->Release();
  return FAILED(request_hr) ? request_hr : session_hr;
}

void TextService::RebuildPreedit() {
  preedit_kana_ = core::RomajiKanaConverter::Preview(preedit_raw_);
}

void TextService::ConnectHost() {
  if (host_connected_) return;

  const auto now_ms = static_cast<uint64_t>(GetTickCount64());
  if (now_ms < next_host_connect_attempt_ms_) {
    return;
  }
  next_host_connect_attempt_ms_ = now_ms + 2000;

  DisconnectHost();

  auto client = std::make_unique<ipc::NamedPipeClient>();
  if (!client->Connect(ipc::DefaultPipeName(), 100)) {
    DebugLog(L"Host pipe connection failed");
    return;
  }

  host_client_ = std::move(client);
  host_connected_ = true;

  if (!SendHostHandshake() || !SendHostPing()) {
    DebugLog(L"Host handshake or ping failed");
    DisconnectHost();
  } else {
    DebugLog(L"Host handshake and ping succeeded");
  }
}

void TextService::DisconnectHost() {
  if (host_client_) {
    host_client_->Disconnect();
    host_client_.reset();
  }
  host_connected_ = false;
}

ipc::Envelope TextService::MakeHostEnvelope(ipc::MessageType type, std::string payload_json) {
  ipc::Envelope env;
  env.version = 1;
  env.request_id = next_host_request_id_++;
  env.trace_id = "tsf-tip-" + std::to_string(env.request_id);
  env.type = type;
  env.payload_json = std::move(payload_json);
  return env;
}

bool TextService::SendHostHandshake() {
  if (!host_client_ || !host_connected_) return false;

  ipc::HandshakeRequest request;
  request.tip_version = "0.1.0";
  request.protocol_version = 1;
  request.capabilities = {"ping", "query_candidates"};

  auto envelope =
      MakeHostEnvelope(ipc::MessageType::Handshake, ipc::BuildHandshakeRequest(request));
  if (!host_client_->Send(envelope)) return false;

  auto response = host_client_->Receive();
  if (!response || response->request_id != envelope.request_id ||
      response->type != ipc::MessageType::Handshake) {
    return false;
  }

  auto payload = ipc::ParseHandshakeResponse(response->payload_json);
  return payload.has_value() && payload->accepted;
}

bool TextService::SendHostPing() {
  if (!host_client_ || !host_connected_) return false;

  ipc::PingPayload request;
  request.nonce = next_host_request_id_;
  request.t_ms = 0;

  auto envelope = MakeHostEnvelope(ipc::MessageType::Ping, ipc::BuildPing(request));
  if (!host_client_->Send(envelope)) return false;

  auto response = host_client_->Receive();
  if (!response || response->request_id != envelope.request_id ||
      response->type != ipc::MessageType::Ping) {
    return false;
  }

  auto payload = ipc::ParsePing(response->payload_json);
  return payload.has_value() && payload->nonce == request.nonce;
}

bool TextService::SendHostQueryCandidates() {
  host_candidates_.clear();
  if (preedit_kana_.empty()) return true;

  if (!host_connected_) {
    ConnectHost();
  }
  if (!host_client_ || !host_connected_) return false;

  ipc::QueryCandidatesRequest request;
  request.reading = preedit_kana_;
  request.left_context = "";
  request.max_candidates = 10;
  request.live = true;

  auto envelope = MakeHostEnvelope(ipc::MessageType::QueryCandidates,
                                   ipc::BuildQueryCandidatesRequest(request));
  if (!host_client_->Send(envelope)) {
    DebugLog(L"Host QueryCandidates send failed");
    DisconnectHost();
    return false;
  }

  auto response = host_client_->Receive();
  if (!response || response->request_id != envelope.request_id ||
      response->type != ipc::MessageType::QueryCandidates) {
    DebugLog(L"Host QueryCandidates response mismatch");
    DisconnectHost();
    return false;
  }

  auto payload = ipc::ParseQueryCandidatesResponse(response->payload_json);
  if (!payload) {
    DebugLog(L"Host QueryCandidates response parse failed");
    return false;
  }

  host_candidates_ = std::move(payload->candidates);
  std::wstring message = L"Host candidates received: " +
                         std::to_wstring(host_candidates_.size());
  if (!host_candidates_.empty()) {
    message += L", top=" + Utf8ToWideString(host_candidates_.front().surface);
  }
  DebugLog(message);
  return true;
}

EditSession::EditSession(TextService* service, ITfContext* context, EditSessionMode mode)
    : service_(service), context_(context), mode_(mode) {
  if (service_) service_->AddRef();
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
    if (service_) service_->Release();
    delete this;
  }
  return c;
}
STDMETHODIMP EditSession::DoEditSession(TfEditCookie ec) {
  if (!service_) return E_FAIL;

  if (mode_ == EditSessionMode::CommitPreedit) {
    ITfComposition* composition = service_->composition_;
    if (composition) {
      const std::wstring text = Utf8ToWideString(service_->commit_text_);
      ITfRange* range = nullptr;
      HRESULT hr = composition->GetRange(&range);
      if (SUCCEEDED(hr)) {
        hr = range->SetText(ec, 0, text.c_str(), static_cast<LONG>(text.size()));
        range->Release();
      }
      if (FAILED(hr)) return hr;

      service_->composition_ = nullptr;
      hr = composition->EndComposition(ec);
      composition->Release();
      service_->commit_text_.clear();
      return hr;
    }
    service_->commit_text_.clear();
    return S_OK;
  }

  const std::wstring text = Utf8ToWideString(service_->preedit_kana_);
  if (text.empty()) {
    ITfComposition* composition = service_->composition_;
    service_->composition_ = nullptr;
    if (composition) {
      HRESULT hr = S_OK;
      ITfRange* range = nullptr;
      if (SUCCEEDED(composition->GetRange(&range))) {
        hr = range->SetText(ec, 0, L"", 0);
        range->Release();
      }
      if (SUCCEEDED(hr)) {
        hr = composition->EndComposition(ec);
      }
      composition->Release();
      return hr;
    }
    return S_OK;
  }

  if (!service_->composition_) {
    ITfInsertAtSelection* insert_at_selection = nullptr;
    HRESULT hr = context_->QueryInterface(IID_ITfInsertAtSelection,
                                          reinterpret_cast<void**>(&insert_at_selection));
    if (FAILED(hr)) return hr;

    ITfRange* insertion_range = nullptr;
    hr = insert_at_selection->InsertTextAtSelection(ec, TF_IAS_QUERYONLY, nullptr, 0,
                                                    &insertion_range);
    insert_at_selection->Release();
    if (FAILED(hr)) return hr;

    ITfContextComposition* context_composition = nullptr;
    hr = context_->QueryInterface(IID_ITfContextComposition,
                                  reinterpret_cast<void**>(&context_composition));
    if (FAILED(hr)) {
      insertion_range->Release();
      return hr;
    }

    hr = context_composition->StartComposition(
        ec, insertion_range, static_cast<ITfCompositionSink*>(service_),
        &service_->composition_);
    context_composition->Release();
    insertion_range->Release();
    if (FAILED(hr)) return hr;
  }

  ITfRange* composition_range = nullptr;
  HRESULT hr = service_->composition_->GetRange(&composition_range);
  if (FAILED(hr)) return hr;

  hr = composition_range->SetText(ec, 0, text.c_str(), static_cast<LONG>(text.size()));
  if (SUCCEEDED(hr)) {
    TF_SELECTION selection{};
    selection.range = composition_range;
    selection.style.ase = TF_AE_END;
    selection.style.fInterimChar = FALSE;
    context_->SetSelection(ec, 1, &selection);
  }
  composition_range->Release();
  return hr;
}

}  // namespace azookey::tsf
