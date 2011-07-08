use 5.006;
use strict;
use warnings;

package Metabase::Archive::MongoDB;
# ABSTRACT: Metabase storage using MongoDB

use boolean;
use Carp       ();
use Compress::Zlib 2 qw(compress uncompress);
use Data::Stream::Bulk::Filter;
use JSON 2 qw/encode_json decode_json/;
use Metabase::Fact;
use Try::Tiny;


use Moose;

with 'Metabase::Backend::MongoDB';
with 'Metabase::Archive';

#--------------------------------------------------------------------------#
# required by Metabase::Backend::MongoDB
#--------------------------------------------------------------------------#

sub _build_collection_name {
  return 'metabase_archive';
}

sub _ensure_index {
  my ($self, $coll) = @_;
  return $coll->ensure_index(
    { 'g' => 1 },
    { safe => 1, unique => true} 
  );
}

#--------------------------------------------------------------------------#
# required by Metabase::Archive
#--------------------------------------------------------------------------#

# given fact, store it and return guid;
sub store {
    my ( $self, $fact_struct ) = @_;
    my $guid = $fact_struct->{metadata}{core}{guid};
    my $type = $fact_struct->{metadata}{core}{type};

    unless ($guid) {
        Carp::confess "Can't store: no GUID set for fact\n";
    }

    my $json = compress(encode_json($fact_struct));

    # g for guid; d for data
    return $self->coll->insert( { g => $guid, d => $json }, {safe => 1} );
}

# given guid, retrieve it and return it
# type is directory path
# class isa Metabase::Fact::Subclass
sub extract {
    my ( $self, $guid ) = @_;
    local $MongoDB::Cursor::slave_okay = 1;
    my $obj = $self->coll->find_one( { g => $guid } );
    return decode_json(uncompress($obj->{d}));
}

# DO NOT lc() GUID
sub delete {
    my ( $self, $guid ) = @_;
    return $self->coll->remove( {g => $guid}, {safe => 1} );
}

sub iterator {
  my $self = shift;
  local $MongoDB::Cursor::slave_okay = 1;
  my $cursor = $self->coll->query;
  $cursor->immortal(1); # this could take a while!
  return Data::Stream::Bulk::Callback->new(
    callback => sub {
      my @results;
      for ( 1 .. 50 ) {
        last unless $cursor->has_next;
        my $obj = $cursor->next;
        push @results, decode_json(uncompress($obj->{d}));
      }
      return @results ? \@results : undef;
    }
  );
}

1;

__END__

=for Pod::Coverage::TrustPod store extract delete iterator

=head1 SYNOPSIS


=head1 DESCRIPTION


=head1 USAGE

See L<Metabase::Archive> and L<Metabase::Librarian>.

=cut
