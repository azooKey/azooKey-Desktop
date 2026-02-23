#include <Windows.h>

#include "azookey/tsf/TextServiceFactory.h"

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID reserved) {
  UNREFERENCED_PARAMETER(module);
  UNREFERENCED_PARAMETER(reason);
  UNREFERENCED_PARAMETER(reserved);
  return TRUE;
}

extern "C" STDAPI DllGetClassObject(REFCLSID rclsid, REFIID riid, LPVOID* ppv) {
  if (rclsid != azookey::tsf::kTextServiceClsid) return CLASS_E_CLASSNOTAVAILABLE;
  auto* factory = new azookey::tsf::TextServiceFactory();
  const auto hr = factory->QueryInterface(riid, ppv);
  factory->Release();
  return hr;
}

extern "C" STDAPI DllCanUnloadNow() { return S_FALSE; }
extern "C" STDAPI DllRegisterServer() { return S_OK; }
extern "C" STDAPI DllUnregisterServer() { return S_OK; }
