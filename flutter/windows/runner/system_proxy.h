#ifndef RUNNER_SYSTEM_PROXY_H_
#define RUNNER_SYSTEM_PROXY_H_

#include <flutter/binary_messenger.h>

// Registers the channel used by Dart to resolve the current Windows user's
// PAC, WPAD, or manual proxy configuration for the OpenIRN API.
void RegisterSystemProxyChannel(flutter::BinaryMessenger* messenger);

#endif  // RUNNER_SYSTEM_PROXY_H_
