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

=head1 NAME

  RT::Date - a simple Object Oriented date.

=head1 SYNOPSIS

  use RT::Date

=head1 DESCRIPTION

RT Date is a simple Date Object designed to be speedy and easy for RT to use

The fact that it assumes that a time of 0 means "never" is probably a bug.


=head1 METHODS

=cut


package RT::Date;

use Time::Local;
use POSIX qw(tzset);

use strict;
use warnings;
use base qw/RT::Base/;

use vars qw($MINUTE $HOUR $DAY $WEEK $MONTH $YEAR);

$MINUTE = 60;
$HOUR   = 60 * $MINUTE;
$DAY    = 24 * $HOUR;
$WEEK   = 7 * $DAY;
$MONTH  = 30.4375 * $DAY;
$YEAR   = 365.25 * $DAY;

our @MONTHS = (
    'Jan', # loc
    'Feb', # loc
    'Mar', # loc
    'Apr', # loc
    'May', # loc
    'Jun', # loc
    'Jul', # loc
    'Aug', # loc
    'Sep', # loc
    'Oct', # loc
    'Nov', # loc
    'Dec', # loc
);

our @DAYS_OF_WEEK = (
    'Sun', # loc
    'Mon', # loc
    'Tue', # loc
    'Wed', # loc
    'Thu', # loc
    'Fri', # loc
    'Sat', # loc
);

our @FORMATTERS = (
    'DefaultFormat', # loc
    'ISO',           # loc
    'W3CDTF',        # loc
    'RFC2822',       # loc
    'RFC2616',       # loc
    'iCal',          # loc
);
if ( eval 'use DateTime qw(); 1;' && eval 'use DateTime::Locale qw(); 1;' ) {
    push @FORMATTERS, 'LocalizedDateTime'; # loc
}

=head2 new

Object constructor takes one argument C<RT::CurrentUser> object.

=cut

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = {};
    bless ($self, $class);
    $self->CurrentUser(@_);
    $self->Unix(0);
    return $self;
}

=head2 Set

Takes a param hash with the fields C<Format>, C<Value> and C<Timezone>.

If $args->{'Format'} is 'unix', takes the number of seconds since the epoch.

If $args->{'Format'} is ISO, tries to parse an ISO date.

If $args->{'Format'} is 'unknown', require Time::ParseDate and make it figure
things out. This is a heavyweight operation that should never be called from
within RT's core. But it's really useful for something like the textbox date
entry where we let the user do whatever they want.

If $args->{'Value'} is 0, assumes you mean never.

=cut

sub Set {
    my $self = shift;
    my %args = (
        Format   => 'unix',
        Value    => time,
        Timezone => 'user',
        @_
    );

    return $self->Unix(0) unless $args{'Value'};

    if ( $args{'Format'} =~ /^unix$/i ) {
        return $self->Unix( $args{'Value'} );
    }
    elsif ( $args{'Format'} =~ /^(sql|datemanip|iso)$/i ) {
        $args{'Value'} =~ s!/!-!g;

        if (   ( $args{'Value'} =~ /^(\d{4})?(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)$/ )
            || ( $args{'Value'} =~ /^(\d{4})?(\d\d)(\d\d)(\d\d):(\d\d):(\d\d)$/ )
            || ( $args{'Value'} =~ /^(?:(\d{4})-)?(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)$/ )
            || ( $args{'Value'} =~ /^(?:(\d{4})-)?(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)\+00$/ )
          ) {

            my ($year, $mon, $mday, $hours, $min, $sec)  = ($1, $2, $3, $4, $5, $6);

            # use current year if string has no value
            $year ||= (localtime time)[5] + 1900;

            #timegm expects month as 0->11
            $mon--;

            #now that we've parsed it, deal with the case where everything was 0
            return $self->Unix(0) if $mon < 0 || $mon > 11;

            my $tz = lc $args{'Format'} eq 'datemanip'? 'user': 'utc';
            $self->Unix( $self->Timelocal( $tz, $sec, $min, $hours, $mday, $mon, $year ) );

            $self->Unix(0) unless $self->Unix > 0;
        }
        else {
            $RT::Logger->warning(
                "Couldn't parse date '$args{'Value'}' as a $args{'Format'} format"
            );
            return $self->Unix(0);
        }
    }
    elsif ( $args{'Format'} =~ /^unknown$/i ) {
        require Time::ParseDate;
        # the module supports only legacy timezones like PDT or EST...
        # so we parse date as GMT and later apply offset, this only
        # should be applied to absolute times, so compensate shift in NOW
        my $now = time;
        $now += ($self->Localtime( $args{Timezone}, $now ))[9];
        my $date = Time::ParseDate::parsedate(
            $args{'Value'},
            GMT           => 1,
            NOW           => $now,
            UK            => RT->Config->Get('DateDayBeforeMonth'),
            PREFER_PAST   => RT->Config->Get('AmbiguousDayInPast'),
            PREFER_FUTURE => RT->Config->Get('AmbiguousDayInFuture'),
        );
        # apply timezone offset
        $date -= ($self->Localtime( $args{Timezone}, $date ))[9];

        $RT::Logger->debug(
            "RT::Date used Time::ParseDate to make '$args{'Value'}' $date\n"
        );

        return $self->Set( Format => 'unix', Value => $date);
    }
    else {
        $RT::Logger->error(
            "Unknown Date format: $args{'Format'}\n"
        );
        return $self->Unix(0);
    }

    return $self->Unix;
}

=head2 SetToNow

Set the object's time to the current time. Takes no arguments
and returns unix time.

=cut

sub SetToNow {
    return $_[0]->Unix(time);
}

=head2 SetToMidnight [Timezone => 'utc']

Sets the date to midnight (at the beginning of the day).
Returns the unixtime at midnight.

Arguments:

=over 4

=item Timezone

Timezone context C<user>, C<server> or C<UTC>. See also L</Timezone>.

=back

=cut

sub SetToMidnight {
    my $self = shift;
    my %args = ( Timezone => '', @_ );
    my $new = $self->Timelocal(
        $args{'Timezone'},
        0,0,0,($self->Localtime( $args{'Timezone'} ))[3..9]
    );
    return $self->Unix( $new );
}

=head2 Diff

Takes either an C<RT::Date> object or the date in unixtime format as a string,
if nothing is specified uses the current time.

Returns the differnce between the time in the current object and that time
as a number of seconds. Returns C<undef> if any of two compared values is
incorrect or not set.

=cut

sub Diff {
    my $self = shift;
    my $other = shift;
    $other = time unless defined $other;
    if ( UNIVERSAL::isa( $other, 'RT::Date' ) ) {
        $other = $other->Unix;
    }
    return undef unless $other=~ /^\d+$/ && $other > 0;

    my $unix = $self->Unix;
    return undef unless $unix > 0;

    return $unix - $other;
}

=head2 DiffAsString

Takes either an C<RT::Date> object or the date in unixtime format as a string,
if nothing is specified uses the current time.

Returns the differnce between C<$self> and that time as a number of seconds as
a localized string fit for human consumption. Returns empty string if any of
two compared values is incorrect or not set.

=cut

sub DiffAsString {
    my $self = shift;
    my $diff = $self->Diff( @_ );
    return '' unless defined $diff;

    return $self->DurationAsString( $diff );
}

=head2 DurationAsString

Takes a number of seconds. Returns a localized string describing
that duration.

=cut

sub DurationAsString {
    my $self     = shift;
    my $duration = int shift;

    my ( $negative, $s, $time_unit );
    $negative = 1 if $duration < 0;
    $duration = abs $duration;

    if ( $duration < $MINUTE ) {
        $s         = $duration;
        $time_unit = $self->loc("sec");
    }
    elsif ( $duration < ( 2 * $HOUR ) ) {
        $s         = int( $duration / $MINUTE + 0.5 );
        $time_unit = $self->loc("min");
    }
    elsif ( $duration < ( 2 * $DAY ) ) {
        $s         = int( $duration / $HOUR + 0.5 );
        $time_unit = $self->loc("hours");
    }
    elsif ( $duration < ( 2 * $WEEK ) ) {
        $s         = int( $duration / $DAY + 0.5 );
        $time_unit = $self->loc("days");
    }
    elsif ( $duration < ( 2 * $MONTH ) ) {
        $s         = int( $duration / $WEEK + 0.5 );
        $time_unit = $self->loc("weeks");
    }
    elsif ( $duration < $YEAR ) {
        $s         = int( $duration / $MONTH + 0.5 );
        $time_unit = $self->loc("months");
    }
    else {
        $s         = int( $duration / $YEAR + 0.5 );
        $time_unit = $self->loc("years");
    }

    if ( $negative ) {
        return $self->loc( "[_1] [_2] ago", $s, $time_unit );
    }
    else {
        return $self->loc( "[_1] [_2]", $s, $time_unit );
    }
}

=head2 AgeAsString

Takes nothing. Returns a string that's the differnce between the
time in the object and now.

=cut

sub AgeAsString { return $_[0]->DiffAsString }



=head2 AsString

Returns the object's time as a localized string with curent user's prefered
format and timezone.

If the current user didn't choose prefered format then system wide setting is
used or L</DefaultFormat> if the latter is not specified. See config option
C<DateTimeFormat>.

=cut

sub AsString {
    my $self = shift;
    my %args = (@_);

    return $self->loc("Not set") unless $self->Unix > 0;

    my $format = RT->Config->Get( 'DateTimeFormat', $self->CurrentUser ) || 'DefaultFormat';
    $format = { Format => $format } unless ref $format;
    %args = (%$format, %args);

    return $self->Get( Timezone => 'user', %args );
}

=head2 GetWeekday DAY

Takes an integer day of week and returns a localized string for
that day of week. Valid values are from range 0-6, Note that B<0
is sunday>.

=cut

sub GetWeekday {
    my $self = shift;
    my $dow = shift;
    
    return $self->loc($DAYS_OF_WEEK[$dow])
        if $DAYS_OF_WEEK[$dow];
    return '';
}

=head2 GetMonth MONTH

Takes an integer month and returns a localized string for that month.
Valid values are from from range 0-11.

=cut

sub GetMonth {
    my $self = shift;
    my $mon = shift;

    return $self->loc($MONTHS[$mon])
        if $MONTHS[$mon];
    return '';
}

=head2 AddSeconds SECONDS

Takes a number of seconds and returns the new unix time.

Negative value can be used to substract seconds.

=cut

sub AddSeconds {
    my $self = shift;
    my $delta = shift or return $self->Unix;
    
    $self->Set(Format => 'unix', Value => ($self->Unix + $delta));
 
    return ($self->Unix);
}

=head2 AddDays [DAYS]

Adds C<24 hours * DAYS> to the current time. Adds one day when
no argument is specified. Negative value can be used to substract
days.

Returns new unix time.

=cut

sub AddDays {
    my $self = shift;
    my $days = shift || 1;
    return $self->AddSeconds( $days * $DAY );
}

=head2 AddDay

Adds 24 hours to the current time. Returns new unix time.

=cut

sub AddDay { return $_[0]->AddSeconds($DAY) }

=head2 Unix [unixtime]

Optionally takes a date in unix seconds since the epoch format.
Returns the number of seconds since the epoch

=cut

sub Unix {
    my $self = shift; 
    $self->{'time'} = int(shift || 0) if @_;
    return $self->{'time'};
}

=head2 DateTime

Alias for L</Get> method. Arguments C<Date> and <Time>
are fixed to true values, other arguments could be used
as described in L</Get>.

=cut

sub DateTime {
    my $self = shift;
    return $self->Get( @_, Date => 1, Time => 1 );
}

=head2 Date

Takes Format argument which allows you choose date formatter.
Pass throught other arguments to the formatter method.

Returns the object's formatted date. Default formatter is ISO.

=cut

sub Date {
    my $self = shift;
    return $self->Get( @_, Date => 1, Time => 0 );
}

=head2 Time


=cut

sub Time {
    my $self = shift;
    return $self->Get( @_, Date => 0, Time => 1 );
}

=head2 Get

Returnsa a formatted and localized string that represets time of
the current object.


=cut

sub Get
{
    my $self = shift;
    my %args = (Format => 'ISO', @_);
    my $formatter = $args{'Format'};
    $formatter = 'ISO' unless $self->can($formatter);
    return $self->$formatter( %args );
}

=head2 Output formatters

Fomatter is a method that returns date and time in different configurable
format.

Each method takes several arguments:

=over 1

=item Date

=item Time

=item Timezone - Timezone context C<server>, C<user> or C<UTC>

=back

Formatters may also add own arguments to the list, for example
in RFC2822 format day of time in output is optional so it
understand boolean argument C<DayOfTime>.

=head3 Formatters

Returns an array of available formatters.

=cut

sub Formatters
{
    my $self = shift;

    return @FORMATTERS;
}

=head3 DefaultFormat

=cut

sub DefaultFormat
{
    my $self = shift;
    my %args = ( Date => 1,
                 Time => 1,
                 Timezone => '',
                 Seconds => 1,
                 @_,
               );
    
       #  0    1    2     3     4    5     6     7      8      9
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$ydaym,$isdst,$offset) =
                            $self->Localtime($args{'Timezone'});
    $wday = $self->GetWeekday($wday);
    $mon = $self->GetMonth($mon);
    ($mday, $hour, $min, $sec) = map { sprintf "%02d", $_ } ($mday, $hour, $min, $sec);

    if( $args{'Date'} && !$args{'Time'} ) {
        return $self->loc('[_1] [_2] [_3] [_4]',
                          $wday,$mon,$mday,$year);
    } elsif( !$args{'Date'} && $args{'Time'} ) {
        if( $args{'Seconds'} ) {
            return $self->loc('[_1]:[_2]:[_3]',
                              $hour,$min,$sec);
        } else {
            return $self->loc('[_1]:[_2]',
                              $hour,$min);
        }
    } else {
        if( $args{'Seconds'} ) {
            return $self->loc('[_1] [_2] [_3] [_4]:[_5]:[_6] [_7]',
                              $wday,$mon,$mday,$hour,$min,$sec,$year);
        } else {
            return $self->loc('[_1] [_2] [_3] [_4]:[_5] [_6]',
                              $wday,$mon,$mday,$hour,$min,$year);
        }
    }
}

=head3 LocalizedDateTime

Returns date and time as string, with user localization.

Supports arguments: C<DateFormat> and C<TimeFormat> which may contains date and
time format as specified in DateTime::Locale (default to full_date_format and
medium_time_format), C<AbbrDay> and C<AbbrMonth> which may be set to 0 if
you want full Day/Month names instead of abbreviated ones.

Require optionnal DateTime::Locale module.

=cut

sub LocalizedDateTime
{
    my $self = shift;
    my %args = ( Date => 1,
                 Time => 1,
                 Timezone => '',
                 DateFormat => 'full_date_format',
                 TimeFormat => 'medium_time_format',
                 AbbrDay => 1,
                 AbbrMonth => 1,
                 @_,
               );

    return $self->loc("DateTime module missing") unless ( eval 'use DateTime qw(); 1;' );
    return $self->loc("DateTime::Locale module missing") unless ( eval 'use DateTime::Locale qw(); 1;' );
    my $date_format = $args{'DateFormat'};
    my $time_format = $args{'TimeFormat'};

    my $lang = $self->CurrentUser->UserObj->Lang || 'en';

    my $formatter = DateTime::Locale->load($lang);
    $date_format = $formatter->$date_format;
    $time_format = $formatter->$time_format;
    $date_format =~ s/\%A/\%a/g if ( $args{'AbbrDay'} );
    $date_format =~ s/\%B/\%b/g if ( $args{'AbbrMonth'} );

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$ydaym,$isdst,$offset) =
                            $self->Localtime($args{'Timezone'});
    $mon++;
    my $tz = $self->Timezone($args{'Timezone'});

    # FIXME : another way to call this module without conflict with local
    # DateTime method?
    my $dt = new DateTime::( locale => $lang,
                            time_zone => $tz,
                            year => $year,
                            month => $mon,
                            day => $mday,
                            hour => $hour,
                            minute => $min,
                            second => $sec,
                            nanosecond => 0,
                          );

    if ( $args{'Date'} && !$args{'Time'} ) {
        return $dt->strftime($date_format);
    } elsif ( !$args{'Date'} && $args{'Time'} ) {
        return $dt->strftime($time_format);
    } else {
        return $dt->strftime($date_format) . " " . $dt->strftime($time_format);
    }
}

=head3 ISO

Returns the object's date in ISO format C<YYYY-MM-DD mm:hh:ss>.
ISO format is locale independant, but adding timezone offset info
is not implemented yet.

Supports arguments: C<Timezone>, C<Date>, C<Time> and C<Seconds>.
See </Output formatters> for description of arguments.

=cut

sub ISO {
    my $self = shift;
    my %args = ( Date => 1,
                 Time => 1,
                 Timezone => '',
                 Seconds => 1,
                 @_,
               );
       #  0    1    2     3     4    5     6     7      8      9
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$ydaym,$isdst,$offset) =
                            $self->Localtime($args{'Timezone'});

    #the month needs incrementing, as gmtime returns 0-11
    $mon++;

    my $res = '';
    $res .= sprintf("%04d-%02d-%02d", $year, $mon, $mday) if $args{'Date'};
    $res .= sprintf(' %02d:%02d', $hour, $min) if $args{'Time'};
    $res .= sprintf(':%02d', $sec, $min) if $args{'Time'} && $args{'Seconds'};
    $res =~ s/^\s+//;

    return $res;
}

=head3 W3CDTF

Returns the object's date and time in W3C date time format
(L<http://www.w3.org/TR/NOTE-datetime>).

Format is locale independand and is close enought to ISO, but
note that date part is B<not optional> and output string
has timezone offset mark in C<[+-]hh:mm> format.

Supports arguments: C<Timezone>, C<Time> and C<Seconds>.
See </Output formatters> for description of arguments.

=cut

sub W3CDTF {
    my $self = shift;
    my %args = (
        Time => 1,
        Timezone => '',
        Seconds => 1,
        @_,
        Date => 1,
    );
       #  0    1    2     3     4    5     6     7      8      9
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$ydaym,$isdst,$offset) =
                            $self->Localtime( $args{'Timezone'} );

    #the month needs incrementing, as gmtime returns 0-11
    $mon++;

    my $res = '';
    $res .= sprintf("%04d-%02d-%02d", $year, $mon, $mday);
    if ( $args{'Time'} ) {
        $res .= sprintf('T%02d:%02d', $hour, $min);
        $res .= sprintf(':%02d', $sec, $min) if $args{'Seconds'};
        if ( $offset ) {
            $res .= sprintf "%s%02d:%02d", $self->_SplitOffset( $offset );
        } else {
            $res .= 'Z';
        }
    }

    return $res;
};


=head3 RFC2822 (MIME)

Returns the object's date and time in RFC2822 format,
for example C<Sun, 06 Nov 1994 08:49:37 +0000>.
Format is locale independand as required by RFC. Time
part always has timezone offset in digits with sign prefix.

Supports arguments: C<Timezone>, C<Date>, C<Time>, C<DayOfWeek>
and C<Seconds>. See </Output formatters> for description of
arguments.

=cut

sub RFC2822 {
    my $self = shift;
    my %args = ( Date => 1,
                 Time => 1,
                 Timezone => '',
                 DayOfWeek => 1,
                 Seconds => 1,
                 @_,
               );

       #  0    1    2     3     4    5     6     7      8     9
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$ydaym,$isdst,$offset) =
                            $self->Localtime($args{'Timezone'});

    my ($date, $time) = ('','');
    $date .= "$DAYS_OF_WEEK[$wday], " if $args{'DayOfWeek'} && $args{'Date'};
    $date .= "$mday $MONTHS[$mon] $year" if $args{'Date'};

    if ( $args{'Time'} ) {
        $time .= sprintf("%02d:%02d", $hour, $min);
        $time .= sprintf(":%02d", $sec) if $args{'Seconds'};
        $time .= sprintf " %s%02d%02d", $self->_SplitOffset( $offset );
    }

    return join ' ', grep $_, ($date, $time);
}

=head3 RFC2616 (HTTP)

Returns the object's date and time in RFC2616 (HTTP/1.1) format,
for example C<Sun, 06 Nov 1994 08:49:37 GMT>. While the RFC describes
version 1.1 of HTTP, but the same form date can be used in version 1.0.

Format is fixed length, locale independand and always represented in GMT
what makes it quite useless for users, but any date in HTTP transfers
must be presented using this format.

    HTTP-date = rfc1123 | ...
    rfc1123   = wkday "," SP date SP time SP "GMT"
    date      = 2DIGIT SP month SP 4DIGIT
                ; day month year (e.g., 02 Jun 1982)
    time      = 2DIGIT ":" 2DIGIT ":" 2DIGIT
                ; 00:00:00 - 23:59:59
    wkday     = "Mon" | "Tue" | "Wed" | "Thu" | "Fri" | "Sat" | "Sun"
    month     = "Jan" | "Feb" | "Mar" | "Apr" | "May" | "Jun"
              | "Jul" | "Aug" | "Sep" | "Oct" | "Nov" | "Dec"

Supports arguments: C<Date> and C<Time>, but you should use them only for
some personal reasons, RFC2616 doesn't define any optional parts.
See </Output formatters> for description of arguments.

=cut

sub RFC2616 {
    my $self = shift;
    my %args = ( Date => 1, Time => 1,
                 @_,
                 Timezone => 'utc',
                 Seconds => 1, DayOfWeek => 1,
               );

    my $res = $self->RFC2822( @_ );
    $res =~ s/\s*[+-]\d\d\d\d$/ GMT/ if $args{'Time'};
    return $res;
}

=head4 iCal

Returns the object's date and time in iCalendar format,

Supports arguments: C<Date> and C<Time>.
See </Output formatters> for description of arguments.

=cut

sub iCal {
    my $self = shift;
    my %args = (
        Date => 1, Time => 1,
        @_,
    );
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$ydaym,$isdst,$offset) =
        $self->Localtime( 'utc' );

    #the month needs incrementing, as gmtime returns 0-11
    $mon++;

    my $res;
    if ( $args{'Date'} && !$args{'Time'} ) {
        $res = sprintf( '%04d%02d%02d', $year, $mon, $mday );
    }
    elsif ( !$args{'Date'} && $args{'Time'} ) {
        $res = sprintf( 'T%02d%02d%02dZ', $hour, $min, $sec );
    }
    else {
        $res = sprintf( '%04d%02d%02dT%02d%02d%02dZ', $year, $mon, $mday, $hour, $min, $sec );
    }
    return $res;
}

# it's been added by mistake in 3.8.0
sub iCalDate { return (shift)->iCal( Time => 0, @_ ) }

sub _SplitOffset {
    my ($self, $offset) = @_;
    my $sign = $offset < 0? '-': '+';
    $offset = int( (abs $offset) / 60 + 0.001 );
    my $mins = $offset % 60;
    my $hours = int( $offset/60 + 0.001 );
    return $sign, $hours, $mins; 
}

=head2 Timezones handling

=head3 Localtime $context [$time]

Takes one mandatory argument C<$context>, which determines whether
we want "user local", "system" or "UTC" time. Also, takes optional
argument unix C<$time>, default value is the current unix time.

Returns object's date and time in the format provided by perl's
builtin functions C<localtime> and C<gmtime> with two exceptions:

1) "Year" is a four-digit year, rather than "years since 1900"

2) The last element of the array returned is C<offset>, which
represents timezone offset against C<UTC> in seconds.

=cut

sub Localtime
{
    my $self = shift;
    my $tz = $self->Timezone(shift);

    my $unix = shift || $self->Unix;
    $unix = 0 unless $unix >= 0;
    
    my @local;
    if ($tz eq 'UTC') {
        @local = gmtime($unix);
    } else {
        {
            local $ENV{'TZ'} = $tz;
            ## Using POSIX::tzset fixes a bug where the TZ environment variable
            ## is cached.
            POSIX::tzset();
            @local = localtime($unix);
        }
        POSIX::tzset(); # return back previouse value
    }
    $local[5] += 1900; # change year to 4+ digits format
    my $offset = Time::Local::timegm_nocheck(@local) - $unix;
    return @local, $offset;
}

=head3 Timelocal $context @time

Takes argument C<$context>, which determines whether we should
treat C<@time> as "user local", "system" or "UTC" time.

C<@time> is array returned by L<Localtime> functions. Only first
six elements are mandatory - $sec, $min, $hour, $mday, $mon and $year.
You may pass $wday, $yday and $isdst, these are ignored.

If you pass C<$offset> as ninth argument, it's used instead of
C<$context>. It's done such way as code 
C<$self->Timelocal('utc', $self->Localtime('server'))> doesn't
makes much sense and most probably would produce unexpected
result, so the method ignore 'utc' context and uses offset
returned by L<Localtime> method.

=cut

sub Timelocal {
    my $self = shift;
    my $tz = shift;
    if ( defined $_[9] ) {
        return timegm(@_[0..5]) - $_[9];
    } else {
        $tz = $self->Timezone( $tz );
        if ( $tz eq 'UTC' ) {
            return Time::Local::timegm(@_[0..5]);
        } else {
            my $rv;
            {
                local $ENV{'TZ'} = $tz;
                ## Using POSIX::tzset fixes a bug where the TZ environment variable
                ## is cached.
                POSIX::tzset();
                $rv = Time::Local::timelocal(@_[0..5]);
            };
            POSIX::tzset(); # switch back to previouse value
            return $rv;
        }
    }
}


=head3 Timezone $context

Returns the timezone name.

Takes one argument, C<$context> argument which could be C<user>, C<server> or C<utc>.

=over

=item user

Default value is C<user> that mean it returns current user's Timezone value.

=item server

If context is C<server> it returns value of the C<Timezone> RT config option.

=item  utc

If both server's and user's timezone names are undefined returns 'UTC'.

=back

=cut

sub Timezone {
    my $self = shift;
    my $context = lc(shift);

    $context = 'utc' unless $context =~ /^(?:utc|server|user)$/i;

    my $tz;
    if( $context eq 'user' ) {
        $tz = $self->CurrentUser->UserObj->Timezone;
    } elsif( $context eq 'server') {
        $tz = RT->Config->Get('Timezone');
    } else {
        $tz = 'UTC';
    }
    $tz ||= RT->Config->Get('Timezone') || 'UTC';
    $tz = 'UTC' if lc $tz eq 'gmt';
    return $tz;
}


eval "require RT::Date_Vendor";
die $@ if ($@ && $@ !~ qr{^Can't locate RT/Date_Vendor.pm});
eval "require RT::Date_Local";
die $@ if ($@ && $@ !~ qr{^Can't locate RT/Date_Local.pm});

1;
