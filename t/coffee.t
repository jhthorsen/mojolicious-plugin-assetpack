use lib '.';
use t::Helper;
plan skip_all => 'TEST_COFFEE=1' unless $ENV{TEST_COFFEE} or -e '.test-everything';

my $t = t::Helper->t(pipes => [qw(CoffeeScript JavaScript)]);
$t->app->asset->process('app.js' => 'foo.coffee');
$t->get_ok('/')->status_is(200)->element_exists(qq(script[src="/asset/e4c4b04389/foo.js"]));

$t->get_ok($t->tx->res->dom->at('script')->{src})->status_is(200)
  ->content_like(qr{\sconsole.log\('hello from foo coffee'\)});

$ENV{MOJO_MODE} = 'test_minify_from_here';
$t = t::Helper->t(pipes => [qw(CoffeeScript JavaScript)]);
Mojo::Util::monkey_patch('Mojolicious::Plugin::AssetPack::Pipe::CoffeeScript', run => sub { die 'Not cached!' });
$t->app->asset->process('app.js' => 'foo.coffee');
$t->get_ok('/')->status_is(200)->element_exists(qq(script[src="/asset/e4c4b04389/foo.js"]));
$t->get_ok($t->tx->res->dom->at('script')->{src})->status_is(200)
  ->content_like(qr/\{console.log\('hello from foo coffee'\)/);

done_testing;

__DATA__
@@ index.html.ep
%= asset 'app.js'
@@ foo.coffee
console.log 'hello from foo coffee'
