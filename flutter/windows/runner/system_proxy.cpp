#include "system_proxy.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <wincrypt.h>
#include <winhttp.h>

#include <cstdint>
#include <limits>
#include <memory>
#include <string>
#include <variant>
#include <vector>

#include "utils.h"

namespace {

constexpr char kChannelName[] = "io.github.archoad.openirn/system_proxy";

struct ProxyResolution {
  bool succeeded;
  std::string proxy;
  DWORD error;
};

class WinHttpSession {
 public:
  WinHttpSession()
      : handle_(::WinHttpOpen(
            L"OpenIRN", WINHTTP_ACCESS_TYPE_NO_PROXY,
            WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0)) {
    if (handle_ != nullptr) {
      ::WinHttpSetTimeouts(handle_, 5000, 5000, 5000, 5000);
    }
  }

  ~WinHttpSession() {
    if (handle_ != nullptr) {
      ::WinHttpCloseHandle(handle_);
    }
  }

  WinHttpSession(const WinHttpSession&) = delete;
  WinHttpSession& operator=(const WinHttpSession&) = delete;

  HINTERNET handle() const { return handle_; }

 private:
  HINTERNET handle_;
};

HINTERNET GetWinHttpSession() {
  static WinHttpSession session;
  return session.handle();
}

std::wstring Utf16FromUtf8(const std::string& value) {
  if (value.empty() ||
      value.size() > static_cast<size_t>(std::numeric_limits<int>::max())) {
    return std::wstring();
  }
  const int input_length = static_cast<int>(value.size());
  const int target_length = ::MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), input_length, nullptr, 0);
  if (target_length <= 0) {
    return std::wstring();
  }

  std::wstring converted(static_cast<size_t>(target_length), L'\0');
  const int converted_length = ::MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), input_length,
      converted.data(), target_length);
  return converted_length == target_length ? converted : std::wstring();
}

void FreeCurrentUserProxyConfig(
    WINHTTP_CURRENT_USER_IE_PROXY_CONFIG* config) {
  if (config->lpszAutoConfigUrl != nullptr) {
    ::GlobalFree(config->lpszAutoConfigUrl);
  }
  if (config->lpszProxy != nullptr) {
    ::GlobalFree(config->lpszProxy);
  }
  if (config->lpszProxyBypass != nullptr) {
    ::GlobalFree(config->lpszProxyBypass);
  }
}

void FreeProxyInfo(WINHTTP_PROXY_INFO* proxy_info) {
  if (proxy_info->lpszProxy != nullptr) {
    ::GlobalFree(proxy_info->lpszProxy);
  }
  if (proxy_info->lpszProxyBypass != nullptr) {
    ::GlobalFree(proxy_info->lpszProxyBypass);
  }
}

ProxyResolution ResolveSystemProxy(const std::wstring& url) {
  WINHTTP_CURRENT_USER_IE_PROXY_CONFIG config{};
  if (!::WinHttpGetIEProxyConfigForCurrentUser(&config)) {
    const DWORD error = ::GetLastError();
    if (error == ERROR_FILE_NOT_FOUND) {
      return {true, "DIRECT", ERROR_SUCCESS};
    }
    return {false, std::string(), error};
  }

  const bool auto_detect = config.fAutoDetect == TRUE;
  const std::wstring auto_config_url = config.lpszAutoConfigUrl == nullptr
      ? std::wstring()
      : std::wstring(config.lpszAutoConfigUrl);
  const std::string manual_proxy = Utf8FromUtf16(config.lpszProxy);
  FreeCurrentUserProxyConfig(&config);

  if (!auto_detect && auto_config_url.empty()) {
    return {true, manual_proxy.empty() ? "DIRECT" : manual_proxy,
            ERROR_SUCCESS};
  }

  HINTERNET session = GetWinHttpSession();
  if (session == nullptr) {
    return {false, std::string(), ERROR_WINHTTP_INTERNAL_ERROR};
  }

  WINHTTP_AUTOPROXY_OPTIONS options{};
  options.fAutoLogonIfChallenged = TRUE;
  if (auto_detect) {
    options.dwFlags |= WINHTTP_AUTOPROXY_AUTO_DETECT;
    options.dwAutoDetectFlags =
        WINHTTP_AUTO_DETECT_TYPE_DHCP | WINHTTP_AUTO_DETECT_TYPE_DNS_A;
  }
  if (!auto_config_url.empty()) {
    options.dwFlags |= WINHTTP_AUTOPROXY_CONFIG_URL;
    options.lpszAutoConfigUrl = auto_config_url.c_str();
  }

  WINHTTP_PROXY_INFO proxy_info{};
  if (!::WinHttpGetProxyForUrl(session, url.c_str(), &options, &proxy_info)) {
    const DWORD error = ::GetLastError();
    if (!manual_proxy.empty()) {
      return {true, manual_proxy, ERROR_SUCCESS};
    }
    return {false, std::string(), error};
  }
  const DWORD access_type = proxy_info.dwAccessType;
  const std::string resolved_proxy = Utf8FromUtf16(proxy_info.lpszProxy);
  FreeProxyInfo(&proxy_info);

  if (access_type == WINHTTP_ACCESS_TYPE_NO_PROXY) {
    return {true, "DIRECT", ERROR_SUCCESS};
  }
  if (!resolved_proxy.empty()) {
    return {true, resolved_proxy, ERROR_SUCCESS};
  }
  if (!manual_proxy.empty()) {
    return {true, manual_proxy, ERROR_SUCCESS};
  }
  return {false, std::string(), ERROR_WINHTTP_UNABLE_TO_DOWNLOAD_SCRIPT};
}

flutter::EncodableList LoadTrustedRoots() {
  flutter::EncodableList roots;
  constexpr DWORD kStoreLocations[] = {
      CERT_SYSTEM_STORE_CURRENT_USER,
      CERT_SYSTEM_STORE_LOCAL_MACHINE,
  };

  for (const DWORD location : kStoreLocations) {
    HCERTSTORE store = ::CertOpenStore(
        CERT_STORE_PROV_SYSTEM_W, 0, 0,
        location | CERT_STORE_OPEN_EXISTING_FLAG | CERT_STORE_READONLY_FLAG,
        L"ROOT");
    if (store == nullptr) {
      continue;
    }

    PCCERT_CONTEXT certificate = nullptr;
    while ((certificate =
                ::CertEnumCertificatesInStore(store, certificate)) != nullptr) {
      const auto* begin = certificate->pbCertEncoded;
      roots.emplace_back(std::vector<uint8_t>(
          begin, begin + static_cast<size_t>(certificate->cbCertEncoded)));
    }
    ::CertCloseStore(store, 0);
  }
  return roots;
}

}  // namespace

void RegisterSystemProxyChannel(flutter::BinaryMessenger* messenger) {
  static auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, kChannelName,
          &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler([](
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    if (call.method_name() == "trustedRoots") {
      result->Success(flutter::EncodableValue(LoadTrustedRoots()));
      return;
    }
    if (call.method_name() != "resolveProxy") {
      result->NotImplemented();
      return;
    }

    const auto* arguments =
        std::get_if<flutter::EncodableMap>(call.arguments());
    if (arguments == nullptr) {
      result->Error("invalid_arguments", "The URL argument is required.");
      return;
    }
    const auto url_entry = arguments->find(flutter::EncodableValue("url"));
    if (url_entry == arguments->end()) {
      result->Error("invalid_arguments", "The URL argument is required.");
      return;
    }
    const auto* url = std::get_if<std::string>(&url_entry->second);
    if (url == nullptr || url->empty()) {
      result->Error("invalid_arguments", "The URL argument is invalid.");
      return;
    }

    const std::wstring windows_url = Utf16FromUtf8(*url);
    if (windows_url.empty()) {
      result->Error("invalid_arguments", "The URL encoding is invalid.");
      return;
    }

    const ProxyResolution resolution = ResolveSystemProxy(windows_url);
    if (!resolution.succeeded) {
      result->Error(
          "windows_proxy_resolution_failed",
          "Windows could not resolve the current user's proxy configuration.",
          flutter::EncodableValue(static_cast<int64_t>(resolution.error)));
      return;
    }
    result->Success(flutter::EncodableValue(resolution.proxy));
  });
}
