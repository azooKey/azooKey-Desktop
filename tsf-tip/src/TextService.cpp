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

  candidate_window_.Create();
  candidate_window_.SetOnClick([this](int idx) {
    selected_candidate_idx_ = idx;
    if (active_context_) CommitSelected(active_context_);
  });

  StartIpcWorker();
  return S_OK;
}

STDMETHODIMP TextService::Deactivate() {
  StopIpcWorker();

  candidate_window_.Hide();
  candidate_window_.Destroy();

  if (composition_ && active_context_) {
    preedit_kana_.clear();
    romaji_.Reset();
    committing_ = false;
    commit_surface_.clear();
    ITfEditSession* edit = new EditSession(this, active_context_);
    HRESULT hr = S_OK;
    active_context_->RequestEditSession(client_id_, edit, TF_ES_SYNC | TF_ES_READWRITE, &hr);
    edit->Release();
  }
  if (composition_) {
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
  *eaten = FALSE;

  const bool has_preedit = !preedit_kana_.empty() || romaji_.HasPending();
  const bool cand_visible = candidate_window_.IsVisible();

  if (wParam >= 'A' && wParam <= 'Z') {
    *eaten = TRUE;
  } else if (wParam == VK_BACK) {
    *eaten = has_preedit ? TRUE : FALSE;
  } else if (wParam == VK_SPACE) {
    *eaten = (has_preedit || cand_visible) ? TRUE : FALSE;
  } else if (wParam == VK_UP || wParam == VK_DOWN) {
    *eaten = cand_visible ? TRUE : FALSE;
  } else if (wParam == VK_RETURN) {
    *eaten = (cand_visible || has_preedit) ? TRUE : FALSE;
  } else if (wParam == VK_ESCAPE) {
    *eaten = (cand_visible || has_preedit) ? TRUE : FALSE;
  } else if (wParam >= '1' && wParam <= '9') {
    *eaten = cand_visible ? TRUE : FALSE;
  }
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
    const bool cand_visible = candidate_window_.IsVisible();

    if (wParam >= 'A' && wParam <= 'Z') {
      // Hide candidate window when the user resumes typing.
      if (cand_visible) {
        candidate_window_.Hide();
        selected_candidate_idx_ = 0;
        std::lock_guard<std::mutex> lk(candidates_mtx_);
        candidates_.clear();
      }
      preedit_kana_ += romaji_.Feed(static_cast<char>(wParam));
      RequestPreeditUpdate(context);
      PostQueryCandidates(preedit_kana_);
      *eaten = TRUE;

    } else if (wParam == VK_BACK) {
      if (cand_visible) {
        candidate_window_.Hide();
        selected_candidate_idx_ = 0;
      }
      if (romaji_.HasPending()) {
        romaji_.PopPending();
        *eaten = TRUE;
      } else if (!preedit_kana_.empty()) {
        auto& s = preedit_kana_;
        size_t i = s.size();
        while (i > 0 && (s[i - 1] & 0xC0) == 0x80) --i;
        if (i > 0) --i;
        s.erase(i);
        RequestPreeditUpdate(context);
        if (!preedit_kana_.empty()) PostQueryCandidates(preedit_kana_);
        *eaten = TRUE;
      }

    } else if (wParam == VK_SPACE) {
      // Flush any pending romaji so the reading is complete.
      const std::string flushed = romaji_.Flush();
      if (!flushed.empty()) {
        preedit_kana_ += flushed;
        RequestPreeditUpdate(context);
      }
      if (!preedit_kana_.empty()) {
        std::vector<std::wstring> items;
        {
          std::lock_guard<std::mutex> lk(candidates_mtx_);
          for (auto& c : candidates_) items.push_back(Utf8ToWide(c.surface));
        }
        if (!items.empty()) {
          if (cand_visible) {
            // Cycle to next candidate.
            candidate_window_.MoveSelection(+1);
            selected_candidate_idx_ = candidate_window_.GetSelected();
          } else {
            // Show window with first candidate selected.
            selected_candidate_idx_ = 0;
            POINT pt = caret_pt_;
            if (pt.x == 0 && pt.y == 0) GetCursorPos(&pt);
            candidate_window_.Show(pt, items, 0);
          }
          *eaten = TRUE;
        }
      }

    } else if (wParam == VK_UP) {
      if (cand_visible) {
        candidate_window_.MoveSelection(-1);
        selected_candidate_idx_ = candidate_window_.GetSelected();
        *eaten = TRUE;
      }

    } else if (wParam == VK_DOWN) {
      if (cand_visible) {
        candidate_window_.MoveSelection(+1);
        selected_candidate_idx_ = candidate_window_.GetSelected();
        *eaten = TRUE;
      }

    } else if (wParam == VK_RETURN) {
      if (cand_visible) {
        CommitSelected(context);
        *eaten = TRUE;
      } else if (!preedit_kana_.empty() || romaji_.HasPending()) {
        CommitPreeditAsIs(context);
        *eaten = TRUE;
      }

    } else if (wParam >= '1' && wParam <= '9') {
      if (cand_visible) {
        int idx = static_cast<int>(wParam - '1');
        if (idx < candidate_window_.GetCount()) {
          selected_candidate_idx_ = idx;
          CommitSelected(context);
          *eaten = TRUE;
        }
      }

    } else if (wParam == VK_ESCAPE) {
      if (cand_visible) {
        candidate_window_.Hide();
        selected_candidate_idx_ = 0;
        *eaten = TRUE;
      } else if (!preedit_kana_.empty() || romaji_.HasPending()) {
        preedit_kana_.clear();
        romaji_.Reset();
        {
          std::lock_guard<std::mutex> lk(candidates_mtx_);
          candidates_.clear();
        }
        RequestPreeditUpdate(context);
        *eaten = TRUE;
      }
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
  candidate_window_.Hide();
  selected_candidate_idx_ = 0;
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

// --- Commit helpers (M5) ---

void TextService::CommitSelected(ITfContext* context) {
  if (!context) return;

  std::string reading;
  ipc::CandidateField chosen;
  std::vector<ipc::CandidateField> shown;

  {
    std::lock_guard<std::mutex> lk(candidates_mtx_);
    if (!candidates_.empty() &&
        selected_candidate_idx_ >= 0 &&
        selected_candidate_idx_ < static_cast<int>(candidates_.size())) {
      chosen = candidates_[selected_candidate_idx_];
      shown = candidates_;
    }
    candidates_.clear();
  }
  reading = preedit_kana_;

  candidate_window_.Hide();
  selected_candidate_idx_ = 0;

  // M10: cancel any outstanding QueryCandidates so the host can abort early.
  {
    std::lock_guard<std::mutex> lk(ipc_mtx_);
    if (ipc_has_request_) {
      const uint64_t old_id = ipc_pending_id_;
      ipc_has_request_ = false;
      ipc_send_queue_.push_back(
          {ipc::MessageType::Cancel, ipc::BuildCancel({old_id}), false});
    }
  }

  commit_surface_ = chosen.surface.empty() ? preedit_kana_ : chosen.surface;
  committing_ = true;
  preedit_kana_.clear();
  romaji_.Reset();
  RequestPreeditUpdate(context);

  if (!chosen.surface.empty() && !reading.empty()) {
    PostCommitObservation(reading, chosen, shown);
  }
}

void TextService::CommitPreeditAsIs(ITfContext* context) {
  if (!context) return;

  // Flush any pending romaji first.
  const std::string flushed = romaji_.Flush();
  preedit_kana_ += flushed;

  if (preedit_kana_.empty()) return;

  candidate_window_.Hide();
  selected_candidate_idx_ = 0;
  {
    std::lock_guard<std::mutex> lk(candidates_mtx_);
    candidates_.clear();
  }

  // M10: cancel any outstanding QueryCandidates.
  {
    std::lock_guard<std::mutex> lk(ipc_mtx_);
    if (ipc_has_request_) {
      const uint64_t old_id = ipc_pending_id_;
      ipc_has_request_ = false;
      ipc_send_queue_.push_back(
          {ipc::MessageType::Cancel, ipc::BuildCancel({old_id}), false});
    }
  }

  commit_surface_ = preedit_kana_;
  committing_ = true;
  preedit_kana_.clear();
  romaji_.Reset();
  RequestPreeditUpdate(context);
}

// --- IPC worker (M4 + M6 + M10) ---

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
  ipc_client_.Disconnect();
  ipc_thread_.join();
}

void TextService::IpcWorkerThread() {
  using namespace azookey::ipc;

  const auto pipe_name = DefaultPipeName();
  constexpr uint32_t kSliceMs = 250;
  constexpr uint32_t kTotalMs = 5000;
  bool connected = false;
  for (uint32_t elapsed = 0; elapsed < kTotalMs && !ipc_stop_.load(); elapsed += kSliceMs) {
    if (ipc_client_.Connect(pipe_name, kSliceMs)) { connected = true; break; }
  }
  if (!connected) {
    if (!ipc_stop_.load()) DebugLog("IPC: host pipe unavailable: " + pipe_name);
    return;
  }

  HandshakeRequest hs;
  hs.tip_version = kTipVersion;
  hs.protocol_version = 1;
  hs.capabilities = {"ping", "query_candidates", "commit_observation", "cancel"};

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
    bool has_qc = false;
    std::vector<IpcSendItem> to_send;

    {
      std::unique_lock<std::mutex> lock(ipc_mtx_);
      ipc_cv_.wait(lock, [this] {
        return ipc_stop_.load() || ipc_has_request_ || !ipc_send_queue_.empty();
      });
      if (ipc_stop_.load()) break;

      to_send = std::move(ipc_send_queue_);
      ipc_send_queue_.clear();

      if (ipc_has_request_) {
        reading = ipc_pending_reading_;
        req_id = ipc_pending_id_;
        ipc_has_request_ = false;
        has_qc = true;
      }
    }

    // Drain fire-and-forget queue (CommitObservation, Cancel) first.
    for (auto& item : to_send) {
      Envelope env;
      env.version = 1;
      env.request_id = next_id++;
      env.trace_id = "tip-faf";
      env.type = item.type;
      env.payload_json = item.payload_json;
      if (!ipc_client_.Send(env)) {
        DebugLog("IPC: faf send failed for type=" + TypeToString(item.type));
        continue;
      }
      if (item.expects_response) {
        auto res = ipc_client_.Receive();
        if (!res && !ipc_stop_.load()) {
          DebugLog("IPC: faf receive failed for type=" + TypeToString(item.type));
        }
      }
    }

    if (!has_qc || reading.empty()) continue;

    QueryCandidatesRequest qreq;
    qreq.reading = reading;
    qreq.left_context = "";
    qreq.max_candidates = 9;
    qreq.live = true;

    Envelope qenv;
    qenv.version = 1;
    qenv.request_id = req_id;
    qenv.trace_id = "tip-key-query";
    qenv.type = MessageType::QueryCandidates;
    qenv.payload_json = BuildQueryCandidatesRequest(qreq);

    if (!ipc_client_.Send(qenv)) { DebugLog("IPC: QueryCandidates send failed"); break; }

    auto qres = ipc_client_.Receive();
    if (!qres) {
      if (!ipc_stop_.load()) DebugLog("IPC: QueryCandidates receive failed");
      break;
    }

    auto qpayload = ParseQueryCandidatesResponse(qres->payload_json);
    if (!qpayload) {
      ++next_id;
      continue;
    }

    // M10: discard stale response — a newer request is already pending.
    bool is_fresh = false;
    {
      std::lock_guard<std::mutex> lock(ipc_mtx_);
      is_fresh = !ipc_has_request_;
    }

    if (is_fresh) {
      if (!qpayload->candidates.empty()) {
        DebugLog("IPC: " + std::to_string(qpayload->candidates.size()) +
                 " candidates for [" + reading + "] top=" + qpayload->candidates[0].surface);
      }
      std::lock_guard<std::mutex> lock(candidates_mtx_);
      candidates_ = qpayload->candidates;
    } else {
      DebugLog("IPC: stale response for req_id=" + std::to_string(req_id) + ", discarding");
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

void TextService::PostCommitObservation(const std::string& reading,
                                        const ipc::CandidateField& chosen,
                                        const std::vector<ipc::CandidateField>& shown) {
  using namespace std::chrono;
  const uint64_t now_ms = static_cast<uint64_t>(
      duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count());

  ipc::CommitObservationRequest req;
  req.reading = reading;
  req.chosen = chosen;
  req.shown = shown;
  req.left_context = "";
  req.timestamp_ms = now_ms;

  PostIpcSend(ipc::MessageType::CommitObservation,
              ipc::BuildCommitObservationRequest(req), true);
}

void TextService::PostCancel(uint64_t target_request_id) {
  PostIpcSend(ipc::MessageType::Cancel, ipc::BuildCancel({target_request_id}), false);
}

void TextService::PostIpcSend(ipc::MessageType type, std::string payload, bool expects_response) {
  std::lock_guard<std::mutex> lock(ipc_mtx_);
  ipc_send_queue_.push_back({type, std::move(payload), expects_response});
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
  // M5/M6: commit path — set final surface text and end composition.
  if (service_->committing_) {
    service_->committing_ = false;
    const std::wstring surface = Utf8ToWide(service_->commit_surface_);
    service_->commit_surface_.clear();

    if (service_->composition_) {
      if (!surface.empty()) {
        ITfRange* pRange = nullptr;
        if (SUCCEEDED(service_->composition_->GetRange(&pRange)) && pRange) {
          pRange->SetText(ec, 0, surface.c_str(), static_cast<LONG>(surface.size()));
          pRange->Release();
        }
      }
      // EndComposition finalizes the text in the document.
      ITfComposition* comp = service_->composition_;
      service_->composition_ = nullptr;
      comp->EndComposition(ec);
      comp->Release();
    }
    return S_OK;
  }

  // Normal preedit update.
  const std::wstring kana = Utf8ToWide(service_->preedit_kana_);

  if (kana.empty()) {
    if (service_->composition_) {
      ITfComposition* comp = service_->composition_;
      service_->composition_ = nullptr;
      comp->EndComposition(ec);
      comp->Release();
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

  // Cache the caret screen position for the candidate window anchor (M5).
  {
    ITfContextView* pView = nullptr;
    if (SUCCEEDED(context_->GetActiveView(&pView)) && pView) {
      RECT rc{};
      BOOL clipped = FALSE;
      if (SUCCEEDED(pView->GetTextExt(ec, pRange, &rc, &clipped))) {
        service_->caret_pt_ = {rc.left, rc.bottom};
      }
      pView->Release();
    }
  }

  // Apply underline display attribute via GUID_PROP_ATTRIBUTE.
  ITfProperty* pProp = nullptr;
  if (SUCCEEDED(context_->GetProperty(GUID_PROP_ATTRIBUTE, &pProp)) && pProp) {
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
