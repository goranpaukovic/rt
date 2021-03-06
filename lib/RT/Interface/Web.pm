# BEGIN BPS TAGGED BLOCK {{{
# 
# COPYRIGHT:
# 
# This software is Copyright (c) 1996-2009 Best Practical Solutions, LLC
#                                          <jesse@bestpractical.com>
# 
# (Except where explicitly superseded by other copyright notices)
# 
# 
# LICENSE:
# 
# This work is made available to you under the terms of Version 2 of
# the GNU General Public License. A copy of that license should have
# been provided with this software, but in any event can be snarfed
# from www.gnu.org.
# 
# This work is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301 or visit their web page on the internet at
# http://www.gnu.org/licenses/old-licenses/gpl-2.0.html.
# 
# 
# CONTRIBUTION SUBMISSION POLICY:
# 
# (The following paragraph is not intended to limit the rights granted
# to you to modify and distribute this software under the terms of
# the GNU General Public License and is only of importance to you if
# you choose to contribute your changes and enhancements to the
# community by submitting them to Best Practical Solutions, LLC.)
# 
# By intentionally submitting any modifications, corrections or
# derivatives to this work, or any other work intended for use with
# Request Tracker, to Best Practical Solutions, LLC, you confirm that
# you are the copyright holder for those contributions and you grant
# Best Practical Solutions,  LLC a nonexclusive, worldwide, irrevocable,
# royalty-free, perpetual, license to use, copy, create derivative
# works based on those contributions, and sublicense and distribute
# those contributions and any derivatives thereof.
# 
# END BPS TAGGED BLOCK }}}

## Portions Copyright 2000 Tobias Brox <tobix@fsck.com>

## This is a library of static subs to be used by the Mason web
## interface to RT


=head1 NAME

RT::Interface::Web


=cut


use strict;
use warnings;

package RT::Interface::Web;

use RT::SavedSearches;
use URI qw();
use Digest::MD5 ();


# {{{ EscapeUTF8

=head2 EscapeUTF8 SCALARREF

does a css-busting but minimalist escaping of whatever html you're passing in.

=cut

sub EscapeUTF8  {
    my $ref = shift;
    return unless defined $$ref;

    $$ref =~ s/&/&#38;/g;
    $$ref =~ s/</&lt;/g; 
    $$ref =~ s/>/&gt;/g;
    $$ref =~ s/\(/&#40;/g;
    $$ref =~ s/\)/&#41;/g;
    $$ref =~ s/"/&#34;/g;
    $$ref =~ s/'/&#39;/g;
}

# }}}

# {{{ EscapeURI

=head2 EscapeURI SCALARREF

Escapes URI component according to RFC2396

=cut

use Encode qw();
sub EscapeURI {
    my $ref = shift;
    return unless defined $$ref;

    use bytes;
    $$ref =~ s/([^a-zA-Z0-9_.!~*'()-])/uc sprintf("%%%02X", ord($1))/eg;
}

# }}}

# {{{ WebCanonicalizeInfo

=head2 WebCanonicalizeInfo();

Different web servers set different environmental varibles. This
function must return something suitable for REMOTE_USER. By default,
just downcase $ENV{'REMOTE_USER'}

=cut

sub WebCanonicalizeInfo {
    return $ENV{'REMOTE_USER'}? lc $ENV{'REMOTE_USER'}: $ENV{'REMOTE_USER'};
}

# }}}

# {{{ WebExternalAutoInfo

=head2 WebExternalAutoInfo($user);

Returns a hash of user attributes, used when WebExternalAuto is set.

=cut

sub WebExternalAutoInfo {
    my $user = shift;

    my %user_info;

    # default to making Privileged users, even if they specify
    # some other default Attributes
    if (!$RT::AutoCreate ||
        ( ref($RT::AutoCreate) && not exists $RT::AutoCreate->{Privileged})) {
        $user_info{'Privileged'} = 1;
    }

    if ($^O !~ /^(?:riscos|MacOS|MSWin32|dos|os2)$/) {
        # Populate fields with information from Unix /etc/passwd

        my ($comments, $realname) = (getpwnam($user))[5, 6];
        $user_info{'Comments'} = $comments if defined $comments;
        $user_info{'RealName'} = $realname if defined $realname;
    }
    elsif ($^O eq 'MSWin32' and eval 'use Net::AdminMisc; 1') {
        # Populate fields with information from NT domain controller
    }

    # and return the wad of stuff
    return {%user_info};
}

# }}}



=head2 Redirect URL

This routine ells the current user's browser to redirect to URL.  
Additionally, it unties the user's currently active session, helping to avoid 
A bug in Apache::Session 1.81 and earlier which clobbers sessions if we try to use 
a cached DBI statement handle twice at the same time.

=cut


sub Redirect {
    my $redir_to = shift;
    untie $HTML::Mason::Commands::session;
    my $uri = URI->new($redir_to);
    my $server_uri = URI->new( RT->Config->Get('WebURL') );

    # If the user is coming in via a non-canonical
    # hostname, don't redirect them to the canonical host,
    # it will just upset them (and invalidate their credentials)
    # don't do this if $RT::CanoniaclRedirectURLs is true
    if (   !RT->Config->Get('CanonicalizeRedirectURLs')
        && $uri->host eq $server_uri->host
        && $uri->port eq $server_uri->port )
    {
        if ( defined $ENV{HTTPS} and $ENV{'HTTPS'} eq 'on' ) {
            $uri->scheme('https');
        }
        else {
            $uri->scheme('http');
        }

        # [rt3.fsck.com #12716] Apache recommends use of $SERVER_HOST
        $uri->host( $ENV{'SERVER_HOST'} || $ENV{'HTTP_HOST'} );
        $uri->port( $ENV{'SERVER_PORT'} );
    }

    # not sure why, but on some systems without this call mason doesn't
    # set status to 302, but 200 instead and people see blank pages
    $HTML::Mason::Commands::r->status(302);

    # Perlbal expects a status message, but Mason's default redirect status 
    # doesn't provide one. See also rt.cpan.org #36689.
    $HTML::Mason::Commands::m->redirect($uri->canonical, "302 Found");

    $HTML::Mason::Commands::m->abort;
}


=head2 StaticFileHeaders 

Send the browser a few headers to try to get it to (somewhat agressively)
cache RT's static Javascript and CSS files.

This routine could really use _accurate_ heuristics. (XXX TODO)

=cut

sub StaticFileHeaders {
    my $date = RT::Date->new( $RT::SystemUser );

    # make cache public
    $HTML::Mason::Commands::r->headers_out->{'Cache-Control'} = 'max-age=259200, public';

    # Expire things in a month.
    $date->Set( Value => time + 30*24*60*60 );
    $HTML::Mason::Commands::r->headers_out->{'Expires'} = $date->RFC2616;

    # if we set 'Last-Modified' then browser request a comp using 'If-Modified-Since'
    # request, but we don't handle it and generate full reply again
    # Last modified at server start time
    # $date->Set( Value => $^T );
    # $HTML::Mason::Commands::r->headers_out->{'Last-Modified'} = $date->RFC2616;
}

=head2 SendStaticFile 

Takes a File => path and a Type => Content-type

If Type isn't provided and File is an image, it will
figure out a sane Content-type, otherwise it will
send application/octet-stream

Will set caching headers using StaticFileHeaders

=cut

sub SendStaticFile {
    my $self = shift;
    my %args = @_;
    my $file = $args{File};
    my $type = $args{Type};

    $self->StaticFileHeaders();

    unless ( $type ) {
        if ($file =~ /\.(gif|png|jpe?g)$/i) {
            $type = "image/$1";
            $type =~ s/jpg/jpeg/gi;
        }
        $type ||= "application/octet-stream";
    }
    $HTML::Mason::Commands::r->content_type($type);
    open my $fh, "<$file" or die "couldn't open file: $!";
    binmode($fh);
    {
        local $/ = \16384;
        $HTML::Mason::Commands::m->out($_) while (<$fh>);
        $HTML::Mason::Commands::m->flush_buffer;
    }
    close $fh;
}

sub StripContent {
    my %args    = @_;
    my $content = $args{Content};
    my $html    = ( ( $args{ContentType} || '' ) eq "text/html" );
    my $sigonly = $args{StripSignature};

    # Save us from undef warnings
    return '' unless defined $content;

    # Make the content have no 'weird' newlines in it
    $content =~ s/\r+\n/\n/g;

    # Filter empty content when type is text/html
    return '' if $html && $content =~ m{^\s*(?:<br[^>]*/?>)*\s*$}s;

    # If we aren't supposed to strip the sig, just bail now.
    return $content unless $sigonly;

    # Find the signature
    my $sig = $args{'CurrentUser'}->UserObj->Signature || '';
    $sig =~ s/^\s+//;
    $sig =~ s/\s+$//;

    # Check for plaintext sig
    return '' if not $html and $content =~ /^\s*(--)?\s*\Q$sig\E\s*$/;

    # Check for html-formatted sig
    RT::Interface::Web::EscapeUTF8( \$sig );
    return ''
        if $html
        and $content
        =~ m{^\s*(?:<p>)?\s*(--)?\s*<br[^>]*?/?>\s*\Q$sig\E\s*(?:</p>)?\s*$}s;

    # Pass it through
    return $content;
}


package HTML::Mason::Commands;

use vars qw/$r $m %session/;


# {{{ loc

=head2 loc ARRAY

loc is a nice clean global routine which calls $session{'CurrentUser'}->loc()
with whatever it's called with. If there is no $session{'CurrentUser'}, 
it creates a temporary user, so we have something to get a localisation handle
through

=cut

sub loc {

    if ($session{'CurrentUser'} && 
        UNIVERSAL::can($session{'CurrentUser'}, 'loc')){
        return($session{'CurrentUser'}->loc(@_));
    }
    elsif ( my $u = eval { RT::CurrentUser->new() } ) {
        return ($u->loc(@_));
    }
    else {
        # pathetic case -- SystemUser is gone.
        return $_[0];
    }
}

# }}}


# {{{ loc_fuzzy

=head2 loc_fuzzy STRING

loc_fuzzy is for handling localizations of messages that may already
contain interpolated variables, typically returned from libraries
outside RT's control.  It takes the message string and extracts the
variable array automatically by matching against the candidate entries
inside the lexicon file.

=cut

sub loc_fuzzy {
    my $msg  = shift;
    
    if ($session{'CurrentUser'} && 
        UNIVERSAL::can($session{'CurrentUser'}, 'loc')){
        return($session{'CurrentUser'}->loc_fuzzy($msg));
    }
    else  {
        my $u = RT::CurrentUser->new($RT::SystemUser->Id);
        return ($u->loc_fuzzy($msg));
    }
}

# }}}


# {{{ sub Abort
# Error - calls Error and aborts
sub Abort {
    my $why  = shift;
    my %args = @_;

    if ($session{'ErrorDocument'} && 
        $session{'ErrorDocumentType'}) {
        $r->content_type($session{'ErrorDocumentType'});
        $m->comp($session{'ErrorDocument'} , Why => $why, %args);
        $m->abort;
    } 
    else  {
        $m->comp("/Elements/Error" , Why => $why, %args);
        $m->abort;
    }
}

# }}}

# {{{ sub CreateTicket 

=head2 CreateTicket ARGS

Create a new ticket, using Mason's %ARGS.  returns @results.

=cut

sub CreateTicket {
    my %ARGS = (@_);

    my (@Actions);

    my $Ticket = new RT::Ticket( $session{'CurrentUser'} );

    my $Queue = new RT::Queue( $session{'CurrentUser'} );
    unless ( $Queue->Load( $ARGS{'Queue'} ) ) {
        Abort('Queue not found');
    }

    unless ( $Queue->CurrentUserHasRight('CreateTicket') ) {
        Abort('You have no permission to create tickets in that queue.');
    }

    my $due;
    if (defined $ARGS{'Due'} and $ARGS{'Due'} =~ /\S/) {
        $due = new RT::Date( $session{'CurrentUser'} );
        $due->Set( Format => 'unknown', Value => $ARGS{'Due'} );
    }
    my $starts;
    if (defined $ARGS{'Starts'} and $ARGS{'Starts'} =~ /\S/) {
        $starts = new RT::Date( $session{'CurrentUser'} );
        $starts->Set( Format => 'unknown', Value => $ARGS{'Starts'} );
    }

    my $sigless = RT::Interface::Web::StripContent(
        Content        => $ARGS{Content},
        ContentType    => $ARGS{ContentType},
        StripSignature => 1,
        CurrentUser    => $session{'CurrentUser'},
    );

    my $MIMEObj = MakeMIMEEntity(
        Subject             => $ARGS{'Subject'},
        From                => $ARGS{'From'},
        Cc                  => $ARGS{'Cc'},
        Body                => $sigless,
        Type                => $ARGS{'ContentType'},
    );

    if ( $ARGS{'Attachments'} ) {
        my $rv = $MIMEObj->make_multipart;
        $RT::Logger->error("Couldn't make multipart message")
            if !$rv || $rv !~ /^(?:DONE|ALREADY)$/;

        foreach ( values %{$ARGS{'Attachments'}} ) {
            unless ( $_ ) {
                $RT::Logger->error("Couldn't add empty attachemnt");
                next;
            }
            $MIMEObj->add_part($_);
        }
    }

    foreach my $argument (qw(Encrypt Sign)) {
        $MIMEObj->head->add(
            "X-RT-$argument" => $ARGS{ $argument }
        ) if defined $ARGS{ $argument };
    }

    my %create_args = (
        Type            => $ARGS{'Type'} || 'ticket',
        Queue           => $ARGS{'Queue'},
        Owner           => $ARGS{'Owner'},
        # note: name change
        Requestor       => $ARGS{'Requestors'},
        Cc              => $ARGS{'Cc'},
        AdminCc         => $ARGS{'AdminCc'},
        InitialPriority => $ARGS{'InitialPriority'},
        FinalPriority   => $ARGS{'FinalPriority'},
        TimeLeft        => $ARGS{'TimeLeft'},
        TimeEstimated   => $ARGS{'TimeEstimated'},
        TimeWorked      => $ARGS{'TimeWorked'},
        Subject         => $ARGS{'Subject'},
        Status          => $ARGS{'Status'},
        Due             => $due ? $due->ISO : undef,
        Starts          => $starts ? $starts->ISO : undef,
        MIMEObj         => $MIMEObj
    );

    my @temp_squelch;
    foreach my $type (qw(Requestor Cc AdminCc)) {
        push @temp_squelch, map $_->address, Email::Address->parse( $create_args{ $type } )
            if grep $_ eq $type || $_ eq ($type.'s'), @{ $ARGS{'SkipNotification'} || [] };

    }

    if ( @temp_squelch ) {
        require RT::Action::SendEmail;
        RT::Action::SendEmail->SquelchMailTo( RT::Action::SendEmail->SquelchMailTo, @temp_squelch );
    }

    if ( $ARGS{'AttachTickets'} ) {
        require RT::Action::SendEmail;
        RT::Action::SendEmail->AttachTickets(
            RT::Action::SendEmail->AttachTickets,
            ref $ARGS{'AttachTickets'}?
                @{ $ARGS{'AttachTickets'} }
                :( $ARGS{'AttachTickets'} )
        );
    }

    foreach my $arg (keys %ARGS) {
        next if $arg =~ /-(?:Magic|Category)$/;

        if ($arg =~ /^Object-RT::Transaction--CustomField-/) {
            $create_args{$arg} = $ARGS{$arg};
        }
        # Object-RT::Ticket--CustomField-3-Values
        elsif ( $arg =~ /^Object-RT::Ticket--CustomField-(\d+)/ ) {
            my $cfid = $1;

            my $cf = RT::CustomField->new( $session{'CurrentUser'} );
            $cf->Load( $cfid );
            unless ( $cf->id ) {
                $RT::Logger->error( "Couldn't load custom field #". $cfid );
                next;
            }

            if ( $arg =~ /-Upload$/ ) {
                $create_args{"CustomField-$cfid"} = _UploadedFile( $arg );
                next;
            }

            my $type = $cf->Type;

            my @values = ();
            if ( ref $ARGS{ $arg } eq 'ARRAY' ) {
                @values = @{ $ARGS{ $arg } };
            } elsif ( $type =~ /text/i ) {
                @values = ($ARGS{ $arg });
            } else {
                no warnings 'uninitialized';
                @values = split /\r*\n/, $ARGS{ $arg };
            }
            @values = grep length,
                map {
                    s/\r+\n/\n/g;
                    s/^\s+//;
                    s/\s+$//;
                    $_;
                }
                grep defined, @values;

            $create_args{"CustomField-$cfid"} = \@values;
        }
    }

    # turn new link lists into arrays, and pass in the proper arguments
    my %map = (
        'new-DependsOn' => 'DependsOn',
        'DependsOn-new' => 'DependedOnBy',
        'new-MemberOf'  => 'Parents',
        'MemberOf-new'  => 'Children',
        'new-RefersTo'  => 'RefersTo',
        'RefersTo-new'  => 'ReferredToBy',
    );
    foreach my $key ( keys %map ) {
        next unless $ARGS{ $key };
        $create_args{ $map{ $key } } = [ grep $_, split ' ', $ARGS{ $key } ];
        
    }
 
    my ( $id, $Trans, $ErrMsg ) = $Ticket->Create(%create_args);
    unless ( $id ) {
        Abort($ErrMsg);
    }

    push ( @Actions, split("\n", $ErrMsg) );
    unless ( $Ticket->CurrentUserHasRight('ShowTicket') ) {
        Abort( "No permission to view newly created ticket #"
            . $Ticket->id . "." );
    }
    return ( $Ticket, @Actions );

}

# }}}

# {{{ sub LoadTicket - loads a ticket

=head2  LoadTicket id

Takes a ticket id as its only variable. if it's handed an array, it takes
the first value.

Returns an RT::Ticket object as the current user.

=cut

sub LoadTicket {
    my $id = shift;

    if ( ref($id) eq "ARRAY" ) {
        $id = $id->[0];
    }

    unless ($id) {
        Abort("No ticket specified");
    }

    my $Ticket = RT::Ticket->new( $session{'CurrentUser'} );
    $Ticket->Load($id);
    unless ( $Ticket->id ) {
        Abort("Could not load ticket $id");
    }
    return $Ticket;
}

# }}}

# {{{ sub ProcessUpdateMessage

=head2 ProcessUpdateMessage

Takes paramhash with fields ARGSRef, TicketObj and SkipSignatureOnly.

Don't write message if it only contains current user's signature and
SkipSignatureOnly argument is true. Function anyway adds attachments
and updates time worked field even if skips message. The default value
is true.

=cut

sub ProcessUpdateMessage {

    my %args = (
        ARGSRef           => undef,
        TicketObj         => undef,
        SkipSignatureOnly => 1,
        @_
    );

    if ( $args{ARGSRef}->{'UpdateAttachments'}
        && !keys %{ $args{ARGSRef}->{'UpdateAttachments'} } )
    {
        delete $args{ARGSRef}->{'UpdateAttachments'};
    }

    # Strip the signature
    $args{ARGSRef}->{UpdateContent} = RT::Interface::Web::StripContent(
        Content        => $args{ARGSRef}->{UpdateContent},
        ContentType    => $args{ARGSRef}->{UpdateContentType},
        StripSignature => $args{SkipSignatureOnly},
        CurrentUser    => $args{'TicketObj'}->CurrentUser,
    );

    # If, after stripping the signature, we have no message, move the
    # UpdateTimeWorked into adjusted TimeWorked, so that a later
    # ProcessBasics can deal -- then bail out.
    if ( not $args{ARGSRef}->{'UpdateAttachments'}
        and not length $args{ARGSRef}->{'UpdateContent'} )
    {
        if ( $args{ARGSRef}->{'UpdateTimeWorked'} ) {
            $args{ARGSRef}->{TimeWorked} = $args{TicketObj}->TimeWorked
                + delete $args{ARGSRef}->{'UpdateTimeWorked'};
        }
        return;
    }

    if ( $args{ARGSRef}->{'UpdateSubject'} eq $args{'TicketObj'}->Subject ) {
        $args{ARGSRef}->{'UpdateSubject'} = undef;
    }

    my $Message = MakeMIMEEntity(
        Subject => $args{ARGSRef}->{'UpdateSubject'},
        Body    => $args{ARGSRef}->{'UpdateContent'},
        Type    => $args{ARGSRef}->{'UpdateContentType'},
    );

    $Message->head->add(
        'Message-ID' => RT::Interface::Email::GenMessageId(
            Ticket => $args{'TicketObj'},
        )
    );
    my $old_txn = RT::Transaction->new( $session{'CurrentUser'} );
    if ( $args{ARGSRef}->{'QuoteTransaction'} ) {
        $old_txn->Load( $args{ARGSRef}->{'QuoteTransaction'} );
    } else {
        $old_txn = $args{TicketObj}->Transactions->First();
    }

    if ( my $msg = $old_txn->Message->First ) {
        RT::Interface::Email::SetInReplyTo(
            Message   => $Message,
            InReplyTo => $msg
        );
    }

    if ( $args{ARGSRef}->{'UpdateAttachments'} ) {
        $Message->make_multipart;
        $Message->add_part($_)
            foreach values %{ $args{ARGSRef}->{'UpdateAttachments'} };
    }

    if ( $args{ARGSRef}->{'AttachTickets'} ) {
        require RT::Action::SendEmail;
        RT::Action::SendEmail->AttachTickets(
            RT::Action::SendEmail->AttachTickets,
            ref $args{ARGSRef}->{'AttachTickets'}
            ? @{ $args{ARGSRef}->{'AttachTickets'} }
            : ( $args{ARGSRef}->{'AttachTickets'} )
        );
    }

    my $bcc = $args{ARGSRef}->{'UpdateBcc'};
    my $cc  = $args{ARGSRef}->{'UpdateCc'};

    my %message_args = (
        CcMessageTo  => $cc,
        BccMessageTo => $bcc,
        Sign         => $args{ARGSRef}->{'Sign'},
        Encrypt      => $args{ARGSRef}->{'Encrypt'},
        MIMEObj      => $Message,
        TimeTaken    => $args{ARGSRef}->{'UpdateTimeWorked'}
    );

    unless ( $args{'ARGSRef'}->{'UpdateIgnoreAddressCheckboxes'} ) {
        foreach my $key ( keys %{ $args{ARGSRef} } ) {
            next unless $key =~ /^Update(Cc|Bcc)-(.*)$/;

            my $var   = ucfirst($1) . 'MessageTo';
            my $value = $2;
            if ( $message_args{$var} ) {
                $message_args{$var} .= ", $value";
            } else {
                $message_args{$var} = $value;
            }
        }
    }

    my @results;
    if ( $args{ARGSRef}->{'UpdateType'} =~ /^(private|public)$/ ) {
        my ( $Transaction, $Description, $Object )
            = $args{TicketObj}->Comment(%message_args);
        push( @results, $Description );
        $Object->UpdateCustomFields( ARGSRef => $args{ARGSRef} ) if $Object;
    } elsif ( $args{ARGSRef}->{'UpdateType'} eq 'response' ) {
        my ( $Transaction, $Description, $Object )
            = $args{TicketObj}->Correspond(%message_args);
        push( @results, $Description );
        $Object->UpdateCustomFields( ARGSRef => $args{ARGSRef} ) if $Object;
    } else {
        push( @results,
            loc("Update type was neither correspondence nor comment.") . " "
                . loc("Update not recorded.") );
    }
    return @results;
}

# }}}

# {{{ sub MakeMIMEEntity

=head2 MakeMIMEEntity PARAMHASH

Takes a paramhash Subject, Body and AttachmentFieldName.

Also takes Form, Cc and Type as optional paramhash keys.

  Returns a MIME::Entity.

=cut

sub MakeMIMEEntity {

    #TODO document what else this takes.
    my %args = (
        Subject             => undef,
        From                => undef,
        Cc                  => undef,
        Body                => undef,
        AttachmentFieldName => undef,
        Type                => undef,
        @_,
    );
    my $Message = MIME::Entity->build(
        Type    => 'multipart/mixed',
        Subject => $args{'Subject'} || "",
        From    => $args{'From'},
        Cc      => $args{'Cc'},        
    );

    if ( defined $args{'Body'} && length $args{'Body'} ) {
        # Make the update content have no 'weird' newlines in it
        $args{'Body'} =~ s/\r\n/\n/gs;

        # MIME::Head is not happy in utf-8 domain.  This only happens
        # when processing an incoming email (so far observed).
        no utf8;
        use bytes;
        $Message->attach(
            Type    => $args{'Type'} || 'text/plain',
            Charset => 'UTF-8',
            Data    => $args{'Body'},
        );
    }

    if ( $args{'AttachmentFieldName'} ) {

        my $cgi_object = $m->cgi_object;

        if ( my $filehandle = $cgi_object->upload( $args{'AttachmentFieldName'} ) ) {

            my (@content,$buffer);
            while ( my $bytesread = read( $filehandle, $buffer, 4096 ) ) {
                push @content, $buffer;
            }

            my $uploadinfo = $cgi_object->uploadInfo($filehandle);

            # Prefer the cached name first over CGI.pm stringification.
            my $filename = $RT::Mason::CGI::Filename;
            $filename = "$filehandle" unless defined($filename);
            $filename = Encode::decode_utf8($filename);
            $filename =~ s{^.*[\\/]}{};

            $Message->attach(
                Type     => $uploadinfo->{'Content-Type'},
                Filename => $filename,
                Data     => \@content,
            );
            if ( !$args{'Subject'} && !(defined $args{'Body'} && length $args{'Body'}) ) {
                $Message->head->set( 'Subject' => $filename );
            }
        }
    }

    $Message->make_singlepart;
    RT::I18N::SetMIMEEntityToUTF8($Message); # convert text parts into utf-8

    return ($Message);

}

# }}}

# {{{ sub ParseDateToISO

=head2 ParseDateToISO

Takes a date in an arbitrary format.
Returns an ISO date and time in GMT

=cut

sub ParseDateToISO {
    my $date = shift;

    my $date_obj = RT::Date->new($session{'CurrentUser'});
    $date_obj->Set(
        Format => 'unknown',
        Value  => $date
    );
    return ( $date_obj->ISO );
}

# }}}

# {{{ sub ProcessACLChanges

sub ProcessACLChanges {
    my $ARGSref = shift;

    #XXX: why don't we get ARGSref like in other Process* subs?

    my @results;

    foreach my $arg (keys %$ARGSref) {
        next unless ( $arg =~ /^(GrantRight|RevokeRight)-(\d+)-(.+?)-(\d+)$/ );

        my ($method, $principal_id, $object_type, $object_id) = ($1, $2, $3, $4);

        my @rights;
        if ( UNIVERSAL::isa( $ARGSref->{$arg}, 'ARRAY' ) ) {
            @rights = @{$ARGSref->{$arg}}
        } else {
            @rights = $ARGSref->{$arg};
        }
        @rights = grep $_, @rights;
        next unless @rights;

        my $principal = RT::Principal->new( $session{'CurrentUser'} );
        $principal->Load( $principal_id );

        my $obj;
        if ($object_type eq 'RT::System') {
            $obj = $RT::System;
        } elsif ($RT::ACE::OBJECT_TYPES{$object_type}) {
            $obj = $object_type->new($session{'CurrentUser'});
            $obj->Load($object_id);
            unless( $obj->id ) {
                $RT::Logger->error("couldn't load $object_type #$object_id");
                next;
            }
        } else {
            $RT::Logger->error("object type '$object_type' is incorrect");
            push (@results, loc("System Error"). ': '.
                            loc("Rights could not be granted for [_1]", $object_type));
            next;
        }

        foreach my $right (@rights) {
            my ($val, $msg) = $principal->$method(Object => $obj, Right => $right);
            push (@results, $msg);
        }
    }

    return (@results);
}

# }}}

# {{{ sub UpdateRecordObj

=head2 UpdateRecordObj ( ARGSRef => \%ARGS, Object => RT::Record, AttributesRef => \@attribs)

@attribs is a list of ticket fields to check and update if they differ from the  B<Object>'s current values. ARGSRef is a ref to HTML::Mason's %ARGS.

Returns an array of success/failure messages

=cut

sub UpdateRecordObject {
    my %args = (
        ARGSRef       => undef,
        AttributesRef => undef,
        Object        => undef,
        AttributePrefix => undef,
        @_
    );

    my $Object = $args{'Object'};
    my @results = $Object->Update(
        AttributesRef   => $args{'AttributesRef'},
        ARGSRef         => $args{'ARGSRef'},
        AttributePrefix => $args{'AttributePrefix'},
    );

    return (@results);
}

# }}}

# {{{ Sub ProcessCustomFieldUpdates

sub ProcessCustomFieldUpdates {
    my %args = (
        CustomFieldObj => undef,
        ARGSRef        => undef,
        @_
    );

    my $Object  = $args{'CustomFieldObj'};
    my $ARGSRef = $args{'ARGSRef'};

    my @attribs = qw(Name Type Description Queue SortOrder);
    my @results = UpdateRecordObject(
        AttributesRef => \@attribs,
        Object        => $Object,
        ARGSRef       => $ARGSRef
    );

    my $prefix = "CustomField-" . $Object->Id;
    if ( $ARGSRef->{ "$prefix-AddValue-Name" } ) {
        my ( $addval, $addmsg ) = $Object->AddValue(
            Name        => $ARGSRef->{ "$prefix-AddValue-Name" },
            Description => $ARGSRef->{ "$prefix-AddValue-Description" },
            SortOrder   => $ARGSRef->{ "$prefix-AddValue-SortOrder" },
        );
        push ( @results, $addmsg );
    }

    my @delete_values = (
        ref $ARGSRef->{ "$prefix-DeleteValue" } eq 'ARRAY' )
      ? @{ $ARGSRef->{ "$prefix-DeleteValue" } }
      : ( $ARGSRef->{ "$prefix-DeleteValue" } );

    foreach my $id (@delete_values) {
        next unless defined $id;
        my ( $err, $msg ) = $Object->DeleteValue($id);
        push ( @results, $msg );
    }

    my $vals = $Object->Values();
    while (my $cfv = $vals->Next()) {
        if (my $so = $ARGSRef->{ "$prefix-SortOrder" . $cfv->Id }) {
            if ($cfv->SortOrder != $so) {
                my ( $err, $msg ) = $cfv->SetSortOrder($so);
                push ( @results, $msg );
            }
        }
    }

    return (@results);
}

# }}}

# {{{ sub ProcessTicketBasics

=head2 ProcessTicketBasics ( TicketObj => $Ticket, ARGSRef => \%ARGS );

Returns an array of results messages.

=cut

sub ProcessTicketBasics {

    my %args = (
        TicketObj => undef,
        ARGSRef   => undef,
        @_
    );

    my $TicketObj = $args{'TicketObj'};
    my $ARGSRef   = $args{'ARGSRef'};

    # {{{ Set basic fields 
    my @attribs = qw(
      Subject
      FinalPriority
      Priority
      TimeEstimated
      TimeWorked
      TimeLeft
      Type
      Status
      Queue
    );


    if ( $ARGSRef->{'Queue'} and ( $ARGSRef->{'Queue'} !~ /^(\d+)$/ ) ) {
        my $tempqueue = RT::Queue->new($RT::SystemUser);
        $tempqueue->Load( $ARGSRef->{'Queue'} );
        if ( $tempqueue->id ) {
            $ARGSRef->{'Queue'} = $tempqueue->id;
        }
    }


    # Status isn't a field that can be set to a null value.
    # RT core complains if you try
    delete $ARGSRef->{'Status'} unless $ARGSRef->{'Status'};
    
    my @results = UpdateRecordObject(
        AttributesRef => \@attribs,
        Object        => $TicketObj,
        ARGSRef       => $ARGSRef,
    );

    # We special case owner changing, so we can use ForceOwnerChange
    if ( $ARGSRef->{'Owner'} && ( $TicketObj->Owner != $ARGSRef->{'Owner'} ) ) {
        my ($ChownType);
        if ( $ARGSRef->{'ForceOwnerChange'} ) {
            $ChownType = "Force";
        }
        else {
            $ChownType = "Give";
        }

        my ( $val, $msg ) =
            $TicketObj->SetOwner( $ARGSRef->{'Owner'}, $ChownType );
        push ( @results, $msg );
    }

    # }}}

    return (@results);
}

# }}}

sub ProcessTicketCustomFieldUpdates {
    my %args = @_;
    $args{'Object'} = delete $args{'TicketObj'};
    my $ARGSRef = { %{ $args{'ARGSRef'} } };

    # Build up a list of objects that we want to work with
    my %custom_fields_to_mod;
    foreach my $arg ( keys %$ARGSRef ) {
        if ( $arg =~ /^Ticket-(\d+-.*)/) {
            $ARGSRef->{"Object-RT::Ticket-$1"} = delete $ARGSRef->{$arg};
        }
        elsif ( $arg =~ /^CustomField-(\d+-.*)/) {
            $ARGSRef->{"Object-RT::Ticket--$1"} = delete $ARGSRef->{$arg};
        }
    }

    return ProcessObjectCustomFieldUpdates(%args, ARGSRef => $ARGSRef);
}

sub ProcessObjectCustomFieldUpdates {
    my %args = @_;
    my $ARGSRef = $args{'ARGSRef'};
    my @results;

    # Build up a list of objects that we want to work with
    my %custom_fields_to_mod;
    foreach my $arg ( keys %$ARGSRef ) {
        # format: Object-<object class>-<object id>-CustomField-<CF id>-<commands>
        next unless $arg =~ /^Object-([\w:]+)-(\d*)-CustomField-(\d+)-(.*)$/;

        # For each of those objects, find out what custom fields we want to work with.
        $custom_fields_to_mod{ $1 }{ $2 || 0 }{ $3 }{ $4 } = $ARGSRef->{ $arg };
    }

    # For each of those objects
    foreach my $class ( keys %custom_fields_to_mod ) {
        foreach my $id ( keys %{$custom_fields_to_mod{$class}} ) {
            my $Object = $args{'Object'};
            $Object = $class->new( $session{'CurrentUser'} )
                unless $Object && ref $Object eq $class;

            $Object->Load( $id ) unless ($Object->id || 0) == $id;
            unless ( $Object->id ) {
                $RT::Logger->warning("Couldn't load object $class #$id");
                next;
            }

            foreach my $cf ( keys %{ $custom_fields_to_mod{ $class }{ $id } } ) {
                my $CustomFieldObj = RT::CustomField->new( $session{'CurrentUser'} );
                $CustomFieldObj->LoadById( $cf );
                unless ( $CustomFieldObj->id ) {
                    $RT::Logger->warning("Couldn't load custom field #$cf");
                    next;
                }
                push @results, _ProcessObjectCustomFieldUpdates(
                    Prefix      => "Object-$class-$id-CustomField-$cf-",
                    Object      => $Object,
                    CustomField => $CustomFieldObj,
                    ARGS        => $custom_fields_to_mod{$class}{$id}{$cf},
                );
            }
        }
    }
    return @results;
}

sub _ProcessObjectCustomFieldUpdates {
    my %args = @_;
    my $cf = $args{'CustomField'};
    my $cf_type = $cf->Type;

    # Remove blank Values since the magic field will take care of this. Sometimes
    # the browser gives you a blank value which causes CFs to be processed twice
    if ( defined $args{'ARGS'}->{'Values'}
        && !length $args{'ARGS'}->{'Values'}
        && $args{'ARGS'}->{'Values-Magic'}
    ) {
        delete $args{'ARGS'}->{'Values'};
    }

    my @results;
    foreach my $arg ( keys %{ $args{'ARGS'} } ) {
        # skip category argument
        next if $arg eq 'Category';

        # since http won't pass in a form element with a null value, we need
        # to fake it
        if ( $arg eq 'Values-Magic' ) {
            # We don't care about the magic, if there's really a values element;
            next if defined $args{'ARGS'}->{'Value'} && length $args{'ARGS'}->{'Value'};
            next if defined $args{'ARGS'}->{'Values'} && length $args{'ARGS'}->{'Values'};

            # "Empty" values does not mean anything for Image and Binary fields
            next if $cf_type =~ /^(?:Image|Binary)$/;

            $arg = 'Values';
            $args{'ARGS'}->{'Values'} = undef;
        }

        my @values = ();
        if ( ref $args{'ARGS'}->{ $arg } eq 'ARRAY' ) {
            @values = @{ $args{'ARGS'}->{$arg} };
        } elsif ( $cf_type =~ /text/i ) { # Both Text and Wikitext
            @values = ($args{'ARGS'}->{$arg});
        } else {
            @values = split /\r*\n/, $args{'ARGS'}->{ $arg }
                if defined $args{'ARGS'}->{ $arg };
        }
        @values = grep length,
            map {
                s/\r+\n/\n/g;
                s/^\s+//;
                s/\s+$//;
                $_;
            }
            grep defined, @values;
        
        if ( $arg eq 'AddValue' || $arg eq 'Value' ) {
            foreach my $value (@values) {
                my ( $val, $msg ) = $args{'Object'}->AddCustomFieldValue(
                    Field => $cf->id,
                    Value => $value
                );
                push ( @results, $msg );
            }
        }
        elsif ( $arg eq 'Upload' ) {
            my $value_hash = _UploadedFile( $args{'Prefix'} . $arg ) or next;
            my ( $val, $msg ) = $args{'Object'}->AddCustomFieldValue(
                %$value_hash,
                Field => $cf,
            );
            push ( @results, $msg );
        }
        elsif ( $arg eq 'DeleteValues' ) {
            foreach my $value ( @values ) {
                my ( $val, $msg ) = $args{'Object'}->DeleteCustomFieldValue(
                    Field => $cf,
                    Value => $value,
                );
                push ( @results, $msg );
            }
        }
        elsif ( $arg eq 'DeleteValueIds' ) {
            foreach my $value ( @values ) {
                my ( $val, $msg ) = $args{'Object'}->DeleteCustomFieldValue(
                    Field   => $cf,
                    ValueId => $value,
                );
                push ( @results, $msg );
            }
        }
        elsif ( $arg eq 'Values' && !$cf->Repeated ) {
            my $cf_values = $args{'Object'}->CustomFieldValues( $cf->id );

            my %values_hash;
            foreach my $value ( @values ) {
                if ( my $entry = $cf_values->HasEntry( $value ) ) {
                    $values_hash{ $entry->id } = 1;
                    next;
                }

                my ( $val, $msg ) = $args{'Object'}->AddCustomFieldValue(
                    Field => $cf,
                    Value => $value
                );
                push ( @results, $msg );
                $values_hash{ $val } = 1 if $val;
            }

            $cf_values->RedoSearch;
            while ( my $cf_value = $cf_values->Next ) {
                next if $values_hash{ $cf_value->id };

                my ( $val, $msg ) = $args{'Object'}->DeleteCustomFieldValue(
                    Field => $cf,
                    ValueId => $cf_value->id
                );
                push ( @results, $msg);
            }
        }
        elsif ( $arg eq 'Values' ) {
            my $cf_values = $args{'Object'}->CustomFieldValues( $cf->id );

            # keep everything up to the point of difference, delete the rest
            my $delete_flag;
            foreach my $old_cf (@{$cf_values->ItemsArrayRef}) {
                if (!$delete_flag and @values and $old_cf->Content eq $values[0]) {
                    shift @values;
                    next;
                }

                $delete_flag ||= 1;
                $old_cf->Delete;
            }

            # now add/replace extra things, if any
            foreach my $value ( @values ) {
                my ( $val, $msg ) = $args{'Object'}->AddCustomFieldValue(
                    Field => $cf,
                    Value => $value
                );
                push ( @results, $msg );
            }
        }
        else {
            push ( @results,
                loc("User asked for an unknown update type for custom field [_1] for [_2] object #[_3]",
                $cf->Name, ref $args{'Object'}, $args{'Object'}->id )
            );
        }
    }
    return @results;
}

# {{{ sub ProcessTicketWatchers

=head2 ProcessTicketWatchers ( TicketObj => $Ticket, ARGSRef => \%ARGS );

Returns an array of results messages.

=cut

sub ProcessTicketWatchers {
    my %args = (
        TicketObj => undef,
        ARGSRef   => undef,
        @_
    );
    my (@results);

    my $Ticket  = $args{'TicketObj'};
    my $ARGSRef = $args{'ARGSRef'};

    # Munge watchers

    foreach my $key ( keys %$ARGSRef ) {

        # Delete deletable watchers
        if ( $key =~ /^Ticket-DeleteWatcher-Type-(.*)-Principal-(\d+)$/ ) {
            my ( $code, $msg ) = $Ticket->DeleteWatcher(
                PrincipalId => $2,
                Type        => $1
            );
            push @results, $msg;
        }

        # Delete watchers in the simple style demanded by the bulk manipulator
        elsif ( $key =~ /^Delete(Requestor|Cc|AdminCc)$/ ) {
            my ( $code, $msg ) = $Ticket->DeleteWatcher(
                Email => $ARGSRef->{$key},
                Type  => $1
            );
            push @results, $msg;
        }

        # Add new wathchers by email address
        elsif ( ( $ARGSRef->{$key} || '' ) =~ /^(?:AdminCc|Cc|Requestor)$/
            and $key =~ /^WatcherTypeEmail(\d*)$/ )
        {

            #They're in this order because otherwise $1 gets clobbered :/
            my ( $code, $msg ) = $Ticket->AddWatcher(
                Type  => $ARGSRef->{$key},
                Email => $ARGSRef->{ "WatcherAddressEmail" . $1 }
            );
            push @results, $msg;
        }

        #Add requestors in the simple style demanded by the bulk manipulator
        elsif ( $key =~ /^Add(Requestor|Cc|AdminCc)$/ ) {
            my ( $code, $msg ) = $Ticket->AddWatcher(
                Type  => $1,
                Email => $ARGSRef->{$key}
            );
            push @results, $msg;
        }

        # Add new  watchers by owner
        elsif ( $key =~ /^Ticket-AddWatcher-Principal-(\d*)$/ ) {
            my $principal_id = $1;
            my $form = $ARGSRef->{$key};
            foreach my $value ( ref($form) ? @{$form} : ($form) ) {
                next unless $value =~ /^(?:AdminCc|Cc|Requestor)$/i;

                my ( $code, $msg ) = $Ticket->AddWatcher(
                    Type        => $value,
                    PrincipalId => $principal_id
                );
                push @results, $msg;
            }
        }

    }
    return (@results);
}

# }}}

# {{{ sub ProcessTicketDates

=head2 ProcessTicketDates ( TicketObj => $Ticket, ARGSRef => \%ARGS );

Returns an array of results messages.

=cut

sub ProcessTicketDates {
    my %args = (
        TicketObj => undef,
        ARGSRef   => undef,
        @_
    );

    my $Ticket  = $args{'TicketObj'};
    my $ARGSRef = $args{'ARGSRef'};

    my (@results);

    # {{{ Set date fields
    my @date_fields = qw(
      Told
      Resolved
      Starts
      Started
      Due
    );

    #Run through each field in this list. update the value if apropriate
    foreach my $field (@date_fields) {
        next unless exists $ARGSRef->{ $field . '_Date' };
        next if $ARGSRef->{ $field . '_Date' } eq '';
    
        my ( $code, $msg );

        my $DateObj = RT::Date->new( $session{'CurrentUser'} );
        $DateObj->Set(
            Format => 'unknown',
            Value  => $ARGSRef->{ $field . '_Date' }
        );

        my $obj = $field . "Obj";
        if ( ( defined $DateObj->Unix )
            and ( $DateObj->Unix != $Ticket->$obj()->Unix() ) )
        {
            my $method = "Set$field";
            my ( $code, $msg ) = $Ticket->$method( $DateObj->ISO );
            push @results, "$msg";
        }
    }

    # }}}
    return (@results);
}

# }}}

# {{{ sub ProcessTicketLinks

=head2 ProcessTicketLinks ( TicketObj => $Ticket, ARGSRef => \%ARGS );

Returns an array of results messages.

=cut

sub ProcessTicketLinks {
    my %args = ( TicketObj => undef,
                 ARGSRef   => undef,
                 @_ );

    my $Ticket  = $args{'TicketObj'};
    my $ARGSRef = $args{'ARGSRef'};


    my (@results) = ProcessRecordLinks(RecordObj => $Ticket, ARGSRef => $ARGSRef);

    #Merge if we need to
    if ( $ARGSRef->{ $Ticket->Id . "-MergeInto" } ) {
        $ARGSRef->{ $Ticket->Id . "-MergeInto" } =~ s/\s+//g;
        my ( $val, $msg ) =
          $Ticket->MergeInto( $ARGSRef->{ $Ticket->Id . "-MergeInto" } );
        push @results, $msg;
    }

    return (@results);
}

# }}}

sub ProcessRecordLinks {
    my %args = ( RecordObj => undef,
                 ARGSRef   => undef,
                 @_ );

    my $Record  = $args{'RecordObj'};
    my $ARGSRef = $args{'ARGSRef'};

    my (@results);

    # Delete links that are gone gone gone.
    foreach my $arg ( keys %$ARGSRef ) {
        if ( $arg =~ /DeleteLink-(.*?)-(DependsOn|MemberOf|RefersTo)-(.*)$/ ) {
            my $base   = $1;
            my $type   = $2;
            my $target = $3;

            my ( $val, $msg ) = $Record->DeleteLink( Base   => $base,
                                                     Type   => $type,
                                                     Target => $target );

            push @results, $msg;

        }

    }

    my @linktypes = qw( DependsOn MemberOf RefersTo );

    foreach my $linktype (@linktypes) {
        if ( $ARGSRef->{ $Record->Id . "-$linktype" } ) {
            $ARGSRef->{ $Record->Id . "-$linktype" } =
                join(' ', @{$ARGSRef->{ $Record->Id . "-$linktype" }})
                    if ref( $ARGSRef->{ $Record->Id . "-$linktype" } );

            for my $luri ( split ( / /, $ARGSRef->{ $Record->Id . "-$linktype" } ) ) {
                next unless $luri;
                $luri =~ s/\s+$//;    # Strip trailing whitespace
                my ( $val, $msg ) = $Record->AddLink( Target => $luri,
                                                      Type   => $linktype );
                push @results, $msg;
            }
        }
        if ( $ARGSRef->{ "$linktype-" . $Record->Id } ) {
            $ARGSRef->{ "$linktype-" . $Record->Id } =
                join(' ', @{$ARGSRef->{ "$linktype-" . $Record->Id }})
                    if ref( $ARGSRef->{ "$linktype-" . $Record->Id } );

            for my $luri ( split ( / /, $ARGSRef->{ "$linktype-" . $Record->Id } ) ) {
                next unless $luri;
                my ( $val, $msg ) = $Record->AddLink( Base => $luri,
                                                      Type => $linktype );

                push @results, $msg;
            }
        } 
    }

    return (@results);
}


=head2 _UploadedFile ( $arg );

Takes a CGI parameter name; if a file is uploaded under that name,
return a hash reference suitable for AddCustomFieldValue's use:
C<( Value => $filename, LargeContent => $content, ContentType => $type )>.

Returns C<undef> if no files were uploaded in the C<$arg> field.

=cut

sub _UploadedFile {
    my $arg = shift;
    my $cgi_object = $m->cgi_object;
    my $fh = $cgi_object->upload($arg) or return undef;
    my $upload_info = $cgi_object->uploadInfo($fh);

    my $filename = "$fh";
    $filename =~ s#^.*[\\/]##;
    binmode($fh);

    return {
        Value => $filename,
        LargeContent => do { local $/; scalar <$fh> },
        ContentType => $upload_info->{'Content-Type'},
    };
}

sub GetColumnMapEntry {
    my %args = ( Map => {}, Name => '', Attribute => undef, @_ );
    # deal with the simplest thing first
    if ( $args{'Map'}{ $args{'Name'} } ) {
        return $args{'Map'}{ $args{'Name'} }{ $args{'Attribute'} };
    }
    # complex things
    elsif ( my ($mainkey, $subkey) = $args{'Name'} =~ /^(.*?)\.{(.+)}$/ ) {
        return undef unless $args{'Map'}->{ $mainkey };
        return $args{'Map'}{ $mainkey }{ $args{'Attribute'} }
            unless ref $args{'Map'}{ $mainkey }{ $args{'Attribute'} } eq 'CODE';

        return sub { $args{'Map'}{ $mainkey }{ $args{'Attribute'} }->( @_, $subkey ) };
    }
    return undef;
}

sub ProcessColumnMapValue {
    my $value = shift;
    my %args = ( Arguments => [], Escape => 1, @_ );

    if ( ref $value ) {
        if ( UNIVERSAL::isa( $value, 'CODE' ) ) {
            my @tmp = $value->( @{ $args{'Arguments'} } );
            return ProcessColumnMapValue( (@tmp > 1? \@tmp: $tmp[0]), %args );
        }
        elsif ( UNIVERSAL::isa( $value, 'ARRAY' ) ) {
            return join '', map ProcessColumnMapValue($_, %args), @$value;
        }
        elsif ( UNIVERSAL::isa( $value, 'SCALAR' ) ) {
            return $$value;
        }
    }

    return $m->interp->apply_escapes( $value, 'h' ) if $args{'Escape'};
    return $value;
}

=head2 _load_container_object ( $type, $id );

Instantiate container object for saving searches.

=cut

sub _load_container_object {
    my ($obj_type, $obj_id) = @_;
    return RT::SavedSearch->new($session{'CurrentUser'})->_load_privacy_object($obj_type, $obj_id);
}

=head2 _parse_saved_search ( $arg );

Given a serialization string for saved search, and returns the
container object and the search id.

=cut

sub _parse_saved_search {
    my $spec = shift;
    return unless $spec;
    if ($spec  !~ /^(.*?)-(\d+)-SavedSearch-(\d+)$/ ) {
        return;
    }
    my $obj_type  = $1;
    my $obj_id    = $2;
    my $search_id = $3;

    return (_load_container_object ($obj_type, $obj_id), $search_id);
}

eval "require RT::Interface::Web_Vendor";
die $@ if ($@ && $@ !~ qr{^Can't locate RT/Interface/Web_Vendor.pm});
eval "require RT::Interface::Web_Local";
die $@ if ($@ && $@ !~ qr{^Can't locate RT/Interface/Web_Local.pm});

1;
