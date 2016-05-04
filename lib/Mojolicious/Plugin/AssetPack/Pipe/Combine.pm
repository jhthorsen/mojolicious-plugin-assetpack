package Mojolicious::Plugin::AssetPack::Pipe::Combine;
use Mojo::Base 'Mojolicious::Plugin::AssetPack::Pipe';
use Mojolicious::Plugin::AssetPack::Util qw(checksum diag DEBUG);

has enabled => sub { shift->assetpack->minify };

sub process {
  my ($self, $assets) = @_;
  my $combined = Mojo::Collection->new;
  my @other;

  return unless $self->enabled;

  for my $asset (@$assets) {
    if ($asset->isa('Mojolicious::Plugin::AssetPack::Asset::Null')) {
      next;
    }
    elsif (grep { $asset->format eq $_ } qw(css js)) {
      push @$combined, $asset;
    }
    else {
      push @other, $asset;
    }
  }

  if ( $combined->size > 0 ) {
    my $checksum = checksum $combined->map('checksum')->join(':');
    my $content  = $combined->map('content')->join("\n");

    diag 'Combining assets into "%s" with checksum %s.', $self->topic, $checksum if DEBUG;

    @$assets = (
      @other,
      Mojolicious::Plugin::AssetPack::Asset->new(url => $self->topic)->checksum($checksum)
        ->minified(1)->content($content)
    );
  }
  else {
    @$assets = @other;
  }
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Plugin::AssetPack::Pipe::Combine - Combine multiple assets to one

=head1 DESCRIPTION

L<Mojolicious::Plugin::AssetPack::Pipe::Combine> will take a list of
assets and turn them into a single asset.

=head1 ATTRIBUTES

  $bool = $self->enabled;

Set this to false to disable combining assets into a single file. The default
value will be L<Mojolicious::Plugin::AssetPack/minify>.

=head1 METHODS

=head2 process

See L<Mojolicious::Plugin::AssetPack::Pipe/process>.

=head1 SEE ALSO

L<Mojolicious::Plugin::AssetPack>.

=cut
