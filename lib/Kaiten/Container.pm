package Kaiten::Container;

use v5.10;
use strict;
use warnings;

use constant::def DEBUG => $ENV{Kaiten_Container_DEBUG} || 0;

=head1 NAME

Kaiten::Container - Simples dependency-injection (DI) container, distant relation of IoC.

=head1 VERSION

Version 0.21

=cut

our $VERSION = '0.21';

use Moo;

use Carp qw(croak carp);
use Scalar::Util qw(reftype);

#======== DEVELOP THINGS ===========>
# develop mode
#use Smart::Comments;
#use Data::Printer;

#======== DEVELOP THINGS ===========<


my $error = [
              'Error: handler [%s] not defined at [init], die ',
              'Error: handler [%s] init wrong, [probe] sub not defined, die ',
              'Warning: handler [%s] don`t pass [probe] check on reuse, try to create new one, working ',
              'Error: handler [%s] don`t pass [probe] check on create, somthing wrong, die ',
              'Error: [init] value must be HASHREF only, die ',
              'Error: [add_handler] method REQUIRE handlers at args, die',
              'Error: handler [%s] exists, to rewrite handler remove it at first, die ',
              'Error: [remove_handler] method REQUIRE handlers at args, die',
              'Error: handler [%s] NOT exists, nothing to remove, die ',
            ];

has 'init' => (
    is       => 'rw',
    required => 1,
    isa      => sub {
        croak sprintf $error->[4] unless ( defined $_[0] && ( reftype $_[0] || '' ) eq 'HASH' );
    },
    default => sub { {} },
              );

has '_cache' => (
                  is      => 'rw',
                  default => sub { {} },
                );

=head1 SYNOPSIS

This module resolve dependency injection conception in easiest way ever.
You are just create some code first and put it on kaiten in named container.
Later you take it by name and got yours code result fresh and crispy.

No more humongous multi-level dependency configuration, service provider and etc.

You got what you put on, no more, no less.

Ok, little bit more - L<Kaiten::Container> run |probe| sub every time when you want to take something to ensure all working properly.

And another one - KC try to re-use |handler| return if it requested.

    use Kaiten::Container;

    my $config = {
         ExampleP => {
             handler  => sub { return DBI->connect( "dbi:ExampleP:", "", "", { RaiseError => 1 } ) or die $DBI::errstr },
             probe    => sub { shift->ping() },
             settings => { reusable => 1 }
         }
    };

    my $container = Kaiten::Container->new( init => $config );
    my $dbh = $container->get_by_name('ExampleP');

All done, now we are have container and may get DB handler on call.
Simple!

=head1 SUBROUTINES/METHODS

=head2 C<new(%init_configuration?)>

This method create container with entities as |init| configuration hash values, also may called without config.
Its possible add all entities later, with C<add> method.

    my $config = {
         ExampleP => {
             handler  => sub { return DBI->connect( "dbi:ExampleP:", "", "", { RaiseError => 1 } ) or die $DBI::errstr },
             probe    => sub { shift->ping() },
             settings => { reusable => 1 }
         },
         test => {
             handler  => sub        { return 'Hello world!' },
             probe    => sub        { return 1 },
        },
    };

    my $container = Kaiten::Container->new( init => $config );  

Entity MUST have:

  - unique name
  
  - |handler| sub - its return something helpfully
  
  - |probe| sub - its must return true, as first arguments this sub got |handler| sub result.

Entity MAY have settings hashref:

  - 'reusable' if it setted to true - KC try to use cache. If cached handler DONT pass probe KC try to create new one instance.

NB. New instance always be tested by call |probe|. 
If you dont want test handler - just cheat with 

    probe => sub { 1 }

but its bad idea, I notice you.

=head2 C<get_by_name($what)>

Use this method to execute |handler| sub and get it as result.

    my $dbh = $container->get_by_name('ExampleP');
    # now $dbh contain normal handler to ExampleP DB

=cut

sub get_by_name {
    my $self         = shift;
    my $handler_name = shift;

    my $handler_config = $self->init->{$handler_name};

    croak sprintf( $error->[0], $handler_name ) unless defined $handler_config;
    croak sprintf( $error->[1], $handler_name ) unless defined $handler_config->{probe} && ( reftype $handler_config->{probe} || '' ) eq 'CODE';

    my $result;

    my $reusable = defined $handler_config->{settings} && $handler_config->{settings}{reusable};

    if ( $reusable && defined $self->_cache->{$handler_name} ) {
        $result = $self->_cache->{$handler_name};

        # checkout handler and wipe it if it don`t pass [probe]
        unless ( eval { $handler_config->{probe}->($result) } ) {
            carp sprintf( $error->[2], $handler_name ) if DEBUG;
            $result = undef;
        }
    }

    unless ($result) {
        $result = $self->init->{$handler_name}{handler}->();

        # checkout handler and die it if dont pass [probe]
        unless ( eval { $handler_config->{probe}->($result) } ) {
            croak sprintf( $error->[3], $handler_name );
        }
    }

    # put it to cache if it used
    $self->_cache->{$handler_name} = $result if $reusable;

    return $result;
}

=pod

=head2 C<add(%config)>

Use this method to add some more entities to container.

    my $configutarion_explodable = {
           explode => {
                        handler  => sub        { return 'ExplodeSQL there!' },
                        probe    => sub        { state $a= [ 1, 0, 0 ]; return shift @$a; },
                        settings => { reusable => 1 }
                      },
           explode_now => { 
                        handler => sub { return 'ExplodeNowSQL there!' },
                        probe    => sub        { 0 },
                        settings => { reusable => 1 }
                      },
    };

    $container->add(%$configutarion_explodable); # list, NOT hashref!!!
    
=cut

sub add {
    my $self     = shift;
    my %handlers = @_;

    croak sprintf $error->[5] unless scalar keys %handlers;

    while ( my ( $handler_name, $handler_config ) = each %handlers ) {

        croak sprintf( $error->[6], $handler_name ) if exists $self->init->{$handler_name};

        $self->init->{$handler_name} = $handler_config;

    }

    return $self;
}

=pod

=head2 C<remove(@what)>

This method remove some entities from container

    $container->remove('explode_now','ExampleP'); # list, NOT arayref!!!

=cut

sub remove {
    my $self     = shift;
    my @handlers = @_;

    croak sprintf $error->[7] unless scalar @handlers;

    foreach my $handler_name (@handlers) {

        croak sprintf( $error->[8], $handler_name ) if !exists $self->init->{$handler_name};

        delete $self->init->{$handler_name};
        # clear cache if it exists too
        delete $self->_cache->{$handler_name} if exists $self->_cache->{$handler_name};

    }

    return $self;
}

=pod

=head2 C<show_list>

Use this method to view list of available handler in container

    my @handler_list = $container->show_list;
    
    # @handler_list == ( 'explode', 'test' )

NB. Entities sorted with perl sort function

=cut

sub show_list {
    my $self = shift;

    my @result = sort keys %{ $self->init };
    return wantarray ? @result : \@result;

}

=head1 AUTHOR

Meettya, C<< <meettya at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-kaiten-container at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Kaiten-Container>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 DEVELOPMENT

=head2 Repository

    https://github.com/Meettya/Kaiten-Container


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Kaiten::Container


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Kaiten-Container>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Kaiten-Container>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Kaiten-Container>

=item * Search CPAN

L<http://search.cpan.org/dist/Kaiten-Container/>

=back

=head1 SEE ALSO

L<Bread::Broad> - a Moose-based DI framework

L<IOC> - the ancestor of L<Bread::Board>

L<Peco::Container> - another DI container

L<IOC::Slinky::Container> - an alternative DI container

=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2011 Meettya.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1;    # End of Kaiten::Container
