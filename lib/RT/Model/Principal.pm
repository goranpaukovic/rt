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
#

package RT::Model::Principal;

use strict;
use warnings;

use Cache::Simple::TimedExpiry;


use RT;
use RT::Model::Group;
use RT::Model::User;

use base qw/RT::Record/;

use Jifty::DBI::Schema;
use Jifty::DBI::Record schema {

    column PrincipalType => type is 'text';
    column ObjectId      => type is 'integer';
    column Disabled      => type is 'integer';

};

sub table {'Principals'}

# Set up the ACL cache on startup
our $_ACL_CACHE;
invalidate_acl_cache();

# {{{ IsGroup

=head2 IsGroup

Returns true if this principal is a group. 
Returns undef, otherwise

=cut

sub IsGroup {
    my $self = shift;
    if ( $self->PrincipalType eq 'Group' ) {
        return 1;
    }
    return undef;
}

# }}}

# {{{ IsUser

=head2 IsUser 

Returns true if this principal is a User. 
Returns undef, otherwise

=cut

sub IsUser {
    my $self = shift;
    if ($self->PrincipalType eq 'User') {
        return(1);
    }
    else {
        return undef;
    }
}

# }}}

# {{{ Object

=head2 Object

Returns the user or group associated with this principal

=cut

sub Object {
    my $self = shift;

    unless ( $self->{'object'} ) {
        if ( $self->IsUser ) {
           $self->{'object'} = RT::Model::User->new($self->CurrentUser);
        }
        elsif ( $self->IsGroup ) {
            $self->{'object'}  = RT::Model::Group->new($self->CurrentUser);
        }
        else { 
            return(undef);
        }
        $self->{'object'}->load( $self->ObjectId() );
    }
    return ($self->{'object'});


}
# }}} 

# {{{ ACL Related routines

# {{{ GrantRight 

=head2 GrantRight  { Right => RIGHTNAME, Object => undef }

A helper function which calls RT::Model::ACE->create



   Returns a tuple of (STATUS, MESSAGE);  If the call succeeded, STATUS is true. Otherwise it's 
   false.

=cut

sub GrantRight {
    my $self = shift;
    my %args = ( Right => undef,
                Object => undef,
                @_);


    unless ($args{'Right'}) {
        return(0, $self->loc("Invalid Right"));
    }


    #ACL check handled in ACE.pm
    my $ace = RT::Model::ACE->new( $self->CurrentUser );


    my $type = $self->_GetPrincipalTypeForACL();

    # If it's a user, we really want to grant the right to their 
    # user equivalence group
        return ( $ace->create(RightName => $args{'Right'},
                          Object => $args{'Object'},
                          PrincipalType =>  $type,
                          PrincipalId => $self->id
                          ) );
}
# }}}

# {{{ RevokeRight

=head2 RevokeRight { Right => "RightName", Object => "object" }

Delete a right that a user has 


   Returns a tuple of (STATUS, MESSAGE);  If the call succeeded, STATUS is true. Otherwise it's 
      false.


=cut

sub RevokeRight {

    my $self = shift;
    my %args = (
        Right      => undef,
        Object => undef,
        @_
    );

    #if we haven't specified any sort of right, we're talking about a global right
    if (!defined $args{'Object'} && !defined $args{'ObjectId'} && !defined $args{'ObjectType'}) {
        $args{'Object'} = $RT::System;
    }
    #ACL check handled in ACE.pm
    my $type = $self->_GetPrincipalTypeForACL();

    my $ace = RT::Model::ACE->new( $self->CurrentUser );
    $ace->load_by_values(
        RightName     => $args{'Right'},
        Object    => $args{'Object'},
        PrincipalType => $type,
        PrincipalId   => $self->id
    );

    unless ( $ace->id ) {
        return ( 0, $self->loc("ACE not found") );
    }
    return ( $ace->delete );
}

# }}}

# {{{ sub _CleanupInvalidDelegations

=head2 sub _CleanupInvalidDelegations { InsideTransaction => undef }

Revokes all ACE entries delegated by this principal which are
inconsistent with this principal's current delegation rights.  Does
not perform permission checks, but takes no action and returns success
if this principal still retains DelegateRights.  Should only ever be
called from inside the RT library.

If this principal is a group, recursively calls this method on each
cached user member of itself.

If called from inside a transaction, specify a true value for the
InsideTransaction parameter.

Returns a true value if the deletion succeeded; returns a false value
and logs an internal error if the deletion fails (should not happen).

=cut

# This is currently just a stub for the methods of the same name in
# RT::Model::User and RT::Model::Group.

sub _CleanupInvalidDelegations {
    my $self = shift;
    unless ( $self->id ) {
	$RT::Logger->warning("Principal not loaded.");
	return (undef);
    }
    return ($self->Object->_CleanupInvalidDelegations(@_));
}

# }}}

# {{{ sub has_right

=head2 sub has_right (Right => 'right' Object => undef)


Checks to see whether this principal has the right "Right" for the Object
specified. If the Object parameter is omitted, checks to see whether the 
user has the right globally.

This still hard codes to check to see if a user has queue-level rights
if we ask about a specific ticket.


This takes the params:

    Right => name of a right

    And either:

    Object => an RT style object (->id will get its id)


Returns 1 if a matching ACE was found.

Returns undef if no ACE was found.

=cut

sub has_right {

    my $self = shift;
    my %args = (
        Right        => undef,
        Object       => undef,
        EquivObjects => undef,
        @_,
    );
    unless ( $args{'Right'} ) {
        $RT::Logger->crit("has_right called without a right");
        return (undef);
    }

    $args{EquivObjects} = [ @{ $args{EquivObjects} } ] if $args{EquivObjects};

    if ( $self->Disabled ) {
        $RT::Logger->error( "Disabled User #"
              . $self->id
              . " failed access check for "
              . $args{'Right'} );
        return (undef);
    }

    if (   defined( $args{'Object'} )
        && UNIVERSAL::can( $args{'Object'}, 'id' )
        && $args{'Object'}->id ) {

        push( @{ $args{'EquivObjects'} }, $args{Object} );
    }
    else {
        $RT::Logger->crit("has_right called with no valid object");
        return (undef);
    }

    # If this object is a ticket, we care about ticket roles and queue roles
    if ( UNIVERSAL::isa( $args{'Object'} => 'RT::Model::Ticket' ) ) {
         


        # this is a little bit hacky, but basically, now that we've done
        # the ticket roles magic, we load the queue object
        # and ask all the rest of our questions about the queue.
        push( @{ $args{'EquivObjects'} }, $args{'Object'}->ACLEquivalenceObjects);

    }

    # {{{ If we've cached a win or loss for this lookup say so

    # {{{ Construct a hashkey to cache decisions in
    my $hashkey = do {
        no warnings 'uninitialized';

        # We don't worry about the hash ordering, as this is only
        # temporarily used; also if the key changes it would be
        # invalidated anyway.
        join(
            ";:;",
            $self->id,
            map {
                $_,    # the key of each arguments
                  ( $_ eq 'EquivObjects' )    # for object arrayref...
                  ? map( _ReferenceId($_), @{ $args{$_} } )    # calculate each
                  : _ReferenceId( $args{$_} )    # otherwise just the value
              } keys %args
        );
    };

    # }}}

    # Returns undef on cache miss
    my $cached_answer = $_ACL_CACHE->fetch($hashkey);
    if ( defined $cached_answer ) {
        if ( $cached_answer == 1 ) {
            return (1);
        }
        elsif ( $cached_answer == -1 ) {
            return (undef);
        }
    }

    my $hitcount = $self->_has_right( %args );

    $_ACL_CACHE->set( $hashkey => $hitcount? 1:-1 );
    return ($hitcount);
}

=head2 _has_right

Low level has_right implementation, use has_right method instead.

=cut

sub _has_right
{
    my $self = shift;
    my %args = (
        Right        => undef,
        Object       => undef,
        EquivObjects => [],
        @_
    );

    my $right = $args{'Right'};
    my @objects = @{ $args{'EquivObjects'} };

    # If an object is defined, we want to look at rights for that object

    push( @objects, 'RT::System' )
      unless $self->can('_IsOverrideGlobalACL')
             && $self->_IsOverrideGlobalACL( $args{Object} );

    my ($check_roles, $check_objects) = ('','');
    if( @objects ) {
        my @role_clauses;
        my @object_clauses;
        foreach my $obj ( @objects ) {
            my $type = ref($obj)? ref($obj): $obj;
            my $id;
            $id = $obj->id if ref($obj) && UNIVERSAL::can($obj, 'id') && $obj->id;

            my $role_clause = "Groups.Domain = '$type-Role'";
            # XXX: Groups.Instance is VARCHAR in DB, we should quote value
            # if we want mysql 4.0 use indexes here. we MUST convert that
            # field to integer and drop this quotes.
            $role_clause   .= " AND Groups.Instance = '$id'" if $id;
            push @role_clauses, "($role_clause)";

            my $object_clause = "ACL.ObjectType = '$type'";
            $object_clause   .= " AND ACL.ObjectId = $id" if $id;
            push @object_clauses, "($object_clause)";
        }

        $check_roles .= join ' OR ', @role_clauses;
        $check_objects = join ' OR ', @object_clauses;
    }

    my $query_base =
      "SELECT ACL.id from ACL, Groups, Principals, CachedGroupMembers WHERE  " .

      # Only find superuser or rights with the name $right
      "(ACL.RightName = 'SuperUser' OR  ACL.RightName = '$right') "

      # Never find disabled groups.
      . "AND Principals.Disabled = 0 "
      . "AND CachedGroupMembers.Disabled = 0 "

      # We always grant rights to Groups
      . "AND Principals.id = Groups.id "
      . "AND Principals.PrincipalType = 'Group' "

      # See if the principal is a member of the group recursively or _is the rightholder_
      # never find recursively disabled group members
      # also, check to see if the right is being granted _directly_ to this principal,
      #  as is the case when we want to look up group rights
      . "AND Principals.id = CachedGroupMembers.GroupId "
      . "AND CachedGroupMembers.MemberId = ". $self->id ." "

      # Make sure the rights apply to the entire system or to the object in question
      . "AND ($check_objects) ";

    # The groups query does the query based on group membership and individual user rights
    my $groups_query = $query_base
      # limit the result set to groups of types ACLEquivalence (user),
      # UserDefined, SystemInternal and Personal. All this we do
      # via (ACL.PrincipalType = 'Group') condition
      . "AND ACL.PrincipalId = Principals.id "
      . "AND ACL.PrincipalType = 'Group' ";

    $self->_Handle->apply_limits( \$groups_query, 1 ); #only return one result
    my $hitcount = $self->_Handle->fetch_result($groups_query);
    return 1 if $hitcount; # get out of here if success

    # The roles query does the query based on roles
    my $roles_query = $query_base
      . "AND ACL.PrincipalType = Groups.Type "
      . "AND ($check_roles) ";
    $self->_Handle->apply_limits( \$roles_query, 1 ); #only return one result

    $hitcount = $self->_Handle->fetch_result($roles_query);
    return 1 if $hitcount; # get out of here if success

    return 0;
}

# }}}

# }}}

# {{{ ACL caching


# {{{ invalidate_acl_cache

=head2 invalidate_acl_cache

Cleans out and reinitializes the user rights cache

=cut

sub invalidate_acl_cache {
    $_ACL_CACHE = Cache::Simple::TimedExpiry->new();
    my $lifetime;
    $lifetime = $RT::Config->Get('ACLCacheLifetime') if $RT::Config;
    $_ACL_CACHE->expire_after( $lifetime || 60 );
}

# }}}

# }}}


# {{{ _GetPrincipalTypeForACL

=head2 _GetPrincipalTypeForACL

Gets the principal type. if it's a user, it's a user. if it's a role group and it has a Type, 
return that. if it has no type, return group.

=cut

sub _GetPrincipalTypeForACL {
    my $self = shift;
    my $type;    
    if ($self->PrincipalType eq 'Group' && $self->Object->Domain =~ /Role$/) {
        $type = $self->Object->Type;
    }
    else {
        $type = $self->PrincipalType;
    }

    return($type);
}

# }}}

# {{{ _ReferenceId

=head2 _ReferenceId

Returns a list uniquely representing an object or normal scalar.

For scalars, its string value is returned; for objects that has an
id() method, its class name and Id are returned as a string separated by a "-".

=cut

sub _ReferenceId {
    my $scalar = shift;

    # just return the value for non-objects
    return $scalar unless UNIVERSAL::can($scalar, 'id');

    return ref($scalar) unless $scalar->id;

    # an object -- return the class and id
    return(ref($scalar)."-". $scalar->id);
}

# }}}

1;