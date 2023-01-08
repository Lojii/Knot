/*-
 */

#include "opts.h"
#include "filter.h"

#include "sys.h"
#include "log.h"
#include "util.h"

ACM_DEFINE (char);

#define free_list(list, type) do { \
	while (list) { \
		type *next = (list)->next; \
		free(list); \
		list = next; \
	} \
} while (0)

#define append_list(list, value, type) do { \
	type *l = *list; \
	while (l) { \
		if (!l->next) \
			break; \
		l = l->next; \
	} \
	if (l) \
		l->next = value; \
	else \
		*list = value; \
} while (0)

#define match_acm(acm, haystack, value) do { \
	const ACState(char) *state = ACM_reset(acm); \
	for (char *c = haystack; *c; c++) { \
		if (ACM_match(state, *c)) { \
			ACM_get_match(state, 0, 0, (void **)&value); \
			break; \
		} \
	} \
} while (0)

//#ifndef WITHOUT_USERAUTH
//void
//filter_userlist_free(userlist_t *ul)
//{
//	while (ul) {
//		userlist_t *next = ul->next;
//		free(ul->user);
//		free(ul);
//		ul = next;
//	}
//}
//
//int
//filter_userlist_copy(userlist_t *userlist, const char *argv0, userlist_t **ul)
//{
//	while (userlist) {
//		userlist_t *du = malloc(sizeof(userlist_t));
//		if (!du)
//			return oom_return(argv0);
//		memset(du, 0, sizeof(userlist_t));
//
//		du->user = strdup(userlist->user);
//		if (!du->user)
//			return oom_return(argv0);
//
//		append_list(ul, du, userlist_t);
//
//		userlist = userlist->next;
//	}
//	return 0;
//}
//
//char *
//filter_userlist_str(userlist_t *u)
//{
//	char *us = NULL;
//
//	if (!u) {
//		us = strdup("");
//		if (!us)
//			return oom_return_na_null();
//		goto out;
//	}
//
//	while (u) {
//		char *nus;
//		if (asprintf(&nus, "%s%s%s", STRORNONE(us), us ? "," : "", u->user) < 0) {
//			goto err;
//		}
//
//		if (us)
//			free(us);
//		us = nus;
//		u = u->next;
//	}
//	goto out;
//err:
//	if (us) {
//		free(us);
//		us = NULL;
//	}
//out:
//	return us;
//}
//
//// Limit the number of users to max 50
//#define MAX_USERS 50
//
//int
//filter_userlist_set(char *value, unsigned int line_num, userlist_t **list, const char *listname)
//{
//	// Delimiter can be either or all of ",", " ", and "\t"
//	// Using space as a delimiter disables spaces in user names too
//	// user1[,user2[,user3]]
//	char *argv[sizeof(char *) * MAX_USERS];
//	int argc = 0;
//	char *p, *last = NULL;
//
//	// strtok_r() removes all delimiters around user names, and does not return empty tokens
//	for ((p = strtok_r(value, ", \t", &last));
//		 p;
//		 (p = strtok_r(NULL, ", \t", &last))) {
//		if (argc < MAX_USERS) {
//			argv[argc++] = p;
//		} else {
//			fprintf(stderr, "Too many arguments in user list, max users allowed %d, on line %d\n", MAX_USERS, line_num);
//			return -1;
//		}
//	}
//
//	if (!argc) {
//		fprintf(stderr, "%s requires at least one parameter on line %d\n", listname, line_num);
//		return -1;
//	}
//
//	// Override the copied global list, if any
//	if (*list) {
//		filter_userlist_free(*list);
//		*list = NULL;
//	}
//
//	while (argc--) {
//		userlist_t *ul = malloc(sizeof(userlist_t));
//		if (!ul)
//			return oom_return_na();
//		memset(ul, 0, sizeof(userlist_t));
//
//		ul->user = strdup(argv[argc]);
//		if (!ul->user)
//			return oom_return_na();
//
//		append_list(list, ul, userlist_t);
//	}
//	return 0;
//}
//#endif /* !WITHOUT_USERAUTH */

static void
filter_value_free(value_t *value)
{
	while (value) {
		value_t *next = value->next;
		free(value->value);
		free(value);
		value = next;
	}
}

void
filter_macro_free(opts_t *opts)
{
	macro_t *macro = opts->macro;
	while (macro) {
		macro_t *next = macro->next;
		free(macro->name);
		filter_value_free(macro->value);
		free(macro);
		macro = next;
	}
	opts->macro = NULL;
}

static void
filter_rule_free(filter_rule_t *rule)
{
	if (rule->dstip)
		free(rule->dstip);
	if (rule->sni)
		free(rule->sni);
	if (rule->cn)
		free(rule->cn);
	if (rule->host)
		free(rule->host);
	if (rule->uri)
		free(rule->uri);
	if (rule->port)
		free(rule->port);
	if (rule->ip)
		free(rule->ip);
//#ifndef WITHOUT_USERAUTH
//	if (rule->user)
//		free(rule->user);
//	if (rule->desc)
//		free(rule->desc);
//#endif /* !WITHOUT_USERAUTH */
	if (rule->action.conn_opts)
		conn_opts_free(rule->action.conn_opts);
	free(rule);
}

void
filter_rules_free(opts_t *opts)
{
	filter_rule_t *rule = opts->filter_rules;
	while (rule) {
		filter_rule_t *next = rule->next;
		filter_rule_free(rule);
		rule = next;
	}
	opts->filter_rules = NULL;
}

#define free_port(p) do { \
	if ((*p)->action.conn_opts) \
		conn_opts_free((*p)->action.conn_opts); \
	free((*p)->port); \
	free(*p); \
} while (0)

static void
free_port_func(void *p)
{
	free_port((filter_port_t **)&p);
}

static void
filter_port_btree_free(kbtree_t(port) *btree)
{
	if (btree) {
		__kb_traverse(filter_port_p_t, btree, free_port);
		__kb_destroy(btree);
	}
}

#define free_site(p) do { \
	if ((*p)->action.conn_opts) \
		conn_opts_free((*p)->action.conn_opts); \
	free((*p)->site); \
	filter_port_btree_free((*p)->port_btree); \
	if ((*p)->port_acm) \
		ACM_release((*p)->port_acm); \
	if ((*p)->port_all) \
		free_port_func((*p)->port_all); \
	free(*p); \
} while (0)

static void
free_site_func(void *s)
{
	free_site((filter_site_t **)&s);
}

static void
filter_list_free(filter_list_t *list)
{
	if (list->ip_btree) {
		__kb_traverse(filter_site_p_t, list->ip_btree, free_site);
		__kb_destroy(list->ip_btree);
	}
	if (list->ip_acm)
		ACM_release(list->ip_acm);
	if (list->ip_all)
		free_site_func(list->ip_all);

	if (list->sni_btree) {
		__kb_traverse(filter_site_p_t, list->sni_btree, free_site);
		__kb_destroy(list->sni_btree);
	}
	if (list->sni_acm)
		ACM_release(list->sni_acm);
	if (list->sni_all)
		free_site_func(list->sni_all);

	if (list->cn_btree) {
		__kb_traverse(filter_site_p_t, list->cn_btree, free_site);
		__kb_destroy(list->cn_btree);
	}
	if (list->cn_acm)
		ACM_release(list->cn_acm);
	if (list->cn_all)
		free_site_func(list->cn_all);

	if (list->host_btree) {
		__kb_traverse(filter_site_p_t, list->host_btree, free_site);
		__kb_destroy(list->host_btree);
	}
	if (list->host_acm)
		ACM_release(list->host_acm);
	if (list->host_all)
		free_site_func(list->host_all);

	if (list->uri_btree) {
		__kb_traverse(filter_site_p_t, list->uri_btree, free_site);
		__kb_destroy(list->uri_btree);
	}
	if (list->uri_acm)
		ACM_release(list->uri_acm);
	if (list->uri_all)
		free_site_func(list->uri_all);

	free(list);
}

//#ifndef WITHOUT_USERAUTH
//#define free_desc(p) do { \
//	free((*p)->desc); \
//	filter_list_free((*p)->list); \
//	free(*p); \
//} while (0)
//
//static void
//filter_user_free(filter_user_t *user)
//{
//	free(user->user);
//	filter_list_free(user->list);
//
//	if (user->desc_btree) {
//		__kb_traverse(filter_desc_p_t, user->desc_btree, free_desc);
//		__kb_destroy(user->desc_btree);
//	}
//
//	if (user->desc_acm)
//		ACM_release(user->desc_acm);
//}
//
//#define free_user(p) do { \
//	filter_user_free(*p); \
//	free(*p); \
//} while (0)
//#endif /* !WITHOUT_USERAUTH */

#define free_ip(p) do { \
	free((*p)->ip); \
	filter_list_free((*p)->list); \
	free(*p); \
} while (0)

void
filter_free(opts_t *opts)
{
	if (!opts->filter)
		return;

	filter_t *pf = opts->filter;
//#ifndef WITHOUT_USERAUTH
//	if (pf->user_btree) {
//		__kb_traverse(filter_user_p_t, pf->user_btree, free_user);
//		__kb_destroy(pf->user_btree);
//	}
//
//	if (pf->user_acm)
//		ACM_release(pf->user_acm);
//
//	if (pf->desc_btree) {
//		__kb_traverse(filter_desc_p_t, pf->desc_btree, free_desc);
//		__kb_destroy(pf->desc_btree);
//	}
//
//	if (pf->desc_acm)
//		ACM_release(pf->desc_acm);
//
//	filter_list_free(pf->all_user);
//#endif /* !WITHOUT_USERAUTH */

	if (pf->ip_btree) {
		__kb_traverse(filter_ip_p_t, pf->ip_btree, free_ip);
		__kb_destroy(pf->ip_btree);
	}

	if (pf->ip_acm)
		ACM_release(pf->ip_acm);

	filter_list_free(pf->all);

	free(opts->filter);
	opts->filter = NULL;
}

int
filter_macro_copy(macro_t *macro, const char *argv0, opts_t *opts)
{
	while (macro) {
		macro_t *m = malloc(sizeof(macro_t));
		if (!m)
			return oom_return(argv0);
		memset(m, 0, sizeof(macro_t));

		m->name = strdup(macro->name);
		if (!m->name)
			return oom_return(argv0);

		value_t *value = macro->value;
		while (value) {
			value_t *v = malloc(sizeof(value_t));
			if (!v)
				return oom_return(argv0);
			memset(v, 0, sizeof(value_t));

			v->value = strdup(value->value);
			if (!v->value)
				return oom_return(argv0);

			append_list(&m->value, v, value_t);
			value = value->next;
		}

		append_list(&opts->macro, m, macro_t);
		macro = macro->next;
	}
	return 0;
}

int
filter_rule_copy(filter_rule_t *rule, const char *argv0, opts_t *opts, tmp_opts_t *tmp_opts)
{
	while (rule) {
		filter_rule_t *r = malloc(sizeof(filter_rule_t));
		if (!r)
			return oom_return(argv0);
		memset(r, 0, sizeof(filter_rule_t));

		r->all_conns = rule->all_conns;

//#ifndef WITHOUT_USERAUTH
//		r->all_users = rule->all_users;
//
//		if (rule->user) {
//			r->user = strdup(rule->user);
//			if (!r->user)
//				return oom_return(argv0);
//		}
//		r->exact_user = rule->exact_user;
//
//		if (rule->desc) {
//			r->desc = strdup(rule->desc);
//			if (!r->desc)
//				return oom_return(argv0);
//		}
//		r->exact_desc = rule->exact_desc;
//#endif /* !WITHOUT_USERAUTH */

		if (rule->ip) {
			r->ip = strdup(rule->ip);
			if (!r->ip)
				return oom_return(argv0);
		}
		r->exact_ip = rule->exact_ip;

		if (rule->dstip) {
			r->dstip = strdup(rule->dstip);
			if (!r->dstip)
				return oom_return(argv0);
		}
		if (rule->sni) {
			r->sni = strdup(rule->sni);
			if (!r->sni)
				return oom_return(argv0);
		}
		if (rule->cn) {
			r->cn = strdup(rule->cn);
			if (!r->cn)
				return oom_return(argv0);
		}
		if (rule->host) {
			r->host = strdup(rule->host);
			if (!r->host)
				return oom_return(argv0);
		}
		if (rule->uri) {
			r->uri = strdup(rule->uri);
			if (!r->uri)
				return oom_return(argv0);
		}

		r->exact_dstip = rule->exact_dstip;
		r->exact_sni = rule->exact_sni;
		r->exact_cn = rule->exact_cn;
		r->exact_host = rule->exact_host;
		r->exact_uri = rule->exact_uri;

		r->all_dstips = rule->all_dstips;
		r->all_snis = rule->all_snis;
		r->all_cns = rule->all_cns;
		r->all_hosts = rule->all_hosts;
		r->all_uris = rule->all_uris;

		if (rule->port) {
			r->port = strdup(rule->port);
			if (!r->port)
				return oom_return(argv0);
		}
		r->all_ports = rule->all_ports;
		r->exact_port = rule->exact_port;

		// The action field is not a pointer, hence the direct assignment (copy)
		r->action = rule->action;

		// But deep copy for conn_opts
		if (rule->action.conn_opts) {
			r->action.conn_opts = conn_opts_copy(rule->action.conn_opts, argv0, tmp_opts);
			if (!r->action.conn_opts)
				return oom_return(argv0);
		}

		append_list(&opts->filter_rules, r, filter_rule_t);

		rule = rule->next;
	}
	return 0;
}

static char *
filter_value_str(value_t *value)
{
	char *s = NULL;

	while (value) {
		char *p;
		if (asprintf(&p, "%s%s%s", STRORNONE(s), s ? ", " : "", value->value) < 0) {
			goto err;
		}
		if (s)
			free(s);
		s = p;
		value = value->next;
	}
	goto out;
err:
	if (s) {
		free(s);
		s = NULL;
	}
out:
	return s;
}

char *
filter_macro_str(macro_t *macro)
{
	char *s = NULL;

	if (!macro) {
		s = strdup("");
		if (!s)
			return oom_return_na_null();
		goto out;
	}

	while (macro) {
		char *v = filter_value_str(macro->value);

		char *p;
		if (asprintf(&p, "%s%smacro %s = %s", STRORNONE(s), NLORNONE(s), macro->name, STRORNONE(v)) < 0) {
			if (v)
				free(v);
			goto err;
		}
		if (v)
			free(v);
		if (s)
			free(s);
		s = p;
		macro = macro->next;
	}
	goto out;
err:
	if (s) {
		free(s);
		s = NULL;
	}
out:
	return s;
}

static char *
filter_rule_site_str(filter_rule_t *rule, char *site, unsigned int exact_site, unsigned int all_sites, char *apply_to, int rule_num)
{
	char *s = NULL;

	char *copts_str = conn_opts_str(rule->action.conn_opts);
	if (!copts_str)
		return oom_return_na_null();

	char *rule_num_str = NULL;
	if (rule_num >= 0) {
		if (asprintf(&rule_num_str, " %d", rule_num) < 0)
			goto err;
	} else {
		rule_num_str = strdup("");
		if (!rule_num_str)
			goto err;
	}

	if (asprintf(&s, "filter rule%s: %s=%s, dstport=%s, srcip=%s"
//#ifndef WITHOUT_USERAUTH
//		", user=%s, desc=%s"
//#endif /* !WITHOUT_USERAUTH */
		", exact=%s|%s|%s"
//#ifndef WITHOUT_USERAUTH
//		"|%s|%s"
//#endif /* !WITHOUT_USERAUTH */
		", all=%s|"
//#ifndef WITHOUT_USERAUTH
//		"%s|"
//#endif /* !WITHOUT_USERAUTH */
		"%s|%s, action=%s|%s|%s|%s|%s, log=%s|%s|%s|%s|%s"
		", precedence=%d"
#ifdef DEBUG_PROXY
		", line=%d"
#endif /* DEBUG_PROXY */
		"%s%s\n",
		rule_num_str, apply_to, site, STRORNONE(rule->port), STRORNONE(rule->ip),
//#ifndef WITHOUT_USERAUTH
//		STRORNONE(rule->user), STRORNONE(rule->desc),
//#endif /* !WITHOUT_USERAUTH */
		exact_site ? "site" : "", rule->exact_port ? "port" : "", rule->exact_ip ? "ip" : "",
//#ifndef WITHOUT_USERAUTH
//		rule->exact_user ? "user" : "", rule->exact_desc ? "desc" : "",
//#endif /* !WITHOUT_USERAUTH */
		rule->all_conns ? "conns" : "",
//#ifndef WITHOUT_USERAUTH
//		rule->all_users ? "users" : "",
//#endif /* !WITHOUT_USERAUTH */
		all_sites ? "sites" : "", rule->all_ports ? "ports" : "",
		rule->action.divert ? "divert" : "", rule->action.split ? "split" : "", rule->action.pass ? "pass" : "", rule->action.block ? "block" : "", rule->action.match ? "match" : "",
		rule->action.log_connect ? (rule->action.log_connect == 1 ? "!connect" : "connect") : "", rule->action.log_master ? (rule->action.log_master == 1 ? "!master" : "master") : "",
		rule->action.log_cert ? (rule->action.log_cert == 1 ? "!cert" : "cert") : "", rule->action.log_content ? (rule->action.log_content == 1 ? "!content" : "content") : "",
		rule->action.log_pcap ? (rule->action.log_pcap == 1 ? "!pcap" : "pcap") : "",
		rule->action.precedence,
#ifdef DEBUG_PROXY
		rule->action.line_num,
#endif /* DEBUG_PROXY */
		strlen(copts_str) ? "\n  " : "", copts_str) < 0) {
		s = NULL;
	}
err:
	if (rule_num_str)
		free(rule_num_str);
	free(copts_str);
	return s;
}

static char *
filter_rule_site_all_str(filter_rule_t *rule, int rule_num)
{
	char *s = NULL;

	char *dstip = NULL;
	char *sni = NULL;
	char *cn = NULL;
	char *host = NULL;
	char *uri = NULL;

	if (rule->dstip) {
		dstip = filter_rule_site_str(rule, rule->dstip, rule->exact_dstip, rule->all_dstips, "dstip", rule_num);
		if (!dstip)
			goto err;
	}
	if (rule->sni) {
		sni = filter_rule_site_str(rule, rule->sni, rule->exact_sni, rule->all_snis, "sni", rule_num);
		if (!sni)
			goto err;
	}
	if (rule->cn) {
		cn = filter_rule_site_str(rule, rule->cn, rule->exact_cn, rule->all_cns, "cn", rule_num);
		if (!cn)
			goto err;
	}
	if (rule->host) {
		host = filter_rule_site_str(rule, rule->host, rule->exact_host, rule->all_hosts, "host", rule_num);
		if (!host)
			goto err;
	}
	if (rule->uri) {
		uri = filter_rule_site_str(rule, rule->uri, rule->exact_uri, rule->all_uris, "uri", rule_num);
		if (!uri)
			goto err;
	}

	if (asprintf(&s, "%s%s%s%s%s", STRORNONE(dstip), STRORNONE(sni), STRORNONE(cn), STRORNONE(host), STRORNONE(uri)) < 0) {
		s = NULL;
	}
err:
	if (dstip)
		free(dstip);
	if (sni)
		free(sni);
	if (cn)
		free(cn);
	if (host)
		free(host);
	if (uri)
		free(uri);
	return s;
}

char *
filter_rule_str(filter_rule_t *rule)
{
	char *frs = NULL;

	if (!rule) {
		frs = strdup("");
		if (!frs)
			return oom_return_na_null();
		goto out;
	}

	int count = 0;
	while (rule) {
		char *p = filter_rule_site_all_str(rule, count);
		if (!p)
			goto err;

		char *nfrs;
		if (asprintf(&nfrs, "%s%s", STRORNONE(frs), p) < 0) {
			free(p);
			goto err;
		}
		free(p);
		if (frs)
			free(frs);
		frs = nfrs;
		rule = rule->next;
		count++;
	}
	goto out;
err:
	if (frs) {
		free(frs);
		frs = NULL;
	}
out:
	return frs;
}

static char *
filter_port_str(filter_port_list_t *port_list)
{
	char *s = NULL;

	int count = 0;
	while (port_list) {
		char *copts_str = conn_opts_str(port_list->port->action.conn_opts);
		if (!copts_str)
			goto err;

		char *p;
		if (asprintf(&p, "%s\n          %d: %s (%s%s, action=%s|%s|%s|%s|%s, log=%s|%s|%s|%s|%s"
				", precedence=%d"
#ifdef DEBUG_PROXY
				", line=%d"
#endif /* DEBUG_PROXY */
				"%s%s)", STRORNONE(s), count,
				port_list->port->port, port_list->port->all_ports ? "all_ports, " : "", port_list->port->exact ? "exact" : "substring",
				port_list->port->action.divert ? "divert" : "", port_list->port->action.split ? "split" : "", port_list->port->action.pass ? "pass" : "", port_list->port->action.block ? "block" : "", port_list->port->action.match ? "match" : "",
				port_list->port->action.log_connect ? (port_list->port->action.log_connect == 1 ? "!connect" : "connect") : "", port_list->port->action.log_master ? (port_list->port->action.log_master == 1 ? "!master" : "master") : "",
				port_list->port->action.log_cert ? (port_list->port->action.log_cert == 1 ? "!cert" : "cert") : "", port_list->port->action.log_content ? (port_list->port->action.log_content == 1 ? "!content" : "content") : "",
				port_list->port->action.log_pcap ? (port_list->port->action.log_pcap == 1 ? "!pcap" : "pcap") : "",
				port_list->port->action.precedence,
#ifdef DEBUG_PROXY
				port_list->port->action.line_num,
#endif /* DEBUG_PROXY */
				strlen(copts_str) ? "\n            " : "", copts_str) < 0) {
			if (copts_str)
				free(copts_str);
			goto err;
		}
		if (copts_str)
			free(copts_str);
		if (s)
			free(s);
		s = p;
		port_list = port_list->next;
		count++;
	}
	goto out;
err:
	if (s) {
		free(s);
		s = NULL;
	}
out:
	return s;
}

#define build_port_list(p) do { \
	filter_port_list_t *s = malloc(sizeof(filter_port_list_t)); \
	memset(s, 0, sizeof(filter_port_list_t)); \
	s->port = *p; \
	append_list(&port, s, filter_port_list_t); \
} while (0)

static filter_port_list_t *port_list_acm = NULL;

static void
build_port_list_acm(UNUSED MatchHolder(char) match, void *v)
{
	filter_port_t *port = v;

	filter_port_list_t *p = malloc(sizeof(filter_port_list_t));
	memset(p, 0, sizeof(filter_port_list_t));
	p->port = port;

	append_list(&port_list_acm, p, filter_port_list_t);
}

static char *
filter_sites_str(filter_site_list_t *site_list)
{
	char *s = NULL;

	int count = 0;
	while (site_list) {
		filter_port_list_t *port = NULL;

		if (site_list->site->port_btree)
			__kb_traverse(filter_port_p_t, site_list->site->port_btree, build_port_list);

		char *ports_exact = filter_port_str(port);
		free_list(port, filter_port_list_t);

		if (site_list->site->port_acm)
			ACM_foreach_keyword(site_list->site->port_acm, build_port_list_acm);

		char *ports_substring = filter_port_str(port_list_acm);
		free_list(port_list_acm, filter_port_list_t);
		port_list_acm = NULL;

		if (site_list->site->port_all)
			build_port_list_acm((MatchHolder(char)){0}, site_list->site->port_all);

		char *ports_all = filter_port_str(port_list_acm);
		free_list(port_list_acm, filter_port_list_t);
		port_list_acm = NULL;

		char *copts_str = conn_opts_str(site_list->site->action.conn_opts);
		if (!copts_str)
			goto err;

		char *p;
		if (asprintf(&p, "%s\n      %d: %s (%s%s, action=%s|%s|%s|%s|%s, log=%s|%s|%s|%s|%s"
				", precedence=%d"
#ifdef DEBUG_PROXY
				", line=%d"
#endif /* DEBUG_PROXY */
				"%s%s)%s%s%s%s%s%s",
				STRORNONE(s), count,
				site_list->site->site, site_list->site->all_sites ? "all_sites, " : "", site_list->site->exact ? "exact" : "substring",
				site_list->site->action.divert ? "divert" : "", site_list->site->action.split ? "split" : "", site_list->site->action.pass ? "pass" : "", site_list->site->action.block ? "block" : "", site_list->site->action.match ? "match" : "",
				site_list->site->action.log_connect ? (site_list->site->action.log_connect == 1 ? "!connect" : "connect") : "", site_list->site->action.log_master ? (site_list->site->action.log_master == 1 ? "!master" : "master") : "",
				site_list->site->action.log_cert ? (site_list->site->action.log_cert == 1 ? "!cert" : "cert") : "", site_list->site->action.log_content ? (site_list->site->action.log_content == 1 ? "!content" : "content") : "",
				site_list->site->action.log_pcap ? (site_list->site->action.log_pcap == 1 ? "!pcap" : "pcap") : "",
				site_list->site->action.precedence,
#ifdef DEBUG_PROXY
				site_list->site->action.line_num,
#endif /* DEBUG_PROXY */
				strlen(copts_str) ? "\n        " : "", copts_str,
				ports_exact ? "\n        port exact:" : "", STRORNONE(ports_exact),
				ports_substring ? "\n        port substring:" : "", STRORNONE(ports_substring),
				ports_all ? "\n        port all:" : "", STRORNONE(ports_all)) < 0) {
			if (ports_exact)
				free(ports_exact);
			if (ports_substring)
				free(ports_substring);
			if (ports_all)
				free(ports_all);
			if (copts_str)
				free(copts_str);
			goto err;
		}
		if (ports_exact)
			free(ports_exact);
		if (ports_substring)
			free(ports_substring);
		if (ports_all)
			free(ports_all);
		if (copts_str)
			free(copts_str);
		if (s)
			free(s);
		s = p;
		site_list = site_list->next;
		count++;
	}
	goto out;
err:
	if (s) {
		free(s);
		s = NULL;
	}
out:
	return s;
}

static char *
filter_list_sub_str(filter_site_list_t *list, char *old_s, const char *name)
{
	char *new_s = NULL;
	char *s = filter_sites_str(list);
	if (asprintf(&new_s, "%s%s    %s:%s", STRORNONE(old_s), NLORNONE(old_s), name, STRORNONE(s)) < 0) {
		// @todo Handle oom, and don't just use STRORNONE()
		new_s = NULL;
	}
	if (s)
		free(s);
	if (old_s)
		free(old_s);
	return new_s;
}

static filter_site_list_t *site_list_acm = NULL;

static void
build_site_list_acm(UNUSED MatchHolder(char) match, void *v)
{
	filter_site_t *site = v;

	filter_site_list_t *s = malloc(sizeof(filter_site_list_t));
	memset(s, 0, sizeof(filter_site_list_t));
	s->site = site;

	append_list(&site_list_acm, s, filter_site_list_t);
}

static void
filter_tmp_site_list_free(filter_site_list_t **list)
{
	free_list(*list, filter_site_list_t);
	*list = NULL;
}

static char *
filter_list_str(filter_list_t *list)
{
	char *s = NULL;
	filter_site_list_t *site = NULL;

#define build_site_list(p) do { \
	filter_site_list_t *s = malloc(sizeof(filter_site_list_t)); \
	memset(s, 0, sizeof(filter_site_list_t)); \
	s->site = *p; \
	append_list(&site, s, filter_site_list_t); \
} while (0)

	if (list->ip_btree) {
		__kb_traverse(filter_site_p_t, list->ip_btree, build_site_list);
		s = filter_list_sub_str(site, s, "ip exact");
		filter_tmp_site_list_free(&site);
	}
	if (list->ip_acm) {
		ACM_foreach_keyword(list->ip_acm, build_site_list_acm);
		s = filter_list_sub_str(site_list_acm, s, "ip substring");
		filter_tmp_site_list_free(&site_list_acm);
	}
	if (list->ip_all) {
		build_site_list_acm((MatchHolder(char)){0}, list->ip_all);
		s = filter_list_sub_str(site_list_acm, s, "ip all");
		filter_tmp_site_list_free(&site_list_acm);
	}

	if (list->sni_btree) {
		__kb_traverse(filter_site_p_t, list->sni_btree, build_site_list);
		s = filter_list_sub_str(site, s, "sni exact");
		filter_tmp_site_list_free(&site);
	}
	if (list->sni_acm) {
		ACM_foreach_keyword(list->sni_acm, build_site_list_acm);
		s = filter_list_sub_str(site_list_acm, s, "sni substring");
		filter_tmp_site_list_free(&site_list_acm);
	}
	if (list->sni_all) {
		build_site_list_acm((MatchHolder(char)){0}, list->sni_all);
		s = filter_list_sub_str(site_list_acm, s, "sni all");
		filter_tmp_site_list_free(&site_list_acm);
	}

	if (list->cn_btree) {
		__kb_traverse(filter_site_p_t, list->cn_btree, build_site_list);
		s = filter_list_sub_str(site, s, "cn exact");
		filter_tmp_site_list_free(&site);
	}
	if (list->cn_acm) {
		ACM_foreach_keyword(list->cn_acm, build_site_list_acm);
		s = filter_list_sub_str(site_list_acm, s, "cn substring");
		filter_tmp_site_list_free(&site_list_acm);
	}
	if (list->cn_all) {
		build_site_list_acm((MatchHolder(char)){0}, list->cn_all);
		s = filter_list_sub_str(site_list_acm, s, "cn all");
		filter_tmp_site_list_free(&site_list_acm);
	}

	if (list->host_btree) {
		__kb_traverse(filter_site_p_t, list->host_btree, build_site_list);
		s = filter_list_sub_str(site, s, "host exact");
		filter_tmp_site_list_free(&site);
	}
	if (list->host_acm) {
		ACM_foreach_keyword(list->host_acm, build_site_list_acm);
		s = filter_list_sub_str(site_list_acm, s, "host substring");
		filter_tmp_site_list_free(&site_list_acm);
	}
	if (list->host_all) {
		build_site_list_acm((MatchHolder(char)){0}, list->host_all);
		s = filter_list_sub_str(site_list_acm, s, "host all");
		filter_tmp_site_list_free(&site_list_acm);
	}

	if (list->uri_btree) {
		__kb_traverse(filter_site_p_t, list->uri_btree, build_site_list);
		s = filter_list_sub_str(site, s, "uri exact");
		filter_tmp_site_list_free(&site);
	}
	if (list->uri_acm) {
		ACM_foreach_keyword(list->uri_acm, build_site_list_acm);
		s = filter_list_sub_str(site_list_acm, s, "uri substring");
		filter_tmp_site_list_free(&site_list_acm);
	}
	if (list->uri_all) {
		build_site_list_acm((MatchHolder(char)){0}, list->uri_all);
		s = filter_list_sub_str(site_list_acm, s, "uri all");
		filter_tmp_site_list_free(&site_list_acm);
	}
	return s;
}

static char *
filter_ip_list_str(filter_ip_list_t *ip_list)
{
	char *s = NULL;

	int count = 0;
	while (ip_list) {
		char *list = filter_list_str(ip_list->ip->list);

		char *p;
		if (asprintf(&p, "%s%s  ip %d %s (%s)=\n%s", STRORNONE(s), NLORNONE(s),
				count, ip_list->ip->ip, ip_list->ip->exact ? "exact" : "substring", STRORNONE(list)) < 0) {
			if (list)
				free(list);
			goto err;
		}
		if (list)
			free(list);
		if (s)
			free(s);
		s = p;
		ip_list = ip_list->next;
		count++;
	}
	goto out;
err:
	if (s) {
		free(s);
		s = NULL;
	}
out:
	return s;
}

static char *
filter_ip_btree_str(kbtree_t(ip) *btree)
{
	if (!btree)
		return NULL;

#define build_ip_list(p) do { \
	filter_ip_list_t *i = malloc(sizeof(filter_ip_list_t)); \
	memset(i, 0, sizeof(filter_ip_list_t)); \
	i->ip = *p; \
	append_list(&ip, i, filter_ip_list_t); \
} while (0)
	
	filter_ip_list_t *ip = NULL;
	__kb_traverse(filter_ip_p_t, btree, build_ip_list);

	char *s = filter_ip_list_str(ip);
	
	free_list(ip, filter_ip_list_t);
	return s;
}

static filter_ip_list_t *ip_list_acm = NULL;

static void
build_ip_list_acm(UNUSED MatchHolder(char) match, void *v)
{
	filter_ip_t *ip = v;

	filter_ip_list_t *i = malloc(sizeof(filter_ip_list_t));
	memset(i, 0, sizeof(filter_ip_list_t));
	i->ip = ip;

	append_list(&ip_list_acm, i, filter_ip_list_t);
}

static char *
filter_ip_acm_str(ACMachine(char) *acm)
{
	if (!acm)
		return NULL;

	ACM_foreach_keyword(acm, build_ip_list_acm);

	char *s = filter_ip_list_str(ip_list_acm);

	free_list(ip_list_acm, filter_ip_list_t);
	ip_list_acm = NULL;
	return s;
}

//#ifndef WITHOUT_USERAUTH
//static char *
//filter_user_list_str(filter_user_list_t *user)
//{
//	char *s = NULL;
//
//	int count = 0;
//	while (user) {
//		// Make sure the user has a filter rule
//		// It is possible to have users without any filter rule,
//		// but the user exists because it has desc filters,
//		// so the current user should not have any desc
//		if (user->user->desc_btree || user->user->desc_acm)
//			goto skip;
//
//		char *list = filter_list_str(user->user->list);
//
//		char *p = NULL;
//
//		if (list) {
//			if (asprintf(&p, "%s%s  user %d %s (%s)=\n%s", STRORNONE(s), NLORNONE(s),
//					count, user->user->user, user->user->exact ? "exact" : "substring", list) < 0) {
//				free(list);
//				goto err;
//			}
//			free(list);
//		}
//		if (s)
//			free(s);
//		s = p;
//		count++;
//skip:
//		user = user->next;
//	}
//	goto out;
//err:
//	if (s) {
//		free(s);
//		s = NULL;
//	}
//out:
//	return s;
//}
//
//#define build_user_list(p) do { \
//	filter_user_list_t *u = malloc(sizeof(filter_user_list_t)); \
//	memset(u, 0, sizeof(filter_user_list_t)); \
//	u->user = *p; \
//	append_list(&user, u, filter_user_list_t); \
//} while (0)
//
//static char *
//filter_user_btree_str(kbtree_t(user) *btree)
//{
//	if (!btree)
//		return NULL;
//
//	filter_user_list_t *user = NULL;
//	__kb_traverse(filter_user_p_t, btree, build_user_list);
//
//	char *s = filter_user_list_str(user);
//
//	free_list(user, filter_user_list_t);
//	return s;
//}
//
//static filter_user_list_t *user_list_acm = NULL;
//
//static void
//build_user_list_acm(UNUSED MatchHolder(char) match, void *v)
//{
//	filter_user_t *user = v;
//
//	filter_user_list_t *u = malloc(sizeof(filter_user_list_t));
//	memset(u, 0, sizeof(filter_user_list_t));
//	u->user = user;
//
//	append_list(&user_list_acm, u, filter_user_list_t);
//}
//
//static char *
//filter_user_acm_str(ACMachine(char) *acm)
//{
//	if (!acm)
//		return NULL;
//
//	ACM_foreach_keyword(acm, build_user_list_acm);
//
//	char *s = filter_user_list_str(user_list_acm);
//
//	free_list(user_list_acm, filter_user_list_t);
//	user_list_acm = NULL;
//	return s;
//}
//
//static char *
//filter_desc_list_str(filter_desc_list_t *desc)
//{
//	char *s = NULL;
//
//	int count = 0;
//	while (desc) {
//		char *list = filter_list_str(desc->desc->list);
//
//		char *p;
//		if (asprintf(&p, "%s%s   desc %d %s (%s)=\n%s", STRORNONE(s), NLORNONE(s),
//				count, desc->desc->desc, desc->desc->exact ? "exact" : "substring", STRORNONE(list)) < 0) {
//			if (list)
//				free(list);
//			goto err;
//		}
//		if (list)
//			free(list);
//		if (s)
//			free(s);
//		s = p;
//		desc = desc->next;
//		count++;
//	}
//	goto out;
//err:
//	if (s) {
//		free(s);
//		s = NULL;
//	}
//out:
//	return s;
//}
//
//static char *
//filter_desc_btree_str(kbtree_t(desc) *btree)
//{
//	if (!btree)
//		return NULL;
//
//#define build_desc_list(p) do { \
//	filter_desc_list_t *d = malloc(sizeof(filter_desc_list_t)); \
//	memset(d, 0, sizeof(filter_desc_list_t)); \
//	d->desc = *p; \
//	append_list(&desc, d, filter_desc_list_t); \
//} while (0)
//
//	filter_desc_list_t *desc = NULL;
//	__kb_traverse(filter_desc_p_t, btree, build_desc_list);
//
//	char *s = filter_desc_list_str(desc);
//
//	free_list(desc, filter_desc_list_t);
//	return s;
//}
//
//static filter_desc_list_t *desc_list_acm = NULL;
//
//static void
//build_desc_list_acm(UNUSED MatchHolder(char) match, void *v)
//{
//	filter_desc_t *desc = v;
//
//	filter_desc_list_t *d = malloc(sizeof(filter_desc_list_t));
//	memset(d, 0, sizeof(filter_desc_list_t));
//	d->desc = desc;
//
//	append_list(&desc_list_acm, d, filter_desc_list_t);
//}
//
//static char *
//filter_desc_acm_str(ACMachine(char) *acm)
//{
//	if (!acm)
//		return NULL;
//
//	ACM_foreach_keyword(acm, build_desc_list_acm);
//
//	char *s = filter_desc_list_str(desc_list_acm);
//
//	free_list(desc_list_acm, filter_desc_list_t);
//	desc_list_acm = NULL;
//	return s;
//}
//
//static char *
//filter_userdesc_list_str(filter_user_list_t *user)
//{
//	char *s = NULL;
//
//	int count = 0;
//	while (user) {
//		// Make sure the current user has a desc
//		if (!user->user->desc_btree && !user->user->desc_acm)
//			goto skip;
//
//		char *list_exact = filter_desc_btree_str(user->user->desc_btree);
//		char *list_substr = filter_desc_acm_str(user->user->desc_acm);
//
//		char *p = NULL;
//		if (asprintf(&p, "%s%s user %d %s (%s)=%s%s%s%s", STRORNONE(s), NLORNONE(s),
//				count, user->user->user, user->user->exact ? "exact" : "substring",
//				list_exact ? "\n  desc exact:\n" : "", STRORNONE(list_exact),
//				list_substr ? "\n  desc substring:\n" : "", STRORNONE(list_substr)
//				) < 0) {
//			if (list_exact)
//				free(list_exact);
//			if (list_substr)
//				free(list_substr);
//			goto err;
//		}
//		if (list_exact)
//			free(list_exact);
//		if (list_substr)
//			free(list_substr);
//		if (s)
//			free(s);
//		s = p;
//		count++;
//skip:
//		user = user->next;
//	}
//	goto out;
//err:
//	if (s) {
//		free(s);
//		s = NULL;
//	}
//out:
//	return s;
//}
//
//static char *
//filter_userdesc_btree_str(kbtree_t(user) *btree)
//{
//	if (!btree)
//		return NULL;
//
//	filter_user_list_t *user = NULL;
//	__kb_traverse(filter_user_p_t, btree, build_user_list);
//
//	char *s = filter_userdesc_list_str(user);
//
//	free_list(user, filter_user_list_t);
//	return s;
//}
//
//static char *
//filter_userdesc_acm_str(ACMachine(char) *acm)
//{
//	if (!acm)
//		return NULL;
//
//	ACM_foreach_keyword(acm, build_user_list_acm);
//
//	char *s = filter_userdesc_list_str(user_list_acm);
//
//	free_list(user_list_acm, filter_user_list_t);
//	user_list_acm = NULL;
//	return s;
//}
//
//#endif /* !WITHOUT_USERAUTH */

char *
filter_str(filter_t *filter)
{
	char *fs = NULL;
//#ifndef WITHOUT_USERAUTH
//	char *userdesc_filter_exact = NULL;
//	char *userdesc_filter_substr = NULL;
//	char *user_filter_exact = NULL;
//	char *user_filter_substr = NULL;
//	char *desc_filter_exact = NULL;
//	char *desc_filter_substr = NULL;
//	char *user_filter_all = NULL;
//#endif /* !WITHOUT_USERAUTH */
	char *ip_filter_exact = NULL;
	char *ip_filter_substr = NULL;
	char *filter_all = NULL;

	if (!filter) {
		fs = strdup("");
		if (!fs)
			return oom_return_na_null();
		goto out;
	}

//#ifndef WITHOUT_USERAUTH
//	userdesc_filter_exact = filter_userdesc_btree_str(filter->user_btree);
//	userdesc_filter_substr = filter_userdesc_acm_str(filter->user_acm);
//	user_filter_exact = filter_user_btree_str(filter->user_btree);
//	user_filter_substr = filter_user_acm_str(filter->user_acm);
//	desc_filter_exact = filter_desc_btree_str(filter->desc_btree);
//	desc_filter_substr = filter_desc_acm_str(filter->desc_acm);
//	user_filter_all = filter_list_str(filter->all_user);
//#endif /* !WITHOUT_USERAUTH */
	ip_filter_exact = filter_ip_btree_str(filter->ip_btree);
	ip_filter_substr = filter_ip_acm_str(filter->ip_acm);
	filter_all = filter_list_str(filter->all);

	if (asprintf(&fs, "filter=>\n"
//#ifndef WITHOUT_USERAUTH
//			"userdesc_filter_exact->%s%s\n"
//			"userdesc_filter_substring->%s%s\n"
//			"user_filter_exact->%s%s\n"
//			"user_filter_substring->%s%s\n"
//			"desc_filter_exact->%s%s\n"
//			"desc_filter_substring->%s%s\n"
//			"user_filter_all->%s%s\n"
//#endif /* !WITHOUT_USERAUTH */
			"ip_filter_exact->%s%s\n"
			"ip_filter_substring->%s%s\n"
			"filter_all->%s%s\n",
//#ifndef WITHOUT_USERAUTH
//			NLORNONE(userdesc_filter_exact), STRORNONE(userdesc_filter_exact),
//			NLORNONE(userdesc_filter_substr), STRORNONE(userdesc_filter_substr),
//			NLORNONE(user_filter_exact), STRORNONE(user_filter_exact),
//			NLORNONE(user_filter_substr), STRORNONE(user_filter_substr),
//			NLORNONE(desc_filter_exact), STRORNONE(desc_filter_exact),
//			NLORNONE(desc_filter_substr), STRORNONE(desc_filter_substr),
//			NLORNONE(user_filter_all), STRORNONE(user_filter_all),
//#endif /* !WITHOUT_USERAUTH */
			NLORNONE(ip_filter_exact), STRORNONE(ip_filter_exact),
			NLORNONE(ip_filter_substr), STRORNONE(ip_filter_substr),
			NLORNONE(filter_all), STRORNONE(filter_all)) < 0) {
		// fs is undefined
		goto err;
	}
	goto out;
err:
	if (fs) {
		free(fs);
		fs = NULL;
	}
out:
//#ifndef WITHOUT_USERAUTH
//	if (userdesc_filter_exact)
//		free(userdesc_filter_exact);
//	if (userdesc_filter_substr)
//		free(userdesc_filter_substr);
//	if (user_filter_exact)
//		free(user_filter_exact);
//	if (user_filter_substr)
//		free(user_filter_substr);
//	if (desc_filter_exact)
//		free(desc_filter_exact);
//	if (desc_filter_substr)
//		free(desc_filter_substr);
//	if (user_filter_all)
//		free(user_filter_all);
//#endif /* !WITHOUT_USERAUTH */
	if (ip_filter_exact)
		free(ip_filter_exact);
	if (ip_filter_substr)
		free(ip_filter_substr);
	if (filter_all)
		free(filter_all);
	return fs;
}

#ifdef DEBUG_OPTS
static void
filter_rule_dbg_print(filter_rule_t *rule)
{
	char *s = filter_rule_site_all_str(rule, -1);
	if (!s)
		return;
	log_dbg_printf("%s", s);
	free(s);
}
#endif /* DEBUG_OPTS */

#define MAX_SITE_LEN 200

int
filter_passsite_set(opts_t *opts, UNUSED conn_opts_t *conn_opts, char *value, unsigned int line_num)
{
#define MAX_PASSSITE_TOKENS 3

	// site[*] [(clientaddr|user|*) [desc]]
	char *argv[sizeof(char *) * MAX_PASSSITE_TOKENS];
	int argc = 0;
	char *p, *last = NULL;

	for ((p = strtok_r(value, " ", &last));
		 p;
		 (p = strtok_r(NULL, " ", &last))) {
		if (argc < MAX_PASSSITE_TOKENS) {
			argv[argc++] = p;
		} else {
			fprintf(stderr, "Too many arguments in passsite option on line %d\n", line_num);
			return -1;
		}
	}

	if (!argc) {
		fprintf(stderr, "Filter rule requires at least one parameter on line %d\n", line_num);
		return -1;
	}

	filter_rule_t *rule = malloc(sizeof(filter_rule_t));
	if (!rule)
		return oom_return_na();
	memset(rule, 0, sizeof(filter_rule_t));

	// The for loop with strtok_r() above does not output empty strings
	// So, no need to check if the length of argv[0] > 0
	size_t len = strlen(argv[0]);

	if (len > MAX_SITE_LEN) {
		fprintf(stderr, "Filter site too long %zu > %d on line %d\n", len, MAX_SITE_LEN, line_num);
		return -1;
	}

	unsigned int exact_site = 0;
	unsigned int all_sites = 0;
	if (argv[0][len - 1] == '*') {
		exact_site = 0;
		len--;
		argv[0][len] = '\0';
		// site == "*" ?
		if (len == 0)
			all_sites = 1;
	} else {
		exact_site = 1;
	}

	rule->sni = strdup(argv[0]);
	if (!rule->sni)
		return oom_return_na();
	rule->exact_sni = exact_site;
	rule->all_snis = all_sites;

	rule->cn = strdup(argv[0]);
	if (!rule->cn)
		return oom_return_na();
	rule->exact_cn = exact_site;
	rule->all_cns = all_sites;

	// precedence can only go up not down
	rule->action.precedence = 0;

	if (argc == 1) {
		// Apply filter rule to all conns
		// Equivalent to "site *" without user auth
		rule->all_conns = 1;
	}

	if (argc > 1) {
		if (!strcmp(argv[1], "*")) {
//#ifndef WITHOUT_USERAUTH
//			// Apply filter rule to all users perhaps with desc
//			rule->action.precedence++;
//			rule->all_users = 1;
//		} else if (sys_isuser(argv[1])) {
//			if (!conn_opts->user_auth) {
//				fprintf(stderr, "User filter requires user auth on line %d\n", line_num);
//				return -1;
//			}
//			rule->action.precedence += 2;
//			rule->user = strdup(argv[1]);
//			if (!rule->user)
//				return oom_return_na();
//#else /* !WITHOUT_USERAUTH */
			// Apply filter rule to all conns, if USERAUTH is disabled, ip == '*'
			rule->all_conns = 1;
//#endif /* WITHOUT_USERAUTH */
		} else {
			rule->action.precedence++;
			rule->ip = strdup(argv[1]);
			if (!rule->ip)
				return oom_return_na();
		}
	}

	if (argc > 2) {
		if (rule->ip) {
			fprintf(stderr, "Ip filter cannot define desc filter"
//#ifndef WITHOUT_USERAUTH
//					", or user '%s' does not exist"
//#endif /* !WITHOUT_USERAUTH */
					" on line %d\n",
//#ifndef WITHOUT_USERAUTH
//					rule->ip,
//#endif /* !WITHOUT_USERAUTH */
					line_num);
			return -1;
		}
//#ifndef WITHOUT_USERAUTH
//		if (!conn_opts->user_auth) {
//			fprintf(stderr, "Keyword filter requires user auth on line %d\n", line_num);
//			return -1;
//		}
//		rule->action.precedence++;
//		rule->desc = strdup(argv[2]);
//		if (!rule->desc)
//			return oom_return_na();
//#endif /* !WITHOUT_USERAUTH */
	}

	rule->action.precedence++;
	rule->action.pass = 1;

	append_list(&opts->filter_rules, rule, filter_rule_t);

#ifdef DEBUG_OPTS
	filter_rule_dbg_print(rule);
#endif /* DEBUG_OPTS */
	return 0;
}

static macro_t *
filter_macro_find(macro_t *macro, char *name)
{
	while (macro) {
		if (equal(macro->name, name)) {
			return macro;
		}
		macro = macro->next;
	}
	return NULL;
}

int
filter_macro_set(opts_t *opts, char *value, unsigned int line_num)
{
#define MAX_MACRO_TOKENS 50

	// $name value1 [value2 [value3] ...]
	char *argv[sizeof(char *) * MAX_MACRO_TOKENS];
	int argc = 0;
	char *p, *last = NULL;

	for ((p = strtok_r(value, " ", &last));
		 p;
		 (p = strtok_r(NULL, " ", &last))) {
		if (argc < MAX_MACRO_TOKENS) {
			argv[argc++] = p;
		} else {
			fprintf(stderr, "Too many arguments in macro definition on line %d\n", line_num);
			return -1;
		}
	}

	if (argc < 2) {
		fprintf(stderr, "Macro definition requires at least two arguments on line %d\n", line_num);
		return -1;
	}

	if (argv[0][0] != '$') {
		fprintf(stderr, "Macro name should start with '$' on line %d\n", line_num);
		return -1;
	}

	if (filter_macro_find(opts->macro, argv[0])) {
		fprintf(stderr, "Macro name '%s' already exists on line %d\n", argv[0], line_num);
		return -1;
	}

	macro_t *macro = malloc(sizeof(macro_t));
	if (!macro)
		return oom_return_na();
	memset(macro, 0, sizeof(macro_t));

	macro->name = strdup(argv[0]);
	if (!macro->name)
		return oom_return_na();

	int i = 1;
	while (i < argc) {
		// Do not allow macro within macro, no recursive macro definitions
		if (argv[i][0] == '$') {
			fprintf(stderr, "Invalid macro value '%s' on line %d\n", argv[i], line_num);
			return -1;
		}

		value_t *v = malloc(sizeof(value_t));
		if (!v)
			return oom_return_na();
		memset(v, 0, sizeof(value_t));

		v->value = strdup(argv[i++]);
		if (!v->value)
			return oom_return_na();

		append_list(&macro->value, v, value_t);
	}

	append_list(&opts->macro, macro, macro_t);

#ifdef DEBUG_OPTS
	char *s = filter_value_str(macro->value);
	if (!s)
		return oom_return_na();
	log_dbg_printf("Macro: %s = %s\n", macro->name, s);
	free(s);
#endif /* DEBUG_OPTS */
	return 0;
}

static char * WUNRES
filter_site_set(filter_rule_t *rule, const char *name, const char *site, unsigned int line_num)
{
	// The for loop with strtok_r() does not output empty strings
	// So, no need to check if the length of site > 0
	size_t len = strlen(site);

	if (len > MAX_SITE_LEN) {
		fprintf(stderr, "Filter site too long %zu > %d on line %d\n", len, MAX_SITE_LEN, line_num);
		return NULL;
	}

	// Don't modify site, site is reused in macro expansion
	char *s = strdup(site);
	if (!s)
		return oom_return_na_null();

	unsigned int exact_site = 0;
	unsigned int all_sites = 0;
	if (s[len - 1] == '*') {
		exact_site = 0;
		len--;
		s[len] = '\0';
		// site == "*" ?
		if (len == 0)
			all_sites = 1;
	} else {
		exact_site = 1;
	}

	// redundant?
	if (equal(s, "*"))
		all_sites = 1;

	if (equal(name, "ip") || equal(name, "DstIp")) {
		rule->dstip = s;
		rule->exact_dstip = exact_site;
		rule->all_dstips = all_sites;
	}
	else if (equal(name, "sni") || equal(name, "SNI")) {
		rule->sni = s;
		rule->exact_sni = exact_site;
		rule->all_snis = all_sites;
	}
	else if (equal(name, "cn") || equal(name, "CN")) {
		rule->cn = s;
		rule->exact_cn = exact_site;
		rule->all_cns = all_sites;
	}
	else if (equal(name, "host") || equal(name, "Host")) {
		rule->host = s;
		rule->exact_host = exact_site;
		rule->all_hosts = all_sites;
	}
	else if (equal(name, "uri") || equal(name, "URI")) {
		rule->uri = s;
		rule->exact_uri = exact_site;
		rule->all_uris = all_sites;
	}

	return s;
}

static int WUNRES
filter_port_set(filter_rule_t *rule, const char *port, unsigned int line_num)
{
#define MAX_PORT_LEN 6

	size_t len = strlen(port);

	if (len > MAX_PORT_LEN) {
		fprintf(stderr, "Filter port too long %zu > %d on line %d\n", len, MAX_PORT_LEN, line_num);
		return -1;
	}

	rule->port = strdup(port);
	if (!rule->port)
		return oom_return_na();

	if (rule->port[len - 1] == '*') {
		rule->exact_port = 0;
		len--;
		rule->port[len] = '\0';
		// site == "*" ?
		if (len == 0)
			rule->all_ports = 1;
	} else {
		rule->exact_port = 1;
	}

	// redundant?
	if (equal(rule->port, "*"))
		rule->all_ports = 1;
	return 0;
}

static int WUNRES
filter_is_exact(const char *arg)
{
	return arg[strlen(arg) - 1] != '*';
}

static int WUNRES
filter_is_all(const char *arg)
{
	return equal(arg, "*");
}

static int WUNRES
filter_field_set(char **field, const char *arg, unsigned int line_num)
{
	// The for loop with strtok_r() does not output empty strings
	// So, no need to check if the length of field > 0
	size_t len = strlen(arg);

	if (len > MAX_SITE_LEN) {
		fprintf(stderr, "Filter field too long %zu > %d on line %d\n", len, MAX_SITE_LEN, line_num);
		return -1;
	}

	*field = strdup(arg);
	if (!*field)
		return oom_return_na();

	if ((*field)[len - 1] == '*')
		(*field)[len - 1] = '\0';
	return 0;
}

static int WUNRES
filter_arg_index_inc(int i, int argc, char *last, unsigned int line_num)
{
	if (i + 1 < argc) {
		return i + 1;
	} else {
		fprintf(stderr, "Not enough arguments in filter rule after '%s' on line %d\n", last, line_num);
		return -1;
	}
}

static int WUNRES
filter_rule_translate(opts_t *opts, const char *name, int argc, char **argv, unsigned int line_num)
{
	filter_rule_t *rule = malloc(sizeof(filter_rule_t));
	if (!rule)
		return oom_return_na();
	memset(rule, 0, sizeof(filter_rule_t));

	if (equal(name, "Divert"))
		rule->action.divert = 1;
	else if (equal(name, "Split"))
		rule->action.split = 1;
	else if (equal(name, "Pass"))
		rule->action.pass = 1;
	else if (equal(name, "Block"))
		rule->action.block = 1;
	else if (equal(name, "Match"))
		rule->action.match = 1;

	// precedence can only go up not down
	rule->action.precedence = 0;

	int done_from = 0;
	int done_site = 0;
	int i = 0;
	while (i < argc) {
		if (equal(argv[i], "*")) {
			i++;
		}
		else if (equal(argv[i], "from")) {
			if ((i = filter_arg_index_inc(i, argc, argv[i], line_num)) == -1)
				return -1;
//#ifndef WITHOUT_USERAUTH
//			if (equal(argv[i], "user") || equal(argv[i], "desc")) {
//				// The existence of user or desc should increment precedence, all_users or not
//				// user spec is more specific than ip spec
//				rule->action.precedence++;
//
//				if (equal(argv[i], "user")) {
//					if ((i = filter_arg_index_inc(i, argc, argv[i], line_num)) == -1)
//						return -1;
//
//					rule->all_users = filter_is_all(argv[i]);
//
//					if (!rule->all_users) {
//						rule->exact_user = filter_is_exact(argv[i]);
//						if (filter_field_set(&rule->user, argv[i], line_num) == -1)
//							return -1;
//						rule->action.precedence++;
//					}
//					i++;
//				}
//
//				if (i < argc && equal(argv[i], "desc")) {
//					if ((i = filter_arg_index_inc(i, argc, argv[i], line_num)) == -1)
//						return -1;
//
//					if (filter_is_all(argv[i])) {
//						if (!rule->user) {
//							rule->all_users = 1;
//						}
//					}
//					else {
//						rule->exact_desc = filter_is_exact(argv[i]);
//						if (filter_field_set(&rule->desc, argv[i], line_num) == -1)
//							return -1;
//						rule->action.precedence++;
//					}
//					i++;
//				}
//
//				done_from = 1;
//			}
//			else
//#endif /* !WITHOUT_USERAUTH */
			if (equal(argv[i], "ip")) {
				if ((i = filter_arg_index_inc(i, argc, argv[i], line_num)) == -1)
					return -1;

				rule->all_conns = filter_is_all(argv[i]);

				if (!rule->all_conns) {
					rule->exact_ip = filter_is_exact(argv[i]);
					if (filter_field_set(&rule->ip, argv[i], line_num) == -1)
						return -1;
					rule->action.precedence++;
				}
				i++;
				done_from = 1;
			}
			else if (equal(argv[i], "*")) {
				i++;
			}
		}
		else if (equal(argv[i], "to")) {
			if ((i = filter_arg_index_inc(i, argc, argv[i], line_num)) == -1)
				return -1;

			if (equal(argv[i], "ip") || equal(argv[i], "sni") || equal(argv[i], "cn") || equal(argv[i], "host") || equal(argv[i], "uri") ||
					equal(argv[i], "port")) {
				if (equal(argv[i], "ip") || equal(argv[i], "sni") || equal(argv[i], "cn") || equal(argv[i], "host") || equal(argv[i], "uri")) {
					char *name = argv[i];

					if ((i = filter_arg_index_inc(i, argc, name, line_num)) == -1)
						return -1;

					char *value = argv[i++];

					if (!filter_site_set(rule, name, value, line_num))
						return -1;

					rule->action.precedence++;
					done_site = 1;
				}

				if (i < argc && equal(argv[i], "port")) {
					if ((i = filter_arg_index_inc(i, argc, argv[i], line_num)) == -1)
						return -1;

					rule->action.precedence++;

					if (filter_port_set(rule, argv[i++], line_num) == -1)
						return -1;
				}
			}
			else if (equal(argv[i], "*")) {
				i++;
			}
		}
		else if (equal(argv[i], "log")) {
			if ((i = filter_arg_index_inc(i, argc, argv[i], line_num)) == -1)
				return -1;

			// Log actions increase rule precedence too, but this effects log actions only, not the precedence of filter actions
			rule->action.precedence++;

			if (equal(argv[i], "connect") || equal(argv[i], "master") || equal(argv[i], "cert") || equal(argv[i], "content") || equal(argv[i], "pcap") ||
				equal(argv[i], "!connect") || equal(argv[i], "!master") || equal(argv[i], "!cert") || equal(argv[i], "!content") || equal(argv[i], "!pcap")
				) {
				do {
					if (equal(argv[i], "connect"))
						rule->action.log_connect = 2;
					else if (equal(argv[i], "master"))
						rule->action.log_master = 2;
					else if (equal(argv[i], "cert"))
						rule->action.log_cert = 2;
					else if (equal(argv[i], "content"))
						rule->action.log_content = 2;
					else if (equal(argv[i], "pcap"))
						rule->action.log_pcap = 2;
					else if (equal(argv[i], "!connect"))
						rule->action.log_connect = 1;
					else if (equal(argv[i], "!master"))
						rule->action.log_master = 1;
					else if (equal(argv[i], "!cert"))
						rule->action.log_cert = 1;
					else if (equal(argv[i], "!content"))
						rule->action.log_content = 1;
					else if (equal(argv[i], "!pcap"))
						rule->action.log_pcap = 1;

					if (++i == argc)
						break;
				} while (equal(argv[i], "connect") || equal(argv[i], "master") || equal(argv[i], "cert") || equal(argv[i], "content") || equal(argv[i], "pcap") ||
						 equal(argv[i], "!connect") || equal(argv[i], "!master") || equal(argv[i], "!cert") || equal(argv[i], "!content") || equal(argv[i], "!pcap")
					);
			}
			else if (equal(argv[i], "*")) {
				rule->action.log_connect = 2;
				rule->action.log_master = 2;
				rule->action.log_cert = 2;
				rule->action.log_content = 2;
				rule->action.log_pcap = 2;
				i++;
			}
			else if (equal(argv[i], "!*")) {
				rule->action.log_connect = 1;
				rule->action.log_master = 1;
				rule->action.log_cert = 1;
				rule->action.log_content = 1;
				rule->action.log_pcap = 1;
				i++;
			}
		}
	}

	if (!done_from) {
		rule->all_conns = 1;
	}
	if (!done_site) {
		rule->dstip = strdup("");
		if (!rule->dstip)
			return oom_return_na();
		rule->all_dstips = 1;

		rule->sni = strdup("");
		if (!rule->sni)
			return oom_return_na();
		rule->all_snis = 1;

		rule->cn = strdup("");
		if (!rule->cn)
			return oom_return_na();
		rule->all_cns = 1;

		rule->host = strdup("");
		if (!rule->host)
			return oom_return_na();
		rule->all_hosts = 1;

		rule->uri = strdup("");
		if (!rule->uri)
			return oom_return_na();
		rule->all_uris = 1;
	}

#ifdef DEBUG_PROXY
	rule->action.line_num = line_num;
#endif /* DEBUG_PROXY */

	append_list(&opts->filter_rules, rule, filter_rule_t);

#ifdef DEBUG_OPTS
	filter_rule_dbg_print(rule);
#endif /* DEBUG_OPTS */
	return 0;
}

static int WUNRES
filter_rule_parse(opts_t *opts, conn_opts_t *conn_opts, const char *name, int argc, char **argv, unsigned int line_num);

// Max = from(1) + user(2) + desc(2) + to(1) + sni(2) + port(2) + log(16 with macro)
#define MAX_FILTER_RULE_TOKENS 26

static int WUNRES
filter_rule_macro_expand(opts_t *opts, conn_opts_t *conn_opts, const char *name, int argc, char **argv, int i, unsigned int line_num)
{
	if (argv[i][0] == '$') {
		macro_t *macro;
		if ((macro = filter_macro_find(opts->macro, argv[i]))) {
			value_t *value = macro->value;
			while (value) {
				// Prevent infinite macro expansion, macros do not allow it, but macro expansion should detect it too
				if (value->value[0] == '$') {
					fprintf(stderr, "Invalid macro value '%s' on line %d\n", value->value, line_num);
					return -1;
				}

				char *expanded_argv[sizeof(char *) * MAX_FILTER_RULE_TOKENS];
				memcpy(expanded_argv, argv, sizeof expanded_argv);

				expanded_argv[i] = value->value;

				if (filter_rule_parse(opts, conn_opts, name, argc, expanded_argv, line_num) == -1)
					return -1;

				value = value->next;
			}
			// End of macro expansion, the caller must stop processing the rule
			return 1;
		}
		else {
			fprintf(stderr, "No such macro '%s' on line %d\n", argv[i], line_num);
			return -1;
		}
	}
	return 0;
}

static int WUNRES
filter_rule_parse(opts_t *opts, conn_opts_t *conn_opts, const char *name, int argc, char **argv, unsigned int line_num)
{
	int done_all = 0;
	int done_from = 0;
	int done_to = 0;
	int done_log = 0;
	int rv = 0;
	int i = 0;
	while (i < argc) {
		if (equal(argv[i], "*")) {
			if (done_all) {
				fprintf(stderr, "Only one '*' statement allowed on line %d\n", line_num);
				return -1;
			}
			if (++i > argc) {
				fprintf(stderr, "Too many arguments for '*' on line %d\n", line_num);
				return -1;
			}
			done_all = 1;
		}
		else if (equal(argv[i], "from")) {
			if (done_from) {
				fprintf(stderr, "Only one 'from' statement allowed on line %d\n", line_num);
				return -1;
			}

			if ((i = filter_arg_index_inc(i, argc, argv[i], line_num)) == -1)
				return -1;
//#ifndef WITHOUT_USERAUTH
			if (equal(argv[i], "desc")) {
				// It is possible to define desc without user (i.e. * or all_users), hence no 'else' here
				if (i < argc && equal(argv[i], "desc")) {
					if ((i = filter_arg_index_inc(i, argc, argv[i], line_num)) == -1)
						return -1;

					if (argv[i][strlen(argv[i]) - 1] == '*') {
						// Nothing to do for '*' or substring search for 'desc*'
					}
					else if ((rv = filter_rule_macro_expand(opts, conn_opts, name, argc, argv, i, line_num)) != 0) {
						return rv;
					}
					i++;
				}

				done_from = 1;
			}
			else
//#endif /* !WITHOUT_USERAUTH */
			if (equal(argv[i], "ip")) {
				if ((i = filter_arg_index_inc(i, argc, argv[i], line_num)) == -1)
					return -1;

				if (argv[i][strlen(argv[i]) - 1] == '*') {
					// Nothing to do for '*' or substring search for 'ip*'
					}
				else if ((rv = filter_rule_macro_expand(opts, conn_opts, name, argc, argv, i, line_num)) != 0) {
					return rv;
				}
				i++;
				done_from = 1;
			}
			else if (equal(argv[i], "*")) {
				i++;
			}
			else {
				fprintf(stderr, "Unknown argument in filter rule at '%s' on line %d\n", argv[i], line_num);
				return -1;
			}
		}
		else if (equal(argv[i], "to")) {
			if (done_to) {
				fprintf(stderr, "Only one 'to' statement allowed on line %d\n", line_num);
				return -1;
			}

			if ((i = filter_arg_index_inc(i, argc, argv[i], line_num)) == -1)
				return -1;

			if (equal(argv[i], "ip") || equal(argv[i], "sni") || equal(argv[i], "cn") || equal(argv[i], "host") || equal(argv[i], "uri") ||
					equal(argv[i], "port")) {
				if (equal(argv[i], "ip") || equal(argv[i], "sni") || equal(argv[i], "cn") || equal(argv[i], "host") || equal(argv[i], "uri")) {
					if ((i = filter_arg_index_inc(i, argc, argv[i], line_num)) == -1)
						return -1;

					if ((rv = filter_rule_macro_expand(opts, conn_opts, name, argc, argv, i, line_num)) != 0) {
						return rv;
					}
					i++;
				}

				// It is possible to define port without site (i.e. * or all_sites), hence no 'else' here
				if (i < argc && equal(argv[i], "port")) {
					if ((i = filter_arg_index_inc(i, argc, argv[i], line_num)) == -1)
						return -1;

					if ((rv = filter_rule_macro_expand(opts, conn_opts, name, argc, argv, i, line_num)) != 0) {
						return rv;
					}
					i++;
				}
				done_to = 1;
			}
			else if (equal(argv[i], "*")) {
				i++;
			}
			else {
				fprintf(stderr, "Unknown argument in filter rule at '%s' on line %d\n", argv[i], line_num);
				return -1;
			}
		}
		else if (equal(argv[i], "log")) {
			if (done_log) {
				fprintf(stderr, "Only one 'log' statement allowed on line %d\n", line_num);
				return -1;
			}

			if ((i = filter_arg_index_inc(i, argc, argv[i], line_num)) == -1)
				return -1;

			if (equal(argv[i], "connect") || equal(argv[i], "master") || equal(argv[i], "cert") || equal(argv[i], "content") || equal(argv[i], "pcap") ||
				equal(argv[i], "!connect") || equal(argv[i], "!master") || equal(argv[i], "!cert") || equal(argv[i], "!content") || equal(argv[i], "!pcap")
				|| argv[i][0] == '$') {
				do {
					if ((rv = filter_rule_macro_expand(opts, conn_opts, name, argc, argv, i, line_num)) != 0) {
						return rv;
					}
					if (++i == argc)
						break;
				} while (equal(argv[i], "connect") || equal(argv[i], "master") || equal(argv[i], "cert") || equal(argv[i], "content") || equal(argv[i], "pcap") ||
						 equal(argv[i], "!connect") || equal(argv[i], "!master") || equal(argv[i], "!cert") || equal(argv[i], "!content") || equal(argv[i], "!pcap")
					|| argv[i][0] == '$');

				done_log = 1;
			}
			else if (equal(argv[i], "*")) {
				i++;
				done_log = 1;
			}
			else if (equal(argv[i], "!*")) {
				i++;
				done_log = 1;
			}
			else {
				fprintf(stderr, "Unknown argument in filter rule at '%s' on line %d\n", argv[i], line_num);
				return -1;
			}
		}
		else {
			fprintf(stderr, "Unknown argument in filter rule at '%s' on line %d\n", argv[i], line_num);
				return -1;
		}
	}

	// All checks passed and all macros expanded, if any
	return filter_rule_translate(opts, name, argc, argv, line_num);
}

int
filter_rule_set(opts_t *opts, conn_opts_t *conn_opts, const char *name, char *value, unsigned int line_num)
{
	char *argv[sizeof(char *) * MAX_FILTER_RULE_TOKENS];
	int argc = 0;
	char *p, *last = NULL;

	for ((p = strtok_r(value, " ", &last));
		 p;
		 (p = strtok_r(NULL, " ", &last))) {
		if (argc < MAX_FILTER_RULE_TOKENS) {
			argv[argc++] = p;
		} else {
			fprintf(stderr, "Too many arguments in filter rule on line %d\n", line_num);
			return -1;
		}
	}

	return filter_rule_parse(opts, conn_opts, name, argc, argv, line_num);
}

static int WUNRES
filter_rule_struct_translate(filter_rule_t *rule, UNUSED conn_opts_t *conn_opts, const char *name, char *value, unsigned int line_num)
{
	if (equal(name, "Action")) {
		if (equal(value, "Divert"))
			rule->action.divert = 1;
		else if (equal(value, "Split"))
			rule->action.split = 1;
		else if (equal(value, "Pass"))
			rule->action.pass = 1;
		else if (equal(value, "Block"))
			rule->action.block = 1;
		else if (equal(value, "Match"))
			rule->action.match = 1;
		else {
			fprintf(stderr, "Error in conf: Unknown Action '%s' on line %d\n", value, line_num);
			return -1;
		}
	}
//#ifndef WITHOUT_USERAUTH
//	else if (equal(name, "User")) {
//		if (!conn_opts->user_auth) {
//			fprintf(stderr, "User filter requires user auth on line %d\n", line_num);
//			return -1;
//		}
//
//		if (value[strlen(value) - 1] != '*' && !sys_isuser(value)) {
//			fprintf(stderr, "No such user '%s' on line %d\n", value, line_num);
//			return -1;
//		}
//
//		if (!rule->desc && !rule->all_users) {
//			rule->action.precedence++;
//		}
//
//		rule->all_users = filter_is_all(value);
//
//		if (!rule->all_users) {
//			rule->exact_user = filter_is_exact(value);
//			if (filter_field_set(&rule->user, value, line_num) == -1)
//				return -1;
//			rule->action.precedence++;
//		}
//	}
//	else if (equal(name, "Desc")) {
//		if (!conn_opts->user_auth) {
//			fprintf(stderr, "Desc filter requires user auth on line %d\n", line_num);
//			return -1;
//		}
//
//		if (!rule->user && !rule->all_users) {
//			rule->action.precedence++;
//		}
//
//		if (filter_is_all(value)) {
//			if (!rule->user) {
//				rule->all_users = 1;
//			}
//		}
//		else {
//			rule->exact_desc = filter_is_exact(value);
//			if (filter_field_set(&rule->desc, value, line_num) == -1)
//				return -1;
//			rule->action.precedence++;
//		}
//	}
//#endif /* !WITHOUT_USERAUTH */
	else if (equal(name, "SrcIp")) {
		rule->all_conns = filter_is_all(value);

		if (!rule->all_conns) {
			rule->exact_ip = filter_is_exact(value);
			if (filter_field_set(&rule->ip, value, line_num) == -1)
				return -1;
			rule->action.precedence++;
		}
	}
	else if (equal(name, "SNI") || equal(name, "CN") || equal(name, "Host") || equal(name, "URI") || equal(name, "DstIp")) {
		if (!filter_site_set(rule, name, value, line_num))
			return -1;
	}
	else if (equal(name, "DstPort")) {
		rule->action.precedence++;

		if (filter_port_set(rule, value, line_num) == -1)
			return -1;
	}
	else if (equal(name, "Log")) {
		// We don't support $macros within multi valued Log lines, i.e. cannot mix log actions with $macros
		// use either log actions concat with spaces or just a $macro, and no point trying to support it either
#define MAX_LOG_TOKENS 14
		int argc = 0;
		char *p, *last = NULL;

		for ((p = strtok_r(value, " ", &last));
			 p;
			 (p = strtok_r(NULL, " ", &last))) {
			if (argc < MAX_LOG_TOKENS) {
				argc++;

				if (equal(p, "connect"))
					rule->action.log_connect = 2;
				else if (equal(p, "master"))
					rule->action.log_master = 2;
				else if (equal(p, "cert"))
					rule->action.log_cert = 2;
				else if (equal(p, "content"))
					rule->action.log_content = 2;
				else if (equal(p, "pcap"))
					rule->action.log_pcap = 2;
				else if (equal(p, "!connect"))
					rule->action.log_connect = 1;
				else if (equal(p, "!master"))
					rule->action.log_master = 1;
				else if (equal(p, "!cert"))
					rule->action.log_cert = 1;
				else if (equal(p, "!content"))
					rule->action.log_content = 1;
				else if (equal(p, "!pcap"))
					rule->action.log_pcap = 1;
				else if (equal(p, "*")) {
					rule->action.log_connect = 2;
					rule->action.log_master = 2;
					rule->action.log_cert = 2;
					rule->action.log_content = 2;
					rule->action.log_pcap = 2;
				}
				else if (equal(p, "!*")) {
					rule->action.log_connect = 1;
					rule->action.log_master = 1;
					rule->action.log_cert = 1;
					rule->action.log_content = 1;
					rule->action.log_pcap = 1;
				}
				else {
					fprintf(stderr, "Error in conf: Unknown Log '%s' on line %d\n", p, line_num);
					return -1;
				}
			} else {
				fprintf(stderr, "Too many Log arguments in filter rule on line %d\n", line_num);
				return -1;
			}
		}
	}
	else if (equal(name, "ReconnectSSL")) {
		// Already processed by the parser
	}
	else {
		// This should have been handled by the parser, but in case
		fprintf(stderr, "Error in conf: Unknown option '%s' on line %d\n", name, line_num);
		return -1;
	}
	return 0;
}

static int WUNRES
filter_rule_struct_translate_nvls(opts_t *opts, name_value_lines_t nvls[], int nvls_size, conn_opts_t *conn_opts,
		const char *argv0, tmp_opts_t *tmp_opts, filter_parse_state_t parse_state)
{
	filter_rule_t *rule = malloc(sizeof(filter_rule_t));
	if (!rule)
		return oom_return_na();
	memset(rule, 0, sizeof(filter_rule_t));

	for (int i = 0; i < nvls_size; i++) {
		if (filter_rule_struct_translate(rule, conn_opts, nvls[i].name, nvls[i].value, nvls[i].line_num) == -1) {
			filter_rule_free(rule);
			return -1;
		}
	}

	if (!rule->ip
//#ifndef WITHOUT_USERAUTH
//		&& !rule->all_users && !rule->user && !rule->desc
//#endif /* !WITHOUT_USERAUTH */
		) {
		rule->all_conns = 1;
	}
	if (!rule->dstip && !rule->sni && !rule->cn && !rule->host && !rule->uri) {
		rule->dstip = strdup("");
		if (!rule->dstip)
			return oom_return_na();
		rule->all_dstips = 1;

		rule->sni = strdup("");
		if (!rule->sni)
			return oom_return_na();
		rule->all_snis = 1;

		rule->cn = strdup("");
		if (!rule->cn)
			return oom_return_na();
		rule->all_cns = 1;

		rule->host = strdup("");
		if (!rule->host)
			return oom_return_na();
		rule->all_hosts = 1;

		rule->uri = strdup("");
		if (!rule->uri)
			return oom_return_na();
		rule->all_uris = 1;
	}
	else {
		// Increment precedence for dst site only once here, we allow for multi site struct rules
		rule->action.precedence++;
	}

	// Increment precedence for log action only once here, if any specified, because otherwise
	// we would inc it multiple times while translating Log specifications, since we allow for multiple Log lines
	if (rule->action.log_connect || rule->action.log_master || rule->action.log_cert || rule->action.log_content || rule->action.log_pcap
			) {
		rule->action.precedence++;
	}

	// Set conn_opts only if the rule specifies any conn option to override the global or proxyspec conn options
	if (parse_state.conn_opts) {
		rule->action.conn_opts = conn_opts_copy(conn_opts, argv0, tmp_opts);
		if (!rule->action.conn_opts) {
			filter_rule_free(rule);
			return oom_return_na();
		}
	}

#ifdef DEBUG_PROXY
	rule->action.line_num = tmp_opts->line_num;
#endif /* DEBUG_PROXY */

	append_list(&opts->filter_rules, rule, filter_rule_t);

#ifdef DEBUG_OPTS
	filter_rule_dbg_print(rule);
#endif /* DEBUG_OPTS */
	return 0;
}

static int WUNRES
filter_rule_struct_macro_expand(opts_t *opts, name_value_lines_t nvls[], int nvls_size, conn_opts_t *conn_opts,
		const char *argv0, tmp_opts_t *tmp_opts, filter_parse_state_t parse_state)
{
	for (int i = 0; i < nvls_size; i++) {
		if (nvls[i].value[0] == '$') {
			macro_t *macro;
			if ((macro = filter_macro_find(opts->macro, nvls[i].value))) {
				value_t *value = macro->value;
				while (value) {
					// Prevent infinite macro expansion, macros do not allow it, but macro expansion should detect it too
					if (value->value[0] == '$') {
						fprintf(stderr, "Invalid macro value '%s' on line %d\n", value->value, nvls[i].line_num);
						return -1;
					}

					name_value_lines_t n[nvls_size];
					memcpy(n, nvls, sizeof(name_value_lines_t) * nvls_size);

					n[i].value = value->value;

					if (filter_rule_struct_macro_expand(opts, n, nvls_size, conn_opts, argv0, tmp_opts, parse_state) == -1)
						return -1;

					value = value->next;
				}
				// End of macro expansion, the caller must stop processing the rule
				return 1;
			}
			else {
				fprintf(stderr, "No such macro '%s' on line %d\n", nvls[i].value, nvls[i].line_num);
				return -1;
			}
		}
	}

	if (filter_rule_struct_translate_nvls(opts, nvls, nvls_size, conn_opts, argv0, tmp_opts, parse_state) == -1)
		return -1;
	return 0;
}

static int WUNRES
filter_rule_struct_parse(name_value_lines_t nvls[], int *nvls_size, conn_opts_t *conn_opts, const char *argv0,
		char *name, char *value, unsigned int line_num, tmp_opts_t *tmp_opts, filter_parse_state_t *parse_state)
{
	// Closing brace '}' is the only option without a value
	// and only allowed in structured filtering rules and proxyspecs
	if ((!value || !strlen(value)) && !equal(name, "}")) {
		fprintf(stderr, "Error in conf: No value assigned for %s on line %d\n", name, line_num);
		return -1;
	}

	if (equal(name, "}")) {
#ifdef DEBUG_OPTS
		log_dbg_printf("FilterRule } on line %d\n", line_num);
#endif /* DEBUG_OPTS */
		if (!parse_state->action) {
			fprintf(stderr, "Incomplete FilterRule on line %d\n", line_num);
			return -1;
		}
		// Return 2 to indicate the end of structured filter rule
		return 2;
	}

	int rv = set_conn_opts_option(conn_opts, argv0, name, value, line_num, tmp_opts);
	if (rv == -1) {
		fprintf(stderr, "Error in conf: '%s' on line %d\n", name, line_num);
		return -1;
	} else if (rv == 0) {
		parse_state->conn_opts = 1;
		return 0;
	}

	if (equal(name, "Action")) {
		if (parse_state->action) {
			fprintf(stderr, "Error in conf: Only one Action spec allowed '%s' on line %d\n", value, line_num);
			return -1;
		}
		parse_state->action = 1;
	}
	else if (equal(name, "User")) {
		if (parse_state->user) {
			fprintf(stderr, "Error in conf: Only one User spec allowed '%s' on line %d\n", value, line_num);
			return -1;
		}
		if (parse_state->srcip) {
			fprintf(stderr, "Error in conf: Cannot specify both SrcIp and User '%s' on line %d\n", value, line_num);
			return -1;
		}
		parse_state->user = 1;
	}
	else if (equal(name, "Desc")) {
		if (parse_state->desc) {
			fprintf(stderr, "Error in conf: Only one Desc spec allowed '%s' on line %d\n", value, line_num);
			return -1;
		}
		if (parse_state->srcip) {
			fprintf(stderr, "Error in conf: Cannot specify both SrcIp and Desc '%s' on line %d\n", value, line_num);
			return -1;
		}
		parse_state->desc = 1;
	}
	else if (equal(name, "SrcIp")) {
		if (parse_state->srcip) {
			fprintf(stderr, "Error in conf: Only one SrcIp spec allowed '%s' on line %d\n", value, line_num);
			return -1;
		}
		if (parse_state->user || parse_state->desc) {
			fprintf(stderr, "Error in conf: Cannot specify both User/Desc and SrcIp '%s' on line %d\n", value, line_num);
			return -1;
		}
		parse_state->srcip = 1;
	}
	else if (equal(name, "SNI")) {
		if (parse_state->sni) {
			fprintf(stderr, "Error in conf: Only one SNI spec allowed '%s' on line %d\n", value, line_num);
			return -1;
		}
		parse_state->sni = 1;
	}
	else if (equal(name, "CN")) {
		if (parse_state->cn) {
			fprintf(stderr, "Error in conf: Only one CN spec allowed '%s' on line %d\n", value, line_num);
			return -1;
		}
		parse_state->cn = 1;
	}
	else if (equal(name, "Host")) {
		if (parse_state->host) {
			fprintf(stderr, "Error in conf: Only one Host spec allowed '%s' on line %d\n", value, line_num);
			return -1;
		}
		parse_state->host = 1;
	}
	else if (equal(name, "URI")) {
		if (parse_state->uri) {
			fprintf(stderr, "Error in conf: Only one URI spec allowed '%s' on line %d\n", value, line_num);
			return -1;
		}
		parse_state->uri = 1;
	}
	else if (equal(name, "DstIp")) {
		if (parse_state->dstip) {
			fprintf(stderr, "Error in conf: Only one DstIp spec allowed '%s' on line %d\n", value, line_num);
			return -1;
		}
		parse_state->dstip = 1;
	}
	else if (equal(name, "DstPort")) {
		if (parse_state->dstport) {
			fprintf(stderr, "Error in conf: Only one DstPort spec allowed '%s' on line %d\n", value, line_num);
			return -1;
		}
		parse_state->dstport = 1;
	}
	else if (equal(name, "Log")) {
		// Log can be used more than once to define multiple log actions, if not using macros
	}
	else if (equal(name, "ReconnectSSL")) {
		if (parse_state->reconnect_ssl) {
			fprintf(stderr, "Error in conf: Only one ReconnectSSL spec allowed '%s' on line %d\n", value, line_num);
			return -1;
		}
		parse_state->reconnect_ssl = 1;

		int yes = check_value_yesno(value, "ReconnectSSL", line_num);
		if (yes == -1)
			return -1;
		conn_opts->reconnect_ssl = yes;
#ifdef DEBUG_OPTS
		log_dbg_printf("ReconnectSSL: %u\n", conn_opts->reconnect_ssl);
#endif /* DEBUG_OPTS */
	}
	else {
		fprintf(stderr, "Error in conf: Unknown option '%s' on line %d\n", name, line_num);
		return -1;
	}

	nvls[*nvls_size].name = strdup(name);
	nvls[*nvls_size].value = strdup(value);
	nvls[*nvls_size].line_num = line_num;
	(*nvls_size)++;

	return 0;
}

int
load_filterrule_struct(opts_t *opts, conn_opts_t *conn_opts, const char *argv0, unsigned int *line_num, FILE *f, tmp_opts_t *orig_tmp_opts)
{
	int retval = -1;
	char *name, *value;
	char *line = NULL;
	size_t line_len;
	int i;

	filter_parse_state_t parse_state;
	memset(&parse_state, 0, sizeof(filter_parse_state_t));

#define MAX_NVLS_SIZE 100
	int nvls_size = 0;
	name_value_lines_t nvls[MAX_NVLS_SIZE];

	conn_opts_t *copts = conn_opts_copy(conn_opts, argv0, orig_tmp_opts);
	if (!copts)
		return -1;

	// Operate on a local copy of orig_tmp_opts, do not modify the orig_tmp_opts
	// otherwise struct filtering rules can override global or proxyspec options
	tmp_opts_t *tmp_opts = tmp_opts_copy(orig_tmp_opts);
	if (!tmp_opts) {
		retval = -1;
		goto err;
	}

#ifdef DEBUG_PROXY
	tmp_opts->line_num = *line_num;
#endif /* DEBUG_PROXY */

	int closing_brace = 0;

	while (!feof(f) && !closing_brace) {
		if (getline(&line, &line_len, f) == -1) {
			break;
		}
		if (line == NULL) {
			fprintf(stderr, "Error in conf file: getline() returns NULL line after line %d\n", *line_num);
			retval = -1;
			goto err;
		}
		(*line_num)++;

		/* Skip white space */
		for (name = line; *name == ' ' || *name == '\t'; name++);

		/* Skip comments and empty lines */
		if ((name[0] == '\0') || (name[0] == '#') || (name[0] == ';') ||
			(name[0] == '\r') || (name[0] == '\n')) {
			continue;
		}

		retval = get_name_value(name, &value, ' ', *line_num);
		if (retval == 0) {
			retval = filter_rule_struct_parse(nvls, &nvls_size, copts, argv0, name, value, *line_num, tmp_opts, &parse_state);
		}
		if (retval == -1) {
			goto err;
		} else if (retval == 2) {
			closing_brace = 1;
		}

		if (nvls_size >= MAX_NVLS_SIZE) {
			fprintf(stderr, "Error in conf file: max allowed lines reached in struct FilterRule on line %d\n", *line_num);
			retval = -1;
			goto err;
		}

		free(line);
		line = NULL;
	}

	if (!closing_brace) {
		fprintf(stderr, "Error in conf file: struct FilterRule has no closing brace '}' after line %d\n", *line_num);
		retval = -1;
		goto err;
	}

	if (filter_rule_struct_macro_expand(opts, nvls, nvls_size, copts, argv0, tmp_opts, parse_state) == -1) {
		retval = -1;
		goto err;
	}

	retval = 0;
err:
	conn_opts_free(copts);
	if (tmp_opts)
		tmp_opts_free(tmp_opts);
	for (i = 0; i < nvls_size; i++) {
		free(nvls[i].name);
		free(nvls[i].value);
	}
	if (line)
		free(line);
	return retval;
}

static filter_port_t *
filter_port_exact_match(kbtree_t(port) *btree, char *p)
{
	if (!btree)
		return NULL;
	filter_port_t **port = kb_get(port, btree, p);
	return port ? *port : NULL;
}

static filter_port_t *
filter_port_substring_match(ACMachine(char) *acm, char *port)
{
	if (!acm)
		return NULL;
	filter_port_t *p = NULL;
	match_acm(acm, port, p);
	return p;
}

filter_port_t *
filter_port_find(filter_site_t *site, char *p)
{
	filter_port_t *port;
	if ((port = filter_port_exact_match(site->port_btree, p)))
		return port;
	if ((port = filter_port_substring_match(site->port_acm, p)))
		return port;
	return site->port_all;
}

static filter_port_t *
filter_port_substring_exact_match(ACMachine(char) *acm, char *p)
{
	if (acm) {
		const ACState(char) *state = ACM_reset(acm);
		for (char *c = p; *c; c++) {
			size_t nb = ACM_match(state, *c);
			for (size_t j = 0; j < nb; j++) {
				filter_port_t *value;
				ACM_get_match(state, j, 0, (void **)&value);
				// ACM matches any substring, make sure the match is exact
				if (equal(value->port, p))
					return value;
			}
		}
	}
	return NULL;
}

static filter_port_t *
filter_port_find_exact(filter_site_t *site, filter_rule_t *rule)
{
	if (rule->all_ports)
		return site->port_all;
	else if (rule->exact_port)
		return filter_port_exact_match(site->port_btree, rule->port);
	else
		return filter_port_substring_exact_match(site->port_acm, rule->port);
}

static int NONNULL(1,2) WUNRES
filter_port_add(filter_site_t *site, filter_rule_t *rule, const char *argv0, tmp_opts_t *tmp_opts)
{
	filter_port_t *port = filter_port_find_exact(site, rule);
	if (!port) {
		port = malloc(sizeof(filter_port_t));
		if (!port)
			return oom_return_na();
		memset(port, 0, sizeof(filter_port_t));

		port->port = strdup(rule->port);
		if (!port->port)
			return oom_return_na();

		if (rule->all_ports) {
			site->port_all = port;
		}
		else if (rule->exact_port) {
			if (!site->port_btree)
				if (!(site->port_btree = kb_init(port, KB_DEFAULT_SIZE)))
					return oom_return_na();

			kb_put(port, site->port_btree, port);
		}
		else {
			if (!site->port_acm)
				if (!(site->port_acm = ACM_create(char)))
					return oom_return_na();

			Keyword(char) k;
			ACM_KEYWORD_SET(k, port->port, strlen(port->port));
			ACM_register_keyword(site->port_acm, k, port, free_port_func);
		}
	}

	port->all_ports = rule->all_ports;
	port->exact = rule->exact_port;

	// Do not override the specs of port rules at higher precedence
	// precedence can only go up not down
	if (rule->action.precedence >= port->action.precedence) {
		// Multiple rules can set an action for the same port, hence the bit-wise OR
		port->action.divert |= rule->action.divert;
		port->action.split |= rule->action.split;
		port->action.pass |= rule->action.pass;
		port->action.block |= rule->action.block;
		port->action.match |= rule->action.match;

		// Multiple log actions can be set for the same port
		// Multiple rules can enable/disable or don't change a log action for the same port
		// 0: don't change, 1: disable, 2: enable
		if (rule->action.log_connect)
			port->action.log_connect = rule->action.log_connect;
		if (rule->action.log_master)
			port->action.log_master = rule->action.log_master;
		if (rule->action.log_cert)
			port->action.log_cert = rule->action.log_cert;
		if (rule->action.log_content)
			port->action.log_content = rule->action.log_content;
		if (rule->action.log_pcap)
			port->action.log_pcap = rule->action.log_pcap;

		if (rule->action.conn_opts) {
			if (port->action.conn_opts)
				conn_opts_free(port->action.conn_opts);
			port->action.conn_opts = conn_opts_copy(rule->action.conn_opts, argv0, tmp_opts);
			if (!port->action.conn_opts)
				return oom_return_na();
		}

		port->action.precedence = rule->action.precedence;
#ifdef DEBUG_PROXY
		port->action.line_num = rule->action.line_num;
#endif /* DEBUG_PROXY */
	}
	return 0;
}

filter_site_t *
filter_site_exact_match(kbtree_t(site) *btree, char *s)
{
	if (!btree)
		return NULL;
	filter_site_t **site = kb_get(site, btree, s);
	return site ? *site : NULL;
}

filter_site_t *
filter_site_substring_match(ACMachine(char) *acm, char *site)
{
	if (!acm)
		return NULL;
	filter_site_t *s = NULL;
	match_acm(acm, site, s);
	return s;
}

filter_site_t *
filter_site_find(kbtree_t(site) *btree, ACMachine(char) *acm, filter_site_t *all, char *s)
{
	filter_site_t *site;
	if ((site = filter_site_exact_match(btree, s)))
		return site;
	if ((site = filter_site_substring_match(acm, s)))
		return site;
	return all;
}

static filter_site_t *
filter_site_substring_exact_match(ACMachine(char) *acm, char *s)
{
	if (acm) {
		const ACState(char) *state = ACM_reset(acm);
		for (char *c = s; *c; c++) {
			size_t nb = ACM_match(state, *c);
			for (size_t j = 0; j < nb; j++) {
				filter_site_t *value;
				ACM_get_match(state, j, 0, (void **)&value);
				// ACM matches any substring, make sure the match is exact
				if (equal(value->site, s))
					return value;
			}
		}
	}
	return NULL;
}

static filter_site_t *
filter_site_find_exact(kbtree_t(site) *btree, ACMachine(char) *acm, filter_site_t *all, char *s, unsigned int exact_site, unsigned int all_sites)
{
	if (all_sites)
		return all;
	else if (exact_site)
		return filter_site_exact_match(btree, s);
	else
		return filter_site_substring_exact_match(acm, s);
}

static int NONNULL(3) WUNRES
filter_site_add(kbtree_t(site) **btree, ACMachine(char) **acm, filter_site_t **all, filter_rule_t *rule, char *s, unsigned int exact_site, unsigned int all_sites, const char *argv0, tmp_opts_t *tmp_opts)
{
	filter_site_t *site = filter_site_find_exact(*btree, *acm, *all, s, exact_site, all_sites);
	if (!site) {
		site = malloc(sizeof(filter_site_t));
		if (!site)
			return oom_return_na();
		memset(site, 0, sizeof(filter_site_t));

		site->site = strdup(s);
		if (!site->site)
			return oom_return_na();

		if (all_sites) {
			*all = site;
		}
		else if (exact_site) {
			if (!*btree)
				if (!(*btree = kb_init(site, KB_DEFAULT_SIZE)))
					return oom_return_na();

			kb_put(site, *btree, site);
		}
		else {
			if (!*acm)
				if (!(*acm = ACM_create(char)))
					return oom_return_na();

			Keyword(char) k;
			ACM_KEYWORD_SET(k, site->site, strlen(site->site));
			ACM_register_keyword(*acm, k, site, free_site_func);
		}
	}

	site->all_sites = all_sites;
	site->exact = exact_site;

	// Do not override the specs of a site with a port rule
	// Port rule is added as a new port under the same site
	// hence 'if else', not just 'if'
	if (rule->port) {
		if (filter_port_add(site, rule, argv0, tmp_opts) == -1)
			return -1;
	}
	// Do not override the specs of site rules at higher precedence
	// precedence can only go up not down
	else if (rule->action.precedence >= site->action.precedence) {
		// Multiple rules can set an action for the same site, hence the bit-wise OR
		site->action.divert |= rule->action.divert;
		site->action.split |= rule->action.split;
		site->action.pass |= rule->action.pass;
		site->action.block |= rule->action.block;
		site->action.match |= rule->action.match;

		// Multiple log actions can be set for the same site
		// Multiple rules can enable/disable or don't change a log action for the same site
		// 0: don't change, 1: disable, 2: enable
		if (rule->action.log_connect)
			site->action.log_connect = rule->action.log_connect;
		if (rule->action.log_master)
			site->action.log_master = rule->action.log_master;
		if (rule->action.log_cert)
			site->action.log_cert = rule->action.log_cert;
		if (rule->action.log_content)
			site->action.log_content = rule->action.log_content;
		if (rule->action.log_pcap)
			site->action.log_pcap = rule->action.log_pcap;

		if (rule->action.conn_opts) {
			if (site->action.conn_opts)
				conn_opts_free(site->action.conn_opts);
			site->action.conn_opts = conn_opts_copy(rule->action.conn_opts, argv0, tmp_opts);
			if (!site->action.conn_opts)
				return oom_return_na();
		}

		site->action.precedence = rule->action.precedence;
#ifdef DEBUG_PROXY
		site->action.line_num = rule->action.line_num;
#endif /* DEBUG_PROXY */
	}
	return 0;
}

static int
filter_sitelist_add(filter_list_t *list, filter_rule_t *rule, const char *argv0, tmp_opts_t *tmp_opts)
{
	if (rule->dstip) {
		if (filter_site_add(&list->ip_btree, &list->ip_acm, &list->ip_all, rule, rule->dstip, rule->exact_dstip, rule->all_dstips, argv0, tmp_opts) == -1)
			return -1;
	}
	if (rule->sni) {
		if (filter_site_add(&list->sni_btree, &list->sni_acm, &list->sni_all, rule, rule->sni, rule->exact_sni, rule->all_snis, argv0, tmp_opts) == -1)
			return -1;
	}
	if (rule->cn) {
		if (filter_site_add(&list->cn_btree, &list->cn_acm, &list->cn_all, rule, rule->cn, rule->exact_cn, rule->all_cns, argv0, tmp_opts) == -1)
			return -1;
	}
	if (rule->host) {
		if (filter_site_add(&list->host_btree, &list->host_acm, &list->host_all, rule, rule->host, rule->exact_host, rule->all_hosts, argv0, tmp_opts) == -1)
			return -1;
	}
	if (rule->uri) {
		if (filter_site_add(&list->uri_btree, &list->uri_acm, &list->uri_all, rule, rule->uri, rule->exact_uri, rule->all_uris, argv0, tmp_opts) == -1)
			return -1;
	}
	return 0;
}

filter_ip_t *
filter_ip_exact_match(kbtree_t(ip) *btree, char *i)
{
	if (!btree)
		return NULL;
	filter_ip_t **ip = kb_get(ip, btree, i);
	return ip ? *ip : NULL;
}

filter_ip_t *
filter_ip_substring_match(ACMachine(char) *acm, char *ip)
{
	if (!acm)
		return NULL;
	filter_ip_t *i = NULL;
	match_acm(acm, ip, i);
	return i;
}

static filter_ip_t *
filter_ip_substring_exact_match(ACMachine(char) *acm, char *i)
{
	if (acm) {
		const ACState(char) *state = ACM_reset(acm);
		for (char *c = i; *c; c++) {
			size_t nb = ACM_match(state, *c);
			for (size_t j = 0; j < nb; j++) {
				filter_ip_t *value;
				ACM_get_match(state, j, 0, (void **)&value);
				// ACM matches any substring, make sure the match is exact
				if (equal(value->ip, i))
					return value;
			}
		}
	}
	return NULL;
}

static filter_ip_t *
filter_ip_find_exact(filter_t *filter, filter_rule_t *rule)
{
	if (rule->exact_ip)
		return filter_ip_exact_match(filter->ip_btree, rule->ip);
	else
		return filter_ip_substring_exact_match(filter->ip_acm, rule->ip);
}

static void
free_ip_func(void *i)
{
	free_ip((filter_ip_t **)&i);
}

static filter_ip_t *
filter_ip_get(filter_t *filter, filter_rule_t *rule)
{
	filter_ip_t *ip = filter_ip_find_exact(filter, rule);
	if (!ip) {
		ip = malloc(sizeof(filter_ip_t));
		if (!ip)
			return oom_return_na_null();
		memset(ip, 0, sizeof(filter_ip_t));

		ip->list = malloc(sizeof(filter_list_t));
		if (!ip->list)
			return oom_return_na_null();
		memset(ip->list, 0, sizeof(filter_list_t));

		ip->ip = strdup(rule->ip);
		if (!ip->ip)
			return oom_return_na_null();

		ip->exact = rule->exact_ip;

		if (rule->exact_ip) {
			if (!filter->ip_btree)
				if (!(filter->ip_btree = kb_init(ip, KB_DEFAULT_SIZE)))
					return oom_return_na_null();

			kb_put(ip, filter->ip_btree, ip);
		}
		else {
			if (!filter->ip_acm)
				if (!(filter->ip_acm = ACM_create(char)))
					return oom_return_na_null();

			Keyword(char) k;
			ACM_KEYWORD_SET(k, ip->ip, strlen(ip->ip));
			ACM_register_keyword(filter->ip_acm, k, ip, free_ip_func);
		}
	}
	return ip;
}

//#ifndef WITHOUT_USERAUTH
//filter_desc_t *
//filter_desc_exact_match(kbtree_t(desc) *btree, char *k)
//{
//	if (!btree)
//		return NULL;
//	filter_desc_t **desc = kb_get(desc, btree, k);
//	return desc ? *desc : NULL;
//}
//
//filter_desc_t *
//filter_desc_substring_match(ACMachine(char) *acm, char *desc)
//{
//	if (!acm)
//		return NULL;
//	filter_desc_t *k = NULL;
//	match_acm(acm, desc, k);
//	return k;
//}
//
//static filter_desc_t *
//filter_desc_substring_exact_match(ACMachine(char) *acm, char *k)
//{
//	if (acm) {
//		const ACState(char) *state = ACM_reset(acm);
//		for (char *c = k; *c; c++) {
//			size_t nb = ACM_match(state, *c);
//			for (size_t j = 0; j < nb; j++) {
//				filter_desc_t *value;
//				ACM_get_match(state, j, 0, (void **)&value);
//				// ACM matches any substring, make sure the match is exact
//				if (equal(value->desc, k))
//					return value;
//			}
//		}
//	}
//	return NULL;
//}
//
//static filter_desc_t *
//filter_desc_find_exact(filter_t *filter, filter_user_t *user, filter_rule_t *rule)
//{
//	if (rule->exact_desc)
//		return filter_desc_exact_match(user ? user->desc_btree : filter->desc_btree, rule->desc);
//	else
//		return filter_desc_substring_exact_match(user ? user->desc_acm : filter->desc_acm, rule->desc);
//}
//
//static void
//free_desc_func(void *k)
//{
//	free_desc((filter_desc_t **)&k);
//}
//
//static filter_desc_t *
//filter_desc_get(filter_t *filter, filter_user_t *user, filter_rule_t *rule)
//{
//	filter_desc_t *desc = filter_desc_find_exact(filter, user, rule);
//	if (!desc) {
//		desc = malloc(sizeof(filter_desc_t));
//		if (!desc)
//			return oom_return_na_null();
//		memset(desc, 0, sizeof(filter_desc_t));
//
//		desc->list = malloc(sizeof(filter_list_t));
//		if (!desc->list)
//			return oom_return_na_null();
//		memset(desc->list, 0, sizeof(filter_list_t));
//
//		desc->desc = strdup(rule->desc);
//		if (!desc->desc)
//			return oom_return_na_null();
//
//		desc->exact = rule->exact_desc;
//
//		if (rule->exact_desc) {
//			kbtree_t(desc) **btree = user ? &user->desc_btree : &filter->desc_btree;
//			if (!*btree)
//				if (!(*btree = kb_init(desc, KB_DEFAULT_SIZE)))
//					return oom_return_na_null();
//
//			kb_put(desc, *btree, desc);
//		}
//		else {
//			ACMachine(char) **acm = user ? &user->desc_acm : &filter->desc_acm;
//			if (!*acm)
//				if (!(*acm = ACM_create(char)))
//					return oom_return_na_null();
//
//			Keyword(char) k;
//			ACM_KEYWORD_SET(k, desc->desc, strlen(desc->desc));
//			ACM_register_keyword(*acm, k, desc, free_desc_func);
//		}
//	}
//	return desc;
//}
//
//filter_user_t *
//filter_user_exact_match(kbtree_t(user) *btree, char *u)
//{
//	if (!btree)
//		return NULL;
//	filter_user_t **user = kb_get(user, btree, u);
//	return user ? *user : NULL;
//}
//
//filter_user_t *
//filter_user_substring_match(ACMachine(char) *acm, char *user)
//{
//	if (!acm)
//		return NULL;
//	filter_user_t *u = NULL;
//	match_acm(acm, user, u);
//	return u;
//}
//
//static filter_user_t *
//filter_user_substring_exact_match(ACMachine(char) *acm, char *u)
//{
//	if (acm) {
//		const ACState(char) *state = ACM_reset(acm);
//		for (char *c = u; *c; c++) {
//			size_t nb = ACM_match(state, *c);
//			for (size_t j = 0; j < nb; j++) {
//				filter_user_t *value;
//				ACM_get_match(state, j, 0, (void **)&value);
//				// ACM matches any substring, make sure the match is exact
//				if (equal(value->user, u))
//					return value;
//			}
//		}
//	}
//	return NULL;
//}
//
//static filter_user_t *
//filter_user_find_exact(filter_t *filter, filter_rule_t *rule)
//{
//	if (rule->exact_user)
//		return filter_user_exact_match(filter->user_btree, rule->user);
//	else
//		return filter_user_substring_exact_match(filter->user_acm, rule->user);
//}
//
//static void
//free_user_func(void *u)
//{
//	free_user((filter_user_t **)&u);
//}
//
//static filter_user_t *
//filter_user_get(filter_t *filter, filter_rule_t *rule)
//{
//	filter_user_t *user = filter_user_find_exact(filter, rule);
//	if (!user) {
//		user = malloc(sizeof(filter_user_t));
//		if (!user)
//			return oom_return_na_null();
//		memset(user, 0, sizeof(filter_user_t));
//
//		user->list = malloc(sizeof(filter_list_t));
//		if (!user->list)
//			return oom_return_na_null();
//		memset(user->list, 0, sizeof(filter_list_t));
//
//		user->user = strdup(rule->user);
//		if (!user->user)
//			return oom_return_na_null();
//
//		user->exact = rule->exact_user;
//
//		if (rule->exact_user) {
//			if (!filter->user_btree)
//				if (!(filter->user_btree = kb_init(user, KB_DEFAULT_SIZE)))
//					return oom_return_na_null();
//
//			kb_put(user, filter->user_btree, user);
//		}
//		else {
//			if (!filter->user_acm)
//				if (!(filter->user_acm = ACM_create(char)))
//					return oom_return_na_null();
//
//			Keyword(char) k;
//			ACM_KEYWORD_SET(k, user->user, strlen(user->user));
//			ACM_register_keyword(filter->user_acm, k, user, free_user_func);
//		}
//	}
//	return user;
//}
//#endif /* WITHOUT_USERAUTH */

/*
 * Translates filtering rules into data structures.将过滤规则转换为数据结构。
 * Never pass NULL as rule param.永远不要传递NULL作为规则参数。
 * Otherwise, we must return NULL, but NULL retval means oom.否则，必须返回NULL，但NULL retval表示空间。
 */
filter_t *
filter_set(filter_rule_t *rule, const char *argv0, tmp_opts_t *tmp_opts)
{
	filter_t *filter = malloc(sizeof(filter_t));
	if (!filter)
		return oom_return_na_null();
	memset(filter, 0, sizeof(filter_t));

//#ifndef WITHOUT_USERAUTH
//	filter->all_user = malloc(sizeof(filter_list_t));
//	if (!filter->all_user)
//		return oom_return_na_null();
//	memset(filter->all_user, 0, sizeof(filter_list_t));
//#endif /* WITHOUT_USERAUTH */

	filter->all = malloc(sizeof(filter_list_t));
	if (!filter->all)
		return oom_return_na_null();
	memset(filter->all, 0, sizeof(filter_list_t));

	while (rule) {
//#ifndef WITHOUT_USERAUTH
//		if (rule->user) {
//			filter_user_t *user = filter_user_get(filter, rule);
//			if (!user)
//				return NULL;
//			if (rule->desc) {
//				filter_desc_t *desc = filter_desc_get(filter, user, rule);
//				if (!desc)
//					return NULL;
//				if (filter_sitelist_add(desc->list, rule, argv0, tmp_opts) == -1)
//					return NULL;
//			}
//			else {
//				if (filter_sitelist_add(user->list, rule, argv0, tmp_opts) == -1)
//					return NULL;
//			}
//		}
//		else if (rule->desc) {
//			filter_desc_t *desc = filter_desc_get(filter, NULL, rule);
//			if (!desc)
//				return NULL;
//			if (filter_sitelist_add(desc->list, rule, argv0, tmp_opts) == -1)
//				return NULL;
//		}
//		else if (rule->all_users) {
//			if (filter_sitelist_add(filter->all_user, rule, argv0, tmp_opts) == -1)
//				return NULL;
//		}
//		else
//#endif /* WITHOUT_USERAUTH */
		if (rule->ip) {
			 filter_ip_t *ip = filter_ip_get(filter, rule);
			if (!ip)
				return NULL;
			if (filter_sitelist_add(ip->list, rule, argv0, tmp_opts) == -1)
				return NULL;
		}
		else if (rule->all_conns) {
			if (filter_sitelist_add(filter->all, rule, argv0, tmp_opts) == -1)
				return NULL;
		}
		rule = rule->next;
	}
	return filter;
}

/* vim: set noet ft=c: */
