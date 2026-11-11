# universal_ble 3.1.0 (vendored)

Copy of pub.dev universal_ble 3.1.0 so the PC tool builds with Visual Studio
2019 on a Korean Windows. Changes, all in windows/CMakeLists.txt:

1. `cmake_minimum_required(VERSION 3.20)` (was 3.21; VS 2019 bundles 3.20).
2. `/utf-8`: sources are UTF-8; under CP949 MSVC warns C4819, which /WX makes
   an error.
3. `/EHsc` and `_HAS_EXCEPTIONS=0` removed for this target: with VS 2019's STL
   std::bad_any_cast otherwise needs bad_cast(const char*), which the runtime
   does not export (LNK2019).

example/, assets/, test/, hil/, skills/, pigeon/ removed.
Upgrade: copy the new version from the pub cache and re-apply the changes.
