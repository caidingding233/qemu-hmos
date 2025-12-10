/**
 * libintl - Minimal but complete implementation for HarmonyOS
 * 
 * This is a full implementation of the libintl API that provides
 * pass-through behavior (returns original strings without translation).
 * Suitable for embedded systems where full gettext is not needed.
 */

#include <stdlib.h>
#include <string.h>
#include <locale.h>

/* Domain management */
static char current_domain[256] = "messages";
static char domain_dir[1024] = "/usr/share/locale";
static char current_codeset[64] = "UTF-8";

/**
 * gettext - Get translated string
 * Returns the original message (no translation in this implementation)
 */
char *gettext(const char *msgid)
{
    return (char *)msgid;
}

/**
 * dgettext - Get translated string from specific domain
 */
char *dgettext(const char *domainname, const char *msgid)
{
    (void)domainname;
    return (char *)msgid;
}

/**
 * dcgettext - Get translated string from specific domain and category
 */
char *dcgettext(const char *domainname, const char *msgid, int category)
{
    (void)domainname;
    (void)category;
    return (char *)msgid;
}

/**
 * ngettext - Get plural form of translated string
 */
char *ngettext(const char *msgid1, const char *msgid2, unsigned long int n)
{
    return (char *)(n == 1 ? msgid1 : msgid2);
}

/**
 * dngettext - Get plural form from specific domain
 */
char *dngettext(const char *domainname, const char *msgid1, 
                const char *msgid2, unsigned long int n)
{
    (void)domainname;
    return (char *)(n == 1 ? msgid1 : msgid2);
}

/**
 * dcngettext - Get plural form from specific domain and category
 */
char *dcngettext(const char *domainname, const char *msgid1,
                 const char *msgid2, unsigned long int n, int category)
{
    (void)domainname;
    (void)category;
    return (char *)(n == 1 ? msgid1 : msgid2);
}

/**
 * textdomain - Set current message domain
 */
char *textdomain(const char *domainname)
{
    if (domainname != NULL && domainname[0] != '\0') {
        strncpy(current_domain, domainname, sizeof(current_domain) - 1);
        current_domain[sizeof(current_domain) - 1] = '\0';
    }
    return current_domain;
}

/**
 * bindtextdomain - Set directory for message catalogs
 */
char *bindtextdomain(const char *domainname, const char *dirname)
{
    (void)domainname;
    if (dirname != NULL) {
        strncpy(domain_dir, dirname, sizeof(domain_dir) - 1);
        domain_dir[sizeof(domain_dir) - 1] = '\0';
    }
    return domain_dir;
}

/**
 * bind_textdomain_codeset - Set encoding for message catalogs
 */
char *bind_textdomain_codeset(const char *domainname, const char *codeset)
{
    (void)domainname;
    if (codeset != NULL) {
        strncpy(current_codeset, codeset, sizeof(current_codeset) - 1);
        current_codeset[sizeof(current_codeset) - 1] = '\0';
    }
    return current_codeset;
}

/* GNU gettext compatibility - context versions */

/**
 * pgettext_aux - Get translated string with context (auxiliary)
 */
char *pgettext_aux(const char *domain, const char *msg_ctxt_id,
                   const char *msgid, int category)
{
    (void)domain;
    (void)msg_ctxt_id;
    (void)category;
    return (char *)msgid;
}

/**
 * npgettext_aux - Get plural translated string with context (auxiliary)
 */
char *npgettext_aux(const char *domain, const char *msg_ctxt_id,
                    const char *msgid1, const char *msgid2,
                    unsigned long int n, int category)
{
    (void)domain;
    (void)msg_ctxt_id;
    (void)category;
    return (char *)(n == 1 ? msgid1 : msgid2);
}

/* Locale functions that some gettext implementations provide */

/**
 * setlocale wrapper - just call the system setlocale
 */
char *libintl_setlocale(int category, const char *locale)
{
    return setlocale(category, locale);
}

/* Version information */
const char *libintl_version = "1.0.0-ohos";

/**
 * libintl_gettext - Alias for gettext
 */
char *libintl_gettext(const char *msgid)
{
    return gettext(msgid);
}

/**
 * libintl_dgettext - Alias for dgettext  
 */
char *libintl_dgettext(const char *domainname, const char *msgid)
{
    return dgettext(domainname, msgid);
}

/**
 * libintl_dcgettext - Alias for dcgettext
 */
char *libintl_dcgettext(const char *domainname, const char *msgid, int category)
{
    return dcgettext(domainname, msgid, category);
}

/**
 * libintl_ngettext - Alias for ngettext
 */
char *libintl_ngettext(const char *msgid1, const char *msgid2, unsigned long int n)
{
    return ngettext(msgid1, msgid2, n);
}

/**
 * libintl_dngettext - Alias for dngettext
 */
char *libintl_dngettext(const char *domainname, const char *msgid1,
                        const char *msgid2, unsigned long int n)
{
    return dngettext(domainname, msgid1, msgid2, n);
}

/**
 * libintl_dcngettext - Alias for dcngettext
 */
char *libintl_dcngettext(const char *domainname, const char *msgid1,
                         const char *msgid2, unsigned long int n, int category)
{
    return dcngettext(domainname, msgid1, msgid2, n, category);
}

/**
 * libintl_textdomain - Alias for textdomain
 */
char *libintl_textdomain(const char *domainname)
{
    return textdomain(domainname);
}

/**
 * libintl_bindtextdomain - Alias for bindtextdomain
 */
char *libintl_bindtextdomain(const char *domainname, const char *dirname)
{
    return bindtextdomain(domainname, dirname);
}

/**
 * libintl_bind_textdomain_codeset - Alias for bind_textdomain_codeset
 */
char *libintl_bind_textdomain_codeset(const char *domainname, const char *codeset)
{
    return bind_textdomain_codeset(domainname, codeset);
}

/* GLib uses g_libintl_ prefix - add aliases */

char *g_libintl_gettext(const char *msgid)
{
    return gettext(msgid);
}

char *g_libintl_dgettext(const char *domainname, const char *msgid)
{
    return dgettext(domainname, msgid);
}

char *g_libintl_dcgettext(const char *domainname, const char *msgid, int category)
{
    return dcgettext(domainname, msgid, category);
}

char *g_libintl_ngettext(const char *msgid1, const char *msgid2, unsigned long int n)
{
    return ngettext(msgid1, msgid2, n);
}

char *g_libintl_dngettext(const char *domainname, const char *msgid1,
                          const char *msgid2, unsigned long int n)
{
    return dngettext(domainname, msgid1, msgid2, n);
}

char *g_libintl_textdomain(const char *domainname)
{
    return textdomain(domainname);
}

char *g_libintl_bindtextdomain(const char *domainname, const char *dirname)
{
    return bindtextdomain(domainname, dirname);
}

char *g_libintl_bind_textdomain_codeset(const char *domainname, const char *codeset)
{
    return bind_textdomain_codeset(domainname, codeset);
}

