autoconf; exec ./configure $@
dnl
dnl Process this file with autoconf to produce a configure script
dnl
dnl Embed in generated ./configure script the following CVS info:
AC_REVISION($Revision$)dnl

dnl Setup autoconf
AC_PREREQ([2.53])
AC_INIT(RT, 3.8.HEAD, [rt-bugs@bestpractical.com])
AC_CONFIG_SRCDIR([lib/RT.pm.in])

dnl Extract RT version number components
AC_SUBST([rt_version_major],
	m4_bregexp(AC_PACKAGE_VERSION,[^\(\w+\)\.\(\w+\)\(\.\(\w+\)\)?],[\1]))
AC_SUBST([rt_version_minor],
	m4_bregexp(AC_PACKAGE_VERSION,[^\(\w+\)\.\(\w+\)\(\.\(\w+\)\)?],[\2]))
AC_SUBST([rt_version_patch],
	m4_bregexp(AC_PACKAGE_VERSION,[^\(\w+\)\.\(\w+\)\(\.\(\w+\)\)?],[\4]))
test "x$rt_version_major" = 'x' && rt_version_major=0
test "x$rt_version_minor" = 'x' && rt_version_minor=0
test "x$rt_version_patch" = 'x' && rt_version_patch=0

dnl Check for programs
AC_PROG_INSTALL
AC_PROG_AWK
AC_ARG_VAR([PERL],[Perl interpreter command])
AC_PATH_PROG([PERL], [perl], [not found])
if test "$PERL" = 'not found'; then
	AC_MSG_ERROR([cannot use $PACKAGE_NAME without perl])
fi


dnl WEB_HANDLER
AC_ARG_WITH(web-handler,
    AC_HELP_STRING([--with-web-handler=LIST],
	[comma separated list of web-handlers RT will be able to use.
         Default is fastcgi when modperl1, modperl2, fastcgi, standalone
         and speedycgi are valid. To succefuly run RT you need only one.
        ]),
    WEB_HANDLER=$withval,
    WEB_HANDLER=fastcgi)
my_web_handler_test=$($PERL -e 'print "ok" unless grep $_ !~ /^(modperl[12]|fastcgi|speedycgi|standalone)$/i, grep defined && length, split /\s*,\s*/, "$WEB_HANDLER"')
if test "$my_web_handler_test" != "ok"; then
	AC_MSG_ERROR([Only modperl1, modperl2, fastcgi, speedycgi and standalone are valid web-handlers])
fi
AC_SUBST(WEB_HANDLER)

dnl SPEED_BIN
AC_ARG_WITH(speedycgi,
	    AC_HELP_STRING([--with-speedycgi=/path/to/speedy],
	    		   [path to your speedycgi binary, if it exists]),
            SPEEDY_BIN=$withval,
            SPEEDY_BIN=/usr/local/bin/speedy) 
if test "$WEB_HANDLER" = 'speedycgi' -a ! -x "$SPEEDY_BIN"; then
	AC_MSG_ERROR([cannot find speedycgi binary])
fi
AC_SUBST(SPEEDY_BIN)

dnl Defaults paths for installation
AC_PREFIX_DEFAULT([/opt/rt3])
RT_ENABLE_LAYOUT


# ACRT_USER_EXISTS( users, variable, default )
# - users is a list of users [www apache www-docs]
#    from highest to lowest priority to high priority (i.e. first match)
# - variable is what you set with the result
#

AC_DEFUN([ACRT_USER_GUESS],
 [ 
   $2=$3
   for x in $1; do
    AC_MSG_CHECKING([if user $x exists]) 
     AS_IF([ $PERL -e"exit( defined getpwnam('$x') ? 0 : 1)" ],
           [ AC_MSG_RESULT([found]); $2=$x ; break],
           [ AC_MSG_RESULT([not found]) ])
   done
  ])
AC_DEFUN([ACRT_GROUP_GUESS],
 [ 
   $2=$3
   for x in $1; do
    AC_MSG_CHECKING([if group $x exists]) 
     AS_IF([ $PERL -e"exit( defined getgrnam('$x') ? 0 : 1)" ],
           [ AC_MSG_RESULT([found]); $2=$x ; break],
           [ AC_MSG_RESULT([not found]) ])
   done
  ])

dnl BIN_OWNER
AC_ARG_WITH(bin-owner,
	    AC_HELP_STRING([--with-bin-owner=OWNER],
	    		   [user that will own RT binaries (default root)]),
            BIN_OWNER=$withval,
            BIN_OWNER=root)
AC_SUBST(BIN_OWNER)

dnl LIBS_OWNER
AC_ARG_WITH(libs-owner,
	    AC_HELP_STRING([--with-libs-owner=OWNER],
	    		   [user that will own RT libraries (default root)]),
            LIBS_OWNER=$withval,
            LIBS_OWNER=root)
AC_SUBST(LIBS_OWNER)

dnl LIBS_GROUP
AC_ARG_WITH(libs-group,
	    AC_HELP_STRING([--with-libs-group=GROUP],
	    		   [group that will own RT binaries (default bin)]),
            LIBS_GROUP=$withval,
            LIBS_GROUP=bin)
AC_SUBST(LIBS_GROUP)

dnl DB_TYPE
AC_ARG_WITH(db-type,
	    AC_HELP_STRING([--with-db-type=TYPE],
	    		   [sort of database RT will use (default: mysql) (mysql, Pg, Oracle and SQLite are valid)]), 
            DB_TYPE=$withval,
            DB_TYPE=mysql)
if test "$DB_TYPE" != 'mysql' -a "$DB_TYPE" != 'Pg' -a "$DB_TYPE" != 'SQLite' -a "$DB_TYPE" != 'Oracle' -a "$DB_TYPE" != 'Informix' -a "$DB_TYPE" != 'Sybase' ; then
	AC_MSG_ERROR([Only Oracle, Pg, mysql and SQLite are valid db types])
fi
AC_SUBST(DB_TYPE)

dnl DATABASE_ENV_PREF
if test "$DB_TYPE" = 'Oracle'; then
	test "x$ORACLE_HOME" = 'x' && AC_MSG_ERROR([Please declare the ORACLE_HOME environment variable])
	DATABASE_ENV_PREF="\$ENV{'ORACLE_HOME'} = '$ORACLE_HOME';"
fi

dnl DATABASE_ENV_PREF
if test "$DB_TYPE" = 'Sybase'; then
	test "x$SYBASE" = 'x' && AC_MSG_ERROR([Please declare the SYBASE_HOME environment variable])
	DATABASE_ENV_PREF="\$ENV{'SYBASE'} = '$SYBASE';"
fi
AC_SUBST(DATABASE_ENV_PREF)

dnl DB_HOST
AC_ARG_WITH(db-host,
	    AC_HELP_STRING([--with-db-host=HOSTNAME],
	    		   [FQDN of database server (default: localhost)]),
            DB_HOST=$withval,
            DB_HOST=localhost)
AC_SUBST(DB_HOST)

dnl DB_PORT
AC_ARG_WITH(db-port,
	    AC_HELP_STRING([--with-db-port=PORT],
	    		   [port on which the database listens on]),
            DB_PORT=$withval,
            DB_PORT=)
AC_SUBST(DB_PORT)

dnl DB_RT_HOST
AC_ARG_WITH(db-rt-host,
	    AC_HELP_STRING([--with-db-rt-host=HOSTNAME],
	    		   [FQDN of RT server which talks to the database server (default: localhost)]),
            DB_RT_HOST=$withval,
            DB_RT_HOST=localhost)
AC_SUBST(DB_RT_HOST)

dnl DB_DATABASE_ADMIN
if test "$DB_TYPE" = "Pg" ; then
        DB_DBA="postgres"
else
        DB_DBA="root"
fi
AC_ARG_WITH(db-dba,
	    AC_HELP_STRING([--with-db-dba=DBA],
	    		   [name of database administrator (default: root or postgres)]),
            DB_DBA=$withval,
            DB_DBA="$DB_DBA")
AC_SUBST(DB_DBA)

dnl DB_DATABASE
AC_ARG_WITH(db-database,
	    AC_HELP_STRING([--with-db-database=DBNAME],
	    		   [name of the database to use (default: rt3)]),
            DB_DATABASE=$withval,
            DB_DATABASE=rt3)
AC_SUBST(DB_DATABASE)

dnl DB_RT_USER
AC_ARG_WITH(db-rt-user,
	    AC_HELP_STRING([--with-db-rt-user=DBUSER],
	    		   [name of database user (default: rt_user)]),
            DB_RT_USER=$withval,
            DB_RT_USER=rt_user)
AC_SUBST(DB_RT_USER)

dnl DB_RT_PASS
AC_ARG_WITH(db-rt-pass,
	    AC_HELP_STRING([--with-db-rt-pass=PASSWORD],
	    		   [password for database user (default: rt_pass)]),
            DB_RT_PASS=$withval,
            DB_RT_PASS=rt_pass)
AC_SUBST(DB_RT_PASS)

dnl WEB_USER
AC_ARG_WITH(web-user,
	    AC_HELP_STRING([--with-web-user=USER],
	    		   [user the web server runs as (default: www)]),
            WEB_USER=$withval,
            ACRT_USER_GUESS([www www-data apache httpd nobody],[WEB_USER],[www])
)
AC_SUBST(WEB_USER)

dnl WEB_GROUP
AC_ARG_WITH(web-group,
	    AC_HELP_STRING([--with-web-group=GROUP],
		           [group the web server runs as (default: www)]),
            WEB_GROUP=$withval,
            ACRT_GROUP_GUESS([www www-data apache httpd nogroup nobody],[WEB_GROUP], [www]))
AC_SUBST(WEB_GROUP)

dnl RTGROUP
AC_ARG_WITH(rt-group,
	    AC_HELP_STRING([--with-rt-group=GROUP],
	    		   [group to own all files (default: rt)]),
            RTGROUP=$withval,
            ACRT_GROUP_GUESS([rt3 rt $WEB_GROUP],[RTGROUP], [rt]))
AC_SUBST(RTGROUP)

dnl INSTALL AS ME
# XXX TODO: The command below to figure out the group brokenly relies on
# output order (and "id -gn" doesn't work on all platforms).
my_group=$(groups|cut -f1 -d' ')
my_user=${USER:-$LOGNAME}
AC_ARG_WITH(my-user-group,
            AC_HELP_STRING([--with-my-user-group],
                           [set all users and groups to current user/group]),
            RTGROUP=$my_group
            BIN_OWNER=$my_user
            LIBS_OWNER=$my_user
            LIBS_GROUP=$my_group
            WEB_USER=$my_user
            WEB_GROUP=$my_group)

# Test for valid database names
AS_IF([ test "$DB_TYPE" = "mysql" ],
      [ AC_MSG_CHECKING([if database name is valid])
          AS_IF([ echo $DB_DATABASE | $AWK '/-/ { exit 1 }' ],
                [ AC_MSG_RESULT([yes]) ],
                [ AC_MSG_ERROR([no.  database name ($DB_DATABASE) contains '-' which is not valid for mysql]) ]
               )
      ]
     )


dnl Set the value of apachectl
AC_ARG_WITH(apachectl,
            AC_HELP_STRING([--with-apachectl],
                           [instruct RT where to find your apachectl]),
            APACHECTL=$withval, 
            APACHECTL=`which apachectl`)
AC_SUBST(APACHECTL)

dnl RT's "maintainer mode"
AC_ARG_WITH(devel-mode,[],RT_DEVEL_MODE=$withval,RT_DEVEL_MODE="0")
AC_ARG_ENABLE(devel-mode,
            AC_HELP_STRING([--enable-devel-mode],
                           [Turn on development aids that might hurt you in production]),
            RT_DEVEL_MODE=$enableval,
            RT_DEVEL_MODE=$RT_DEVEL_MODE)
if test "$RT_DEVEL_MODE" = yes; then
        RT_DEVEL_MODE="1"
else
        RT_DEVEL_MODE="0"
fi
AC_SUBST(RT_DEVEL_MODE)

dnl RT's GraphViz dependency charts
AC_CHECK_LIB([graph],[aginitlib],RT_GRAPHVIZ="1")
AC_ARG_WITH(graphviz,[],RT_GRAPHVIZ=$withval)
AC_ARG_ENABLE(graphviz,
            AC_HELP_STRING([--enable-graphviz],
                           [Turns on support for RT's GraphViz dependency charts]),
            RT_GRAPHVIZ=$enableval)
if test "$RT_GRAPHVIZ" = yes; then
        RT_GRAPHVIZ="1"
else
        RT_GRAPHVIZ="0"
fi
AC_SUBST(RT_GRAPHVIZ)

dnl RT's GD pie and bar charts
AC_CHECK_PROG([RT_GD], [gdlib-config], "yes", "no")
AC_ARG_WITH(gd,[],RT_GD=$withval)
AC_ARG_ENABLE(gd,
            AC_HELP_STRING([--enable-gd],
                           [Turns on support for RT's GD pie and bar charts]),
            RT_GD=$enableval)
if test "$RT_GD" = yes; then
        RT_GD="1"
else
        RT_GD="0"
fi
AC_SUBST(RT_GD)

dnl RT's GPG support
AC_CHECK_PROG([RT_GPG], [gpg], "yes", "no")
AC_ARG_ENABLE(gpg,
            AC_HELP_STRING([--enable-gpg],
                           [Turns on GNU Privacy Guard (GPG) support]),
            RT_GPG=$enableval)
if test "$RT_GPG" = yes; then
        RT_GPG="1"
else
        RT_GPG="0"
fi
AC_SUBST(RT_GPG)


dnl This section maps the variable names this script 'natively' generates
dnl to their existing names. They should be removed from here as the .in
dnl files are changed to use the new names.

dnl version numbers
AC_SUBST(RT_VERSION_MAJOR,		${rt_version_major})
AC_SUBST(RT_VERSION_MINOR,		${rt_version_minor})
AC_SUBST(RT_VERSION_PATCH,		${rt_version_patch})

dnl layout paths
AC_SUBST([RT_PATH],			${exp_prefix})
AC_SUBST([RT_DOC_PATH],			${exp_manualdir})
AC_SUBST([RT_LOCAL_PATH],		${exp_customdir})
AC_SUBST([RT_LIB_PATH],			${exp_libdir})
AC_SUBST([RT_ETC_PATH],			${exp_sysconfdir})
AC_SUBST([CONFIG_FILE_PATH],		${exp_sysconfdir})
AC_SUBST([RT_BIN_PATH],			${exp_bindir})
AC_SUBST([RT_SBIN_PATH],		${exp_sbindir})
AC_SUBST([RT_VAR_PATH],			${exp_localstatedir})
AC_SUBST([RT_MAN_PATH],			${exp_mandir})
AC_SUBST([MASON_DATA_PATH],		${exp_masonstatedir})
AC_SUBST([MASON_SESSION_PATH],		${exp_sessionstatedir})
AC_SUBST([MASON_HTML_PATH],		${exp_htmldir})
AC_SUBST([LOCAL_ETC_PATH],		${exp_custometcdir})
AC_SUBST([MASON_LOCAL_HTML_PATH],	${exp_customhtmldir})
AC_SUBST([LOCAL_LEXICON_PATH],		${exp_customlexdir})
AC_SUBST([LOCAL_LIB_PATH],		${exp_customlibdir})
AC_SUBST([RT_LOG_PATH],			${exp_logfiledir})

if test ${exp_sysconfdir} = "etc"; then
AC_SUBST([RT_PATH_R],			${exp_prefix})
AC_SUBST([RT_DOC_PATH_R],			${exp_prefix}/${exp_manualdir})
AC_SUBST([RT_LOCAL_PATH_R],		${exp_prefix}/${exp_customdir})
AC_SUBST([RT_LIB_PATH_R],			${exp_prefix}/${exp_libdir})
AC_SUBST([RT_ETC_PATH_R],			${exp_prefix}/${exp_sysconfdir})
AC_SUBST([CONFIG_FILE_PATH_R],		${exp_prefix}/${exp_sysconfdir})
AC_SUBST([RT_BIN_PATH_R],			${exp_prefix}/${exp_bindir})
AC_SUBST([RT_SBIN_PATH_R],		${exp_prefix}/${exp_sbindir})
AC_SUBST([RT_VAR_PATH_R],			${exp_prefix}/${exp_localstatedir})
AC_SUBST([RT_MAN_PATH_R],			${exp_prefix}/${exp_mandir})
AC_SUBST([MASON_DATA_PATH_R],		${exp_prefix}/${exp_masonstatedir})
AC_SUBST([MASON_SESSION_PATH_R],		${exp_prefix}/${exp_sessionstatedir})
AC_SUBST([MASON_HTML_PATH_R],		${exp_prefix}/${exp_htmldir})
AC_SUBST([LOCAL_ETC_PATH_R],		${exp_prefix}/${exp_custometcdir})
AC_SUBST([MASON_LOCAL_HTML_PATH_R],	${exp_prefix}/${exp_customhtmldir})
AC_SUBST([LOCAL_LEXICON_PATH_R],		${exp_prefix}/${exp_customlexdir})
AC_SUBST([LOCAL_LIB_PATH_R],		${exp_prefix}/${exp_customlibdir})
AC_SUBST([RT_LOG_PATH_R],			${exp_prefix}/${exp_logfiledir})
else
AC_SUBST([RT_PATH_R],			${exp_prefix})
AC_SUBST([RT_DOC_PATH_R],			${exp_manualdir})
AC_SUBST([RT_LOCAL_PATH_R],		${exp_customdir})
AC_SUBST([RT_LIB_PATH_R],			${exp_libdir})
AC_SUBST([RT_ETC_PATH_R],			${exp_sysconfdir})
AC_SUBST([CONFIG_FILE_PATH_R],		${exp_sysconfdir})
AC_SUBST([RT_BIN_PATH_R],			${exp_bindir})
AC_SUBST([RT_SBIN_PATH_R],		${exp_sbindir})
AC_SUBST([RT_VAR_PATH_R],			${exp_localstatedir})
AC_SUBST([RT_MAN_PATH_R],			${exp_mandir})
AC_SUBST([MASON_DATA_PATH_R],		${exp_masonstatedir})
AC_SUBST([MASON_SESSION_PATH_R],		${exp_sessionstatedir})
AC_SUBST([MASON_HTML_PATH_R],		${exp_htmldir})
AC_SUBST([LOCAL_ETC_PATH_R],		${exp_custometcdir})
AC_SUBST([MASON_LOCAL_HTML_PATH_R],	${exp_customhtmldir})
AC_SUBST([LOCAL_LEXICON_PATH_R],		${exp_customlexdir})
AC_SUBST([LOCAL_LIB_PATH_R],		${exp_customlibdir})
AC_SUBST([RT_LOG_PATH_R],			${exp_logfiledir})

fi

dnl Configure the output files, and generate them.

dnl Binaries that should be +x
AC_CONFIG_FILES([
                 etc/upgrade/3.8-branded-queues-extension
                 etc/upgrade/3.8-ical-extension
                 sbin/rt-attributes-viewer
                 sbin/rt-dump-database
                 sbin/rt-setup-database
                 sbin/rt-test-dependencies
                 sbin/rt-email-digest
                 sbin/rt-email-dashboards
                 sbin/rt-clean-sessions
                 sbin/rt-shredder
                 sbin/rt-validator
                 sbin/rt-email-group-admin
                 sbin/rt-server
                 bin/mason_handler.fcgi
                 bin/mason_handler.scgi
                 bin/standalone_httpd
                 bin/rt-crontool
                 bin/rt-mailgate
                 bin/rt],
                [chmod ug+x $ac_file]
               )

dnl All other generated files
AC_CONFIG_FILES([
                 Makefile
                 etc/RT_Config.pm
                 lib/RT.pm
                 bin/mason_handler.svc
                 bin/webmux.pl],
               )
AC_OUTPUT
