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

/*
 * This file is modified from the original to suppress ISO C and c99 warnings 
 * issued by both gcc and clang, such as those for _Generic selection and %n$ 
 * operand number formats. So, this version is compatible with ISO C and c99, 
 * but does not support generic programming. The keywords can only be of 
 * (char *) type.
 */

// Credits: This implementation of "templates" makes use of a nice idea of Randy Gaul for Generic Programming in C.
// See http://www.randygaul.net/2012/08/10/generic-programming-in-c
//
// Initialized by gcc -fpreprocessed -dD -E -P aho_corasick.c | grep -v '^$' | indent

#ifndef __ACM_TEMPLATE_IMPL__

#  define __ACM_TEMPLATE_IMPL__
#  include <stddef.h>
#  include <inttypes.h>
#  include <stdlib.h>
#  include <stdio.h>
#  include <pthread.h>
#  include <string.h>
#  include <signal.h>

#  define ACM_KEEP_VALUE 0  //  Configures the behavior of ACM_register_keyword_##ACM_SYMBOL if a keyword was already previously registered.
#  include "aho_corasick_template.h"

#  define ACM_ASSERT(cond) do { if (!(cond)) { \
      fprintf(stderr, "FATAL ERROR: !(%s) in function %s at %s:%i)\n", #cond, __func__, __FILE__, __LINE__);\
      pthread_exit(0) ;\
} } while (0)

static int UNUSED
__eqchar (const char a, const char b)
{
  return a == b;
}

#  define EQ_DEFAULT(ACM_SYMBOL) (__eqchar)

// BEGIN DEFINE_ACM
#  define ACM_DEFINE(ACM_SYMBOL)                                       \
\
static int (*EQ_##ACM_SYMBOL) (const ACM_SYMBOL, const ACM_SYMBOL) = 0;\
\
static void                                                            \
__DTOR_##ACM_SYMBOL(UNUSED const ACM_SYMBOL letter)                           \
{                                                                      \
    ((void)0);                             \
}                                                                      \
\
static ACM_SYMBOL                                                      \
__COPY_##ACM_SYMBOL(const ACM_SYMBOL letter)                           \
{                                                                      \
  return letter;   \
}                                                                      \
\
static int __EQ_##ACM_SYMBOL(const ACM_SYMBOL a, const ACM_SYMBOL b)   \
{                                                                      \
  return   EQ_##ACM_SYMBOL ?                                           \
             EQ_##ACM_SYMBOL (a,   b) :                                \
             (size_t)0 != (size_t)(EQ_DEFAULT (ACM_SYMBOL)) ?          \
               EQ_DEFAULT (ACM_SYMBOL)(a,   b) :                       \
               (fprintf (stderr, "%s", "ERROR: " "Missing equality operator for type '" #ACM_SYMBOL "'.\n"  \
                                       "       " "Use SET_EQ_OPERATOR(" #ACM_SYMBOL ", operator),\n"        \
                                       "       " "where operator is a function defined as:\n"               \
                                       "       " "int operator(" #ACM_SYMBOL " a, " #ACM_SYMBOL " b) { return a == b ; }.\n"   \
                                       "ABORT  " "\n"), fflush (0), raise (SIGABRT));                       \
}                                                                      \
\
static const ACState_##ACM_SYMBOL *state_goto_##ACM_SYMBOL (           \
                const ACState_##ACM_SYMBOL * state,                    \
                ACM_SYMBOL letter, EQ_##ACM_SYMBOL##_TYPE eq);         \
\
static void                                                            \
state_reset_output_##ACM_SYMBOL (ACState_##ACM_SYMBOL * r)             \
{                                                                      \
  if (r->is_matching)                                                  \
    r->nb_sequence = 1; /* Reset to original output (as in state_goto_update) */\
  else                                                                 \
    r->nb_sequence = 0;                                                \
  struct _ac_next_##ACM_SYMBOL *p = r->goto_array;                     \
  struct _ac_next_##ACM_SYMBOL *end = p + r->nb_goto;                  \
  for (; p < end; p++)                                                 \
    state_reset_output_##ACM_SYMBOL (p->state);                        \
}                                                                      \
/* Aho-Corasick Algorithm 3: construction of the failure function. */  \
static void                                                            \
state_fail_state_construct_##ACM_SYMBOL (ACMachine_##ACM_SYMBOL * machine) \
{                                                                      \
  ACState_##ACM_SYMBOL *state_0 = machine->state_0; /* [state 0] */    \
  if (machine->reconstruct == 2)                                       \
    state_reset_output_##ACM_SYMBOL (state_0);                         \
  /* Aho-Corasick Algorithm: "(except state 0 for which the failure function is not defined)." */\
  state_0->fail_state = 0;                                             \
  /* Aho-Corasick Algorithm 3: queue <- empty */                       \
  /* The first element in the queue will not be processed, therefore it can be added harmlessly. */\
  size_t queue_length = 0;                                             \
  ACState_##ACM_SYMBOL **queue = 0;                                    \
  ACM_ASSERT (queue = malloc (sizeof (*queue) * (machine->size - 1))); \
  /* Aho-Corasick Algorithm 3: for each a such that s != 0 [fail], where s <- g(0, a) do   [1] */\
  struct _ac_next_##ACM_SYMBOL *p = state_0->goto_array;               \
  struct _ac_next_##ACM_SYMBOL *end = p + state_0->nb_goto;            \
  for (; p < end; p++) /* loop on state_0->goto_array */               \
  {                                                                    \
    ACState_##ACM_SYMBOL *s = p->state; /* [for each a such that s != 0 [fail], where s <- g(0, a)] */\
    /* Aho-Corasick Algorithm 3: queue <- queue U {s} */               \
    queue_length++;                                                    \
    queue[queue_length - 1] = s; /* s */                               \
    /* Aho-Corasick Algorithm 3: f(s) <- 0 */                          \
    s->fail_state = state_0;                                           \
  }   /* loop on state_0->goto_array */                                \
  size_t queue_read_pos = 0;                                           \
  /* Aho-Corasick Algorithm 3: while queue != empty do */              \
  while (queue_read_pos < queue_length)                                \
  {                                                                    \
    /* Aho-Corasick Algorithm 3: let r be the next state in queue */   \
    ACState_##ACM_SYMBOL *r = queue[queue_read_pos];                   \
    /* Aho-Corasick Algorithm 3: queue <- queue - {r} */               \
    queue_read_pos++;                                                  \
    /* Aho-Corasick Algorithm 3: for each a such that s != fail, where s <- g(r, a) */\
    struct _ac_next_##ACM_SYMBOL *p = r->goto_array;                   \
    struct _ac_next_##ACM_SYMBOL *end = p + r->nb_goto;                \
    for (; p < end; p++)                   /* loop on r->goto_array */ \
    {                                                                  \
      ACState_##ACM_SYMBOL *s = p->state; /* [s <- g(r, a)] */         \
      ACM_SYMBOL a = p->letter;                                        \
      /* Aho-Corasick Algorithm 3: queue <- queue U {s} */             \
      queue_length++;                                                  \
      queue[queue_length - 1] = s;                                     \
      /* Aho-Corasick Algorithm 3: state <- f(r) */                    \
      const ACState_##ACM_SYMBOL *state = r->fail_state; /* f(r) */    \
      /* Aho-Corasick Algorithm 3: while g(state, a) = fail [and state != 0] do state <- f(state)        [2] */\
      /*                           [if g(state, a) != fail then] f(s) <- g(state, a) [else f(s) <- 0]    [3] */\
      s->fail_state /* f(s) */ = state_goto_##ACM_SYMBOL (state, a, machine->eq); \
      /* Aho-Corasick Algorithm 3: output (s) <-output (s) U output (f(s)) */\
      s->nb_sequence += s->fail_state->nb_sequence;                    \
    }   /* loop on r->goto_array */                                    \
  }   /* while (queue_read_pos < queue_length) */                      \
  free (queue);                                                        \
  machine->reconstruct = 0;                                            \
}                                                                      \
\
static const ACState_##ACM_SYMBOL *                                    \
state_goto_##ACM_SYMBOL (const ACState_##ACM_SYMBOL * state, ACM_SYMBOL letter /* a[i] */,\
                         EQ_##ACM_SYMBOL##_TYPE eq)                    \
{                                                                      \
  /* Aho-Corasick Algorithm 1: while g(state, a[i]) = fail [and state != 0] do state <- f(state)           [2] */\
  /*                           [if g(state, a[i]) != fail then] state <- g(state, a[i]) [else state <- 0]  [3] */\
  /*                           [The function returns state] */         \
  while (1)                                                            \
  {                                                                    \
    /* [if g(state, a[i]) != fail then return g(state, a[i])] */       \
    struct _ac_next_##ACM_SYMBOL *p = state->goto_array;               \
    struct _ac_next_##ACM_SYMBOL *end = p + state->nb_goto;            \
    for (; p < end; p++)                                               \
      if (eq (p->letter, letter))                                      \
        return p->state;                                               \
    /* From here, [g(state, a[i]) = fail] */                           \
                                                                       \
    /* Algorithms 1 cannot consider that g(0, a) never fails because propoerty LOOP_0 has not been implemented. */\
    /* Therefore, for state 0, we must simulate the property LOOP_0, i.e state 0 must be returned, */\
    /* as if g(0, a[i]) would have been set to state 0 if g(0, a[i]) = fail (property LOOP_0). */\
    /* After Algorithm 3 has been processed, the only state for which f(state) = 0 is state 0. */\
    /* [if g(state, a[i]) = fail and state = 0 then return state 0] */ \
    /* Aho-Corasick Algorithm: "(except state 0 for which the failure function is not defined)." */\
    if (state->fail_state == 0)                                        \
      return state;                                                    \
    /* From here, [state != 0] */                                      \
                                                                       \
    /* [if g(state, a[i]) = fail and state != 0 then state <- f(state) */\
    state = state->fail_state;                                         \
  }                                                                    \
}                                                                      \
/* Aho-Corasick Algorithm 1: Pattern matching machine - if output (state) != empty */\
static size_t                                                          \
ACM_match_##ACM_SYMBOL (const ACState_##ACM_SYMBOL ** pstate, ACM_SYMBOL letter)     \
{                                                                      \
  /* N.B.: In Aho-Corasick, algorithm 3 is executed after all keywords have been inserted */\
  /*       in the goto graph one after the other by algorithm 2. */    \
  /*       As a slight enhancement: the fail state chains are rebuilt from scratch when needed, */\
  /*       i.e. if a keyword has been added since the last pattern maching search. */\
  /*       Therefore, algorithms 2 and 3 can be processed alternately. */\
  /*       (algorithm 3 will traverse the full goto graph after a keyword has been added.) */\
  /* Double-checked locking */                                         \
  ACMachine_##ACM_SYMBOL * machine = (*pstate)->machine;               \
  if (machine->reconstruct)                                            \
  {                                                                    \
    pthread_mutex_lock (&machine->lock);                               \
    if (machine->reconstruct)                                          \
      state_fail_state_construct_##ACM_SYMBOL (machine);               \
    pthread_mutex_unlock (&machine->lock);                             \
  }                                                                    \
  return                                                               \
    (*pstate = state_goto_##ACM_SYMBOL (*pstate, letter, machine->eq)) \
      ->nb_sequence;                                                   \
}                                                                      \
/* Aho-Corasick Algorithm 1: Pattern matching machine - print output (state) [ith element] */\
static size_t                                                          \
ACM_get_match_##ACM_SYMBOL (const ACState_##ACM_SYMBOL * state, size_t index,  \
                            MatchHolder_##ACM_SYMBOL * match, void **value)    \
{                                                                      \
  /* Aho-Corasick Algorithm 1: if output(state) [ith element] */       \
  ACM_ASSERT (index < state->nb_sequence);                             \
  size_t i = 0;                                                        \
  for (; state; state = state->fail_state, i++ /* skip to the next failing state */ )\
  {                                                                    \
    /* Look for the first state in the "failing states" chain which matches a keyword. */\
    while (!state->is_matching && state->fail_state)                   \
      state = state->fail_state;                                       \
    if (i == index)                                                    \
      break;                                                           \
  }                                                                    \
  /* Argument match could be passed to 0 if only value or rank is needed. */\
  if (match)                                                           \
  {                                                                    \
    /* Aho-Corasick Algorithm 1: [print i] */                          \
    /* Aho-Corasick Algorithm 1: print output(state) [ith element] */  \
    /* Reconstruct the matching keyword moving backward from the matching state to the state 0. */\
    match->length = 0;                                                 \
    for (const ACState_##ACM_SYMBOL * s = state; s && s->previous.state; s = s->previous.state)            \
      match->length++;                                                 \
    /* Reallocation of match->letter. match->letter should be freed by the user after the last call to ACM_get_match on match. */\
    ACM_ASSERT (match->letter = realloc (match->letter, sizeof (*match->letter) * match->length));         \
    i = 0;                                                             \
    for (const ACState_##ACM_SYMBOL * s = state; s && s->previous.state; s = s->previous.state)            \
    {                                                                  \
      match->letter[match->length - i - 1] = s->previous.state->goto_array[s->previous.i_letter].letter;   \
      i++;                                                             \
    }                                                                  \
    match->rank = state->rank;                                         \
  }                                                                    \
  /* Argument value could passed to 0 if the associated value is not needed. */\
  if (value)                                                           \
    *value = state->value;                                             \
  return state->rank;                                                  \
}                                                                      \
\
static const struct _acs_vtable_##ACM_SYMBOL ACS_VTABLE_##ACM_SYMBOL = \
{                                                                      \
  ACM_match_##ACM_SYMBOL,                                              \
  ACM_get_match_##ACM_SYMBOL,                                          \
};                                                                     \
\
ACState_##ACM_SYMBOL *                                                 \
state_create_##ACM_SYMBOL (void)                                       \
{                                                                      \
  ACState_##ACM_SYMBOL *s = malloc (sizeof (*s)); /* [state s] */      \
  ACM_ASSERT (s);                                                      \
  /* [g(s, a) is undefined (= fail) for all input symbol a] */         \
  s->goto_array = 0;                                                   \
  s->nb_goto = 0;                                                      \
  s->previous.state = 0;                                               \
  s->previous.i_letter = 0;                                            \
  /* Aho-Corasick Algorithm 2: "We assume output(s) is empty when state s is first created." */ \
  s->nb_sequence = 0;           /* number of outputs in [output(s)] */ \
  s->is_matching = 0; /* if 1, indicates that the state is the last node of a registered keyword */   \
  s->fail_state = 0;                                                   \
  s->rank = 0;                                                         \
  s->value = 0;                                                        \
  s->value_dtor = 0;                                                   \
  s->machine = 0;                                                      \
  s->vtable = &(ACS_VTABLE_##ACM_SYMBOL);                              \
  return s;                                                            \
}                                                                      \
/* Aho-Corasick Algorithm 2: construction of the goto function - procedure enter(a[1] a[2] ... a[n]). */\
static int                                                             \
machine_goto_update_##ACM_SYMBOL (ACMachine_##ACM_SYMBOL * machine,    \
                                  Keyword_##ACM_SYMBOL sequence /* a[1] a[2] ... a[n] */, \
                                  void *value, void (*dtor) (void *))  \
{                                                                      \
  if (!sequence.length)                                                \
  {                                                                    \
    if (dtor)                                                          \
      dtor (value);                                                    \
    return 0;                                                          \
  }                                                                    \
  ACState_##ACM_SYMBOL *state_0 = machine->state_0; /* [state 0] */    \
  /* Iterators */                                                      \
  /* Aho-Corasick Algorithm 2: state <- 0 */                           \
  ACState_##ACM_SYMBOL *state = state_0;                               \
  /* Aho-Corasick Algorithm 2: j <- 1 */                               \
  size_t j = 0; /* j is 0-based here (and not 1-based like in original text) */\
  /* Aho-Corasick Algorithm 2: while g(state, a[j]) != fail [and j <= m] do */\
  /* Iterations on i and s until a final state */                      \
  for (; j < sequence.length /* [j <= m] */ ;)                         \
  {                                                                    \
    ACState_##ACM_SYMBOL *next = 0;                                    \
    /* Aho-Corasick Algorithm 2: "g(s, l) = fail if l is undefined or if g(s, l) has not been defined." */\
    /* Loop on all symbols a for which g(state, a) is defined. */      \
    struct _ac_next_##ACM_SYMBOL *p = state->goto_array;               \
    struct _ac_next_##ACM_SYMBOL *end = p + state->nb_goto;            \
    for (; p < end; p++)                                               \
      if (machine->eq (p->letter, sequence.letter[j]))                 \
      {                                                                \
        /* [if g(state, a[j]) is defined] */                           \
        next = p->state;                                               \
        break;                                                         \
      }                                                                \
    /* [if g(state, a[j]) is defined (!= fail)] */                     \
    if (next)                                                          \
    {                                                                  \
      /* Aho-Corasick Algorithm 2: state <- g(state, a[j]) */          \
      state = next;                                                    \
      /* Aho-Corasick Algorithm 2: j <- j + 1 */                       \
      j++;                                                             \
    }                                                                  \
    /* [g(state, a[j]) is not defined (= fail)] */                     \
    else                                                               \
      break;  /* exit while g(state, a[j]) != fail */                  \
  }                                                                    \
  /* Aho-Corasick Algorithm 2: for p <- j until m do */                \
  /* Appending states for the new sequence to the final state found */ \
  for (size_t p = j; p < sequence.length /* [p <= m] */ ; p++)         \
  {                                                                    \
    state->nb_goto++;                                                  \
    ACM_ASSERT (state->goto_array = realloc (state->goto_array,        \
                sizeof (*state->goto_array) * state->nb_goto));        \
    /* Creation of a new state */                                      \
    /* Aho-Corasick Algorithm 2: newstate <- newstate + 1 */           \
    ACState_##ACM_SYMBOL *newstate = state_create_##ACM_SYMBOL ();     \
    newstate->machine = machine;                                       \
    newstate->id = ++machine->state_counter; /* state UID */           \
    /* Aho-Corasick Algorithm 2: g(state, a[p]) <- newstate */         \
    state->goto_array[state->nb_goto - 1].state = newstate;            \
    state->goto_array[state->nb_goto - 1].letter = machine->copy (sequence.letter[p]);  \
    /* Backward link: previous(newstate, a[p]) <- state */             \
    newstate->previous.state = state;                                  \
    /* state->goto_array[state->nb_goto - 1].state->previous.i_letter = state->nb_goto - 1; */\
    newstate->previous.i_letter = state->nb_goto - 1;                  \
    /* Aho-Corasick Algorithm 2: state <- newstate */                  \
    state = newstate;                                                  \
    machine->size++;                                                   \
  }                                                                    \
  if (!state->is_matching)                                             \
  {                                                                    \
    /* Aho-Corasick Algorithm 2: output (state) <- { a[1] a[2] ... a[n] } */\
    /* Aho-Corasick Algorithm 2: "We assume output(s) is empty when state s is first created." */\
    /* Adding the sequence to the last found state (created or not) */ \
    state->is_matching = 1;                                            \
    state->nb_sequence = 1;                                            \
    state->rank = machine->rank++; /* rank is a 0-based index */       \
    machine->nb_sequence++;                                            \
    if (!machine->reconstruct)                                         \
      machine->reconstruct = 2; /* f(s) must be recomputed */          \
  }                                                                    \
  /* If the keyword was already previously registered (state->is_matching != 0) */\
  else if (ACM_KEEP_VALUE)                                             \
    /*   if !ACM_KEEP_VALUE: the new value replaces the old one: the associated old value is forgotten. */\
    /*   if  ACM_KEEP_VALUE: the rank and associated value are left unchanged. */\
  {                                                                    \
    if (dtor)                                                          \
      dtor (value);                                                    \
    return 0;                                                          \
  }                                                                    \
  /* if (!state->is_matching || !ACM_KEEP_VALUE) */                    \
  if (state->value_dtor)                                               \
    state->value_dtor (state->value);                                  \
  state->value = value;                                                \
  state->value_dtor = dtor;                                            \
  return 1;                                                            \
}                                                                      \
\
static void                                                            \
machine_init_##ACM_SYMBOL (ACMachine_##ACM_SYMBOL *machine,            \
                             ACState_##ACM_SYMBOL * state_0,           \
                             EQ_##ACM_SYMBOL##_TYPE eq,                \
                             COPY_##ACM_SYMBOL##_TYPE copier,          \
                             DESTROY_##ACM_SYMBOL##_TYPE dtor);        \
\
__attribute__ ((unused)) ACMachine_##ACM_SYMBOL *ACM_create_##ACM_SYMBOL (EQ_##ACM_SYMBOL##_TYPE eq, \
                                                 COPY_##ACM_SYMBOL##_TYPE copier,  \
                                                 DESTROY_##ACM_SYMBOL##_TYPE dtor) \
{                                                                      \
  ACMachine_##ACM_SYMBOL *machine = malloc (sizeof (*machine));        \
  ACM_ASSERT (machine);                                                \
  /* Aho-Corasick Algorithm 2: newstate <- 0 */                        \
  /* Create state 0. */                                                \
  machine_init_##ACM_SYMBOL (machine, state_create_##ACM_SYMBOL (), eq, copier, dtor); \
  return machine;                                                      \
}                                                                      \
\
static int                                                             \
ACM_register_keyword_##ACM_SYMBOL (ACMachine_##ACM_SYMBOL * machine, Keyword_##ACM_SYMBOL y,\
                                   void *value, void (*dtor) (void *))                      \
{                                                                      \
  return machine_goto_update_##ACM_SYMBOL (machine, y, value, dtor);   \
                                                                       \
  /* Aho-Corasick Algorithm 2: for all a such that g(0, a) = fail do g(0, a) <- 0 */\
  /* This statement is aimed to set the following property (here called the Aho-Corasick LOOP_0 property): */\
  /*   "All our pattern matching machines have the property that g(0, l) != fail for all input symbol l. */\
  /*    [...] this property of the goto function [g] on state 0 [root] ensures that one input symbol will be processed */\
  /*    by the machine in every machine cycle [state_goto]." */\
  /*   "We add a loop from state 0 to state 0 on all input symbols other than [the symbols l for which g(0, l) is already defined]. */\
  \
  /* N.B.: This property is *NOT* implemented in this code after calls to enter(y[i]) because */\
  /*       it requires that the alphabet of all possible symbols is known in advance. */\
  /*       This would kill the genericity of the code. */\
  /*       Therefore, Algorithms 1, 3 and 4 *CANNOT* consider that g(0, l) never fails for any symbol l. */\
  /*       g(0, l) can fail like any other state transition. */\
  /*       Thus, the implementation slightly differs from the one proposed by Aho-Corasick. */\
}                                                                      \
\
static size_t                                                          \
ACM_nb_keywords_##ACM_SYMBOL (const ACMachine_##ACM_SYMBOL * machine)  \
{                                                                      \
  return machine->nb_sequence;                                         \
}                                                                      \
\
static ACState_##ACM_SYMBOL *                     \
get_last_state_##ACM_SYMBOL (const ACMachine_##ACM_SYMBOL * machine, Keyword_##ACM_SYMBOL sequence) \
{                                                                      \
  if (!sequence.length)                                                \
    return 0;                                                          \
  ACState_##ACM_SYMBOL *state = machine->state_0; /* [state 0] */      \
  for (size_t j = 0; j < sequence.length; j++)                         \
  {                                                                    \
    ACState_##ACM_SYMBOL *next = 0;                                    \
    struct _ac_next_##ACM_SYMBOL *p = state->goto_array;               \
    struct _ac_next_##ACM_SYMBOL *end = p + state->nb_goto;            \
    for (; p < end; p++)                                               \
      if (machine->eq (p->letter, sequence.letter[j]))                 \
      {                                                                \
        next = p->state;                                               \
        break;                                                         \
      }                                                                \
    if (next)                                                          \
      state = next;                                                    \
    else                                                               \
      return 0;                                                        \
  }                                                                    \
  return state->is_matching ? state : 0;                               \
}                                                                      \
\
static int                     \
ACM_is_registered_keyword_##ACM_SYMBOL (const ACMachine_##ACM_SYMBOL * machine, \
                                        Keyword_##ACM_SYMBOL sequence, \
                                        void **value)                  \
{                                                                      \
  ACState_##ACM_SYMBOL *last = get_last_state_##ACM_SYMBOL (machine, sequence);  \
  if (last && value)                                                   \
    *value = last->value;                                              \
  return last ? 1 : 0;                                                 \
}                                                                      \
\
static int                     \
ACM_unregister_keyword_##ACM_SYMBOL (ACMachine_##ACM_SYMBOL * machine, Keyword_##ACM_SYMBOL y)  \
{                                                                      \
  ACState_##ACM_SYMBOL *last = get_last_state_##ACM_SYMBOL (machine, y); \
  if (!last)    /* The keyword y is not a registered keyword */        \
    return 0;                                                          \
  ACState_##ACM_SYMBOL *state_0 = machine->state_0; /* [state 0] */    \
  /* machine->rank is not decreased, so as to ensure unicity. */       \
  machine->nb_sequence--;                                              \
  if (last->nb_goto)  /* The keyword y is the prefix of another registered keyword */ \
  {                                                                    \
    last->is_matching = 0; /* not matching  nymore */                  \
    last->nb_sequence = 0;                                             \
    last->rank = 0;                                                    \
    return 1;                                                          \
  }                                                                    \
  /* From here, last->nb_goto == 0 */                                  \
  ACState_##ACM_SYMBOL *prev = 0;                                      \
  do  /* backward processing the keyword y */                          \
  {                                                                    \
    prev = last->previous.state;                                       \
    /* Remove last from prev->goto_array */                            \
    prev->nb_goto--;                                                   \
    for (size_t k = last->previous.i_letter; k < prev->nb_goto; k++)   \
    {                                                                  \
      machine->destroy (prev->goto_array[k].letter);                   \
      prev->goto_array[k] = prev->goto_array[k + 1];                   \
      prev->goto_array[k].state->previous.i_letter = k;                \
    }                                                                  \
    prev->goto_array = realloc (prev->goto_array, sizeof (*prev->goto_array) * prev->nb_goto);  \
    ACM_ASSERT (!prev->nb_goto || prev->goto_array);                   \
    /* Release associated value; */                                    \
    if (last->value_dtor)                                              \
      last->value_dtor (last->value);                                  \
    /* Release last */                                                 \
    free (last);                                                       \
    machine->size--;                                                   \
    last = prev;                                                       \
  }                                                                    \
  while (prev && prev != state_0 && !prev->is_matching && !prev->nb_goto);  \
                                                                       \
  if (!machine->reconstruct)                                           \
    machine->reconstruct = 2;   /* f(s) must be recomputed */          \
                                                                       \
  return 1;                                                            \
}                                                                      \
\
static void                                                            \
foreach_keyword_##ACM_SYMBOL (const ACState_##ACM_SYMBOL * state, ACM_SYMBOL ** letters, size_t * length, size_t depth, \
                              void (*operator) (MatchHolder_##ACM_SYMBOL, void *)) \
{                                                                      \
  if (state->is_matching && depth)                                     \
  {                                                                    \
    MatchHolder_##ACM_SYMBOL k = {.letter = *letters,.length = depth, .rank = state->rank };    \
    (*operator) (k, state->value);                                     \
  }                                                                    \
  if (state->nb_goto && depth >= *length)                              \
  {                                                                    \
    (*length)++;                                                       \
    *letters = realloc (*letters, sizeof (**letters) * (*length));     \
    ACM_ASSERT (letters);                                              \
  }                                                                    \
  struct _ac_next_##ACM_SYMBOL *p = state->goto_array;                 \
  struct _ac_next_##ACM_SYMBOL *end = p + state->nb_goto;              \
  for (; p < end; p++)                                                 \
  {                                                                    \
    (*letters)[depth] = p->letter;                                     \
    foreach_keyword_##ACM_SYMBOL (p->state, letters, length, depth + 1, operator);  \
  }                                                                    \
}                                                                      \
\
static void                                                            \
ACM_foreach_keyword_##ACM_SYMBOL (const ACMachine_##ACM_SYMBOL * machine, void (*operator) (MatchHolder_##ACM_SYMBOL, void *))                     \
{                                                                      \
  if (!operator)                                                       \
    return;                                                            \
  ACState_##ACM_SYMBOL *state_0 = machine->state_0; /* [state 0] */    \
  ACM_SYMBOL *letters = 0;                                             \
  size_t depth = 0;                                                    \
  foreach_keyword_##ACM_SYMBOL (state_0, &letters, &depth, 0, operator);\
  free (letters);                                                      \
}                                                                      \
\
static void                                                            \
state_release_##ACM_SYMBOL (const ACState_##ACM_SYMBOL * state,        \
                            DESTROY_##ACM_SYMBOL##_TYPE dtor)          \
{                                                                      \
  /* Release goto_array */                                             \
  struct _ac_next_##ACM_SYMBOL *p = state->goto_array;                 \
  struct _ac_next_##ACM_SYMBOL *end = p + state->nb_goto;              \
  for (; p < end; p++)                                                 \
  {                                                                    \
    state_release_##ACM_SYMBOL (p->state, dtor);                       \
    if (dtor)                                                          \
      dtor (p->letter);                                                \
  }                                                                    \
  free (state->goto_array);                                            \
  /* Release associated value */                                       \
  if (state->value_dtor)                                               \
    state->value_dtor (state->value);                                  \
  /* Release state */                                                  \
  free ((ACState_##ACM_SYMBOL *) state);                               \
}                                                                      \
\
static void                                                            \
ACM_cleanup_##ACM_SYMBOL (const ACMachine_##ACM_SYMBOL * machine)      \
{                                                                      \
  state_release_##ACM_SYMBOL (machine->state_0, machine->destroy);     \
  pthread_mutex_destroy (&((ACMachine_##ACM_SYMBOL *) machine)->lock); \
}                                                                      \
\
static void                                                            \
ACM_release_##ACM_SYMBOL (const ACMachine_##ACM_SYMBOL * machine)      \
{                                                                      \
  ACM_cleanup_##ACM_SYMBOL (machine);                                  \
  free ((ACMachine_##ACM_SYMBOL *) machine);                           \
}                                                                      \
\
static const ACState_##ACM_SYMBOL *                                    \
ACM_reset_##ACM_SYMBOL (const ACMachine_##ACM_SYMBOL * machine)        \
{                                                                      \
  return machine->state_0;                                             \
}                                                                      \
                                                                       \
static void                                                            \
state_print_##ACM_SYMBOL (ACState_##ACM_SYMBOL *state,                 \
                          FILE* stream, size_t indent, size_t id_state,\
                          PRINT_##ACM_SYMBOL##_TYPE printer)           \
{                                                                      \
  static size_t nb_states, cur_pos;                                    \
  for (size_t i = 0 ; i < state->nb_goto ; i++)                        \
  {                                                                    \
    if (indent < cur_pos)                                              \
    {                                                                  \
      cur_pos = 0;                                                     \
      fprintf (stream, "\n");                                          \
      if (indent)                                                      \
      {                                                                \
        for (size_t t = 0 ; t < indent - 1 ; t++)                      \
          cur_pos += fprintf (stream, " ");                            \
        cur_pos += fprintf (stream, "L");                              \
      }                                                                \
    }                                                                  \
    else if (indent > cur_pos)                                         \
      for (size_t t = 0 ; t < indent - cur_pos ; t++)                  \
        cur_pos += fprintf (stream, " ");                              \
    if (state == state->machine->state_0)                              \
      cur_pos += fprintf (stream, "(%03zu)", id_state);                \
    cur_pos += fprintf (stream, "---");                                \
    if (printer)                                                       \
      cur_pos += printer (stream, state->goto_array[i].letter);        \
    cur_pos += fprintf (stream, "-->");                                \
    /* cur_pos += fprintf (stream, "%03zu", ++nb_states); */           \
    cur_pos += fprintf (stream, "(%03zu)", state->goto_array[i].state->id);\
    if (state->goto_array[i].state->is_matching)                       \
      cur_pos += fprintf (stream, "[%zu]", state->goto_array[i].state->rank);\
    if (state->goto_array[i].state->fail_state &&                      \
        state->goto_array[i].state->fail_state != state->machine->state_0)\
      cur_pos += fprintf (stream, "(-->%03zu)", state->goto_array[i].state->fail_state->id);\
    state_print_##ACM_SYMBOL (state->goto_array[i].state, stream,      \
      cur_pos, nb_states, printer);                                    \
  }                                                                    \
}                                                                      \
                                                                       \
void                                                                   \
ACM_print_##ACM_SYMBOL (ACMachine_##ACM_SYMBOL *machine,               \
                        FILE* stream,                                  \
                        PRINT_##ACM_SYMBOL##_TYPE printer)             \
{                                                                      \
  if (machine->reconstruct)                                            \
  {                                                                    \
    pthread_mutex_lock (&machine->lock);                               \
    if (machine->reconstruct)                                          \
      state_fail_state_construct_##ACM_SYMBOL (machine);               \
    pthread_mutex_unlock (&machine->lock);                             \
  }                                                                    \
  fprintf (stream, "\n");                                              \
  state_print_##ACM_SYMBOL (machine->state_0, stream, 0, 0, printer);  \
  fprintf (stream, "\n");                                              \
}                                                                      \
\
static const struct _acm_vtable_##ACM_SYMBOL ACM_VTABLE_##ACM_SYMBOL = \
{                                                                      \
  ACM_register_keyword_##ACM_SYMBOL,                                   \
  ACM_is_registered_keyword_##ACM_SYMBOL,                              \
  ACM_unregister_keyword_##ACM_SYMBOL,                                 \
  ACM_nb_keywords_##ACM_SYMBOL,                                        \
  ACM_foreach_keyword_##ACM_SYMBOL,                                    \
  ACM_release_##ACM_SYMBOL,                                            \
  ACM_reset_##ACM_SYMBOL,                                              \
  ACM_print_##ACM_SYMBOL,                                              \
};                                                                     \
                                                                       \
static void                                                            \
machine_init_##ACM_SYMBOL (ACMachine_##ACM_SYMBOL *machine,            \
                             ACState_##ACM_SYMBOL * state_0,           \
                             EQ_##ACM_SYMBOL##_TYPE eq,                \
                             COPY_##ACM_SYMBOL##_TYPE copier,          \
                             DESTROY_##ACM_SYMBOL##_TYPE dtor)         \
{                                                                      \
  machine->reconstruct = 1; /* f(s) is undefined and has not been computed yet */\
  machine->size = 1;                                                   \
  machine->state_0 = state_0;                                          \
  state_0->machine = machine;                                          \
  machine->rank = machine->nb_sequence = machine->state_counter = 0;   \
  pthread_mutex_init (&machine->lock, 0);                              \
  machine->vtable = &(ACM_VTABLE_##ACM_SYMBOL);                        \
  machine->copy = copier ? copier : __COPY_##ACM_SYMBOL;               \
  machine->destroy = dtor ? dtor : __DTOR_##ACM_SYMBOL;                \
  machine->eq = eq ? eq : __EQ_##ACM_SYMBOL;                           \
}                                                                      \
struct __useless_struct_to_allow_trailing_semicolon__##T##__
// END DEFINE_ACM

#endif
