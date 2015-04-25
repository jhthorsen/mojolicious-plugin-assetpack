use t::Helper;

{
  my $t = t::Helper->t({minify => 0});

  ok $t->app->asset->preprocessors->can_process('js'), 'found preprocessor for js';

  $t->app->asset('app.js' => '/js/a.js', '/js/b.js', '/js/*.js');


  is_deeply(
    [$t->app->asset->get('app.js')],
    ['/packed/a-527b09c38362b669ec6e16c00d9fb30d.js', '/packed/b-99eec25eb4441cda45d464c03b92a536.js', '/packed/c-9c9e6dc36e82c8359213088d1ca19359.js','/packed/empty-d41d8cd98f00b204e9800998ecf8427e.js', '/packed/https___patform_twitter_com_widgets-b9d18daeb16035c94dcf1c74f3551a6a.js'],
    'get(app.js)'
  );

  $t->get_ok('/test1')->status_is(200)
    ->content_like(
    qr{<script src="/packed/a-527b09c38362b669ec6e16c00d9fb30d\.js".*<script src="/packed/b-99eec25eb4441cda45d464c03b92a536\.js"}s
    );
}

{
  my $t = t::Helper->t({minify => 1});

  $t->app->asset('app.js' => '/js/a.js', '/js/b.js');

  $t->get_ok('/test1');    # trigger pack_javascripts() twice for coverage
  $t->get_ok('/test1')->status_is(200)
    ->content_like(qr{<script src="/packed/app-ec1f584de6b736ca6aea95c003e498aa\.min\.js"}m);

  $t->get_ok($t->tx->res->dom->at('script')->{src})->status_is(200)->content_like(qr{["']a["'].*["']b["']}s);

  is_deeply([$t->app->asset->get('app.js')], ['/packed/app-ec1f584de6b736ca6aea95c003e498aa.min.js'], 'get(app.js)');
}

done_testing;

__DATA__
@@ test1.html.ep
%= asset 'app.js'
