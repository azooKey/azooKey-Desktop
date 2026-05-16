#include <Windows.h>

#include <string>

#include "azookey/tsf/TextServiceFactory.h"

namespace {

HMODULE g_module = nullptr;
constexpr wchar_t kTextServiceDescription[] = L"azooKey TSF";

std::wstring GuidToString(REFGUID guid) {
  wchar_t buffer[39]{};
  StringFromGUID2(guid, buffer, static_cast<int>(std::size(buffer)));
  return buffer;
}

HRESULT SetStringValue(HKEY key, const wchar_t* name, const std::wstring& value) {
  const DWORD bytes = static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t));
  const LSTATUS status =
      RegSetValueExW(key, name, 0, REG_SZ, reinterpret_cast<const BYTE*>(value.c_str()), bytes);
  return status == ERROR_SUCCESS ? S_OK : HRESULT_FROM_WIN32(status);
}

HRESULT RegisterComClass() {
  wchar_t module_path[MAX_PATH]{};
  if (!GetModuleFileNameW(g_module, module_path, static_cast<DWORD>(std::size(module_path)))) {
    return HRESULT_FROM_WIN32(GetLastError());
  }

  const std::wstring clsid = GuidToString(azookey::tsf::kTextServiceClsid);
  const std::wstring clsid_key = L"Software\\Classes\\CLSID\\" + clsid;

  HKEY key = nullptr;
  LSTATUS status = RegCreateKeyExW(HKEY_CURRENT_USER, clsid_key.c_str(), 0, nullptr, 0,
                                   KEY_SET_VALUE | KEY_CREATE_SUB_KEY, nullptr, &key, nullptr);
  if (status != ERROR_SUCCESS) return HRESULT_FROM_WIN32(status);
  HRESULT hr = SetStringValue(key, nullptr, kTextServiceDescription);
  RegCloseKey(key);
  if (FAILED(hr)) return hr;

  HKEY server_key = nullptr;
  status = RegCreateKeyExW(HKEY_CURRENT_USER, (clsid_key + L"\\InprocServer32").c_str(), 0,
                           nullptr, 0, KEY_SET_VALUE, nullptr, &server_key, nullptr);
  if (status != ERROR_SUCCESS) return HRESULT_FROM_WIN32(status);
  hr = SetStringValue(server_key, nullptr, module_path);
  if (SUCCEEDED(hr)) {
    hr = SetStringValue(server_key, L"ThreadingModel", L"Apartment");
  }
  RegCloseKey(server_key);
  return hr;
}

void UnregisterComClass() {
  const std::wstring clsid_key =
      L"Software\\Classes\\CLSID\\" + GuidToString(azookey::tsf::kTextServiceClsid);
  RegDeleteTreeW(HKEY_CURRENT_USER, clsid_key.c_str());
}

}  // namespace

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID reserved) {
  if (reason == DLL_PROCESS_ATTACH) {
    g_module = module;
    DisableThreadLibraryCalls(module);
  }
  UNREFERENCED_PARAMETER(reserved);
  return TRUE;
}

extern "C" STDAPI DllGetClassObject(REFCLSID rclsid, REFIID riid, LPVOID* ppv) {
  if (!ppv) return E_INVALIDARG;
  *ppv = nullptr;
  if (rclsid != azookey::tsf::kTextServiceClsid) return CLASS_E_CLASSNOTAVAILABLE;
  auto* factory = new azookey::tsf::TextServiceFactory();
  const auto hr = factory->QueryInterface(riid, ppv);
  factory->Release();
  return hr;
}

extern "C" STDAPI DllCanUnloadNow() { return S_FALSE; }
extern "C" STDAPI DllRegisterServer() {
  return RegisterComClass();
}

extern "C" STDAPI DllUnregisterServer() {
  UnregisterComClass();
  return S_OK;
}
