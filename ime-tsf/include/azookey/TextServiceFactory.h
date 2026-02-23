#pragma once

#include <Windows.h>

namespace azookey::tsf {

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
