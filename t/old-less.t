use t::Helper;

{
  my $t = t::Helper->t_old({minify => 0});

  plan skip_all => 'Could not find preprocessors for less' unless $t->app->asset->preprocessors->can_process('less');

  $t->app->asset('less.css' => '/css/a.less', '/css/b.less');

  $t->get_ok('/test1')->status_is(200)
    ->content_like(qr{<link href="/packed/a-\w+\.css".*<link href="/packed/b-\w+\.css"}s);
}

{
  my $t = t::Helper->t_old({minify => 1});

  $t->app->asset('less.css' => '/css/a.less', '/css/b.less');

  $t->get_ok('/test1');    # trigger pack_stylesheets() twice for coverage

  $t->get_ok('/test1')->status_is(200)
    ->content_like(qr{<link href="/packed/less-9bb8a2a996dde4692205a829ba6d1c8a\.min\.css"}m);

  $t->get_ok($t->tx->res->dom->at('link')->{href})->status_is(200)->content_like(qr{a1a1a1.*b1b1b1}s);
}

is(Mojolicious::Plugin::AssetPack::Preprocessor::Less->_url, 'http://lesscss.org/#usage', '_url');

done_testing;

__DATA__
@@ test1.html.ep
%= asset 'less.css'
