#pragma once

#include <Windows.h>
#include <Unknwn.h>

namespace azookey::tsf {

inline constexpr CLSID kTextServiceClsid = {0x71ee04fa,
                                            0xb35d,
                                            0x4eb8,
                                            {0x87, 0xa1, 0x58, 0x2d, 0x44, 0xa9, 0xa5, 0x8c}};

class TextServiceFactory final : public IClassFactory {
 public:
  STDMETHODIMP QueryInterface(REFIID riid, void** ppvObj) override;
  STDMETHODIMP_(ULONG) AddRef() override;
  STDMETHODIMP_(ULONG) Release() override;
  STDMETHODIMP CreateInstance(IUnknown* outer, REFIID riid, void** ppvObject) override;
  STDMETHODIMP LockServer(BOOL lock) override;

 private:
  LONG ref_count_{1};
};

}  // namespace azookey::tsf
