#pragma once

#include <Windows.h>

namespace azookey::tsf {

// {71EE04FA-B35D-4EB8-87A1-582D44A9A58C}
inline constexpr CLSID kTextServiceClsid = {0x71ee04fa,
                                            0xb35d,
                                            0x4eb8,
                                            {0x87, 0xa1, 0x58, 0x2d, 0x44, 0xa9, 0xa5, 0x8c}};

HRESULT RegisterServer();
HRESULT UnregisterServer();

}  // namespace azookey::tsf
