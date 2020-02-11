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
// Unfortunately, even in our brave BoringSSL world, we have "functions" that are
// macros too complex for the clang importer. This file handles them.
#include "CNIOBoringSSLShims.h"

GENERAL_NAME *CNIOBoringSSLShims_sk_GENERAL_NAME_value(const STACK_OF(GENERAL_NAME) *sk, size_t i) {
    return sk_GENERAL_NAME_value(sk, i);
}

size_t CNIOBoringSSLShims_sk_GENERAL_NAME_num(const STACK_OF(GENERAL_NAME) *sk) {
    return sk_GENERAL_NAME_num(sk);
}

void *CNIOBoringSSLShims_SSL_CTX_get_app_data(const SSL_CTX *ctx) {
    return SSL_CTX_get_app_data(ctx);
}

int CNIOBoringSSLShims_SSL_CTX_set_app_data(SSL_CTX *ctx, void *data) {
    return SSL_CTX_set_app_data(ctx, data);
}

int CNIOBoringSSLShims_ERR_GET_LIB(uint32_t err) {
  return ERR_GET_LIB(err);
}

int CNIOBoringSSLShims_ERR_GET_REASON(uint32_t err) {
  return ERR_GET_REASON(err);
}
