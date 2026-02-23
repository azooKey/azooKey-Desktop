#include "azookey/tsf/TextServiceFactory.h"

#include "azookey/tsf/TextService.h"

namespace azookey::tsf {

STDMETHODIMP TextServiceFactory::QueryInterface(REFIID riid, void** ppvObj) {
  if (!ppvObj) return E_INVALIDARG;
  *ppvObj = nullptr;
  if (riid == IID_IUnknown || riid == IID_IClassFactory) {
    *ppvObj = static_cast<IClassFactory*>(this);
    AddRef();
    return S_OK;
  }
  return E_NOINTERFACE;
}
STDMETHODIMP_(ULONG) TextServiceFactory::AddRef() { return static_cast<ULONG>(InterlockedIncrement(&ref_count_)); }
STDMETHODIMP_(ULONG) TextServiceFactory::Release() {
  const auto c = static_cast<ULONG>(InterlockedDecrement(&ref_count_));
  if (c == 0) delete this;
  return c;
}
STDMETHODIMP TextServiceFactory::CreateInstance(IUnknown* outer, REFIID riid, void** ppvObject) {
  if (outer) return CLASS_E_NOAGGREGATION;
  auto* service = new TextService();
  const auto hr = service->QueryInterface(riid, ppvObject);
  service->Release();
  return hr;
}
STDMETHODIMP TextServiceFactory::LockServer(BOOL lock) {
  UNREFERENCED_PARAMETER(lock);
  return S_OK;
}

}  // namespace azookey::tsf
