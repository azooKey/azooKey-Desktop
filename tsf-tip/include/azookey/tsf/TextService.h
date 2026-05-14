#pragma once

#include <Windows.h>
#include <msctf.h>

#include <atomic>
#include <condition_variable>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

#include "azookey/core/RomajiKanaConverter.h"
#include "azookey/ipc/Messages.h"
#include "azookey/ipc/NamedPipeTransport.h"
#include "azookey/ipc/Payloads.h"
#include "azookey/tsf/CandidateWindow.h"

namespace azookey::tsf {

class EditSession;

class TextService final : public ITfTextInputProcessorEx,
                          public ITfKeyEventSink,
                          public ITfThreadMgrEventSink,
                          public ITfCompositionSink,
                          public ITfDisplayAttributeProvider {
 public:
  TextService();
  ~TextService();

  STDMETHODIMP QueryInterface(REFIID riid, void** ppvObj) override;
  STDMETHODIMP_(ULONG) AddRef() override;
  STDMETHODIMP_(ULONG) Release() override;

  STDMETHODIMP Activate(ITfThreadMgr* ptim, TfClientId tid) override;
  STDMETHODIMP Deactivate() override;
  STDMETHODIMP ActivateEx(ITfThreadMgr* ptim, TfClientId tid, DWORD dwFlags) override;

  STDMETHODIMP OnSetFocus(BOOL foreground) override;
  STDMETHODIMP OnTestKeyDown(ITfContext* context, WPARAM wParam, LPARAM lParam, BOOL* eaten) override;
  STDMETHODIMP OnTestKeyUp(ITfContext* context, WPARAM wParam, LPARAM lParam, BOOL* eaten) override;
  STDMETHODIMP OnKeyDown(ITfContext* context, WPARAM wParam, LPARAM lParam, BOOL* eaten) override;
  STDMETHODIMP OnKeyUp(ITfContext* context, WPARAM wParam, LPARAM lParam, BOOL* eaten) override;
  STDMETHODIMP OnPreservedKey(ITfContext* context, REFGUID rguid, BOOL* eaten) override;

  STDMETHODIMP OnInitDocumentMgr(ITfDocumentMgr* pdim) override;
  STDMETHODIMP OnUninitDocumentMgr(ITfDocumentMgr* pdim) override;
  STDMETHODIMP OnSetFocus(ITfDocumentMgr* pdimFocus, ITfDocumentMgr* pdimPrevFocus) override;
  STDMETHODIMP OnPushContext(ITfContext* pic) override;
  STDMETHODIMP OnPopContext(ITfContext* pic) override;

  STDMETHODIMP OnCompositionTerminated(TfEditCookie ecWrite, ITfComposition* pComposition) override;

  STDMETHODIMP EnumDisplayAttributeInfo(IEnumTfDisplayAttributeInfo** ppEnum) override;
  STDMETHODIMP GetDisplayAttributeInfo(REFGUID guidInfo, ITfDisplayAttributeInfo** ppInfo) override;

  HRESULT RequestPreeditUpdate(ITfContext* context);

  // Accessed by EditSession.
  std::string preedit_kana_;
  ITfComposition* composition_{nullptr};
  bool committing_{false};
  std::string commit_surface_;
  POINT caret_pt_{0, 0};

 private:
  LONG ref_count_{1};
  ITfThreadMgr* thread_mgr_{nullptr};
  TfClientId client_id_{TF_CLIENTID_NULL};
  DWORD thread_mgr_sink_cookie_{TF_INVALID_COOKIE};

  core::RomajiKanaConverter romaji_;

  // Last context used for preedit updates; allows Deactivate to end composition.
  ITfContext* active_context_{nullptr};

  // Candidate window (M5).
  CandidateWindow candidate_window_;
  int selected_candidate_idx_{0};
  // Snapshot of candidates taken when the window was opened (used for commit
  // so that a late QueryCandidates response cannot change what is confirmed).
  std::vector<ipc::CandidateField> shown_candidates_;

  // IPC worker thread state.
  ipc::NamedPipeClient ipc_client_;
  std::mutex ipc_mtx_;
  std::condition_variable ipc_cv_;
  std::thread ipc_thread_;
  std::atomic<bool> ipc_stop_{false};
  std::string ipc_pending_reading_;
  uint64_t ipc_pending_id_{0};
  bool ipc_has_request_{false};

  // Fire-and-forget IPC send queue: CommitObservation, Cancel (M6, M10).
  struct IpcSendItem {
    ipc::MessageType type;
    std::string payload_json;
    bool expects_response{false};
  };
  std::vector<IpcSendItem> ipc_send_queue_;  // protected by ipc_mtx_

  // Latest candidates from Host (written by IPC thread, read by TIP thread).
  std::mutex candidates_mtx_;
  std::vector<ipc::CandidateField> candidates_;

  void StartIpcWorker();
  void StopIpcWorker();
  void IpcWorkerThread();
  void PostQueryCandidates(const std::string& reading);

  // M6: enqueue a CommitObservation to the IPC worker.
  void PostCommitObservation(const std::string& reading,
                             const ipc::CandidateField& chosen,
                             const std::vector<ipc::CandidateField>& shown);
  // M10: enqueue a Cancel message to the IPC worker.
  void PostCancel(uint64_t target_request_id);
  // Internal: push an item onto ipc_send_queue_ and notify the worker.
  void PostIpcSend(ipc::MessageType type, std::string payload, bool expects_response);

  // M5 commit helpers.
  void CommitSelected(ITfContext* context);
  void CommitPreeditAsIs(ITfContext* context);
};

class EditSession final : public ITfEditSession {
 public:
  EditSession(TextService* service, ITfContext* context);

  STDMETHODIMP QueryInterface(REFIID riid, void** ppvObj) override;
  STDMETHODIMP_(ULONG) AddRef() override;
  STDMETHODIMP_(ULONG) Release() override;
  STDMETHODIMP DoEditSession(TfEditCookie ec) override;

 private:
  LONG ref_count_{1};
  TextService* service_;
  ITfContext* context_;
};

}  // namespace azookey::tsf
