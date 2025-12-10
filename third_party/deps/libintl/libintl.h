/**
 * libintl.h - GNU gettext compatible header for HarmonyOS
 * 
 * Provides the standard gettext API for internationalization.
 */

#ifndef _LIBINTL_H
#define _LIBINTL_H

#ifdef __cplusplus
extern "C" {
#endif

/* Core gettext functions */
extern char *gettext(const char *msgid);
extern char *dgettext(const char *domainname, const char *msgid);
extern char *dcgettext(const char *domainname, const char *msgid, int category);

/* Plural forms */
extern char *ngettext(const char *msgid1, const char *msgid2, unsigned long int n);
extern char *dngettext(const char *domainname, const char *msgid1, 
                       const char *msgid2, unsigned long int n);
extern char *dcngettext(const char *domainname, const char *msgid1,
                        const char *msgid2, unsigned long int n, int category);

/* Domain management */
extern char *textdomain(const char *domainname);
extern char *bindtextdomain(const char *domainname, const char *dirname);
extern char *bind_textdomain_codeset(const char *domainname, const char *codeset);

/* Context-aware functions (GNU extension) */
extern char *pgettext_aux(const char *domain, const char *msg_ctxt_id,
                          const char *msgid, int category);
extern char *npgettext_aux(const char *domain, const char *msg_ctxt_id,
                           const char *msgid1, const char *msgid2,
                           unsigned long int n, int category);

/* libintl_ prefixed versions (compatibility) */
extern char *libintl_gettext(const char *msgid);
extern char *libintl_dgettext(const char *domainname, const char *msgid);
extern char *libintl_dcgettext(const char *domainname, const char *msgid, int category);
extern char *libintl_ngettext(const char *msgid1, const char *msgid2, unsigned long int n);
extern char *libintl_dngettext(const char *domainname, const char *msgid1,
                               const char *msgid2, unsigned long int n);
extern char *libintl_dcngettext(const char *domainname, const char *msgid1,
                                const char *msgid2, unsigned long int n, int category);
extern char *libintl_textdomain(const char *domainname);
extern char *libintl_bindtextdomain(const char *domainname, const char *dirname);
extern char *libintl_bind_textdomain_codeset(const char *domainname, const char *codeset);

/* Locale wrapper */
extern char *libintl_setlocale(int category, const char *locale);

/* Version */
extern const char *libintl_version;

/* Convenience macros */
#define _(String) gettext(String)
#define N_(String) (String)

/* Context macros (GNU extension) */
#define pgettext(Msgctxt, Msgid) \
    pgettext_aux(NULL, Msgctxt "\004" Msgid, Msgid, 0)

#define npgettext(Msgctxt, Msgid1, Msgid2, N) \
    npgettext_aux(NULL, Msgctxt "\004" Msgid1, Msgid1, Msgid2, N, 0)

#ifdef __cplusplus
}
#endif

#endif /* _LIBINTL_H */

