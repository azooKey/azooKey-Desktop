#pragma once

#include <Windows.h>
#include <msctf.h>

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include "azookey/core/RomajiKanaConverter.h"
#include "azookey/ipc/NamedPipeTransport.h"
#include "azookey/ipc/Payloads.h"

namespace azookey::tsf {

class EditSession;

enum class EditSessionMode {
  UpdatePreedit,
  CommitPreedit,
};

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
  HRESULT RequestPreeditCommit(ITfContext* context);

 private:
  friend class EditSession;

  HRESULT RequestEditSession(ITfContext* context, EditSessionMode mode);
  void RebuildPreedit();
  void ConnectHost();
  void DisconnectHost();
  bool SendHostHandshake();
  bool SendHostPing();
  bool SendHostQueryCandidates();
  ipc::Envelope MakeHostEnvelope(ipc::MessageType type, std::string payload_json);

  LONG ref_count_{1};
  ITfThreadMgr* thread_mgr_{nullptr};
  ITfComposition* composition_{nullptr};
  TfClientId client_id_{TF_CLIENTID_NULL};
  DWORD thread_mgr_sink_cookie_{TF_INVALID_COOKIE};
  bool key_event_sink_advised_{false};

  std::string preedit_raw_;
  std::string preedit_kana_;
  std::string commit_text_;

  std::unique_ptr<ipc::NamedPipeClient> host_client_;
  std::vector<ipc::CandidateField> host_candidates_;
  uint64_t next_host_request_id_{1};
  uint64_t next_host_connect_attempt_ms_{0};
  bool host_connected_{false};
};

class EditSession final : public ITfEditSession {
 public:
  EditSession(TextService* service, ITfContext* context, EditSessionMode mode);

  STDMETHODIMP QueryInterface(REFIID riid, void** ppvObj) override;
  STDMETHODIMP_(ULONG) AddRef() override;
  STDMETHODIMP_(ULONG) Release() override;
  STDMETHODIMP DoEditSession(TfEditCookie ec) override;

 private:
  LONG ref_count_{1};
  TextService* service_;
  ITfContext* context_;
  EditSessionMode mode_;
};

}  // namespace azookey::tsf
