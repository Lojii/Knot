/*
 */

#ifndef ATTRIB_H
#define ATTRIB_H

/*
 * GCC attributes and built-ins for improved compile-time error checking
 * and performance optimization.
 *
 * All of these are fully optional and are automatically disabled on non-GCC
 * and non-LLVM/clang compilers.
 */

/*
 * Attributes.
 * These serve to improve the compiler warnings or optimizations.
 */

#if !defined(__GNUC__) && !defined(__clang__)
#define __attribute__(x) 
#endif

#define UNUSED          __attribute__((unused))
#define NORET           __attribute__((noreturn))
#define PRINTF(f,a)     __attribute__((format(printf,(f),(a))))
#define SCANF(f,a)      __attribute__((format(scanf,(f),(a))))
#define WUNRES          __attribute__((warn_unused_result))
#define MALLOC          __attribute__((malloc)) WUNRES
#define NONNULL(...)    __attribute__((nonnull(__VA_ARGS__)))
#define PURE            __attribute__((pure))
#define INLINE          __attribute__((always_inline))

/*
 * Branch prediction macros.
 * These serve to tell the compiler which of the branches is more likely.
 */

#if !defined(__GNUC__) && !defined(__clang__)
#define likely(expr)    (expr)
#define unlikely(expr)  (expr)
#else
#define likely(expr)    __builtin_expect((expr), 1)
#define unlikely(expr)  __builtin_expect((expr), 0)
#endif

#endif /* !ATTRIB_H */

/* vim: set noet ft=c: */
