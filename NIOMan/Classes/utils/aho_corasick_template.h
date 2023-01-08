
/*
* Copyright 2017 Laurent Farhi
* Contact: lfarhi@sfr.fr
*
*  This file is free software: you can redistribute it and/or modify
*  it under the terms of the GNU Lesser General Public License as published by
*  the Free Software Foundation, version 3 of the License.
*
*  This file is distributed in the hope that it will be useful,
*  but WITHOUT ANY WARRANTY; without even the implied warranty of
*  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
*  GNU Lesser General Public License for more details.
*
*  You should have received a copy of the GNU Lesser General Public License
*  along with this file.  If not, see <http://www.gnu.org/licenses/>.
*/

#ifndef __ACM_TEMPLATE__

#  define __ACM_TEMPLATE__

/// User interface ************************************************************************

/// Texts and keywprds are composed of symbols of type T.
/// T can be any standard type (int, char, wchar_t, ...) or any user defined type (such as a structure).
/// It can be declared and defined in global scope by:
///   #include "aho_corasick_template_impl.h"
///   ACM_DECLARE (T)
///   ACM_DEFINE (T)
///
/// A destructor, and a copy constructor can be declared for type T if required.
/// Type for destructor is: void (*destructor) (const T)
#  define DESTRUCTOR_TYPE(T)                        DESTROY_##T##_TYPE

/// Type for constructor is: T (*constructor) (const T)
#  define COPY_CONSTRUCTOR_TYPE(T)                  COPY_##T##_TYPE

/// Type for equality operator is: int (*equal_operator) (const T, const T)
#  define EQ_OPERATOR_TYPE(T)                       EQ_##T##_TYPE

/// SET_DESTRUCTOR optionally declares a destructor for type T.
/// Example: SET_DESTRUCTOR (mytype, mydestructor);
#  define SET_DESTRUCTOR(T, destructor)             do { DESTROY_##T = (destructor) ; } while (0)

/// SET_COPY_CONSTRUCTOR optionally declares a copy constructor for type T.
/// Example: SET_COPY_CONSTRUCTOR (mytype, myconstructor);
#  define SET_COPY_CONSTRUCTOR(T, constructor)      do { COPY_##T = (constructor) ; } while (0)

/// SET_EQ_OPERATOR optionally declares equality operator for type T.
/// A user defined equality operator can be declared for type T if needed.
/// A default equality operator (memcmp) is used otherwise.
/// Example: static int nocaseeq (wchar_t k, wchar_t t) { return k == towlower (t); }
///          SET_EQ_OPERATOR (wchar_t, nocaseeq);
#  define SET_EQ_OPERATOR(T, equal_operator)        do { EQ_##T = (equal_operator) ; } while (0)

/// ACState (T) is the type of a Aho-Corasick state machine for type T
#  define ACState(T)                                ACState_##T

/// ACMachine (T) is the type of the Aho-Corasick finite state machine for type T
#  define ACMachine(T)                              ACMachine_##T

/// ACMachine (T) *ACM_create (T, [equality_operator], [copy constructor], [destructor])
/// Creates a Aho-Corasick finite state machine for type T.
/// @param [in] T type of symbols composing keywords and text to be parsed.
/// @param [in, optional] equality_operator Equality operator of type EQ_OPERATOR_TYPE(T).
/// @param [in, optional] copy constructor Copy constructor of type COPY_CONSTRUCTOR_TYPE(T).
/// @param [in, optional] destructor Destructor of type DESTRUCTOR_TYPE(T).
/// @returns A pointer to a Aho-Corasick machine for type T.
/// Example: ACMachine (char) * M = ACM_create (char);
/// Note: ACM_create accepts optional arguments thanks to the use of the VFUNC macro (see below).
#  define ACM_create(...)                           VFUNC(ACM_create, __VA_ARGS__)

/// void ACM_release (const ACMachine (T) *machine)
/// Releases the ressources of a Aho-Corasick machine created with ACM_create.
/// @param [in] machine A pointer to a Aho-Corasick machine to be realeased.
/// Example: ACM_release (M);
#  define ACM_release(machine)                      (machine)->vtable->release ((machine))

/// Keyword (T) is the type of a keyword composed of symbols of type T.
/// Exemple: Keyword (char) kw;
#  define Keyword(T)                                Keyword_##T

/// void ACM_KEYWORD_SET (Keyword(T) kw, T* array, size_t length)
/// Initializes a keyword from an array of symbols
/// @param [in] kw Keyword of symbols of type T.
/// @param [in] array Array of symbols
/// @param [in] length Length of the array
/// Note: The array is NOT duplicated by ACM_KEYWORD_SET and should be allocated by the calling user program.
/// Exemple: ACM_KEYWORD_SET (kw, "Duck", 4);
#  define ACM_KEYWORD_SET(keyword,symbols,length)   do { ACM_MATCH_SYMBOLS (keyword) = (symbols); ACM_MATCH_LENGTH (keyword) = (length); } while (0)

/// int ACM_register_keyword(ACMachine(T) *machine, Keyword(T) kw, [void * value_ptr], [void (*destructor) (void *)])
/// Registers a keyword in the Aho-Corasick machine.
/// @param [in] machine A pointer to a Aho-Corasick machine.
/// @param [in] kw Keyword of symbols of type T to be registered.
/// @param [in, optional] value_ptr Pointer to a previously allocated value to associate with keyword kw.
/// @param [in, optional] destructor A destructor to be used to free the value pointed by value_ptr.
///                                  The default destructor is the standard library function `free.
///                                  Use `0` if the allocated value need not be managed by the finite state machine
///                                  (in case of automatic or static values).
/// @return 1 if the keyword was successfully registered, 0 otherwise (if the keyword is empty).
/// Note: When returning 0, the destructor, if any, is called on value, if any.
/// Note: If the keywpord is already registered in the machine, its associated value is forgotten and replaced by the new value.
/// Note: Keyword kw is duplicated and can be released after its registration.
/// Note: The equality operator, either associated to the machine, or associated to the type T, is used if declared.
/// Note: The keyword is registered together with its rank.
///       The rank of the registered keyword is the number of times ACM_register_keyword was previously called
///       since the machine was created. The rank is a 0-based sequence number.
///       This rank can later be retrieved by ACM_get_match.
/// Example: ACM_register_keyword (M, kw);
///          ACM_register_keyword (M, kw, calloc (1, sizeof (int)), free);
#  define ACM_register_keyword(...)                 VFUNC(ACM_register_keyword, __VA_ARGS__)

/// int ACM_is_registered_keyword (const ACMachine(T) * machine, Keyword(T) kw, [void **value_ptr])
/// Checks whether a keyword is already registered in the machine.
/// @param [in] machine A pointer to a Aho-Corasick machine.
/// @param [in] kw Keyword of symbols of type T to be checked.
/// @param [out, optional] value_ptr *value_ptr is set to the pointer of the value associated to the keyword after the call.
/// @return 1 if the keyword is registered in the machine, 0 otherwise.
/// Note: The equality operator, either associated to the machine, or associated to the type T, is used if declared.
#  define ACM_is_registered_keyword(...)            VFUNC(ACM_is_registered_keyword, __VA_ARGS__)

/// int ACM_unregister_keyword (ACMachine(T) *machine, Keyword(T) kw)
/// Unregisters a keyword from the Aho-Corasick machine.
/// @param [in] machine A pointer to a Aho-Corasick machine.
/// @param [in] kw Keyword of symbols of type T to be registered.
/// @return 1 if the keyword was successfully unregistered, 0 otherwise (the keywpord is not registered in the machine).
/// Note: The equality operator, either associated to the machine, or associated to the type T, is used if declared.
#  define ACM_unregister_keyword(machine, keyword)  (machine)->vtable->unregister_keyword ( (machine), (keyword))

/// size_t ACM_nb_keywords (const ACMachine(T) *machine)
/// Returns the number of keywords registered in the machine.
/// @param [in] machine A pointer to a Aho-Corasick machine.
/// @return The number of keywords registered in the machine.
#  define ACM_nb_keywords(machine)                  (machine)->vtable->nb_keywords ((machine))

/// MatchHolder (T) is the type of a match composed of symbols of type T.
/// Exemple: MatchHolder (char) match;
#  define MatchHolder(T)                            MatchHolder_##T

/// size_t ACM_MATCH_LENGTH (MatchHolder(T) match)
/// Returns the length of a matching keyword.
/// @param [in] match A matching keyword.
/// @return The length of the matching keyword.
/// Note: This function can also be applied to a keyword of type Keyword(T).
#  define ACM_MATCH_LENGTH(match)                   ((match).length)

/// T* ACM_MATCH_SYMBOLS (MatchHolder(T) match)
/// Returns the array to the symbols of a matching keyword.
/// @param [in] match A matching keyword.
/// @return The array to the symbols of the matching keyword.
/// Note: This function can also be applied to a keyword of type Keyword(T).
#  define ACM_MATCH_SYMBOLS(match)                  ((match).letter)

/// size_t ACM_MATCH_UID (MatchHolder(T) match)
/// Returns the unique id of a matching keyword.
/// @param [in] match A matching keyword returned by a previous call to `ACM_get_match`.
/// @return The unique id of the matching keyword.
#  define ACM_MATCH_UID(match)                      ((match).rank)

/// void ACM_foreach_keyword (const ACMachine(T) * machine, void (*operator) (MatchHolder(T) kw, void *value))
/// Applies an operator to each registered keyword (by `ACM_register_keyword`) in the machine.
/// @param [in] machine A pointer to a Aho-Corasick machine.
/// @param [in] operator Function of type void (*operator) (Keyword (T), void *)
/// Note: The operator is called for each registered keyword and pointer to associated value successively.
/// Note: The order the keywords are processed in unspecified.
/// Exemple: static void print_match (MatchHolder (wchar_t) match, void *value) { /* user code here */ }
///          ACM_foreach_keyword (M, print_match);
#  define ACM_foreach_keyword(machine, operator)    (machine)->vtable->foreach_keyword ((machine), (operator))

/// const ACState (T) * ACM_reset (ACMachine(T) * machine)
/// Get a valid state, ignoring all the symbols previously matched by ACM_match.
/// @param [in] machine A pointer to a Aho-Corasick machine.
/// @param [in] state A pointer to a valid Aho-Corasick machine state.
/// Note: Several calls to ACM_reset on the same machine can be used to
///       parse several texts concurrently (e.g. by several threads).
#  define ACM_reset(machine)                        (machine)->vtable->reset ((machine))

#  define ACM_print(machine, stream, printer)       (machine)->vtable->print ((machine), (stream), (printer))

/// size_t ACM_match (const ACState(T) *& state, T letter)
/// This is the main function used to parse a text, one symbol after the other, and search for pattern matching.
/// Get the next state matching a symbol injected in the finite state machine.
/// @param [in, out] state A pointer to a valid Aho-Corasick machine state. Argument passed by reference.
/// @param [in] letter A symbol.
/// @return The number of registered keywords that match a sequence of last letters sent to the last calls to `ACM_match`.
/// Note: The equality operator, either associated to the machine, or associated to the type T, is used if declared.
/// Note: The optional argument `nb_matches` avoids the call to ACM_nb_matches.
/// Note: `state` is passed by reference. It is modified by the function.
/// Usage: size_t nb = ACM_match(state, letter);
#  define ACM_match(state, letter)                  (state)->vtable->match(&(state), (letter))

/// void ACM_MATCH_INIT (MatchHolder(T) match)
/// Initializes a match before its first use by ACM_get_match.
/// @param [in] match A match
/// Exemple: ACM_MATCH_INIT (match);
/// Note: this function should only be applied to a matching keyword which reference is passed to ACM_get_match.
#  define ACM_MATCH_INIT(match)                     ACM_KEYWORD_SET((match), 0, ((match).rank = 0))

/// size_t ACM_get_match (const ACState(T) * state, size_t index, [MatchHolder(T) * match], [void **value_ptr])
/// Gets the ith keyword matching with the last symbols.
/// @param [in] state A pointer to a valid Aho-Corasick machine state.
/// @param [in] index Index (ith) of the ith matching keyword.
/// @param [out, optional] match *match is set to the ith matching keyword.
/// @param [out, optional] value_ptr *value_ptr is set to the pointer of the value associated to the keyword after the call.
/// @return The rank (unique id) of the ith matching keyword.
/// Note: index must be lower than value returned by the last call to ACM_match.
/// ?ote: *match should have been initialized by ACM_MATCH_INIT before use.
/// Exemple: size_t rank = ACM_get_match (state, j, &match, 0);
#  define ACM_get_match(...)                        VFUNC(ACM_get_match, __VA_ARGS__)

/// void ACM_MATCH_RELEASE (MatchHolder(T) match)
/// Releases a match after its last use by ACM_get_match.
/// @param [in] match A match
/// Exemple: ACM_MATCH_RELEASE (match);
/// Note: This function should only be applied to a matching keyword which reference is passed to `ACM_get_match`.
///       It should not ne applied to a keyword of type Keyword(T).
#  define ACM_MATCH_RELEASE(match)                  do { free (ACM_MATCH_SYMBOLS (match)); ACM_MATCH_INIT (match); } while (0)

/// Internal declarations ********************************************************************

// BEGIN VFUNC
// Credits: VFUNC is a macro for overloading on number (but not types) of arguments.
// See https://stackoverflow.com/questions/11761703/overloading-macro-on-number-of-arguments
#  define __NARG__(...)  __NARG_I_(__VA_ARGS__,__RSEQ_N())
#  define __NARG_I_(...) __ARG_N(__VA_ARGS__)
#  define __ARG_N( \
      _1, _2, _3, _4, _5, _6, _7, _8, _9,_10, \
     _11,_12,_13,_14,_15,_16,_17,_18,_19,_20, \
     _21,_22,_23,_24,_25,_26,_27,_28,_29,_30, \
     _31,_32,_33,_34,_35,_36,_37,_38,_39,_40, \
     _41,_42,_43,_44,_45,_46,_47,_48,_49,_50, \
     _51,_52,_53,_54,_55,_56,_57,_58,_59,_60, \
     _61,_62,_63,N,...) N
#  define __RSEQ_N() \
     63,62,61,60,                   \
     59,58,57,56,55,54,53,52,51,50, \
     49,48,47,46,45,44,43,42,41,40, \
     39,38,37,36,35,34,33,32,31,30, \
     29,28,27,26,25,24,23,22,21,20, \
     19,18,17,16,15,14,13,12,11,10, \
     9,8,7,6,5,4,3,2,1,0

#  define _VFUNC_(name, n) name##n
#  define _VFUNC(name, n) _VFUNC_(name, n)
#  define VFUNC(func, ...) _VFUNC(func, __NARG__(__VA_ARGS__)) (__VA_ARGS__)
// END VFUNC

// BEGIN DECLARE_ACM
#  define ACM_DECLARE(T)                             \
\
typedef T (*COPY_##T##_TYPE) (const T);              \
typedef void (*DESTROY_##T##_TYPE) (const T);        \
typedef int (*EQ_##T##_TYPE) (const T, const T);     \
\
typedef struct                                       \
{                                                    \
  T *letter;      /* An array of symbols */          \
  size_t length;  /* Length of the array */          \
} Keyword_##T;                                       \
\
typedef struct                                       \
{                                                    \
  T *letter;      /* An array of symbols */          \
  size_t length;  /* Length of the array */          \
  size_t rank;    /* Rank of the regidtered keyword */\
} MatchHolder_##T;                                   \
\
struct _ac_state_##T;                                \
typedef struct _ac_state_##T ACState_##T;            \
struct _ac_machine_##T;                              \
typedef struct _ac_machine_##T ACMachine_##T;        \
typedef int (*PRINT_##T##_TYPE) (FILE *, T);         \
struct _acs_vtable_##T                               \
{                                                    \
  size_t (*match) (const ACState_##T ** state, T letter);                                                    \
  size_t (*get_match) (const ACState_##T * state, size_t index, MatchHolder_##T * match, void **value);      \
};                                                   \
/* A state of the state machine. */                  \
struct _ac_state_##T             /* [state s] */     \
{                                                    \
  /* A link to the next states */                    \
  struct _ac_next_##T                                \
  {                                                  \
    T letter;                    /* [a symbol] */    \
    struct _ac_state_##T *state; /* [g(s, letter)] */\
  } *goto_array;                 /* next states in the tree of the goto function */\
  size_t nb_goto;                                    \
  /* A link to the previous states */                \
  struct                                             \
  {                                                  \
    size_t i_letter; /* Index of the letter in the goto_array */ \
    /* letter = previous.state->goto_array[previous.i_letter].letter */ \
    struct _ac_state_##T *state;                     \
  } previous;                    /* Previous state */\
  const struct _ac_state_##T *fail_state; /* [f(s)] */\
  int is_matching; /* true if the state matches a keyword. */\
  size_t nb_sequence; /* Number of matching keywords (Aho-Corasick : size (output (s)) */\
  size_t rank; /* Rank (0-based) of insertion of a keyword in the machine. */\
  size_t id;   /* state UID */                       \
  void *value; /* An optional value associated to a state. */\
  void (*value_dtor) (void *); /* Destrcutor of the associated value, called a state machine release. */\
  ACMachine_##T * machine;                           \
  const struct _acs_vtable_##T *vtable;              \
};                                                   \
\
struct _acm_vtable_##T                               \
{                                                    \
  int (*register_keyword) (ACMachine_##T * machine, Keyword_##T keyword, void *value, void (*dtor) (void *)); \
  int (*is_registered_keyword) (const ACMachine_##T * machine, Keyword_##T keyword, void **value);            \
  int (*unregister_keyword) (ACMachine_##T * machine, Keyword_##T keyword);                                   \
  size_t (*nb_keywords) (const ACMachine_##T * machine);                                                      \
  void (*foreach_keyword) (const ACMachine_##T * machine, void (*operator) (MatchHolder_##T, void *));        \
  void (*release) (const ACMachine_##T * machine);                                                            \
  const ACState_##T * (*reset) (const ACMachine_##T * machine);                                               \
  void (*print) (ACMachine_##T * machine, FILE * stream, PRINT_##T##_TYPE printer);                           \
};                                                   \
\
struct _ac_machine_##T                               \
{                                                    \
  struct _ac_state_##T *state_0; /* state 0 */       \
  size_t rank; /* Number of keywords registered in the machine. */\
  size_t nb_sequence; /* Number of keywords in the machine. */\
  size_t state_counter;                              \
  int reconstruct;                                   \
  size_t size;                                       \
  pthread_mutex_t lock;                              \
  const struct _acm_vtable_##T *vtable;              \
  T (*copy) (const T);                               \
  void (*destroy) (const T);                         \
  int (*eq) (const T, const T);                      \
};                                                   \
\
__attribute__ ((unused)) ACMachine_##T *ACM_create_##T (EQ_##T##_TYPE eq,        \
                                      COPY_##T##_TYPE copier,  \
                                      DESTROY_##T##_TYPE dtor);  \
struct __useless_struct_to_allow_trailing_semicolon__##T##__
// END DECLARE_ACM

// BEGIN MACROS
#  define ACM_create4(T, eq, copy, dtor)       ACM_create_##T((eq), (copy), (dtor))
#  define ACM_create2(T, eq)                   ACM_create4(T, (eq), 0, 0)
#  define ACM_create1(T)                       ACM_create4(T, 0, 0, 0)

#  define ACM_register_keyword4(machine, keyword, value, dtor)  (machine)->vtable->register_keyword ((machine), (keyword), (value), (dtor))
#  define ACM_register_keyword3(machine, keyword, value)        ACM_register_keyword4((machine), (keyword), (value), free)
#  define ACM_register_keyword2(machine, keyword)               ACM_register_keyword4((machine), (keyword), 0, 0)

#  define ACM_is_registered_keyword3(machine, keyword, value)   (machine)->vtable->is_registered_keyword ((machine), (keyword), (value))
#  define ACM_is_registered_keyword2(machine, keyword)          ACM_is_registered_keyword3((machine), (keyword), 0)

#  define ACM_get_match4(state, index, matchholder, value)      (state)->vtable->get_match ((state), (index), (matchholder), (value))
#  define ACM_get_match3(state, index, matchholder)             ACM_get_match4((state), (index), (matchholder), 0)
#  define ACM_get_match2(state, index)                          ACM_get_match4((state), (index), 0, 0)

#if defined(__GNUC__) || defined (__clang__)
#define ACM_DECL5(var, T, eq, copy, dtor)  \
__attribute__ ((cleanup (ACM_cleanup_##T))) ACMachine_##T var; machine_init_##T (&(var), state_create_##T (), (eq), (copy), (dtor))
#define ACM_DECL3(var, T, eq) ACM_DECL5(var, T, (eq), 0, 0)
#define ACM_DECL2(var, T) ACM_DECL3(var, T, 0)
#define ACM_DECL(...) VFUNC(ACM_DECL, __VA_ARGS__)
#endif
// END MACROS

#endif
