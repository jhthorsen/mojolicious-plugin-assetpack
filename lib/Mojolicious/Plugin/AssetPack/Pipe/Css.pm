package Mojolicious::Plugin::AssetPack::Pipe::Css;
use Mojo::Base 'Mojolicious::Plugin::AssetPack::Pipe';

use Mojolicious::Plugin::AssetPack::Util qw(diag load_module DEBUG);

sub process {
  my ($self, $assets) = @_;

  return $assets unless $self->assetpack->minify;
  return $assets->each(sub {
    my ($asset, $index) = @_;
    my $attrs = $asset->TO_JSON(minified => 1, key => 'min');
    return if $asset->format ne 'css' or $asset->minified;
    return if $self->store->load($asset, $attrs);
    load_module 'CSS::Minifier::XS';
    diag 'Minify "%s" with checksum %s.', $asset->url, $asset->checksum if DEBUG;
    my $css = CSS::Minifier::XS::minify($asset->content);
    $self->store->save($asset, \$css, $attrs);
  });
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Plugin::AssetPack::Pipe::Css - Minify CSS

=head1 DESCRIPTION

L<Mojolicious::Plugin::AssetPack::Pipe::Css> will minify your "css" assets
if L<Mojolicious::Plugin::AssetPack/minify> is true and the asset is not
already minified.

This module requires the optional module L<CSS::Minifier::XS> to minify.

=head1 METHODS

=head2 process

See L<Mojolicious::Plugin::AssetPack::Pipe/process>.

=head1 SEE ALSO

L<Mojolicious::Plugin::AssetPack>.

=cut
