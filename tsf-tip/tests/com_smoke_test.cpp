#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <Windows.h>

#include <stdexcept>

#include "azookey/tsf/TextServiceFactory.h"

namespace {

void Expect(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

using DllGetClassObjectFn = HRESULT(STDAPICALLTYPE*)(REFCLSID, REFIID, LPVOID*);

#define WIDEN_LITERAL2(value) L##value
#define WIDEN_LITERAL(value) WIDEN_LITERAL2(value)

}  // namespace

int main() {
  HMODULE module = LoadLibraryW(WIDEN_LITERAL(AZOOKEY_TSF_TIP_DLL_PATH));
  Expect(module != nullptr, "LoadLibraryW failed");

  auto* proc = reinterpret_cast<DllGetClassObjectFn>(
      GetProcAddress(module, "DllGetClassObject"));
  Expect(proc != nullptr, "DllGetClassObject export not found");

  IClassFactory* factory = nullptr;
  HRESULT hr = proc(azookey::tsf::kTextServiceClsid, IID_IClassFactory,
                    reinterpret_cast<void**>(&factory));
  Expect(SUCCEEDED(hr) && factory != nullptr, "DllGetClassObject failed");

  IUnknown* service = nullptr;
  hr = factory->CreateInstance(nullptr, IID_IUnknown,
                               reinterpret_cast<void**>(&service));
  factory->Release();
  Expect(SUCCEEDED(hr) && service != nullptr, "CreateInstance(IID_IUnknown) failed");

  service->Release();
  return 0;
}
