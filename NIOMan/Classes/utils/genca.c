// Copyright 2020 zelbrium
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include <unistd.h>
#include <string.h>
#include "ssl.h"
#include <openssl/evp.h>
#include <openssl/rsa.h>
#include <openssl/x509v3.h>
#include <openssl/rand.h>
#include <openssl/pem.h>
#include <openssl/err.h>
#include <openssl/pkcs12.h>

#define RSA_KEY_BITS (4096)
#define SEC_PER_DAY (60 * 60 * 24)

static ASN1_INTEGER * generate_random_serial(void)
{
    unsigned char data[20] = {0};
    if (!RAND_bytes(data, sizeof(data))) {
        return NULL;
    }

    // Make data be non-negative, suggested by X509 spec
    data[0] &= 0x7F;

    BIGNUM *bn = BN_bin2bn(data, sizeof(data), NULL);
    if (bn == NULL) {
        return NULL;
    }
    
    ASN1_INTEGER *serial = BN_to_ASN1_INTEGER(bn, NULL);

    BN_free(bn);
    return serial;
}

// https://www.opensource.apple.com/source/OpenSSL/OpenSSL-22/openssl/demos/x509/mkcert.c
static int add_ext(X509 *cert, int nid, char *value)
{
    X509_EXTENSION *ex;
    X509V3_CTX ctx;
    X509V3_set_ctx_nodb(&ctx);
    X509V3_set_ctx(&ctx, cert, cert, NULL, NULL, 0);
    ex = X509V3_EXT_conf_nid(NULL, &ctx, nid, value);
    if (!ex)
        return 0;
    X509_add_ext(cert,ex,-1);
    X509_EXTENSION_free(ex);
    return 1;
}

/*
 * Generate a new RSA key.
 * Returned EVP_PKEY must be freed using EVP_PKEY_free() by the caller.
 */
RSA *rsa_gen(const int keysize)
{
    RSA *rsa;
#if (OPENSSL_VERSION_NUMBER >= 0x10100000L && !defined(LIBRESSL_VERSION_NUMBER)) || (defined(LIBRESSL_VERSION_NUMBER) && LIBRESSL_VERSION_NUMBER < 0x20701000L)
    BIGNUM *bn;
    int rv;
    rsa = RSA_new();
    bn = BN_new();
    BN_dec2bn(&bn, "3");
    rv = RSA_generate_key_ex(rsa, keysize, bn, NULL);
    BN_free(bn);
    if (rv != 1) {
        RSA_free(rsa);
        return NULL;
    }
#else /* OPENSSL_VERSION_NUMBER < 0x10100000L */
    rsa = RSA_generate_key(keysize, 3, NULL, NULL);
    if (!rsa)
        return NULL;
#endif /* OPENSSL_VERSION_NUMBER < 0x10100000L */
    return rsa;
}


static X509 * cacert_from_priv_key(RSA *privKey,
                                   const char *commonName,
                                   const char *countryCode,
                                   int validDay) {
    if (privKey == NULL || commonName == NULL || countryCode == NULL) {
        RSA_free(privKey);
        return NULL;
    }

    EVP_PKEY *pk = EVP_PKEY_new();
    if (pk == NULL) {
        RSA_free(privKey);
        return NULL;
    }

    if (!EVP_PKEY_assign_RSA(pk, privKey)) {
        EVP_PKEY_free(pk);
        RSA_free(privKey);
        return NULL;
    }
    privKey = NULL; // pkey consumes rsa reference

    X509 *x = X509_new();
    if (x == NULL) {
        goto fail;
    }

    if (!X509_set_version(x, 2)) { // version 3
        goto fail;
    }

    ASN1_INTEGER *serial = generate_random_serial();
    if (serial == NULL) {
        goto fail;
    }
    if (!X509_set_serialNumber(x, serial)) {
        ASN1_INTEGER_free(serial);
        goto fail;
    }
    ASN1_INTEGER_free(serial);

    if (X509_gmtime_adj(X509_get_notBefore(x), 0) == NULL) {
        goto fail;
    }
    if (X509_gmtime_adj(X509_get_notAfter(x), validDay * SEC_PER_DAY) == NULL) {
        goto fail;
    }

    if (!X509_set_pubkey(x, pk)) {
        goto fail;
    }

    X509_NAME *name = X509_get_subject_name(x);

    if (!X509_NAME_add_entry_by_txt(name,
        "C", MBSTRING_UTF8, (unsigned char *)countryCode, -1, -1, 0)) {
        goto fail;
    }
    if (!X509_NAME_add_entry_by_txt(name,
        "CN", MBSTRING_UTF8, (unsigned char *)commonName, -1, -1, 0)) {
        goto fail;
    }

    X509_set_issuer_name(x, name);

    if (!add_ext(x, NID_basic_constraints, "critical,CA:TRUE")) {
        goto fail;
    }
    if (!add_ext(x, NID_key_usage, "critical,keyCertSign,digitalSignature,cRLSign")) {
        goto fail;
    }
//    if (!add_ext(x, NID_ext_key_usage, "serverAuth,clientAuth")) {
//        goto fail;
//    }
//    if (!add_ext(x, NID_subject_key_identifier, "hash")) {
//        goto fail;
//    }

    // NID_subject_alt_name takes "type:value,type:value,...". CA certs should have the alt name be the CA's name with the DNS type.
    const char altPrefix[] = "DNS:";
    size_t commonNameLen = strnlen(commonName, 64);
    char *altName = calloc(commonNameLen + sizeof(altPrefix), 1);
    if (altName == NULL) {
        goto fail;
    }
    strcat(altName, altPrefix);
    strncat(altName, commonName, commonNameLen);

    if (!add_ext(x, NID_subject_alt_name, altName)) {
        free(altName);
        goto fail;
    }
    free(altName);

    if (!X509_sign(x, pk, EVP_sha256())) {
        goto fail;
    }

    EVP_PKEY_free(pk);
    return x;

fail:
    if (x == NULL) {
        X509_free(x);
    }
    if (pk == NULL) {
        EVP_PKEY_free(pk);
    }
    return NULL;
}

char *rsa_to_pem(RSA *key){
    BIO *bio;
    char *p, *ret;
    size_t sz;
    
    bio = BIO_new(BIO_s_mem());
    if (!bio)
        return NULL;
    PEM_write_bio_RSAPrivateKey(bio, key, NULL, NULL, 0, NULL, NULL);
    sz = BIO_get_mem_data(bio, &p);
    if (!(ret = malloc(sz + 1))) {
        BIO_free(bio);
        return NULL;
    }
    memcpy(ret, p, sz);
    ret[sz] = '\0';
    BIO_free(bio);
    return ret;
}


char *x509_to_pem(X509 *crt)
{
    BIO *bio;
    char *p, *ret;
    size_t sz;

    bio = BIO_new(BIO_s_mem());
    if (!bio)
        return NULL;
    PEM_write_bio_X509(bio, crt);
    sz = BIO_get_mem_data(bio, &p);
    if (!(ret = malloc(sz + 1))) {
        BIO_free(bio);
        return NULL;
    }
    memcpy(ret, p, sz);
    ret[sz] = '\0';
    BIO_free(bio);
    return ret;
}

int write_to_file(char *str,char *full_path){
    FILE *fp;
    fp = fopen(full_path,"w");
    if(fp!= NULL) {
        fprintf(fp,"%s",str);
        fclose(fp);
        return 1;
    }
    return 0;
}

int write_p12_to_dir(PKCS12 *p12, char *dir_path){
    time_t rawtime;
    struct tm * timeinfo;
    char buffer [128];
    time (&rawtime);
    timeinfo = localtime(&rawtime);
    strftime (buffer,sizeof(buffer),"%Y",timeinfo);
    
    char *p12_path = malloc(strlen(dir_path) + 1 + strlen(buffer) + strlen(".self.p12"));
    asprintf(&p12_path, "%s/%s.self.p12", dir_path, buffer);
    
    FILE *fp = fopen(p12_path,"w");
    if(!fp) {
        printf("p12文件写入失败!\n");
        return 1;
    }
    i2d_PKCS12_fp(fp, p12);
    fclose(fp);
    
    return 0;
}

int self_ssl_x509_v3ext_add(X509V3_CTX *ctx, X509 *crt, char *k, char *v)
{
    X509_EXTENSION *ext;

    if (!(ext = X509V3_EXT_conf(NULL, ctx, k, v))) {
        return -1;
    }
    if (X509_add_ext(crt, ext, -1) != 1) {
        X509_EXTENSION_free(ext);
        return -1;
    }
    X509_EXTENSION_free(ext);
    return 0;
}

EVP_PKEY *self_ssl_key_genrsa(const int keysize)
{
    EVP_PKEY *pkey;
    RSA *rsa;

#if (OPENSSL_VERSION_NUMBER >= 0x10100000L && !defined(LIBRESSL_VERSION_NUMBER)) || (defined(LIBRESSL_VERSION_NUMBER) && LIBRESSL_VERSION_NUMBER < 0x20701000L)
    BIGNUM *bn;
    int rv;
    rsa = RSA_new();
    bn = BN_new();
    BN_dec2bn(&bn, "3");
    rv = RSA_generate_key_ex(rsa, keysize, bn, NULL);
    BN_free(bn);
    if (rv != 1) {
        RSA_free(rsa);
        return NULL;
    }
#else /* OPENSSL_VERSION_NUMBER < 0x10100000L */
    rsa = RSA_generate_key(keysize, 3, NULL, NULL);
    if (!rsa)
        return NULL;
#endif /* OPENSSL_VERSION_NUMBER < 0x10100000L */
    pkey = EVP_PKEY_new();
    EVP_PKEY_assign_RSA(pkey, rsa); /* does not increment refcount */
    return pkey;
}

PKCS12 *self_signed_cert_genrsa_with_prikey(X509 *cacrt, EVP_PKEY *prikey){
    
    EVP_PKEY *pubkey = self_ssl_key_genrsa(2048);
    
    X509_NAME *subject, *issuer;
    X509 *crt;

    subject = X509_NAME_new();
    X509_NAME_add_entry_by_txt(subject, "C", MBSTRING_ASC, (const unsigned char*)("US"), -1, -1, 0);
    X509_NAME_add_entry_by_txt(subject, "O", MBSTRING_ASC, (const unsigned char*)("Company"), -1, -1, 0);
    X509_NAME_add_entry_by_txt(subject, "CN", MBSTRING_ASC, (const unsigned char*)("127.0.0.1"), -1, -1, 0);
    
    issuer = X509_get_subject_name(cacrt);
    if (!subject || !issuer)
        return NULL;

    crt = X509_new();
    if (!crt)
        return NULL;
    
    ASN1_INTEGER_set(X509_get_serialNumber(crt), 0xF001);
    // 自签名的服务器证书，有效期不能超过一年，否则iOS不认可
    if (!X509_set_version(crt, 0x02) ||
        !X509_set_subject_name(crt, subject) ||
        !X509_set_issuer_name(crt, issuer) ||
        !X509_gmtime_adj(X509_get_notBefore(crt), (long)-60*60*24) ||
        !X509_gmtime_adj(X509_get_notAfter(crt), (long)60*60*24*364) ||
        !X509_set_pubkey(crt, pubkey))
        goto errout;
    
    X509V3_CTX ctx;
    X509V3_set_ctx(&ctx, cacrt, crt, NULL, NULL, 0);
    
    if (self_ssl_x509_v3ext_add(&ctx, crt, "subjectKeyIdentifier", "hash") == -1)
        goto errout;
    if (self_ssl_x509_v3ext_add(&ctx, crt, "authorityKeyIdentifier", "keyid,issuer:always") == -1)
        goto errout;
    if (self_ssl_x509_v3ext_add(&ctx, crt, "basicConstraints", "CA:FALSE") == -1)
        goto errout;
    if (self_ssl_x509_v3ext_add(&ctx, crt, "extendedKeyUsage", "serverAuth,OCSPSigning") == -1)
        goto errout;
    if (self_ssl_x509_v3ext_add(&ctx, crt, "subjectAltName", "IP:127.0.0.1,DNS:127.0.0.1") == -1)
        goto errout;
    
    const EVP_MD *md;
    md = EVP_sha256();
    
    if (!X509_sign(crt, prikey, EVP_sha256()))
        goto errout;

    PKCS12 *p12 = PKCS12_create("123", "123", pubkey, crt, NULL, 0, 0, 0, 0, 0);
    X509_free(crt);
    return p12;
errout:
    X509_free(crt);
    return NULL;
}

// 自签名证书，用于检查CA是否被信任，指定CN为127.0.0.1，有效期不能超过一年
PKCS12 *self_signed_cert_genrsa(X509 *cacrt, RSA *carsa){
    EVP_PKEY *prikey = EVP_PKEY_new();
    EVP_PKEY_assign_RSA(prikey, carsa);
    return self_signed_cert_genrsa_with_prikey(cacrt, prikey);
}

int cacert_generate(char *commonName,
                    char *countryCode,
                    int validDay, // 3650 十年
                    char *path){
    
    RSA *privKey = rsa_gen(RSA_KEY_BITS);
    if (privKey == NULL) {
        return 0;
    }
    X509 *cert = cacert_from_priv_key(privKey, commonName, countryCode, validDay);
    if (cert == NULL) {
        return 0;
    }
    
    char *cert_pem_str = x509_to_pem(cert);
    char *key_pem_str = rsa_to_pem(privKey);
    if (cert_pem_str == NULL || key_pem_str == NULL) {
        return 0;
    }
    
    char *cert_path = malloc(strlen(path) + 1 + strlen("CA.cert.pem"));
    asprintf(&cert_path, "%s/CA.cert.pem", path);
    if (write_to_file(cert_pem_str, cert_path) == 0) {
        free(cert_pem_str);
        free(cert_path);
        return 0;
    }
    char *key_path = malloc(strlen(path) + 1 + strlen("CA.key.pem"));
    asprintf(&key_path, "%s/CA.key.pem", path);
    if (write_to_file(key_pem_str, key_path) == 0) {
        free(key_pem_str);
        free(key_path);
        return 0;
    }
    
    free(cert_pem_str);
    free(cert_path);
    free(key_pem_str);
    free(key_path);
    
//    // 自签证书，用于检测本地ca的信任状态，有效期为一年，每年都得更新一次，使用年作为名称，比如2022.self.p12
//    PKCS12 *p12 = self_signed_cert_genrsa(cert, privKey);
//    if (!p12) {
//        fprintf(stderr, "Error creating PKCS#12 structure\n");
//        ERR_print_errors_fp(stderr);
//        return 0;
//    }
//    write_p12_to_dir(p12, path);
//    PKCS12_free(p12);
    
    return 1;
}

// 从本地的pem文件，生成自签证书
int init_self_signed_cert(char *path){
    char *cert_path = malloc(strlen(path) + 1 + strlen("CA.cert.pem"));
    asprintf(&cert_path, "%s/CA.cert.pem", path);
    char *key_path = malloc(strlen(path) + 1 + strlen("CA.key.pem"));
    asprintf(&key_path, "%s/CA.key.pem", path);
    X509 *cert = ssl_x509_load(cert_path);
    EVP_PKEY *pkey = ssl_key_load(key_path);
    
    PKCS12 *p12 = self_signed_cert_genrsa_with_prikey(cert, pkey);
    if (!p12) {
        fprintf(stderr, "Error creating PKCS#12 structure\n");
        ERR_print_errors_fp(stderr);
        return 0;
    }
    write_p12_to_dir(p12, path);
    PKCS12_free(p12);
    
    return 1;
}
