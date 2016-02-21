package Mojolicious::Plugin::AssetPack;
use Mojo::Base 'Mojolicious::Plugin';
use Mojolicious::Plugin::AssetPack::Asset;
use Mojolicious::Plugin::AssetPack::Store;
use Mojolicious::Plugin::AssetPack::Util qw(diag has_ro load_module DEBUG);

our $VERSION = '0.70';

has minify => sub { shift->_app->mode ne 'development' };

has route => sub {
  my $self = shift;
  Scalar::Util::weaken($self);
  $self->_app->routes->route('/asset/:checksum/:name')->via(qw( HEAD GET ))
    ->name('assetpack')->to(cb => sub { $self->_serve(@_) });
};

has store => sub {
  my $self = shift;
  Mojolicious::Plugin::AssetPack::Store->new(
    classes => [@{$self->_app->static->classes}],
    paths   => [$self->_app->home->rel_dir('assets')],
    ua      => $self->ua,
  );
};

has_ro ua => sub { Mojo::UserAgent->new->max_redirects(3) };

sub pipe {
  my ($self, $needle) = @_;
  return +(grep { $_ =~ /::$needle\b/ } @{$self->{pipes}})[0];
}

sub process {
  my ($self, $topic) = (shift, shift);

  return $self->_process_from_def($topic) unless @_;

  # Used by diag()
  local $Mojolicious::Plugin::AssetPack::Util::TOPIC = $topic;

  # TODO: The idea with blessed($_) is that maybe the user can pass inn
  # Mojolicious::Plugin::AssetPack::Sprites object, with images to generate
  # CSS from?
  my $assets = Mojo::Collection->new(
    map {
      Scalar::Util::blessed($_)
        ? $_
        : Mojolicious::Plugin::AssetPack::Asset->new(assetpack => $self, url => $_)
    } @_
  );

  # Prepare asset attributes
  $assets->map($_) for qw(checksum mtime);

  for my $pipe (@{$self->{pipes}}) {
    next unless $pipe->can('process');
    local $pipe->{topic} = $topic;
    diag '%s->process($assets)', ref $pipe if DEBUG;
    $pipe->process($assets);
    push @{$self->{asset_paths}}, $_->path for @$assets;
  }

  $self->_app->log->debug(qq(Processed asset "$topic".));
  $self->{by_checksum}{$_->checksum} = $_ for @$assets;
  $self->{by_topic}{$topic} = $assets;
  $self;
}

sub processed {
  my ($self, $topic) = @_;
  return $self->{by_topic}{$topic};
}

sub register {
  my ($self, $app, $config) = @_;
  my $helper = $config->{helper} || 'asset';

  if ($app->renderer->helpers->{$helper}) {
    return $app->log->debug("AssetPack: Helper $helper() is already registered.");
  }

  $self->ua->server->app($app);
  Scalar::Util::weaken($self->ua->server->{app});

  if (my $proxy = $config->{proxy} // {}) {
    local $ENV{NO_PROXY} = $proxy->{no_proxy} || join ',', grep {$_} $ENV{NO_PROXY},
      $ENV{no_proxy}, '127.0.0.1', '::1', 'localhost';
    diag 'Detecting proxy settings. (NO_PROXY=%s)', $ENV{NO_PROXY} if DEBUG;
    $self->ua->proxy->detect;
  }

  if ($config->{pipes}) {
    $self->_pipes($config->{pipes});
    $app->helper($helper => sub { @_ == 1 ? $self : $self->_tag_helpers(@_) });
  }
  else {
    require Mojolicious::Plugin::AssetPack::Backcompat;
    @Mojolicious::Plugin::AssetPack::ISA = ('Mojolicious::Plugin::AssetPack::Backcompat');
    return $self->SUPER::register($app, $config);
  }
}

sub _app { shift->ua->server->app }

sub _pipes {
  my ($self, $names) = @_;

  $self->{pipes} = [
    map {
      my $class = load_module /::/ ? $_ : "Mojolicious::Plugin::AssetPack::Pipe::$_";
      diag 'Loading pipe "%s".', $class if DEBUG;
      die qq(Unable to load "$_": $@) unless $class;
      $class->new(assetpack => $self);
    } @$names
  ];
}

sub _process_from_def {
  my $self  = shift;
  my $file  = shift || 'assetpack.def';
  my $asset = $self->store->file($file);
  my $topic = '';
  my %process;

  die qq(Unable to load "$file".) unless $asset;
  diag qq(Loading asset definitions from "$file".) if DEBUG;

  for (split /\r?\n/, $asset->slurp) {
    s/\s*\#.*//;
    next if /^\s*$/;
    $topic = $1 if s/^\!\s*(.+)//;
    push @{$process{$topic}}, $1 if s/^\<\s*(.+)//;
  }

  $self->process($_ => @{$process{$_}}) for keys %process;
  $self;
}

sub _reset {
  my ($self, $args) = @_;

  diag 'Reset assetpack.' if DEBUG;

  if ($args->{unlink}) {
    $self->store->_reset;
    for (@{$self->{asset_paths} || []}) {
      next unless /\bcache\b/;
      -e and unlink;
      diag 'unlink %s = %s', $_, $! if DEBUG;
    }
  }

  delete $self->{$_} for qw(by_checksum by_topic);
}

sub _serve {
  my ($self, $c) = @_;
  my $asset = $self->{by_checksum}{$c->stash('checksum')} or return $c->reply->not_found;
  $self->store->serve_asset($c, $asset);
  $c->rendered;
}

sub _tag_helpers {
  my ($self, $c, $topic, @attrs) = @_;
  my $route    = $self->route;
  my $base_url = $route->pattern->defaults->{base_url} || '';
  my $assets   = $self->{by_topic}{$topic}
    or die qq(No assets registered by topic "$topic".);

  $base_url =~ s!/+$!!;

  return $assets->map(
    sub {
      my $tag_helper = $_->format eq 'js' ? 'javascript' : 'stylesheet';
      my $url
        = $base_url
        . $route->render(
        {checksum => $_->checksum, format => $_->format, name => $_->name});
      $c->$tag_helper($url, @attrs);
    }
  )->join("\n");
}

sub DESTROY {
  my $self = shift;
  $self->_reset({unlink => 1}) if $ENV{MOJO_ASSETPACK_CLEANUP} and $self->{store};
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Plugin::AssetPack - Compress and convert css, less, sass, javascript and coffeescript files

=head1 VERSION

0.70

=head1 SYNOPSIS

=head2 Application

  use Mojolicious::Lite;

  # Load plugin and pipes in the right order
  plugin AssetPack => {
    pipes => [qw(Less Sass Css CoffeeScript Riotjs JavaScript Combine)]
  };

  # define asset
  app->asset->process(
    # virtual name of the asset
    "app.css" => (

      # source files used to create the asset
      "sass/bar.scss",
      "https://github.com/Dogfalo/materialize/blob/master/sass/materialize.scss",
    )
  );

=head2 Template

  <html>
    <head>
      %= asset "app.css"
    </head>
    <body><%= content %></body>
  </html>

=head1 FOR EXISTING USERS

Are you already using AssetPack? You can still do so without any change. This
new version was written to make it easier to maintain and also easier to
extend. The new code will be "activated" by loadind this plugin with a list of
pipes:

  $app->plugin(AssetPack => {pipes => [...]});

The old API will not be maintained and slowly deprecated.

=head1 DESCRIPTION

L<Mojolicious::Plugin::AssetPack> is L<Mojolicious plugin|Mojolicious::Plugin>
for processing static assets. The idea is that JavaScript and CSS files should
be served as one minified file to save bandwidth and roundtrip time to the
server.

There are many external tools for doing this, but integrating them with
L<Mojolicious> can be a struggle: You want to serve the source files directly
while developing, but a minified version in production. This assetpack plugin
will handle all of that automatically for you.

The actual processing is delegated to "pipe objects". Please see
L<Mojolicious::Plugin::AssetPack::Guides::Tutorial/Pipes> for a complete list.

=head1 GUIDES

=over 2

=item * L<Mojolicious::Plugin::AssetPack::Guides::Tutorial>

The tutorial will give an introduction to how AssetPack can be used.

=item * L<Mojolicious::Plugin::AssetPack::Guides::Cookbook>

The cookbook has various receipes on how to cook with AssetPack.

=back

=head1 ENVIRONNMENT

It is possible to set environment variables to change the behavior of AssetPack:

=over 2

=item * MOJO_ASSETPACK_DEBUG

Set this environment variable to get more debug to STDERR. Currently you can
set it to a value between 0 and 3, where 3 provides the most debug.

=back

=head1 HELPERS

=head1 asset

  $self = $app->asset;
  $self = $c->asset;
  $bytestream = $c->asset($topic, @args);
  $bytestream = $c->asset("app.css", media => "print");

C<asset()> is the main entry point to this plugin. It can either be used to
access the L<Mojolicious::Plugin::AssetPack> instance or as a tag helper.

The helper name "asset" can be customized by specifying "helper" when
L<registering|/register> the plugin.

See L<Mojolicious::Plugin::AssetPack::Guides::Tutorial> for more details.

=head1 ATTRIBUTES

=head2 minify

  $bool = $self->minify;
  $self = $self->minify($bool);

Set this to true to combine and minify the assets. Defaults to false if
L<Mojolicious/mode> is "development" and true otherwise.

See L<Mojolicious::Plugin::AssetPack::Guides::Tutorial/Application mode>
for more details.

=head2 route

  $route = $self->route;
  $self = $self->route($route);

A L<Mojolicious::Routes::Route> object used to serve assets. The default route
responds to HEAD and GET requests and calls
L<serve_asset()|Mojolicious::Plugin::AssetPack::Store/serve_asset> on L</store>
to serve the asset.

See L<Mojolicious::Plugin::AssetPack::Guides::Cookbook/ASSETS FROM CUSTOM DOMAIN>
for an example on how to customize this route.

=head2 store

  $obj = $self->store;
  $self = $self->store(Mojolicious::Plugin::AssetPack::Store->new);

Holds a L<Mojolicious::Plugin::AssetPack::Store> object used to locate, store
and serve assets.

=head2 ua

  $ua = $self->ua;

Holds a L<Mojo::UserAgent> which can be used to fetch assets either from local
application or from remote web servers.

=head1 METHODS

=head2 pipe

  $obj = $self->pipe($name);
  $obj = $self->pipe("Css");

Will return a registered pipe by C<$name> or C<undef> if none could be found.

=head2 process

  $self = $self->process($topic => @assets);
  $self = $self->process($definition_file);

Used to process assets. A C<$definition_file> can be used to define C<$topic>
and C<@assets> in a seperate file. See
L<Mojolicious::Plugin::AssetPack::Guides::Tutorial/Process assets> for more
details.

C<$definition_file> defaults to "assetpack.def".

=head2 processed

  $collection = $self->processed($topic);

Can be used to retrieve a L<Mojo::Collection> object, with zero or more
L<Mojolicious::Plugin::AssetPack::Asset> objects. Returns undef if C<$topic> is
not defined with L</process>.

=head2 register

  $self->register($app, \%config);

Used to register the plugin in the application. C<%config> can contain:

=over 2

=item * helper

Name of the helper to add to the application. Default is "asset".

=item * pipes

This argument is mandatory and need to contain a complete list of pipes that is
needed. Example:

  $app->plugin(AssetPack => {pipes => [qw(Sass Css Combine)]);

See L<Mojolicious::Plugin::AssetPack::Guides::Tutorial/Pipes> for a complete
list of available pipes.

=item * proxy

A hash of proxy settings. Set this to C<0> to disable proxy detection.
Currently only "no_proxy" is supported, which will set which requests that
should bypass the proxy (if any proxy is detected). Default is to bypass all
requests to localhost.

See L<Mojo::UserAgent::Proxy/detect> for more infomation.

=back

=head1 SEE ALSO

L</GUIDES>,
L<Mojolicious::Plugin::AssetPack::Asset>,
L<Mojolicious::Plugin::AssetPack::Pipe> and
L<Mojolicious::Plugin::AssetPack::Store>.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014, Jan Henning Thorsen

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 AUTHOR

Jan Henning Thorsen - C<jhthorsen@cpan.org>

Alexander Rymasheusky

Per Edin - C<info@peredin.com>

Viktor Turskyi

=cut
