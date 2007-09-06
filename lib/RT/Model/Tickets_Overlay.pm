# BEGIN BPS TAGGED BLOCK {{{
# 
# COPYRIGHT:
#  
# This software is Copyright (c) 1996-2007 Best Practical Solutions, LLC 
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
# http://www.gnu.org/copyleft/gpl.html.
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
# Major Changes:

# - Decimated ProcessRestrictions and broke it into multiple
# functions joined by a LUT
# - Semi-Generic SQL stuff moved to another file

# Known Issues: FIXME!

# - ClearRestrictions and Reinitialization is messy and unclear.  The
# only good way to do it is to create a new RT::Model::Tickets object.

=head1 NAME

  RT::Model::Tickets - A collection of Ticket objects


=head1 SYNOPSIS

  use RT::Model::Tickets;
  my $tickets = new RT::Model::Tickets($CurrentUser);

=head1 description

   A collection of RT::Model::Tickets.

=head1 METHODS


=cut

package RT::Model::Tickets;

use strict;
no warnings qw(redefine);

use RT::Model::CustomFields;
use Jifty::DBI::Collection::Unique;

# Configuration Tables:

# FIELD_METADATA is a mapping of searchable Field name, to Type, and other
# metadata.

our %FIELD_METADATA = (
    Status          => [ 'ENUM', ],
    Queue           => [ 'ENUM' => 'Queue', ],
    Type            => [ 'ENUM', ],
    Creator         => [ 'ENUM' => 'User', ],
    LastUpdatedBy   => [ 'ENUM' => 'User', ],
    Owner           => [ 'WATCHERFIELD' => 'Owner', ],
    EffectiveId     => [ 'INT', ],
    id              => [ 'INT', ],
    InitialPriority => [ 'INT', ],
    FinalPriority   => [ 'INT', ],
    Priority        => [ 'INT', ],
    TimeLeft        => [ 'INT', ],
    TimeWorked      => [ 'INT', ],
    TimeEstimated   => [ 'INT', ],

    Linked          => [ 'LINK' ],
    LinkedTo        => [ 'LINK' => 'To' ],
    LinkedFrom      => [ 'LINK' => 'From' ],
    MemberOf        => [ 'LINK' => To => 'MemberOf', ],
    DependsOn       => [ 'LINK' => To => 'DependsOn', ],
    RefersTo        => [ 'LINK' => To => 'RefersTo', ],
    has_member       => [ 'LINK' => From => 'MemberOf', ],
    DependentOn     => [ 'LINK' => From => 'DependsOn', ],
    DependedOnBy    => [ 'LINK' => From => 'DependsOn', ],
    ReferredToBy    => [ 'LINK' => From => 'RefersTo', ],
    Told             => [ 'DATE'            => 'Told', ],
    Starts           => [ 'DATE'            => 'Starts', ],
    Started          => [ 'DATE'            => 'Started', ],
    Due              => [ 'DATE'            => 'Due', ],
    Resolved         => [ 'DATE'            => 'Resolved', ],
    LastUpdated      => [ 'DATE'            => 'LastUpdated', ],
    Created          => [ 'DATE'            => 'Created', ],
    Subject          => [ 'STRING', ],
    Content          => [ 'TRANSFIELD', ],
    ContentType      => [ 'TRANSFIELD', ],
    Filename         => [ 'TRANSFIELD', ],
    TransactionDate  => [ 'TRANSDATE', ],
    Requestor        => [ 'WATCHERFIELD'    => 'Requestor', ],
    Requestors       => [ 'WATCHERFIELD'    => 'Requestor', ],
    Cc               => [ 'WATCHERFIELD'    => 'Cc', ],
    AdminCc          => [ 'WATCHERFIELD'    => 'AdminCc', ],
    Watcher          => [ 'WATCHERFIELD', ],

    CustomFieldvalue => [ 'CUSTOMFIELD', ],
    CustomField      => [ 'CUSTOMFIELD', ],
    CF               => [ 'CUSTOMFIELD', ],
    Updated          => [ 'TRANSDATE', ],
    RequestorGroup   => [ 'MEMBERSHIPFIELD' => 'Requestor', ],
    CCGroup          => [ 'MEMBERSHIPFIELD' => 'Cc', ],
    AdminCCGroup     => [ 'MEMBERSHIPFIELD' => 'AdminCc', ],
    WatcherGroup     => [ 'MEMBERSHIPFIELD', ],
);

# Mapping of Field Type to Function
our %dispatch = (
    ENUM            => \&_EnumLimit,
    INT             => \&_IntLimit,
    LINK            => \&_LinkLimit,
    DATE            => \&_DateLimit,
    STRING          => \&_StringLimit,
    TRANSFIELD      => \&_TransLimit,
    TRANSDATE       => \&_TransDateLimit,
    WATCHERFIELD    => \&_WatcherLimit,
    MEMBERSHIPFIELD => \&_WatcherMembershipLimit,
    CUSTOMFIELD     => \&_CustomFieldLimit,
);
our %can_bundle = ();# WATCHERFIELD => "yes", );

# Default entry_aggregator per type
# if you specify OP, you must specify all valid OPs
my %DefaultEA = (
    INT  => 'AND',
    ENUM => {
        '='  => 'OR',
        '!=' => 'AND'
    },
    DATE => {
        '='  => 'OR',
        '>=' => 'AND',
        '<=' => 'AND',
        '>'  => 'AND',
        '<'  => 'AND'
    },
    STRING => {
        '='        => 'OR',
        '!='       => 'AND',
        'LIKE'     => 'AND',
        'NOT LIKE' => 'AND'
    },
    TRANSFIELD   => 'AND',
    TRANSDATE    => 'AND',
    LINK         => 'OR',
    LINKFIELD    => 'AND',
    target       => 'AND',
    base         => 'AND',
    WATCHERFIELD => {
        '='        => 'OR',
        '!='       => 'AND',
        'LIKE'     => 'OR',
        'NOT LIKE' => 'AND'
    },

    CUSTOMFIELD => 'OR',
);

# Helper functions for passing the above lexically scoped tables above
# into Tickets_Overlay_SQL.
sub columns     { return \%FIELD_METADATA }
sub dispatch   { return \%dispatch }
sub can_bundle { return \%can_bundle }

# Bring in the clowns.
require RT::Model::Tickets_Overlay_SQL;

# {{{ sub SortFields

our @SORTcolumns = qw(id Status
    Queue Subject
    Owner Created Due Starts Started
    Told
    Resolved LastUpdated Priority TimeWorked TimeLeft);

=head2 SortFields

Returns the list of fields that lists of tickets can easily be sorted by

=cut

sub SortFields {
    my $self = shift;
    return (@SORTcolumns);
}

# }}}

# BEGIN SQL STUFF *********************************


sub clean_slate {
    my $self = shift;
    $self->SUPER::clean_slate( @_ );
    delete $self->{$_} foreach qw(
        _sql_cf_alias
        _sql_group_members_aliases
        _sql_object_cfv_alias
        _sql_role_group_aliases
        _sql_transalias
        _sql_trattachalias
        _sql_u_watchers_alias_for_sort
        _sql_u_watchers_aliases
    );
}

=head1 Limit Helper Routines

These routines are the targets of a dispatch table depending on the
type of field.  They all share the same signature:

  my ($self,$field,$op,$value,@rest) = @_;

The values in @rest should be suitable for passing directly to
Jifty::DBI::limit.

Essentially they are an expanded/broken out (and much simplified)
version of what ProcessRestrictions used to do.  They're also much
more clearly delineated by the type of field being processed.

=head2 _EnumLimit

Handle Fields which are limited to certain values, and potentially
need to be looked up from another class.

This subroutine actually handles two different kinds of fields.  For
some the user is responsible for limiting the values.  (i.e. Status,
Type).

For others, the value specified by the user will be looked by via
specified class.

Meta Data:
  name of class to lookup in (Optional)

=cut

sub _EnumLimit {
    my ( $sb, $field, $op, $value, @rest ) = @_;

    # SQL::Statement changes != to <>.  (Can we remove this now?)
    $op = "!=" if $op eq "<>";

    die "Invalid Operation: $op for $field"
        unless $op eq "="
        or $op     eq "!=";

    my $meta = $FIELD_METADATA{$field};
    if ( defined $meta->[1] && defined $value && $value !~ /^\d+$/ ) {
        my $class = "RT::Model::" . $meta->[1];
        my $o     = $class->new( $sb->CurrentUser );
        $o->load($value);
        $value = $o->id;
    }
    $sb->_sql_limit(
        column    => $field,
        value    => $value,
        operator => $op,
        @rest,
    );
}

=head2 _IntLimit

Handle fields where the values are limited to integers.  (For example,
Priority, TimeWorked.)

Meta Data:
  None

=cut

sub _IntLimit {
    my ( $sb, $field, $op, $value, @rest ) = @_;

    die "Invalid Operator $op for $field"
        unless $op =~ /^(=|!=|>|<|>=|<=)$/;

    $sb->_sql_limit(
        column    => $field,
        value    => $value,
        operator => $op,
        @rest,
    );
}

=head2 _LinkLimit

Handle fields which deal with links between tickets.  (MemberOf, DependsOn)

Meta Data:
  1: Direction (From, To)
  2: Link Type (MemberOf, DependsOn, RefersTo)

=cut

sub _LinkLimit {
    my ( $sb, $field, $op, $value, @rest ) = @_;

    my $meta = $FIELD_METADATA{$field};
    die "Invalid Operator $op for $field" unless $op =~ /^(=|!=|IS|IS NOT)$/io;

    my $direction = $meta->[1] || '';
    my ($matchfield, $linkfield) = ('', '');
    if ( $direction eq 'To' ) {
        ($matchfield, $linkfield) = ("Target", "Base");
    }
    elsif ( $direction eq 'From' ) {
        ($matchfield, $linkfield) = ("Base", "Target");
    }
    elsif ( $direction ) {
        die "Invalid link direction '$direction' for $field\n";
    }

    my ($is_local, $is_null) = (1, 0);
    if ( !$value || $value =~ /^null$/io ) {
        $is_null = 1;
        $op = ($op =~ /^(=|IS)$/)? 'IS': 'IS NOT';
    }
    elsif ( $value =~ /\D/ ) {
        $is_local = 0;
    }
    $matchfield = "Local$matchfield" if $is_local;

    my $is_negative = 0;
    if ( $op eq '!=' ) {
        $is_negative = 1;
        $op = '=';
    }

#For doing a left join to find "unlinked tickets" we want to generate a query that looks like this
#    SELECT main.* FROM Tickets main
#        left join Links Links_1 ON (     (Links_1.Type = 'MemberOf')
#                                      AND(main.id = Links_1.LocalTarget))
#        WHERE Links_1.LocalBase IS NULL;

    if ( $is_null ) {
        my $linkalias = $sb->join(
            type => 'left',
            alias1 => 'main',
            column1 => 'id',
            table2 => 'Links',
            column2 => 'Local' . $linkfield
        );
        $sb->SUPER::limit(
            leftjoin => $linkalias,
            column    => 'Type',
            operator => '=',
            value    => $meta->[2],
        ) if $meta->[2];
        $sb->_sql_limit(
            @rest,
            alias      => $linkalias,
            column      => $matchfield,
            operator   => $op,
            value      => 'NULL',
            quote_value => 0,
        );
    }
    elsif ( $is_negative ) {
        my $linkalias = $sb->join(
            type => 'left',
            alias1 => 'main',
            column1 => 'id',
            table2 => 'Links',
            column2 => 'Local' . $linkfield
        );
        $sb->SUPER::limit(
            leftjoin => $linkalias,
            column    => 'Type',
            operator => '=',
            value    => $meta->[2],
        ) if $meta->[2];
        $sb->SUPER::limit(
            leftjoin => $linkalias,
            column    => $matchfield,
            operator => $op,
            value    => $value,
        );
        $sb->_sql_limit(
            @rest,
            alias      => $linkalias,
            column      => $matchfield,
            operator   => 'IS',
            value      => 'NULL',
            quote_value => 0,
        );
    }
    else {
        my $linkalias = $sb->new_alias('Links');
        $sb->open_paren;

        $sb->_sql_limit(
            @rest,
            alias    => $linkalias,
            column    => 'Type',
            operator => '=',
            value    => $meta->[2],
        ) if $meta->[2];

        $sb->open_paren;
        if ( $direction ) {
            $sb->_sql_limit(
                alias           => $linkalias,
                column           => 'Local' . $linkfield,
                operator        => '=',
                value           => 'main.id',
                quote_value      => 0,
                entry_aggregator => 'AND',
            );
            $sb->_sql_limit(
                alias           => $linkalias,
                column           => $matchfield,
                operator        => '=',
                value           => $value,
                entry_aggregator => 'AND',
            );
        } else {
            $sb->open_paren;
            $sb->_sql_limit(
                alias           => $linkalias,
                column           => 'LocalBase',
                value           => 'main.id',
                quote_value      => 0,
                entry_aggregator => 'AND',
            );
            $sb->_sql_limit(
                alias           => $linkalias,
                column           => $matchfield .'Target',
                value           => $value,
                entry_aggregator => 'AND',
            );
            $sb->close_paren;

            $sb->open_paren;
            $sb->_sql_limit(
                alias           => $linkalias,
                column           => 'LocalTarget',
                value           => 'main.id',
                quote_value      => 0,
                entry_aggregator => 'OR',
            );
            $sb->_sql_limit(
                alias           => $linkalias,
                column           => $matchfield .'Base',
                value           => $value,
                entry_aggregator => 'AND',
            );
            $sb->close_paren;
        }
        $sb->close_paren;
        $sb->close_paren;
    }
}

=head2 _DateLimit

Handle date fields.  (Created, LastTold..)

Meta Data:
  1: type of link.  (Probably not necessary.)

=cut

sub _DateLimit {
    my ( $sb, $field, $op, $value, @rest ) = @_;

    die "Invalid Date Op: $op"
        unless $op =~ /^(=|>|<|>=|<=)$/;

    my $meta = $FIELD_METADATA{$field};
    die "Incorrect Meta Data for $field"
        unless ( defined $meta->[1] );

    my $date = RT::Date->new( $sb->CurrentUser );
    $date->set( Format => 'unknown', value => $value );

    if ( $op eq "=" ) {

        # if we're specifying =, that means we want everything on a
        # particular single day.  in the database, we need to check for >
        # and < the edges of that day.

        $date->set_ToMidnight( Timezone => 'server' );
        my $daystart = $date->ISO;
        $date->AddDay;
        my $dayend = $date->ISO;

        $sb->open_paren;

        $sb->_sql_limit(
            column    => $meta->[1],
            operator => ">=",
            value    => $daystart,
            @rest,
        );

        $sb->_sql_limit(
            column    => $meta->[1],
            operator => "<=",
            value    => $dayend,
            @rest,
            entry_aggregator => 'AND',
        );

        $sb->close_paren;

    }
    else {
        $sb->_sql_limit(
            column    => $meta->[1],
            operator => $op,
            value    => $date->ISO,
            @rest,
        );
    }
}

=head2 _StringLimit

Handle simple fields which are just strings.  (Subject,Type)

Meta Data:
  None

=cut

sub _StringLimit {
    my ( $sb, $field, $op, $value, @rest ) = @_;

    # FIXME:
    # Valid Operators:
    #  =, !=, LIKE, NOT LIKE

    $sb->_sql_limit(
        column         => $field,
        operator      => $op,
        value         => $value,
        case_sensitive => 0,
        @rest,
    );
}

=head2 _TransDateLimit

Handle fields limiting based on Transaction Date.

The inpupt value must be in a format parseable by Time::ParseDate

Meta Data:
  None

=cut

# This routine should really be factored into translimit.
sub _TransDateLimit {
    my ( $sb, $field, $op, $value, @rest ) = @_;

    # See the comments for TransLimit, they apply here too

    unless ( $sb->{_sql_transalias} ) {
        $sb->{_sql_transalias} = $sb->join(
            alias1 => 'main',
            column1 => 'id',
            table2 => 'Transactions',
            column2 => 'ObjectId',
        );
        $sb->SUPER::limit(
            alias           => $sb->{_sql_transalias},
            column           => 'ObjectType',
            value           => 'RT::Model::Ticket',
            entry_aggregator => 'AND',
        );
    }

    my $date = RT::Date->new( $sb->CurrentUser );
    $date->set( Format => 'unknown', value => $value );

    $sb->open_paren;
    if ( $op eq "=" ) {

        # if we're specifying =, that means we want everything on a
        # particular single day.  in the database, we need to check for >
        # and < the edges of that day.

        $date->set_ToMidnight( Timezone => 'server' );
        my $daystart = $date->ISO;
        $date->AddDay;
        my $dayend = $date->ISO;

        $sb->_sql_limit(
            alias         => $sb->{_sql_transalias},
            column         => 'Created',
            operator      => ">=",
            value         => $daystart,
            case_sensitive => 0,
            @rest
        );
        $sb->_sql_limit(
            alias         => $sb->{_sql_transalias},
            column         => 'Created',
            operator      => "<=",
            value         => $dayend,
            case_sensitive => 0,
            @rest,
            entry_aggregator => 'AND',
        );

    }

    # not searching for a single day
    else {

        #Search for the right field
        $sb->_sql_limit(
            alias         => $sb->{_sql_transalias},
            column         => 'Created',
            operator      => $op,
            value         => $date->ISO,
            case_sensitive => 0,
            @rest
        );
    }

    $sb->close_paren;
}

=head2 _TransLimit

Limit based on the Content of a transaction or the ContentType.

Meta Data:
  none

=cut

sub _TransLimit {

    # Content, ContentType, Filename

    # If only this was this simple.  We've got to do something
    # complicated here:

    #Basically, we want to make sure that the limits apply to
    #the same attachment, rather than just another attachment
    #for the same ticket, no matter how many clauses we lump
    #on. We put them in TicketAliases so that they get nuked
    #when we redo the join.

    # In the SQL, we might have
    #       (( Content = foo ) or ( Content = bar AND Content = baz ))
    # The AND group should share the same Alias.

    # Actually, maybe it doesn't matter.  We use the same alias and it
    # works itself out? (er.. different.)

    # Steal more from _ProcessRestrictions

    # FIXME: Maybe look at the previous FooLimit call, and if it was a
    # TransLimit and entry_aggregator == AND, reuse the Aliases?

    # Or better - store the aliases on a per subclause basis - since
    # those are going to be the things we want to relate to each other,
    # anyway.

    # maybe we should not allow certain kinds of aggregation of these
    # clauses and do a psuedo regex instead? - the problem is getting
    # them all into the same subclause when you have (A op B op C) - the
    # way they get parsed in the tree they're in different subclauses.

    my ( $self, $field, $op, $value, @rest ) = @_;

    unless ( $self->{_sql_transalias} ) {
        $self->{_sql_transalias} = $self->join(
            alias1 => 'main',
            column1 => 'id',
            table2 => 'Transactions',
            column2 => 'ObjectId',
        );
        $self->SUPER::limit(
            alias           => $self->{_sql_transalias},
            column           => 'ObjectType',
            value           => 'RT::Model::Ticket',
            entry_aggregator => 'AND',
        );
    }
    unless ( defined $self->{_sql_trattachalias} ) {
        $self->{_sql_trattachalias} = $self->_sql_join(
            type => 'left', # not all txns have an attachment
            alias1 => $self->{_sql_transalias},
            column1 => 'id',
            table2 => 'Attachments',
            column2 => 'TransactionId',
        );
    }

    $self->open_paren;

    #Search for the right field
    if ( $field eq 'Content' and RT->Config->Get('DontSearchFileAttachments') ) {
       $self->_sql_limit(
			alias         => $self->{_sql_trattachalias},
			column         => 'Filename',
			operator      => 'IS',
			value         => 'NULL',
			subclause     => 'contentquery',
			entry_aggregator => 'AND',
		       );
       $self->_sql_limit(
			alias         => $self->{_sql_trattachalias},
			column         => $field,
			operator      => $op,
			value         => $value,
			case_sensitive => 0,
			@rest,
			entry_aggregator => 'AND',
			subclause     => 'contentquery',
		       );
    } else {
        $self->_sql_limit(
			alias         => $self->{_sql_trattachalias},
			column         => $field,
			operator      => $op,
			value         => $value,
			case_sensitive => 0,
			entry_aggregator => 'AND',
			@rest
        );
    }

    $self->close_paren;

}

=head2 _WatcherLimit

Handle watcher limits.  (Requestor, CC, etc..)

Meta Data:
  1: Field to query on



=cut

sub _WatcherLimit {
    my $self  = shift;
    my $field = shift;
    my $op    = shift;
    my $value = shift;
    my %rest  = (@_);

    my $meta = $FIELD_METADATA{ $field };
    my $type = $meta->[1] || '';

    # Owner was ENUM field, so "Owner = 'xxx'" allowed user to
    # search by id and Name at the same time, this is workaround
    # to preserve backward compatibility
    if ( $field eq 'Owner' && !$rest{subkey} && $op =~ /^!?=$/ ) {
        my $o = RT::Model::User->new( $self->CurrentUser );
        $o->load( $value );
        $self->_sql_limit(
            column    => 'Owner',
            operator => $op,
            value    => $o->id,
            %rest,
        );
        return;
    }
    $rest{subkey} ||= 'EmailAddress';

    my $groups = $self->_RoleGroupsjoin( Type => $type );

    $self->open_paren;
    if ( $op =~ /^IS(?: NOT)?$/ ) {
        my $group_members = $self->_GroupMembersjoin( GroupsAlias => $groups );
        $self->SUPER::limit(
            leftjoin   => $group_members,
            column      => 'GroupId',
            operator   => '!=',
            value      => "$group_members.MemberId",
            quote_value => 0,
        );
        $self->_sql_limit(
            alias         => $group_members,
            column         => 'GroupId',
            operator      => $op,
            value         => $value,
            %rest,
        );
    }
    elsif ( $op =~ /^!=$|^NOT\s+/i ) {
        # reverse op
        $op =~ s/!|NOT\s+//i;

        # XXX: we have no way to build correct "Watcher.X != 'Y'" when condition
        # "X = 'Y'" matches more then one user so we try to fetch two records and
        # do the right thing when there is only one exist and semi-working solution
        # otherwise.
        my $users_obj = RT::Model::Users->new( $self->CurrentUser );
        $users_obj->limit(
            column         => $rest{subkey},
            operator      => $op,
            value         => $value,
        );
        $users_obj->order_by;
        $users_obj->rows_per_page(2);
        my @users = @{ $users_obj->items_array_ref };

        my $group_members = $self->_GroupMembersjoin( GroupsAlias => $groups );
        if ( @users <= 1 ) {
            my $uid = 0;
            $uid = $users[0]->id if @users;
            $self->SUPER::limit(
                leftjoin      => $group_members,
                alias         => $group_members,
                column         => 'MemberId',
                value         => $uid,
            );
            $self->_sql_limit(
                %rest,
                alias           => $group_members,
                column           => 'id',
                operator        => 'IS',
                value           => 'NULL',
            );
        } else {
            $self->SUPER::limit(
                leftjoin   => $group_members,
                column      => 'GroupId',
                operator   => '!=',
                value      => "$group_members.MemberId",
                quote_value => 0,
            );
            my $users = $self->join(
                type => 'left',
                alias1          => $group_members,
                column1          => 'MemberId',
                table2          => 'Users',
                column2          => 'id',
            );
            $self->SUPER::limit(
                leftjoin      => $users,
                alias         => $users,
                column         => $rest{subkey},
                operator      => $op,
                value         => $value,
                case_sensitive => 0,
            );
            $self->_sql_limit(
                %rest,
                alias         => $users,
                column         => 'id',
                operator      => 'IS',
                value         => 'NULL',
            );
        }
    } else {
        my $group_members = $self->_GroupMembersjoin(
            GroupsAlias => $groups,
            New => 0,
        );

        my $users = $self->{'_sql_u_watchers_aliases'}{$group_members};
        unless ( $users ) {
            $users = $self->{'_sql_u_watchers_aliases'}{$group_members} = 
                $self->new_alias('Users');
            $self->SUPER::limit(
                leftjoin      => $group_members,
                alias         => $group_members,
                column         => 'MemberId',
                value         => "$users.id",
                quote_value    => 0,
            );
        }

        $self->_sql_limit(
            alias         => $users,
            column         => $rest{subkey},
            value         => $value,
            operator      => $op,
            case_sensitive => 0,
            %rest,
        );
        $self->_sql_limit(
            entry_aggregator => 'AND',
            alias           => $group_members,
            column           => 'id',
            operator        => 'IS NOT',
            value           => 'NULL',
        );
    }
    $self->close_paren;
}

sub _RoleGroupsjoin {
    my $self = shift;
    my %args = (New => 0, Type => '', @_);
    return $self->{'_sql_role_group_aliases'}{ $args{'Type'} }
        if $self->{'_sql_role_group_aliases'}{ $args{'Type'} } && !$args{'New'};

    # XXX: this has been fixed in DBIx::SB-1.48
    # XXX: if we change this from join to new_alias+Limit
    # then Pg and mysql 5.x will complain because SB build wrong query.
    # Query looks like "FROM (Tickets left join CGM ON(Groups.id = CGM.GroupId)), Groups"
    # Pg doesn't like that fact that it doesn't know about Groups table yet when
    # join CGM table into Tickets. Problem is in join method which doesn't use
    # alias1 argument when build braces.

    # we always have watcher groups for ticket, so we use INNER join
    my $groups = $self->join(
        alias1          => 'main',
        column1          => 'id',
        table2          => 'Groups',
        column2          => 'Instance',
        entry_aggregator => 'AND',
    );
    $self->SUPER::limit(
        leftjoin        => $groups,
        alias           => $groups,
        column           => 'Domain',
        value           => 'RT::Model::Ticket-Role',
    );
    $self->SUPER::limit(
        leftjoin        => $groups,
        alias           => $groups,
        column           => 'Type',
        value           => $args{'Type'},
    ) if $args{'Type'};

    $self->{'_sql_role_group_aliases'}{ $args{'Type'} } = $groups
        unless $args{'New'};

    return $groups;
}

sub _GroupMembersjoin {
    my $self = shift;
    my %args = (New => 1, GroupsAlias => undef, @_);

    return $self->{'_sql_group_members_aliases'}{ $args{'GroupsAlias'} }
        if $self->{'_sql_group_members_aliases'}{ $args{'GroupsAlias'} }
            && !$args{'New'};

    my $alias = $self->join(
        type => 'left',
        alias1          => $args{'GroupsAlias'},
        column1          => 'id',
        table2          => 'CachedGroupMembers',
        column2          => 'GroupId',
        entry_aggregator => 'AND',
    );

    $self->{'_sql_group_members_aliases'}{ $args{'GroupsAlias'} } = $alias
        unless $args{'New'};

    return $alias;
}

=head2 _Watcherjoin

Helper function which provides joins to a watchers table both for limits
and for ordering.

=cut

sub _Watcherjoin {
    my $self = shift;
    my $type = shift || '';


    my $groups = $self->_RoleGroupsjoin( Type => $type );
    my $group_members = $self->_GroupMembersjoin( GroupsAlias => $groups );
    # XXX: work around, we must hide groups that
    # are members of the role group we search in,
    # otherwise them result in wrong NULLs in Users
    # table and break ordering. Now, we know that
    # RT doesn't allow to add groups as members of the
    # ticket roles, so we just hide entries in CGM table
    # with MemberId == GroupId from results
    $self->SUPER::limit(
        leftjoin   => $group_members,
        column      => 'GroupId',
        operator   => '!=',
        value      => "$group_members.MemberId",
        quote_value => 0,
    );
    my $users = $self->join(
        type => 'left',
        alias1          => $group_members,
        column1          => 'MemberId',
        table2          => 'Users',
        column2          => 'id',
    );
    return ($groups, $group_members, $users);
}

=head2 _WatcherMembershipLimit

Handle watcher membership limits, i.e. whether the watcher belongs to a
specific group or not.

Meta Data:
  1: Field to query on

SELECT DISTINCT main.*
FROM
    Tickets main,
    Groups Groups_1,
    CachedGroupMembers CachedGroupMembers_2,
    Users Users_3
WHERE (
    (main.EffectiveId = main.id)
) AND (
    (main.Status != 'deleted')
) AND (
    (main.Type = 'ticket')
) AND (
    (
	(Users_3.EmailAddress = '22')
	    AND
	(Groups_1.Domain = 'RT::Model::Ticket-Role')
	    AND
	(Groups_1.Type = 'RequestorGroup')
    )
) AND
    Groups_1.Instance = main.id
AND
    Groups_1.id = CachedGroupMembers_2.GroupId
AND
    CachedGroupMembers_2.MemberId = Users_3.id
order BY main.id ASC
LIMIT 25

=cut

sub _WatcherMembershipLimit {
    my ( $self, $field, $op, $value, @rest ) = @_;
    my %rest = @rest;

    $self->open_paren;

    my $groups       = $self->new_alias('Groups');
    my $groupmembers = $self->new_alias('CachedGroupMembers');
    my $users        = $self->new_alias('Users');
    my $memberships  = $self->new_alias('CachedGroupMembers');

    if ( ref $field ) {    # gross hack
        my @bundle = @$field;
        $self->open_paren;
        for my $chunk (@bundle) {
            ( $field, $op, $value, @rest ) = @$chunk;
            $self->_sql_limit(
                alias    => $memberships,
                column    => 'GroupId',
                value    => $value,
                operator => $op,
                @rest,
            );
        }
        $self->close_paren;
    }
    else {
        $self->_sql_limit(
            alias    => $memberships,
            column    => 'GroupId',
            value    => $value,
            operator => $op,
            @rest,
        );
    }

    # {{{ Tie to groups for tickets we care about
    $self->_sql_limit(
        alias           => $groups,
        column           => 'Domain',
        value           => 'RT::Model::Ticket-Role',
        entry_aggregator => 'AND'
    );

    $self->join(
        alias1 => $groups,
        column1 => 'Instance',
        alias2 => 'main',
        column2 => 'id'
    );

    # }}}

    # If we care about which sort of watcher
    my $meta = $FIELD_METADATA{$field};
    my $type = ( defined $meta->[1] ? $meta->[1] : undef );

    if ($type) {
        $self->_sql_limit(
            alias           => $groups,
            column           => 'Type',
            value           => $type,
            entry_aggregator => 'AND'
        );
    }

    $self->join(
        alias1 => $groups,
        column1 => 'id',
        alias2 => $groupmembers,
        column2 => 'GroupId'
    );

    $self->join(
        alias1 => $groupmembers,
        column1 => 'MemberId',
        alias2 => $users,
        column2 => 'id'
    );

    $self->join(
        alias1 => $memberships,
        column1 => 'MemberId',
        alias2 => $users,
        column2 => 'id'
    );

    $self->close_paren;

}

=head2 _CustomFieldDecipher

Try and turn a CF descriptor into (cfid, cfname) object pair.

=cut

sub _CustomFieldDecipher {
    my ($self, $string) = @_;

    my ($queue, $field, $column) =
        ($string =~ /^(?:(.+?)\.)?{(.+)}(?:\.(.+))?$/);
    $field ||= ($string =~ /^{(.*?)}$/)[0] || $string;

    my $cfid;
    if ( $queue ) {
        my $q = RT::Model::Queue->new( $self->CurrentUser );
        $q->load( $queue );

        my $cf;
        if ( $q->id ) {
            # $queue = $q->Name; # should we normalize the queue?
            $cf = $q->CustomField( $field );
        }
        else {
            $RT::Logger->warning("Queue '$queue' doesn't exists, parsed from '$string'");
            $queue = 0;
        }

        if ( $cf and my $id = $cf->id ) {
            $cfid = $cf->id;
            $field = $cf->Name;
        }
    } else {
        $queue = 0;
    }
 
    return ($queue, $field, $cfid, $column);
}
 
=head2 _CustomFieldjoin

Factor out the join of custom fields so we can use it for sorting too

=cut

sub _CustomFieldjoin {
    my ($self, $cfkey, $cfid, $field) = @_;
    # Perform one join per CustomField
    if ( $self->{_sql_object_cfv_alias}{$cfkey} ||
         $self->{_sql_cf_alias}{$cfkey} )
    {
        return ( $self->{_sql_object_cfv_alias}{$cfkey},
                 $self->{_sql_cf_alias}{$cfkey} );
    }

    my ($TicketCFs, $CFs);
    if ( $cfid ) {
        $TicketCFs = $self->{_sql_object_cfv_alias}{$cfkey} = $self->join(
            type => 'left',
            alias1 => 'main',
            column1 => 'id',
            table2 => 'ObjectCustomFieldValues',
            column2 => 'ObjectId',
        );
        $self->SUPER::limit(
            leftjoin        => $TicketCFs,
            column           => 'CustomField',
            value           => $cfid,
            entry_aggregator => 'AND'
        );
    }
    else {
        my $ocfalias = $self->join(
            type => 'left',
            column1     => 'Queue',
            table2     => 'ObjectCustomFields',
            column2     => 'ObjectId',
            entry_aggregator => 'OR',
        );

        $self->SUPER::limit(
            leftjoin        => $ocfalias,
            column           => 'ObjectId',
            value           => '0',
        );


        $CFs = $self->{_sql_cf_alias}{$cfkey} = $self->join(
            type => 'left',
            alias1     => $ocfalias,
            column1     => 'CustomField',
            table2     => 'CustomFields',
            column2     => 'id',
        );

        $TicketCFs = $self->{_sql_object_cfv_alias}{$cfkey} = $self->join(
            type => 'left',
            alias1 => $CFs,
            column1 => 'id',
            table2 => 'ObjectCustomFieldValues',
            column2 => 'CustomField',
        );
        $self->SUPER::limit(
            leftjoin        => $TicketCFs,
            column           => 'ObjectId',
            value           => 'main.id',
            quote_value      => 0,
            entry_aggregator => 'AND',
        );
    }
    $self->SUPER::limit(
        leftjoin        => $TicketCFs,
        column           => 'ObjectType',
        value           => 'RT::Model::Ticket',
        entry_aggregator => 'AND'
    );
    $self->SUPER::limit(
        leftjoin        => $TicketCFs,
        column           => 'Disabled',
        operator        => '=',
        value           => '0',
        entry_aggregator => 'AND'
    );

    return ($TicketCFs, $CFs);
}

=head2 _CustomFieldLimit

Limit based on CustomFields

Meta Data:
  none

=cut

sub _CustomFieldLimit {
    my ( $self, $_field, $op, $value, %rest ) = @_;

    my $field = $rest{'subkey'} || die "No field specified";

    # For our sanity, we can only limit on one queue at a time

    my ($queue, $cfid, $column);
    ($queue, $field, $cfid, $column) = $self->_CustomFieldDecipher( $field );

# If we're trying to find custom fields that don't match something, we
# want tickets where the custom field has no value at all.  Note that
# we explicitly don't include the "IS NULL" case, since we would
# otherwise end up with a redundant clause.

    my $null_columns_ok;
    if ( ( $op =~ /^NOT LIKE$/i ) or ( $op eq '!=' ) ) {
        $null_columns_ok = 1;
    }

    my $cfkey = $cfid ? $cfid : "$queue.$field";
    my ($TicketCFs, $CFs) = $self->_CustomFieldjoin( $cfkey, $cfid, $field );

    $self->open_paren;

    if ( $CFs && !$cfid ) {
        $self->SUPER::limit(
            alias           => $CFs,
            column           => 'Name',
            value           => $field,
            entry_aggregator => 'AND',
        );
    }

    $self->open_paren if $null_columns_ok;

    $self->_sql_limit(
        alias      => $TicketCFs,
        column      => $column || 'Content',
        operator   => $op,
        value      => $value,
        quote_value => 1,
        %rest
    );

    if ( $null_columns_ok ) {
        $self->_sql_limit(
            alias           => $TicketCFs,
            column           => $column || 'Content',
            operator        => 'IS',
            value           => 'NULL',
            quote_value      => 0,
            entry_aggregator => 'OR',
        );
        $self->close_paren;
    }

    $self->close_paren;

}

# End Helper Functions

# End of SQL Stuff -------------------------------------------------

# {{{ Allow sorting on watchers

=head2 order_by ARRAY

A modified version of the order_by method which automatically joins where
C<alias> is set to the name of a watcher type.

=cut

sub order_by {
    my $self = shift;
    my @args = ref ($_[0])? @_ : {@_};
    my $clause;
    my @res   = ();
    my $order = 0;

    foreach my $row (@args) {
        if ( $row->{alias} || $row->{column} !~ /\./ ) {
            push @res, $row;
            next;
        }
        my ( $field, $subkey ) = split /\./, $row->{column}, 2;
        my $meta = $self->columns->{$field};
        if ( $meta->[0] eq 'WATCHERFIELD' ) {
            # cache alias as we want to use one alias per watcher type for sorting
            my $users = $self->{_sql_u_watchers_alias_for_sort}{ $meta->[1] };
            unless ( $users ) {
                $self->{_sql_u_watchers_alias_for_sort}{ $meta->[1] }
                    = $users = ( $self->_Watcherjoin( $meta->[1] ) )[2];
            }
            push @res, { %$row, alias => $users, column => $subkey };
       } elsif ( $meta->[0] =~ /customfield/i ) {
           my ($queue, $field, $cfid ) = $self->_CustomFieldDecipher( $subkey );
           my $cfkey = $cfid ? $cfid : "$queue.$field";
           my ($TicketCFs, $CFs) = $self->_CustomFieldjoin( $cfkey, $cfid, $field );
           unless ($cfid) {
               # For those cases where we are doing a join against the
               # CF name, and don't have a CFid, use Unique to make sure
               # we don't show duplicate tickets.  NOTE: I'm pretty sure
               # this will stay mixed in for the life of the
               # class/package, and not just for the life of the object.
               # Potential performance issue.
               require Jifty::DBI::Collection::Unique;
               Jifty::DBI::Collection::Unique->import;
           }
           my $CFvs = $self->join(
               type => 'left',
               alias1 => $TicketCFs,
               column1 => 'CustomField',
               table2 => 'CustomFieldValues',
               column2 => 'CustomField',
           );
           $self->SUPER::limit(
               leftjoin => $CFvs,
               column => 'Name',
               quote_value => 0,
               value => $TicketCFs . ".Content",
               entry_aggregator => 'AND'
           );

           push @res, { %$row, alias => $CFvs, column => 'SortOrder' };
           push @res, { %$row, alias => $TicketCFs, column => 'Content' };
       } elsif ( $field eq "Custom" && $subkey eq "Ownership") {
           # PAW logic is "reversed"
           my $order = "ASC";
           if (exists $row->{order} ) {
               my $o = $row->{order};
               delete $row->{order};
               $order = "DESC" if $o =~ /asc/i;
           }

           # Unowned
           # Else

           # Ticket.Owner  1 0 0
           my $ownerId = $self->CurrentUser->id;
           push @res, { %$row, column => "Owner=$ownerId", order => $order } ;

           # Unowned Tickets 0 1 0
           my $nobodyId = $RT::Nobody->id;
           push @res, { %$row, column => "Owner=$nobodyId", order => $order } ;

           push @res, { %$row, column => "Priority", order => $order } ;
       }
       else {
           push @res, $row;
       }
    }
    return $self->SUPER::order_by(@res);
}

# }}}



=head2 limit

Takes a paramhash with the fields column, operator, value and description
Generally best called from LimitFoo methods

=cut

sub limit {
    my $self = shift;
    my %args = (
        column       => undef,
        operator    => '=',
        value       => undef,
        description => undef,
        @_
    );
    $args{'description'} = $self->loc(
        "[_1] [_2] [_3]",  $args{'column'},
        $args{'operator'}, $args{'value'}
        )
        if ( !defined $args{'description'} );

    my $index = $self->_nextIndex;

# make the TicketRestrictions hash the equivalent of whatever we just passed in;

    %{ $self->{'TicketRestrictions'}{$index} } = %args;

    $self->{'RecalcTicketLimits'} = 1;

# If we're looking at the effective id, we don't want to append the other clause
# which limits us to tickets where id = effective id
    if ( $args{'column'} eq 'EffectiveId'
        && ( !$args{'alias'} || $args{'alias'} eq 'main' ) )
    {
        $self->{'looking_at_effective_id'} = 1;
    }

    if ( $args{'column'} eq 'Type'
        && ( !$args{'alias'} || $args{'alias'} eq 'main' ) )
    {
        $self->{'looking_at_type'} = 1;
    }

    return ($index);
}

# }}}

=head2 FreezeLimits

Returns a frozen string suitable for handing back to ThawLimits.

=cut

sub _FreezeThawKeys {
    'TicketRestrictions', 'restriction_index', 'looking_at_effective_id',
        'looking_at_type';
}

# {{{ sub FreezeLimits

sub FreezeLimits {
    my $self = shift;
    require Storable;
    require MIME::Base64;
    MIME::Base64::base64_encode(
        Storable::freeze( \@{$self}{ $self->_FreezeThawKeys } ) );
}

# }}}

=head2 ThawLimits

Take a frozen Limits string generated by FreezeLimits and make this tickets
object have that set of limits.

=cut

# {{{ sub ThawLimits

sub ThawLimits {
    my $self = shift;
    my $in   = shift;

    #if we don't have $in, get outta here.
    return undef unless ($in);

    $self->{'RecalcTicketLimits'} = 1;

    require Storable;
    require MIME::Base64;

    #We don't need to die if the thaw fails.
    @{$self}{ $self->_FreezeThawKeys }
        = eval { @{ Storable::thaw( MIME::Base64::base64_decode($in) ) }; };

    $RT::Logger->error($@) if $@;

}

# }}}

# {{{ Limit by enum or foreign key

# {{{ sub LimitQueue

=head2 LimitQueue

LimitQueue takes a paramhash with the fields operator and value.
operator is one of = or !=. (It defaults to =).
value is a queue id or Name.


=cut

sub LimitQueue {
    my $self = shift;
    my %args = (
        value    => undef,
        operator => '=',
        @_
    );

    #TODO  value should also take queue objects
    if ( defined $args{'value'} && $args{'value'} !~ /^\d+$/ ) {
        my $queue = new RT::Model::Queue( $self->CurrentUser );
        $queue->load( $args{'value'} );
        $args{'value'} = $queue->id;
    }

    # What if they pass in an Id?  Check for isNum() and convert to
    # string.

    #TODO check for a valid queue here

    $self->limit(
        column       => 'Queue',
        value       => $args{'value'},
        operator    => $args{'operator'},
        description => join(
            ' ', $self->loc('Queue'), $args{'operator'}, $args{'value'},
        ),
    );

}

# }}}

# {{{ sub LimitStatus

=head2 LimitStatus

Takes a paramhash with the fields operator and value.
operator is one of = or !=.
value is a status.

RT adds Status != 'deleted' until object has
allow_deleted_search internal property set.
$tickets->{'allow_deleted_search'} = 1;
$tickets->LimitStatus( value => 'deleted' );

=cut

sub LimitStatus {
    my $self = shift;
    my %args = (
        operator => '=',
        @_
    );
    $self->limit(
        column       => 'Status',
        value       => $args{'value'},
        operator    => $args{'operator'},
        description => join( ' ',
            $self->loc('Status'), $args{'operator'},
            $self->loc( $args{'value'} ) ),
    );
}

# }}}

# {{{ sub IgnoreType

=head2 IgnoreType

If called, this search will not automatically limit the set of results found
to tickets of type "Ticket". Tickets of other types, such as "project" and
"approval" will be found.

=cut

sub IgnoreType {
    my $self = shift;

    # Instead of faking a Limit that later gets ignored, fake up the
    # fact that we're already looking at type, so that the check in
    # Tickets_Overlay_SQL/from_sql goes down the right branch

    #  $self->LimitType(value => '__any');
    $self->{looking_at_type} = 1;
}

# }}}

# {{{ sub LimitType

=head2 LimitType

Takes a paramhash with the fields operator and value.
operator is one of = or !=, it defaults to "=".
value is a string to search for in the type of the ticket.



=cut

sub LimitType {
    my $self = shift;
    my %args = (
        operator => '=',
        value    => undef,
        @_
    );
    $self->limit(
        column       => 'Type',
        value       => $args{'value'},
        operator    => $args{'operator'},
        description => join( ' ',
            $self->loc('Type'), $args{'operator'}, $args{'Limit'}, ),
    );
}

# }}}

# }}}

# {{{ Limit by string field

# {{{ sub LimitSubject

=head2 LimitSubject

Takes a paramhash with the fields operator and value.
operator is one of = or !=.
value is a string to search for in the subject of the ticket.

=cut

sub LimitSubject {
    my $self = shift;
    my %args = (@_);
    $self->limit(
        column       => 'Subject',
        value       => $args{'value'},
        operator    => $args{'operator'},
        description => join( ' ',
            $self->loc('Subject'), $args{'operator'}, $args{'value'}, ),
    );
}

# }}}

# }}}

# {{{ Limit based on ticket numerical attributes
# Things that can be > < = !=

# {{{ sub LimitId

=head2 LimitId

Takes a paramhash with the fields operator and value.
operator is one of =, >, < or !=.
value is a ticket Id to search for

=cut

sub LimitId {
    my $self = shift;
    my %args = (
        operator => '=',
        @_
    );

    $self->limit(
        column       => 'id',
        value       => $args{'value'},
        operator    => $args{'operator'},
        description =>
            join( ' ', $self->loc('Id'), $args{'operator'}, $args{'value'}, ),
    );
}

# }}}

# {{{ sub LimitPriority

=head2 LimitPriority

Takes a paramhash with the fields operator and value.
operator is one of =, >, < or !=.
value is a value to match the ticket\'s priority against

=cut

sub LimitPriority {
    my $self = shift;
    my %args = (@_);
    $self->limit(
        column       => 'Priority',
        value       => $args{'value'},
        operator    => $args{'operator'},
        description => join( ' ',
            $self->loc('Priority'),
            $args{'operator'}, $args{'value'}, ),
    );
}

# }}}

# {{{ sub LimitInitialPriority

=head2 LimitInitialPriority

Takes a paramhash with the fields operator and value.
operator is one of =, >, < or !=.
value is a value to match the ticket\'s initial priority against


=cut

sub LimitInitialPriority {
    my $self = shift;
    my %args = (@_);
    $self->limit(
        column       => 'InitialPriority',
        value       => $args{'value'},
        operator    => $args{'operator'},
        description => join( ' ',
            $self->loc('Initial Priority'), $args{'operator'},
            $args{'value'}, ),
    );
}

# }}}

# {{{ sub LimitFinalPriority

=head2 LimitFinalPriority

Takes a paramhash with the fields operator and value.
operator is one of =, >, < or !=.
value is a value to match the ticket\'s final priority against

=cut

sub LimitFinalPriority {
    my $self = shift;
    my %args = (@_);
    $self->limit(
        column       => 'FinalPriority',
        value       => $args{'value'},
        operator    => $args{'operator'},
        description => join( ' ',
            $self->loc('Final Priority'), $args{'operator'},
            $args{'value'}, ),
    );
}

# }}}

# {{{ sub LimitTimeWorked

=head2 LimitTimeWorked

Takes a paramhash with the fields operator and value.
operator is one of =, >, < or !=.
value is a value to match the ticket's TimeWorked attribute

=cut

sub LimitTimeWorked {
    my $self = shift;
    my %args = (@_);
    $self->limit(
        column       => 'TimeWorked',
        value       => $args{'value'},
        operator    => $args{'operator'},
        description => join( ' ',
            $self->loc('Time worked'),
            $args{'operator'}, $args{'value'}, ),
    );
}

# }}}

# {{{ sub LimitTimeLeft

=head2 LimitTimeLeft

Takes a paramhash with the fields operator and value.
operator is one of =, >, < or !=.
value is a value to match the ticket's TimeLeft attribute

=cut

sub LimitTimeLeft {
    my $self = shift;
    my %args = (@_);
    $self->limit(
        column       => 'TimeLeft',
        value       => $args{'value'},
        operator    => $args{'operator'},
        description => join( ' ',
            $self->loc('Time left'),
            $args{'operator'}, $args{'value'}, ),
    );
}

# }}}

# }}}

# {{{ Limiting based on attachment attributes

# {{{ sub LimitContent

=head2 LimitContent

Takes a paramhash with the fields operator and value.
operator is one of =, LIKE, NOT LIKE or !=.
value is a string to search for in the body of the ticket

=cut

sub LimitContent {
    my $self = shift;
    my %args = (@_);
    $self->limit(
        column       => 'Content',
        value       => $args{'value'},
        operator    => $args{'operator'},
        description => join( ' ',
            $self->loc('Ticket content'), $args{'operator'},
            $args{'value'}, ),
    );
}

# }}}

# {{{ sub LimitFilename

=head2 LimitFilename

Takes a paramhash with the fields operator and value.
operator is one of =, LIKE, NOT LIKE or !=.
value is a string to search for in the body of the ticket

=cut

sub LimitFilename {
    my $self = shift;
    my %args = (@_);
    $self->limit(
        column       => 'Filename',
        value       => $args{'value'},
        operator    => $args{'operator'},
        description => join( ' ',
            $self->loc('Attachment filename'), $args{'operator'},
            $args{'value'}, ),
    );
}

# }}}
# {{{ sub LimitContentType

=head2 LimitContentType

Takes a paramhash with the fields operator and value.
operator is one of =, LIKE, NOT LIKE or !=.
value is a content type to search ticket attachments for

=cut

sub LimitContentType {
    my $self = shift;
    my %args = (@_);
    $self->limit(
        column       => 'ContentType',
        value       => $args{'value'},
        operator    => $args{'operator'},
        description => join( ' ',
            $self->loc('Ticket content type'), $args{'operator'},
            $args{'value'}, ),
    );
}

# }}}

# }}}

# {{{ Limiting based on people

# {{{ sub LimitOwner

=head2 LimitOwner

Takes a paramhash with the fields operator and value.
operator is one of = or !=.
value is a user id.

=cut

sub LimitOwner {
    my $self = shift;
    my %args = (
        operator => '=',
        @_
    );

    my $owner = new RT::Model::User( $self->CurrentUser );
    $owner->load( $args{'value'} );

    # FIXME: check for a valid $owner
    $self->limit(
        column       => 'Owner',
        value       => $args{'value'},
        operator    => $args{'operator'},
        description => join( ' ',
            $self->loc('Owner'), $args{'operator'}, $owner->Name(), ),
    );

}

# }}}

# {{{ Limiting watchers

# {{{ sub LimitWatcher

=head2 LimitWatcher

  Takes a paramhash with the fields operator, type and value.
  operator is one of =, LIKE, NOT LIKE or !=.
  value is a value to match the ticket\'s watcher email addresses against
  type is the sort of watchers you want to match against. Leave it undef if you want to search all of them


=cut

sub LimitWatcher {
    my $self = shift;
    my %args = (
        operator => '=',
        value    => undef,
        type => undef,
        @_
    );

    #build us up a description
    my ( $watcher_type, $desc );
    if ( $args{'type'} ) {
        $watcher_type = $args{'type'};
    }
    else {
        $watcher_type = "Watcher";
    }

    $self->limit(
        column       => $watcher_type,
        value       => $args{'value'},
        operator    => $args{'operator'},
        type => $args{'type'},
        description => join( ' ',
            $self->loc($watcher_type),
            $args{'operator'}, $args{'value'}, ),
    );
}

# }}}

# }}}

# }}}

# {{{ Limiting based on links

# {{{ LimitLinkedTo

=head2 LimitLinkedTo

LimitLinkedTo takes a paramhash with two fields: type and target
type limits the sort of link we want to search on

type = { RefersTo, MemberOf, DependsOn }

target is the id or URI of the target of the link

=cut

sub LimitLinkedTo {
    my $self = shift;
    my %args = (
        target   => undef,
        type => undef,
        operator => '=',
        @_
    );

    $self->limit(
        column       => 'LinkedTo',
        base        => undef,
        target      => $args{'target'},
        type => $args{'type'},
        description => $self->loc(
            "Tickets [_1] by [_2]",
            $self->loc( $args{'type'} ),
            $args{'target'}
        ),
        operator    => $args{'operator'},
    );
}

# }}}

# {{{ LimitLinkedFrom

=head2 LimitLinkedFrom

LimitLinkedFrom takes a paramhash with two fields: type and base
type limits the sort of link we want to search on


base is the id or URI of the base of the link

=cut

sub LimitLinkedFrom {
    my $self = shift;
    my %args = (
        base     => undef,
        type => undef,
        operator => '=',
        @_
    );

    # translate RT2 From/To naming to RT3 TicketSQL naming
    my %fromToMap = qw(DependsOn DependentOn
        MemberOf  has_member
        RefersTo  ReferredToBy);

    my $type = $args{'type'};
    $type = $fromToMap{$type} if exists( $fromToMap{$type} );

    $self->limit(
        column       => 'LinkedTo',
        target      => undef,
        base        => $args{'base'},
        type => $type,
        description => $self->loc(
            "Tickets [_1] [_2]",
            $self->loc( $args{'type'} ),
            $args{'base'},
        ),
        operator    => $args{'operator'},
    );
}

# }}}

# {{{ limit_member_of
sub limit_member_of {
    my $self      = shift;
    my $ticket_id = shift;
    return $self->LimitLinkedTo(
        @_,
        target => $ticket_id,
        type => 'MemberOf',
    );
}

# }}}

# {{{ limit_has_member
sub limit_has_member {
    my $self      = shift;
    my $ticket_id = shift;
    return $self->LimitLinkedFrom(
        @_,
        base => "$ticket_id",
        type => 'has_member',
    );

}

# }}}

# {{{ LimitDependsOn

sub LimitDependsOn {
    my $self      = shift;
    my $ticket_id = shift;
    return $self->LimitLinkedTo(
        @_,
        target => $ticket_id,
        type => 'DependsOn',
    );

}

# }}}

# {{{ limit_depended_on_by

sub limit_depended_on_by {
    my $self      = shift;
    my $ticket_id = shift;
    return $self->LimitLinkedFrom(
        @_,
        base => $ticket_id,
        type => 'DependentOn',
    );

}

# }}}

# {{{ LimitRefersTo

sub LimitRefersTo {
    my $self      = shift;
    my $ticket_id = shift;
    return $self->LimitLinkedTo(
        @_,
        target => $ticket_id,
        type => 'RefersTo',
    );

}

# }}}

# {{{ LimitReferredToBy

sub LimitReferredToBy {
    my $self      = shift;
    my $ticket_id = shift;
    return $self->LimitLinkedFrom(
        @_,
        base => $ticket_id,
        type => 'ReferredToBy',
    );
}

# }}}

# }}}

# {{{ limit based on ticket date attribtes

# {{{ sub LimitDate

=head2 LimitDate (column => 'DateField', operator => $oper, value => $ISODate)

Takes a paramhash with the fields column operator and value.

operator is one of > or <
value is a date and time in ISO format in GMT
column is one of Starts, Started, Told, Created, Resolved, LastUpdated

There are also helper functions of the form Limitcolumn that eliminate
the need to pass in a column argument.

=cut

sub LimitDate {
    my $self = shift;
    my %args = (
        column    => undef,
        value    => undef,
        operator => undef,

        @_
    );

    #Set the description if we didn't get handed it above
    unless ( $args{'description'} ) {
        $args{'description'} = $args{'column'} . " "
            . $args{'operator'} . " "
            . $args{'value'} . " GMT";
    }

    $self->limit(%args);

}

# }}}

sub LimitCreated {
    my $self = shift;
    $self->LimitDate( column => 'Created', @_ );
}

sub LimitDue {
    my $self = shift;
    $self->LimitDate( column => 'Due', @_ );

}

sub LimitStarts {
    my $self = shift;
    $self->LimitDate( column => 'Starts', @_ );

}

sub LimitStarted {
    my $self = shift;
    $self->LimitDate( column => 'Started', @_ );
}

sub LimitResolved {
    my $self = shift;
    $self->LimitDate( column => 'Resolved', @_ );
}

sub LimitTold {
    my $self = shift;
    $self->LimitDate( column => 'Told', @_ );
}

sub LimitLastUpdated {
    my $self = shift;
    $self->LimitDate( column => 'LastUpdated', @_ );
}

#
# {{{ sub LimitTransactionDate

=head2 LimitTransactionDate (operator => $oper, value => $ISODate)

Takes a paramhash with the fields column operator and value.

operator is one of > or <
value is a date and time in ISO format in GMT


=cut

sub LimitTransactionDate {
    my $self = shift;
    my %args = (
        column    => 'TransactionDate',
        value    => undef,
        operator => undef,

        @_
    );

    #  <20021217042756.GK28744@pallas.fsck.com>
    #    "Kill It" - Jesse.

    #Set the description if we didn't get handed it above
    unless ( $args{'description'} ) {
        $args{'description'} = $args{'column'} . " "
            . $args{'operator'} . " "
            . $args{'value'} . " GMT";
    }

    $self->limit(%args);

}

# }}}

# }}}

# {{{ Limit based on custom fields
# {{{ sub LimitCustomField

=head2 LimitCustomField

Takes a paramhash of key/value pairs with the following keys:

=over 4

=item customfield - CustomField name or id.  If a name is passed, an additional parameter queue may also be passed to distinguish the custom field.

=item operator - The usual Limit operators

=item value - The value to compare against

=back

=cut

sub LimitCustomField {
    my $self = shift;
    my %args = (
        value       => undef,
        customfield => undef,
        operator    => '=',
        description => undef,
        column       => 'CustomFieldValue',
        quote_value  => 1,
        @_
    );

    warn "Limiting to a cf";
    my $CF = RT::Model::CustomField->new( $self->CurrentUser );
    if ( $args{customfield} =~ /^\d+$/ ) {
        $CF->load( $args{customfield} );
    }
    else {
        $CF->load_by_name_and_queue(
            Name  => $args{customfield},
            Queue => $args{queue}
        );
        $args{customfield} = $CF->id;
    }

    #If we are looking to compare with a null value.
    if ( $args{'operator'} =~ /^is$/i ) {
        $args{'description'}
            ||= $self->loc( "Custom field [_1] has no value.", $CF->Name );
    }
    elsif ( $args{'operator'} =~ /^is not$/i ) {
        $args{'description'}
            ||= $self->loc( "Custom field [_1] has a value.", $CF->Name );
    }

    # if we're not looking to compare with a null value
    else {
        $args{'description'} ||= $self->loc( "Custom field [_1] [_2] [_3]",
            $CF->Name, $args{operator}, $args{value} );
    }

    my $q = "";
    if ( $CF->Queue ) {
        my $qo = new RT::Model::Queue( $self->CurrentUser );
        $qo->load( $CF->Queue );
        $q = $qo->Name;
    }

    my @rest;
    @rest = ( entry_aggregator => 'AND' )
        if ( $CF->Type eq 'SelectMultiple' );

        warn "Limiting  ";
    $self->limit(
        value => $args{value},
        column => "CF."
            . (
              $q
            ? $q . ".{" . $CF->Name . "}"
            : $CF->Name
            ),
        operator    => $args{operator},
        customfield => 1,
        @rest,
    );

    $self->{'RecalcTicketLimits'} = 1;
}

# }}}
# }}}

# {{{ sub _nextIndex

=head2 _nextIndex

Keep track of the counter for the array of restrictions

=cut

sub _nextIndex {
    my $self = shift;
    return ( $self->{'restriction_index'}++ );
}

# }}}

# }}}

# {{{ Core bits to make this a Jifty::DBI object

# {{{ sub _init
sub _init {
    my $self = shift;
    $self->{'table'}                   = "Tickets";
    $self->{'RecalcTicketLimits'}      = 1;
    $self->{'looking_at_effective_id'} = 0;
    $self->{'looking_at_type'}         = 0;
    $self->{'restriction_index'}       = 1;
    $self->{'primary_key'}             = "id";
    delete $self->{'items_array'};
    delete $self->{'item_map'};
    delete $self->{'columns_to_display'};
    $self->SUPER::_init(@_);

    $self->_initSQL;

}

# }}}

# {{{ sub count
sub count {
    my $self = shift;
    $self->_ProcessRestrictions() if ( $self->{'RecalcTicketLimits'} == 1 );
    return ( $self->SUPER::count() );
}

# }}}

# {{{ sub count_all
sub count_all {
    my $self = shift;
    $self->_ProcessRestrictions() if ( $self->{'RecalcTicketLimits'} == 1 );
    return ( $self->SUPER::count_all() );
}

# }}}

# {{{ sub items_array_ref

=head2 items_array_ref

Returns a reference to the set of all items found in this search

=cut

sub items_array_ref {
    my $self = shift;
    my @items;

    unless ( $self->{'items_array'} ) {

        my $placeholder = $self->_ItemsCounter;
        $self->goto_first_item();
        while ( my $item = $self->next ) {
            push( @{ $self->{'items_array'} }, $item );
        }
        $self->GotoItem($placeholder);
        $self->{'items_array'}
            = $self->items_order_by( $self->{'items_array'} );
    }
    return ( $self->{'items_array'} );
}

# }}}

# {{{ sub next
sub next {
    my $self = shift;

    $self->_ProcessRestrictions() if ( $self->{'RecalcTicketLimits'} == 1 );

    my $Ticket = $self->SUPER::next();
    if ( ( defined($Ticket) ) and ( ref($Ticket) ) ) {

        if ( $Ticket->__value('Status') eq 'deleted'
            && !$self->{'allow_deleted_search'} )
        {
            return ( $self->next() );
        }

        # Since Ticket could be granted with more rights instead
        # of being revoked, it's ok if queue rights allow
        # ShowTicket.  It seems need another query, but we have
        # rights cache in Principal::has_right.
        elsif ($Ticket->QueueObj->current_user_has_right('ShowTicket')
            || $Ticket->current_user_has_right('ShowTicket') )
        {
            return ($Ticket);
        }

        if ( $Ticket->__value('Status') eq 'deleted' ) {
            return ( $self->next() );
        }

        # Since Ticket could be granted with more rights instead
        # of being revoked, it's ok if queue rights allow
        # ShowTicket.  It seems need another query, but we have
        # rights cache in Principal::has_right.
        elsif ($Ticket->QueueObj->current_user_has_right('ShowTicket')
            || $Ticket->current_user_has_right('ShowTicket') )
        {
            return ($Ticket);
        }

        #If the user doesn't have the right to show this ticket
        else {
            return ( $self->next() );
        }
    }

    #if there never was any ticket
    else {
        return (undef);
    }

}

# }}}

# }}}

# {{{ Deal with storing and restoring restrictions

# {{{ sub loadRestrictions

=head2 LoadRestrictions

LoadRestrictions takes a string which can fully populate the TicketRestrictons hash.
TODO It is not yet implemented

=cut

# }}}

# {{{ sub DescribeRestrictions

=head2 DescribeRestrictions

takes nothing.
Returns a hash keyed by restriction id.
Each element of the hash is currently a one element hash that contains description which
is a description of the purpose of that TicketRestriction

=cut

sub DescribeRestrictions {
    my $self = shift;

    my ( $row, %listing );

    foreach $row ( keys %{ $self->{'TicketRestrictions'} } ) {
        $listing{$row} = $self->{'TicketRestrictions'}{$row}{'description'};
    }
    return (%listing);
}

# }}}

# {{{ sub RestrictionValues

=head2 RestrictionValues column

Takes a restriction field and returns a list of values this field is restricted
to.

=cut

sub RestrictionValues {
    my $self  = shift;
    my $field = shift;
    map $self->{'TicketRestrictions'}{$_}{'value'}, grep {
               $self->{'TicketRestrictions'}{$_}{'column'}    eq $field
            && $self->{'TicketRestrictions'}{$_}{'operator'} eq "="
        }
        keys %{ $self->{'TicketRestrictions'} };
}

# }}}

# {{{ sub ClearRestrictions

=head2 ClearRestrictions

Removes all restrictions irretrievably

=cut

sub ClearRestrictions {
    my $self = shift;
    delete $self->{'TicketRestrictions'};
    $self->{'looking_at_effective_id'} = 0;
    $self->{'looking_at_type'}         = 0;
    $self->{'RecalcTicketLimits'}      = 1;
}

# }}}

# {{{ sub deleteRestriction

=head2 DeleteRestriction

Takes the row Id of a restriction (From DescribeRestrictions' output, for example.
Removes that restriction from the session's limits.

=cut

sub deleteRestriction {
    my $self = shift;
    my $row  = shift;
    delete $self->{'TicketRestrictions'}{$row};

    $self->{'RecalcTicketLimits'} = 1;

    #make the underlying easysearch object forget all its preconceptions
}

# }}}

# {{{ sub _RestrictionsToClauses

# Convert a set of oldstyle SB Restrictions to Clauses for RQL

sub _RestrictionsToClauses {
    my $self = shift;

    my $row;
    my %clause;
    foreach $row ( keys %{ $self->{'TicketRestrictions'} } ) {
        my $restriction = $self->{'TicketRestrictions'}{$row};

        # We need to reimplement the subclause aggregation that SearchBuilder does.
        # Default Subclause is alias.column, and default alias is 'main',
        # Then SB AND's the different Subclauses together.

        # So, we want to group things into Subclauses, convert them to
        # SQL, and then join them with the appropriate DefaultEA.
        # Then join each subclause group with AND.

        my $field = $restriction->{'column'};
        my $realfield = $field;    # CustomFields fake up a fieldname, so
                                   # we need to figure that out

        # One special case
        # Rewrite LinkedTo meta field to the real field
        if ( $field =~ /LinkedTo/ ) {
            $realfield = $field = $restriction->{'type'};
        }

        # Two special case
        # Handle subkey fields with a different real field
        if ( $field =~ /^(\w+)\./ ) {
            $realfield = $1;
        }

        die "I don't know about $field yet"
            unless ( exists $FIELD_METADATA{$realfield}
                or $restriction->{customfield} );

        my $type = $FIELD_METADATA{$realfield}->[0];
        my $op   = $restriction->{'operator'};

        my $value = (
            grep    {defined}
                map { $restriction->{$_} } qw(value TICKET base target)
        )[0];

        # this performs the moral equivalent of defined or/dor/C<//>,
        # without the short circuiting.You need to use a 'defined or'
        # type thing instead of just checking for truth values, because
        # value could be 0.(i.e. "false")

        # You could also use this, but I find it less aesthetic:
        # (although it does short circuit)
        #( defined $restriction->{'value'}? $restriction->{value} :
        # defined $restriction->{'TICKET'} ?
        # $restriction->{TICKET} :
        # defined $restriction->{'base'} ?
        # $restriction->{base} :
        # defined $restriction->{'target'} ?
        # $restriction->{target} )

        my $ea = $restriction->{entry_aggregator}
            || $DefaultEA{$type}
            || "AND";
        if ( ref $ea ) {
            die "Invalid operator $op for $field ($type)"
                unless exists $ea->{$op};
            $ea = $ea->{$op};
        }

        # Each CustomField should be put into a different Clause so they
        # are ANDed together.
        if ( $restriction->{customfield} ) {
            $realfield = $field;
        }

        exists $clause{$realfield} or $clause{$realfield} = [];

        # Escape Quotes
        $field =~ s!(['"])!\\$1!g;
        $value =~ s!(['"])!\\$1!g;
        my $data = [ $ea, $type, $field, $op, $value ];

        # here is where we store extra data, say if it's a keyword or
        # something.  (I.e. "type SPECIFIC STUFF")

        push @{ $clause{$realfield} }, $data;
    }
    return \%clause;
}

# }}}

# {{{ sub _ProcessRestrictions

=head2 _ProcessRestrictions PARAMHASH

# The new _ProcessRestrictions is somewhat dependent on the SQL stuff,
# but isn't quite generic enough to move into Tickets_Overlay_SQL.

=cut

sub _ProcessRestrictions {
    my $self = shift;

    #Blow away ticket aliases since we'll need to regenerate them for
    #a new search
    delete $self->{'TicketAliases'};
    delete $self->{'items_array'};
    delete $self->{'item_map'};
    delete $self->{'raw_rows'};
    delete $self->{'rows'};
    delete $self->{'count_all'};

    my $sql = $self->Query;    # Violating the _SQL namespace
    if ( !$sql || $self->{'RecalcTicketLimits'} ) {

        #  "Restrictions to Clauses Branch\n";
        my $clauseRef = eval { $self->_RestrictionsToClauses; };
        if ($@) {
            $RT::Logger->error( "RestrictionsToClauses: " . $@ );
            $self->from_sql("");
        }
        else {
            $sql = $self->ClausesToSQL($clauseRef);
            $self->from_sql($sql) if $sql;
        }
    }

    $self->{'RecalcTicketLimits'} = 0;

}

=head2 _BuildItemMap

    # Build up a map of first/last/next/prev items, so that we can display search nav quickly

=cut

sub _BuildItemMap {
    my $self = shift;

    my $items = $self->items_array_ref;
    my $prev  = 0;

    delete $self->{'item_map'};
    if ( $items->[0] ) {
        $self->{'item_map'}->{'first'} = $items->[0]->EffectiveId;
        while ( my $item = shift @$items ) {
            my $id = $item->EffectiveId;
            $self->{'item_map'}->{$id}->{'defined'} = 1;
            $self->{'item_map'}->{$id}->{prev}      = $prev;
            $self->{'item_map'}->{$id}->{next}      = $items->[0]->EffectiveId
                if ( $items->[0] );
            $prev = $id;
        }
        $self->{'item_map'}->{'last'} = $prev;
    }
}

=head2 ItemMap

Returns an a map of all items found by this search. The map is of the form

$ItemMap->{'first'} = first ticketid found
$ItemMap->{'last'} = last ticketid found
$ItemMap->{$id}->{prev} = the ticket id found before $id
$ItemMap->{$id}->{next} = the ticket id found after $id

=cut

sub ItemMap {
    my $self = shift;
    $self->_BuildItemMap()
        unless ( $self->{'items_array'} and $self->{'item_map'} );
    return ( $self->{'item_map'} );
}

=cut



}



# }}}

# }}}

=head2 PrepForSerialization

You don't want to serialize a big tickets object, as the {items} hash will be instantly invalid _and_ eat lots of space

=cut

sub PrepForSerialization {
    my $self = shift;
    delete $self->{'items'};
    $self->redo_search();
}

=head1 FLAGS

RT::Model::Tickets supports several flags which alter search behavior:


allow_deleted_search  (Otherwise never show deleted tickets in search results)
looking_at_type (otherwise limit to type=ticket)

These flags are set by calling 

$tickets->{'flagname'} = 1;

BUG: There should be an API for this

=cut


=cut

1;


