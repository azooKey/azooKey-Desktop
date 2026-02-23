#include "azookey/TextServiceFactory.h"

#include "azookey/TextService.h"
#include "azookey/core/SimpleConverter.h"

namespace azookey::tsf {

STDMETHODIMP TextServiceFactory::QueryInterface(REFIID riid, void** ppvObj) {
  if (!ppvObj) {
    return E_INVALIDARG;
  }
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
  const ULONG current = static_cast<ULONG>(InterlockedDecrement(&ref_count_));
  if (current == 0) {
    delete this;
  }
  return current;
}

STDMETHODIMP TextServiceFactory::CreateInstance(IUnknown* outer, REFIID riid, void** ppvObject) {
  if (outer) {
    return CLASS_E_NOAGGREGATION;
  }

  auto* service = new TextService(std::make_unique<core::SimpleConverter>());
  const HRESULT hr = service->QueryInterface(riid, ppvObject);
  service->Release();
  return hr;
}

STDMETHODIMP TextServiceFactory::LockServer(BOOL lock) {
  UNREFERENCED_PARAMETER(lock);
  return S_OK;
}

}  // namespace azookey::tsf
