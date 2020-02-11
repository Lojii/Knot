//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
#ifndef C_NIO_BORINGSSL_SHIMS_H
#define C_NIO_BORINGSSL_SHIMS_H

// This is for instances when `swift package generate-xcodeproj` is used as CNIOBoringSSL
// is treated as a framework and requires the framework's name as a prefix.
#if __has_include(<CNIOBoringSSL/CNIOBoringSSL.h>)
#include <CNIOBoringSSL/CNIOBoringSSL.h>
#else
#include <CNIOBoringSSL.h>
#endif

GENERAL_NAME *CNIOBoringSSLShims_sk_GENERAL_NAME_value(const STACK_OF(GENERAL_NAME) *sk, size_t i);
size_t CNIOBoringSSLShims_sk_GENERAL_NAME_num(const STACK_OF(GENERAL_NAME) *sk);

void *CNIOBoringSSLShims_SSL_CTX_get_app_data(const SSL_CTX *ctx);
int CNIOBoringSSLShims_SSL_CTX_set_app_data(SSL_CTX *ctx, void *data);

int CNIOBoringSSLShims_ERR_GET_LIB(uint32_t err);
int CNIOBoringSSLShims_ERR_GET_REASON(uint32_t err);

#endif  // C_NIO_BORINGSSL_SHIMS_H
