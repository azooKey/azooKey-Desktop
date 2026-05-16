#include <Windows.h>
#include <msctf.h>
#include <olectl.h>
#include <shlwapi.h>

#include <string>

#include "azookey/tsf/DisplayAttribute.h"
#include "azookey/tsf/TextServiceFactory.h"

static HMODULE g_hmod = nullptr;

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID reserved) {
  UNREFERENCED_PARAMETER(reserved);
  if (reason == DLL_PROCESS_ATTACH) g_hmod = module;
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

// Writes a REG_SZ value under HKCU.  Returns false on any failure.
static bool RegSetSz(HKEY root, const wchar_t* subkey, const wchar_t* name,
                     const wchar_t* value) {
  HKEY hkey = nullptr;
  if (RegCreateKeyExW(root, subkey, 0, nullptr, 0, KEY_WRITE, nullptr, &hkey, nullptr) !=
      ERROR_SUCCESS)
    return false;
  const DWORD size = static_cast<DWORD>((wcslen(value) + 1) * sizeof(wchar_t));
  const LSTATUS st = RegSetValueExW(hkey, name, 0, REG_SZ,
                                    reinterpret_cast<const BYTE*>(value), size);
  RegCloseKey(hkey);
  return st == ERROR_SUCCESS;
}

class ScopedComInit {
 public:
  ScopedComInit() : hr_(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED)) {}
  ~ScopedComInit() {
    if (hr_ == S_OK || hr_ == S_FALSE) CoUninitialize();
  }

  HRESULT hr() const { return hr_; }
  bool ok() const { return SUCCEEDED(hr_) || hr_ == RPC_E_CHANGED_MODE; }

 private:
  HRESULT hr_;
};

extern "C" STDAPI DllRegisterServer() {
  if (!g_hmod) return E_UNEXPECTED;

  wchar_t dll_path[MAX_PATH] = {};
  if (!GetModuleFileNameW(g_hmod, dll_path, MAX_PATH)) return HRESULT_FROM_WIN32(GetLastError());

  // CLSID strings match kTextServiceClsid and the profile GUID in register.ps1.
  constexpr wchar_t kClsid[] = L"{71EE04FA-B35D-4EB8-87A1-582D44A9A58C}";
  constexpr wchar_t kProfileGuid[] = L"{A8F74D91-8DF3-4DA1-B80B-01F7C73D4A90}";
  constexpr wchar_t kLangId[] = L"0x00000411";

  // COM class registration under HKCU (user-scope, no elevation required).
  const std::wstring inproc =
      std::wstring(L"Software\\Classes\\CLSID\\") + kClsid + L"\\InprocServer32";
  if (!RegSetSz(HKEY_CURRENT_USER, inproc.c_str(), nullptr, dll_path)) return SELFREG_E_CLASS;
  if (!RegSetSz(HKEY_CURRENT_USER, inproc.c_str(), L"ThreadingModel", L"Apartment"))
    return SELFREG_E_CLASS;

  // Friendly name on the CLSID key itself.
  const std::wstring clsid_key =
      std::wstring(L"Software\\Classes\\CLSID\\") + kClsid;
  RegSetSz(HKEY_CURRENT_USER, clsid_key.c_str(), nullptr, L"azooKey TSF TIP");

  // TSF language profile keys (same paths as register.ps1).
  const std::wstring profile_key = clsid_key + L"\\Profiles\\" + kLangId + L"\\" + kProfileGuid;
  if (!RegSetSz(HKEY_CURRENT_USER, profile_key.c_str(), L"Description", L"azooKey TSF"))
    return SELFREG_E_CLASS;
  if (!RegSetSz(HKEY_CURRENT_USER, profile_key.c_str(), L"DisplayName", L"azooKey"))
    return SELFREG_E_CLASS;

  // Register the TIP as a display-attribute provider so TSF can resolve
  // ITfDisplayAttributeProvider queries for kInputAttributeGuid. This can fail
  // on user-scope installs, so keep the COM/Profile registration usable.
  ScopedComInit com;
  if (!com.ok()) return S_OK;

  ITfCategoryMgr* pCatMgr = nullptr;
  HRESULT cat_hr = CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER,
                                    IID_ITfCategoryMgr,
                                    reinterpret_cast<void**>(&pCatMgr));
  if (SUCCEEDED(cat_hr) && pCatMgr) {
    pCatMgr->RegisterCategory(azookey::tsf::kTextServiceClsid,
                              GUID_TFCAT_DISPLAYATTRIBUTEPROVIDER,
                              azookey::tsf::kTextServiceClsid);
    pCatMgr->Release();
  }

  return S_OK;
}

extern "C" STDAPI DllUnregisterServer() {
  constexpr wchar_t kClsid[] = L"{71EE04FA-B35D-4EB8-87A1-582D44A9A58C}";
  const std::wstring clsid_key =
      std::wstring(L"Software\\Classes\\CLSID\\") + kClsid;

  // Delete the entire CLSID subtree; SHDeleteKey handles non-existent keys gracefully.
  SHDeleteKeyW(HKEY_CURRENT_USER, clsid_key.c_str());

  ScopedComInit com;
  if (!com.ok()) return S_OK;

  // Remove display-attribute provider category registration.
  ITfCategoryMgr* pCatMgr = nullptr;
  if (SUCCEEDED(CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER,
                                  IID_ITfCategoryMgr,
                                  reinterpret_cast<void**>(&pCatMgr))) &&
      pCatMgr) {
    pCatMgr->UnregisterCategory(azookey::tsf::kTextServiceClsid,
                                 GUID_TFCAT_DISPLAYATTRIBUTEPROVIDER,
                                 azookey::tsf::kTextServiceClsid);
    pCatMgr->Release();
  }

  return S_OK;
}
