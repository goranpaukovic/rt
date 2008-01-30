
use warnings;
use strict;

package RT::Dispatcher;

use Jifty::Dispatcher -base;

use RT;
RT->load_config;
use RT::Interface::Web;
use RT::Interface::Web::Handler;
RT::I18N->init();

before qr/.*/ => run {
    RT::init_system_objects();

};

before qr/.*/ => run {
    if ( int RT->config->get('AutoLogoff') ) {
        my $now = int( time / 60 );

        # XXX TODO 4.0 port this;
        my $last_update;
        if ( $last_update
            && ( $now - $last_update - RT->config->get('AutoLogoff') ) > 0 )
        {

            # clean up sessions, but we should leave the session id
        }

        # save session on each request when AutoLogoff is turned on
    }

};

before qr/.*/ => run {
    Jifty->web->new_action(
        moniker   => 'login',
        class     => 'Login',
        arguments => {
            email    => Jifty->web->request->arguments->{'user'},
            password => Jifty->web->request->arguments->{'pass'}
        }
        )->run
        if ( Jifty->web->request->arguments->{'user'}
        && Jifty->web->request->arguments->{'pass'} );
};

# XXX TODO XXX SECURITY RISK - this regex is WRONG AND UNSAFE
before qr'^/(?!login)' => run {
    tangent '/login'
        unless ( Jifty->web->current_user->id
        || Jifty->web->request->path =~ /NoAuth/i );
};

before qr/(.*)/ => run {
    my $path = Jifty->web->request->path;

    # This code canonicalize_s time inputs in hours into minutes
    # If it's a noauth file, don't ask for auth.

    # Set the proper encoding for the current Language handle
    #    content_type("text/html; charset=utf-8");

    return;

    # XXX TODO 4.0 implmeent self service smarts
    # If the user isn't privileged, they can only see SelfService
    unless ( Jifty->web->current_user->user_object
        && Jifty->web->current_user->user_object->privileged )
    {

        # if the user is trying to access a ticket, redirect them
        if ( $path =~ '^(/+)Ticket/Display.html' && get('id') ) {
            RT::Interface::Web::redirect( RT->config->get('WebURL')
                    . "SelfService/Display.html?id="
                    . get('id') );
        }

        # otherwise, drop the user at the SelfService default page
        elsif ( $path !~ '^(/+)SelfService/' ) {
            RT::Interface::Web::redirect(
                RT->config->get('WebURL') . "SelfService/" );
        }
    }

}

after qr/.*/ => run {
    RT::Interface::Web::Handler::cleanup_request();
};

# Backward compatibility with old RT URLs

before '/NoAuth/Logout.html' => run { redirect '/logout' };

1;