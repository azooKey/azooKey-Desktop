#pragma once

#include <Windows.h>
#include <msctf.h>

namespace azookey::tsf {

// GUID for the input-composition underline display attribute registered by the TIP.
// {5D8F0A63-2B5E-4F8C-A1D4-7E9B2C3F4A5D}
inline constexpr GUID kInputAttributeGuid = {0x5d8f0a63,
                                              0x2b5e,
                                              0x4f8c,
                                              {0xa1, 0xd4, 0x7e, 0x9b, 0x2c, 0x3f, 0x4a, 0x5d}};

// ITfDisplayAttributeInfo for the preedit underline (TF_ATTR_INPUT).
class InputDisplayAttributeInfo final : public ITfDisplayAttributeInfo {
 public:
  STDMETHODIMP QueryInterface(REFIID riid, void** ppvObj) override;
  STDMETHODIMP_(ULONG) AddRef() override;
  STDMETHODIMP_(ULONG) Release() override;

  STDMETHODIMP GetGUID(GUID* pguid) override;
  STDMETHODIMP GetDescription(BSTR* pbstrDesc) override;
  STDMETHODIMP GetDisplayAttribute(TF_DISPLAYATTRIBUTE* pda) override;
  STDMETHODIMP SetDisplayAttribute(const TF_DISPLAYATTRIBUTE* pda) override;
  STDMETHODIMP Reset() override;

 private:
  LONG ref_count_{1};
};

// IEnumTfDisplayAttributeInfo enumerating the single InputDisplayAttributeInfo.
class EnumDisplayAttributeInfo final : public IEnumTfDisplayAttributeInfo {
 public:
  STDMETHODIMP QueryInterface(REFIID riid, void** ppvObj) override;
  STDMETHODIMP_(ULONG) AddRef() override;
  STDMETHODIMP_(ULONG) Release() override;

  STDMETHODIMP Next(ULONG ulCount, ITfDisplayAttributeInfo** rgInfo, ULONG* pcFetched) override;
  STDMETHODIMP Skip(ULONG ulCount) override;
  STDMETHODIMP Reset() override;
  STDMETHODIMP Clone(IEnumTfDisplayAttributeInfo** ppEnum) override;

 private:
  LONG ref_count_{1};
  ULONG index_{0};
};

}  // namespace azookey::tsf
