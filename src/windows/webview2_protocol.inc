typedef void (*ProtocolTrampoline)(void *closure, uint64_t view,
                                   moonbit_bytes_t request_id,
                                   moonbit_bytes_t scheme,
                                   moonbit_bytes_t method,
                                   moonbit_bytes_t uri,
                                   moonbit_bytes_t headers,
                                   moonbit_bytes_t body);
typedef int32_t (*MediaPermissionTrampoline)(void *closure, uint64_t view,
                                             int32_t permission_kind,
                                             moonbit_bytes_t origin);

ProtocolTrampoline g_protocol_trampoline = nullptr;
void *g_protocol_closure = nullptr;
MediaPermissionTrampoline g_media_permission_trampoline = nullptr;
void *g_media_permission_closure = nullptr;
std::atomic<uint64_t> g_next_protocol_handle{1};
std::atomic<UINT_PTR> g_next_protocol_timer{0x4D560001};
std::vector<std::wstring> g_custom_schemes;
bool g_custom_schemes_locked = false;

struct PendingProtocolRequest {
  uint64_t view_handle = 0;
  DWORD thread_id = 0;
  uint64_t context_id = 0;
  UINT_PTR timer_id = 0;
  ComPtr<ICoreWebView2WebResourceRequestedEventArgs> args;
  ComPtr<ICoreWebView2Deferral> deferral;
};

std::map<std::string, std::shared_ptr<PendingProtocolRequest>> g_pending_protocols;
int32_t moonview_media_permission_kind(COREWEBVIEW2_PERMISSION_KIND kind) {
  if (kind == COREWEBVIEW2_PERMISSION_KIND_CAMERA) {
    return 1;
  }
  if (kind == COREWEBVIEW2_PERMISSION_KIND_MICROPHONE) {
    return 2;
  }
  return 0;
}

int32_t media_permission_allowed(const std::shared_ptr<View> &view,
                                 COREWEBVIEW2_PERMISSION_KIND kind,
                                 const std::string &origin) {
  const int32_t moonview_kind = moonview_media_permission_kind(kind);
  if (moonview_kind == 0) {
    return 0;
  }
  if (g_media_permission_trampoline == nullptr || g_media_permission_closure == nullptr) {
    return 0;
  }
  return g_media_permission_trampoline(g_media_permission_closure, view->handle,
                                       moonview_kind, make_bytes(origin)) == 1;
}

void emit_protocol_request(const std::shared_ptr<View> &view,
                           const std::string &request_id,
                           const std::string &scheme,
                           const std::string &method,
                           const std::string &uri,
                           const std::string &headers,
                           const std::string &body) {
  if (!view || view->destroyed || g_protocol_trampoline == nullptr ||
      g_protocol_closure == nullptr) {
    return;
  }
  g_protocol_trampoline(g_protocol_closure, view->handle, make_bytes(request_id),
                        make_bytes(scheme), make_bytes(method), make_bytes(uri),
                        make_bytes(headers), make_bytes(body));
}

void write_u32_be(std::string *output, uint32_t value) {
  output->push_back(static_cast<char>((value >> 24) & 0xFF));
  output->push_back(static_cast<char>((value >> 16) & 0xFF));
  output->push_back(static_cast<char>((value >> 8) & 0xFF));
  output->push_back(static_cast<char>(value & 0xFF));
}

bool read_u32_be(const std::string &input, size_t *offset, uint32_t *value) {
  if (*offset > input.size() || input.size() - *offset < 4) {
    return false;
  }
  const unsigned char *bytes = reinterpret_cast<const unsigned char *>(input.data() + *offset);
  *value = (static_cast<uint32_t>(bytes[0]) << 24) |
           (static_cast<uint32_t>(bytes[1]) << 16) |
           (static_cast<uint32_t>(bytes[2]) << 8) |
           static_cast<uint32_t>(bytes[3]);
  *offset += 4;
  return true;
}

std::string encode_request_headers(ICoreWebView2HttpRequestHeaders *headers) {
  struct Header {
    std::string name;
    std::string value;
  };
  std::vector<Header> entries;
  if (headers != nullptr) {
    ComPtr<ICoreWebView2HttpHeadersCollectionIterator> iterator;
    if (SUCCEEDED(headers->GetIterator(&iterator)) && iterator) {
      BOOL current = FALSE;
      iterator->get_HasCurrentHeader(&current);
      while (current) {
        LPWSTR name = nullptr;
        LPWSTR value = nullptr;
        if (SUCCEEDED(iterator->GetCurrentHeader(&name, &value))) {
          entries.push_back({wide_to_utf8(name), wide_to_utf8(value)});
        }
        if (name != nullptr) {
          CoTaskMemFree(name);
        }
        if (value != nullptr) {
          CoTaskMemFree(value);
        }
        BOOL next = FALSE;
        if (FAILED(iterator->MoveNext(&next))) {
          break;
        }
        current = next;
      }
    }
  }
  std::string output;
  write_u32_be(&output, static_cast<uint32_t>(entries.size()));
  for (const Header &entry : entries) {
    write_u32_be(&output, static_cast<uint32_t>(entry.name.size()));
    output.append(entry.name);
    write_u32_be(&output, static_cast<uint32_t>(entry.value.size()));
    output.append(entry.value);
  }
  return output;
}

bool decode_response_headers(const std::string &input, std::wstring *headers) {
  size_t offset = 0;
  uint32_t count = 0;
  if (!read_u32_be(input, &offset, &count) || count > 1024) {
    return false;
  }
  std::wstring output;
  for (uint32_t index = 0; index < count; ++index) {
    uint32_t name_length = 0;
    uint32_t value_length = 0;
    if (!read_u32_be(input, &offset, &name_length) ||
        name_length > input.size() - offset) {
      return false;
    }
    const std::string name = input.substr(offset, name_length);
    offset += name_length;
    if (!read_u32_be(input, &offset, &value_length) ||
        value_length > input.size() - offset) {
      return false;
    }
    const std::string value = input.substr(offset, value_length);
    offset += value_length;
    std::wstring wide_name;
    std::wstring wide_value;
    if (!utf8_to_wide_checked(name, &wide_name) || !utf8_to_wide_checked(value, &wide_value) ||
        wide_name.empty() || name.find_first_of("\r\n:") != std::string::npos ||
        value.find_first_of("\r\n") != std::string::npos) {
      return false;
    }
    output.append(wide_name);
    output.append(L": ");
    output.append(wide_value);
    output.append(L"\r\n");
  }
  if (offset != input.size()) {
    return false;
  }
  *headers = std::move(output);
  return true;
}

std::string read_request_body(IStream *stream) {
  if (stream == nullptr) {
    return "";
  }
  STATSTG stat{};
  if (FAILED(stream->Stat(&stat, STATFLAG_NONAME)) || stat.cbSize.HighPart != 0 ||
      stat.cbSize.LowPart > 8 * 1024 * 1024) {
    return "";
  }
  LARGE_INTEGER start{};
  if (FAILED(stream->Seek(start, STREAM_SEEK_SET, nullptr))) {
    return "";
  }
  std::string body(stat.cbSize.LowPart, '\0');
  ULONG read = 0;
  if (!body.empty() && FAILED(stream->Read(&body[0], static_cast<ULONG>(body.size()), &read))) {
    return "";
  }
  body.resize(read);
  return body;
}

std::string scheme_of_uri(const std::string &uri) {
  const size_t separator = uri.find(':');
  if (separator == std::string::npos) {
    return "";
  }
  std::string scheme = uri.substr(0, separator);
  for (char &character : scheme) {
    if (character >= 'A' && character <= 'Z') {
      character = static_cast<char>(character - 'A' + 'a');
    }
  }
  return scheme;
}

bool custom_scheme_registered(const std::string &scheme) {
  const std::wstring wide_scheme = utf8_to_wide(scheme);
  for (const std::wstring &registered : g_custom_schemes) {
    if (registered == wide_scheme) {
      return true;
    }
  }
  return false;
}

bool valid_scheme(const std::string &scheme) {
  if (scheme.empty() || !((scheme[0] >= 'a' && scheme[0] <= 'z') ||
                          (scheme[0] >= 'A' && scheme[0] <= 'Z'))) {
    return false;
  }
  for (char character : scheme) {
    const bool alpha = (character >= 'a' && character <= 'z') ||
                       (character >= 'A' && character <= 'Z');
    const bool digit = character >= '0' && character <= '9';
    if (!alpha && !digit && character != '+' && character != '-' && character != '.') {
      return false;
    }
  }
  return true;
}

std::shared_ptr<View> find_view(uint64_t handle) {
  const auto it = g_views.find(handle);
  return it == g_views.end() ? nullptr : it->second;
}

void forget_pending_protocol(const std::string &request_id,
                             const std::shared_ptr<PendingProtocolRequest> &pending) {
  if (pending->timer_id != 0) {
    KillTimer(nullptr, pending->timer_id);
  }
  g_pending_protocols.erase(request_id);
}

bool complete_protocol_response(const std::string &request_id, int32_t status,
                                const std::string &headers, const std::string &body) {
  const auto pending_it = g_pending_protocols.find(request_id);
  if (pending_it == g_pending_protocols.end()) {
    return false;
  }
  const std::shared_ptr<PendingProtocolRequest> pending = pending_it->second;
  if (GetCurrentThreadId() != pending->thread_id) {
    return false;
  }
  std::wstring response_headers;
  if (!decode_response_headers(headers, &response_headers)) {
    return false;
  }
  const auto environment_it = g_environments.find(
      EnvironmentKey{pending->thread_id, pending->context_id});
  if (environment_it == g_environments.end() || !environment_it->second.environment) {
    return false;
  }
  ComPtr<IStream> stream;
  HRESULT result = CreateStreamOnHGlobal(nullptr, TRUE, &stream);
  if (FAILED(result) || !stream) {
    return false;
  }
  if (!body.empty()) {
    ULONG written = 0;
    result = stream->Write(body.data(), static_cast<ULONG>(body.size()), &written);
    if (FAILED(result) || written != body.size()) {
      return false;
    }
  }
  LARGE_INTEGER start{};
  stream->Seek(start, STREAM_SEEK_SET, nullptr);
  ComPtr<ICoreWebView2WebResourceResponse> response;
  result = environment_it->second.environment->CreateWebResourceResponse(
      stream.Get(), status, L"moonview", response_headers.c_str(), &response);
  if (FAILED(result) || !response) {
    return false;
  }
  result = pending->args->put_Response(response.Get());
  if (FAILED(result)) {
    return false;
  }
  pending->deferral->Complete();
  forget_pending_protocol(request_id, pending);
  return true;
}

void cancel_protocol_request(const std::string &request_id) {
  const auto pending_it = g_pending_protocols.find(request_id);
  if (pending_it == g_pending_protocols.end()) {
    return;
  }
  const std::shared_ptr<PendingProtocolRequest> pending = pending_it->second;
  const std::shared_ptr<View> view = find_view(pending->view_handle);
  if (view && !view->destroyed) {
    emit_event(view, kProtocolCancelled, request_id);
  }
  pending->args->put_Response(nullptr);
  pending->deferral->Complete();
  forget_pending_protocol(request_id, pending);
}

void CALLBACK protocol_timeout_proc(HWND, UINT, UINT_PTR timer_id, DWORD) {
  for (const auto &entry : g_pending_protocols) {
    if (entry.second->timer_id == timer_id) {
      cancel_protocol_request(entry.first);
      return;
    }
  }
}

void cancel_protocol_requests_for_view(uint64_t view_handle) {
  std::vector<std::string> request_ids;
  for (const auto &entry : g_pending_protocols) {
    if (entry.second->view_handle == view_handle) {
      request_ids.push_back(entry.first);
    }
  }
  for (const std::string &request_id : request_ids) {
    cancel_protocol_request(request_id);
  }
}

void install_protocol_handlers(const std::shared_ptr<View> &view, EventRegistrationToken *token) {
  const std::weak_ptr<View> weak_view = view;
  for (const std::wstring &scheme : g_custom_schemes) {
    const std::wstring filter = scheme + L"://*";
    view->webview->AddWebResourceRequestedFilter(
        filter.c_str(), COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
  }
  view->webview->add_WebResourceRequested(
      Callback<ICoreWebView2WebResourceRequestedEventHandler>(
          [weak_view](ICoreWebView2 *,
                      ICoreWebView2WebResourceRequestedEventArgs *args) -> HRESULT {
            const std::shared_ptr<View> locked = weak_view.lock();
            if (!locked || locked->destroyed || args == nullptr) {
              return S_OK;
            }
            ComPtr<ICoreWebView2WebResourceRequest> request;
            if (FAILED(args->get_Request(&request)) || !request) {
              return S_OK;
            }
            LPWSTR raw_uri = nullptr;
            LPWSTR raw_method = nullptr;
            request->get_Uri(&raw_uri);
            request->get_Method(&raw_method);
            const std::string uri = wide_to_utf8(raw_uri);
            const std::string method = wide_to_utf8(raw_method);
            if (raw_uri != nullptr) {
              CoTaskMemFree(raw_uri);
            }
            if (raw_method != nullptr) {
              CoTaskMemFree(raw_method);
            }
            const std::string scheme = scheme_of_uri(uri);
            if (!custom_scheme_registered(scheme)) {
              return S_OK;
            }
            ComPtr<ICoreWebView2Deferral> deferral;
            if (FAILED(args->GetDeferral(&deferral)) || !deferral) {
              return S_OK;
            }
            ComPtr<ICoreWebView2HttpRequestHeaders> request_headers;
            request->get_Headers(&request_headers);
            ComPtr<IStream> request_body;
            request->get_Content(&request_body);
            const std::string request_id =
                "protocol-" + std::to_string(g_next_protocol_handle.fetch_add(1));
            auto pending = std::make_shared<PendingProtocolRequest>();
            pending->view_handle = locked->handle;
            pending->thread_id = locked->thread_id;
            pending->context_id = locked->context_id;
            pending->args = args;
            pending->deferral = deferral;
            const UINT_PTR requested_timer = g_next_protocol_timer.fetch_add(1);
            pending->timer_id = SetTimer(nullptr, requested_timer, 30000, protocol_timeout_proc);
            g_pending_protocols.emplace(request_id, pending);
            if (g_protocol_trampoline == nullptr || g_protocol_closure == nullptr) {
              const std::string empty_headers(4, '\0');
              complete_protocol_response(request_id, 404, empty_headers,
                                         "No moonview protocol handler is installed");
              return S_OK;
            }
            emit_protocol_request(locked, request_id, scheme, method, uri,
                                  encode_request_headers(request_headers.Get()),
                                  read_request_body(request_body.Get()));
            return S_OK;
          })
          .Get(),
      token);
  view->webview->add_PermissionRequested(
      Callback<ICoreWebView2PermissionRequestedEventHandler>(
          [weak_view](ICoreWebView2 *,
                      ICoreWebView2PermissionRequestedEventArgs *args) -> HRESULT {
            const std::shared_ptr<View> locked = weak_view.lock();
            if (!locked || locked->destroyed || args == nullptr) {
              return S_OK;
            }
            COREWEBVIEW2_PERMISSION_KIND kind = COREWEBVIEW2_PERMISSION_KIND_UNKNOWN_PERMISSION;
            args->get_PermissionKind(&kind);
            LPWSTR raw_uri = nullptr;
            args->get_Uri(&raw_uri);
            const std::string origin = wide_to_utf8(raw_uri);
            if (raw_uri != nullptr) {
              CoTaskMemFree(raw_uri);
            }
            args->put_State(media_permission_allowed(locked, kind, origin)
                                ? COREWEBVIEW2_PERMISSION_STATE_ALLOW
                                : COREWEBVIEW2_PERMISSION_STATE_DENY);
            return S_OK;
          })
          .Get(),
      token);
}

bool configure_protocol_environment_options(ThreadEnvironment &state) {
  g_custom_schemes_locked = true;
  ComPtr<CoreWebView2EnvironmentOptions> options =
      Microsoft::WRL::Make<CoreWebView2EnvironmentOptions>();
  ComPtr<ICoreWebView2EnvironmentOptions4> options4;
  if (!options || FAILED(options.As(&options4)) || !options4) {
    state.failure = E_OUTOFMEMORY;
    fail_waiting_views(state.key, state.failure, "WebView2 environment options creation");
    return false;
  }
  std::vector<ComPtr<ICoreWebView2CustomSchemeRegistration>> registrations;
  std::vector<ICoreWebView2CustomSchemeRegistration *> registration_ptrs;
  for (const std::wstring &scheme : g_custom_schemes) {
    ComPtr<CoreWebView2CustomSchemeRegistration> registration =
        Microsoft::WRL::Make<CoreWebView2CustomSchemeRegistration>(scheme.c_str());
    if (!registration || FAILED(registration->put_TreatAsSecure(TRUE)) ||
        FAILED(registration->put_HasAuthorityComponent(TRUE))) {
      state.failure = E_OUTOFMEMORY;
      fail_waiting_views(state.key, state.failure, "WebView2 custom-scheme registration");
      return false;
    }
    ComPtr<ICoreWebView2CustomSchemeRegistration> interface_registration;
    if (FAILED(registration.As(&interface_registration))) {
      state.failure = E_NOINTERFACE;
      fail_waiting_views(state.key, state.failure, "WebView2 custom-scheme registration");
      return false;
    }
    registration_ptrs.push_back(interface_registration.Get());
    registrations.push_back(interface_registration);
  }
  if (!registration_ptrs.empty() &&
      FAILED(options4->SetCustomSchemeRegistrations(
          static_cast<UINT32>(registration_ptrs.size()), registration_ptrs.data()))) {
    state.failure = E_FAIL;
    fail_waiting_views(state.key, state.failure, "WebView2 custom-scheme registration");
    return false;
  }
  state.options = options;
  return true;
}
