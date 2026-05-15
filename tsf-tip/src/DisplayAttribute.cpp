#include "azookey/tsf/DisplayAttribute.h"

namespace azookey::tsf {

// --- InputDisplayAttributeInfo ---

STDMETHODIMP InputDisplayAttributeInfo::QueryInterface(REFIID riid, void** ppvObj) {
  if (!ppvObj) return E_INVALIDARG;
  *ppvObj = nullptr;
  if (riid == IID_IUnknown || riid == IID_ITfDisplayAttributeInfo) {
    *ppvObj = static_cast<ITfDisplayAttributeInfo*>(this);
    AddRef();
    return S_OK;
  }
  return E_NOINTERFACE;
}
STDMETHODIMP_(ULONG) InputDisplayAttributeInfo::AddRef() {
  return static_cast<ULONG>(InterlockedIncrement(&ref_count_));
}
STDMETHODIMP_(ULONG) InputDisplayAttributeInfo::Release() {
  const auto c = static_cast<ULONG>(InterlockedDecrement(&ref_count_));
  if (c == 0) delete this;
  return c;
}

STDMETHODIMP InputDisplayAttributeInfo::GetGUID(GUID* pguid) {
  if (!pguid) return E_INVALIDARG;
  *pguid = kInputAttributeGuid;
  return S_OK;
}

STDMETHODIMP InputDisplayAttributeInfo::GetDescription(BSTR* pbstrDesc) {
  if (!pbstrDesc) return E_INVALIDARG;
  *pbstrDesc = SysAllocString(L"azooKey Input");
  return *pbstrDesc ? S_OK : E_OUTOFMEMORY;
}

STDMETHODIMP InputDisplayAttributeInfo::GetAttributeInfo(TF_DISPLAYATTRIBUTE* pda) {
  if (!pda) return E_INVALIDARG;
  pda->crText.type = TF_CT_NONE;
  pda->crBk.type = TF_CT_NONE;
  pda->lsStyle = TF_LS_SOLID;
  pda->fBoldLine = FALSE;
  pda->crLine.type = TF_CT_NONE;
  pda->bAttr = TF_ATTR_INPUT;
  return S_OK;
}

STDMETHODIMP InputDisplayAttributeInfo::SetAttributeInfo(const TF_DISPLAYATTRIBUTE* /*pda*/) {
  return E_NOTIMPL;
}

STDMETHODIMP InputDisplayAttributeInfo::Reset() { return S_OK; }

// --- EnumDisplayAttributeInfo ---

STDMETHODIMP EnumDisplayAttributeInfo::QueryInterface(REFIID riid, void** ppvObj) {
  if (!ppvObj) return E_INVALIDARG;
  *ppvObj = nullptr;
  if (riid == IID_IUnknown || riid == IID_IEnumTfDisplayAttributeInfo) {
    *ppvObj = static_cast<IEnumTfDisplayAttributeInfo*>(this);
    AddRef();
    return S_OK;
  }
  return E_NOINTERFACE;
}
STDMETHODIMP_(ULONG) EnumDisplayAttributeInfo::AddRef() {
  return static_cast<ULONG>(InterlockedIncrement(&ref_count_));
}
STDMETHODIMP_(ULONG) EnumDisplayAttributeInfo::Release() {
  const auto c = static_cast<ULONG>(InterlockedDecrement(&ref_count_));
  if (c == 0) delete this;
  return c;
}

STDMETHODIMP EnumDisplayAttributeInfo::Next(ULONG ulCount, ITfDisplayAttributeInfo** rgInfo,
                                            ULONG* pcFetched) {
  if (!rgInfo) return E_INVALIDARG;
  ULONG fetched = 0;
  while (fetched < ulCount && index_ == 0) {
    rgInfo[fetched] = new InputDisplayAttributeInfo();
    ++fetched;
    ++index_;
  }
  if (pcFetched) *pcFetched = fetched;
  return fetched == ulCount ? S_OK : S_FALSE;
}

STDMETHODIMP EnumDisplayAttributeInfo::Skip(ULONG ulCount) {
  index_ += ulCount;
  return S_OK;
}

STDMETHODIMP EnumDisplayAttributeInfo::Reset() {
  index_ = 0;
  return S_OK;
}

STDMETHODIMP EnumDisplayAttributeInfo::Clone(IEnumTfDisplayAttributeInfo** ppEnum) {
  if (!ppEnum) return E_INVALIDARG;
  auto* clone = new EnumDisplayAttributeInfo();
  clone->index_ = index_;
  *ppEnum = clone;
  return S_OK;
}

}  // namespace azookey::tsf
