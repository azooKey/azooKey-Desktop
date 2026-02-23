#include <Windows.h>

#include "azookey/Registrar.h"
#include "azookey/TextServiceFactory.h"

namespace {

HMODULE g_module = nullptr;

}  // namespace

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID reserved) {
  UNREFERENCED_PARAMETER(reserved);
  if (reason == DLL_PROCESS_ATTACH) {
    g_module = module;
    DisableThreadLibraryCalls(module);
  }
  return TRUE;
}

extern "C" STDAPI DllGetClassObject(REFCLSID rclsid, REFIID riid, LPVOID* ppv) {
  if (rclsid != azookey::tsf::kTextServiceClsid) {
    return CLASS_E_CLASSNOTAVAILABLE;
  }
  auto* factory = new azookey::tsf::TextServiceFactory();
  const HRESULT hr = factory->QueryInterface(riid, ppv);
  factory->Release();
  return hr;
}

extern "C" STDAPI DllCanUnloadNow(void) { return S_FALSE; }

extern "C" STDAPI DllRegisterServer(void) { return azookey::tsf::RegisterServer(); }

extern "C" STDAPI DllUnregisterServer(void) { return azookey::tsf::UnregisterServer(); }
