#include "azookey/Registrar.h"

#include <string>

namespace azookey::tsf {
namespace {

std::wstring ClsidToString(const CLSID& clsid) {
  LPOLESTR clsid_string = nullptr;
  if (FAILED(StringFromCLSID(clsid, &clsid_string)) || !clsid_string) {
    return L"";
  }
  std::wstring result = clsid_string;
  CoTaskMemFree(clsid_string);
  return result;
}

}  // namespace

HRESULT RegisterServer() {
  // MVP scaffold: full TSF profile registration is executed by scripts/register.ps1.
  const std::wstring clsid = ClsidToString(kTextServiceClsid);
  return clsid.empty() ? E_FAIL : S_OK;
}

HRESULT UnregisterServer() {
  const std::wstring clsid = ClsidToString(kTextServiceClsid);
  return clsid.empty() ? E_FAIL : S_OK;
}

}  // namespace azookey::tsf
